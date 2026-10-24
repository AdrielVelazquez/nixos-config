// Checkpoints: a snapshot of the working tree at the start of every prompt, and the commands to go back.
//
//   /undo         rewind the last turn: restore the files it changed and return to before your last message
//   /redo         undo the undo (or the last restore), files and conversation together
//   /checkpoints  pick any snapshot of this branch and restore the files to it
//
// Snapshots live in a private git repository (checkpoint-core.ts), never in the project's own. Each one is recorded
// in the session as a `checkpoint` entry just before the prompt it precedes, so `/tree` branches and resumed
// sessions find the checkpoint that belongs to their point in the conversation. Navigating the tree offers to put
// the files back to match.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CheckpointError, Checkpoints, describeRestore, promptLabel, relativeTime, type Change, type CheckpointConfig } from "./checkpoint-core.ts";

export interface CheckpointOptions extends CheckpointConfig {
  /** Snapshots older than this are dropped when a session starts. */
  maxAgeDays: number;
  /** `ask` offers to restore the files when the tree is navigated; `never` leaves that to /undo and /checkpoints. */
  restoreOnTree: "ask" | "never";
}

interface CheckpointData {
  commit: string;
  tree: string;
  head?: string;
  takenAt: number;
  prompt: string;
}

const ENTRY = "checkpoint";
const DAY = 24 * 3600 * 1000;
const SNAPSHOT_LIMIT_MS = 30_000;

type BranchEntry = ReturnType<ExtensionContext["sessionManager"]["getBranch"]>[number];

const isCheckpoint = (entry: BranchEntry): entry is BranchEntry & { data: CheckpointData } =>
  entry.type === "custom" && entry.customType === ENTRY && typeof (entry as any).data?.commit === "string";
const isUserMessage = (entry: BranchEntry): boolean => entry.type === "message" && (entry as any).message?.role === "user";

/** The checkpoint nearest before `index` on a branch: the snapshot taken when the turn that starts there began. */
function checkpointBefore(branch: BranchEntry[], index: number): (BranchEntry & { data: CheckpointData }) | undefined {
  for (let i = Math.min(index, branch.length - 1); i >= 0; i--) {
    const entry = branch[i];
    if (isCheckpoint(entry)) return entry;
  }
  return undefined;
}

const errorText = (error: unknown): string => (error instanceof Error ? error.message : String(error));

export function createCheckpoints(pi: ExtensionAPI, options: CheckpointOptions) {
  let store: Checkpoints | undefined;
  let unavailable: string | undefined;
  let warned = false;
  let busy = false;
  // While a restore moves the tree itself, the `session_tree` handler must not offer another one.
  let restoring = false;
  // The state a restore replaced: files to put back and, when a rewind moved the conversation, where to return to.
  let redo: { commit: string; leafId: string | null; prompt?: string } | undefined;

  const off = (): string => `Checkpoints are off${unavailable ? `: ${unavailable}` : " for this session"}`;

  /** The lines of a confirmation for restoring to `commit`, and what it would change. */
  async function review(commit: string, head: string | undefined): Promise<{ changes: Change[]; lines: string[] }> {
    const changes = await store!.preview(commit);
    const lines = changes.length ? describeRestore(changes) : ["No file differs from that snapshot."];
    const now = head ? await store!.head() : undefined;
    if (head && now && head !== now) lines.push("", `Git moved from ${head.slice(0, 7)} to ${now.slice(0, 7)}: commits made since stay; only files are restored.`);
    return { changes, lines };
  }

  pi.on("session_start", async (_event, ctx) => {
    store = undefined;
    unavailable = undefined;
    redo = undefined;
    warned = false;
    try {
      store = await Checkpoints.open(ctx.cwd, ctx.sessionManager.getSessionId(), options);
      // Housekeeping never delays the session.
      void store.prune(options.maxAgeDays * DAY).catch(() => undefined);
    } catch (error) {
      unavailable = errorText(error);
    }
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (event.messageType !== "user") return;
    redo = undefined;
    if (!store || busy) return;
    const label = promptLabel(event.prompt);
    busy = true;
    const operation = store.snapshot(label);
    operation
      .then(
        () => undefined,
        () => undefined,
      )
      .finally(() => {
        busy = false;
      });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const taken = await Promise.race([
        operation,
        new Promise<never>((_resolve, reject) => {
          timer = setTimeout(() => reject(new CheckpointError(`a snapshot took longer than ${SNAPSHOT_LIMIT_MS / 1000} s`)), SNAPSHOT_LIMIT_MS);
        }),
      ]);
      pi.appendEntry<CheckpointData>(ENTRY, { commit: taken.commit, tree: taken.tree, head: taken.head, takenAt: Date.now(), prompt: label });
    } catch (error) {
      // A problem that will come back on every prompt (too many files, an unreadable tree) ends checkpointing for the
      // session; one warning says so.
      unavailable = errorText(error);
      if (error instanceof CheckpointError) store = undefined;
      if (!warned) {
        warned = true;
        ctx.ui.notify(`Checkpoints stopped: ${unavailable}`, "warning");
      }
    } finally {
      if (timer) clearTimeout(timer);
    }
  });

  pi.registerCommand("undo", {
    description: "Rewind the last turn: restore the files it changed and return to before your last message",
    handler: async (_args, ctx) => {
      if (!store) return ctx.ui.notify(off(), "warning");
      if (!ctx.isIdle()) return ctx.ui.notify("Wait for the run to finish, or press esc, before /undo", "warning");
      const branch = ctx.sessionManager.getBranch();
      const index = branch.map(isUserMessage).lastIndexOf(true);
      if (index < 0) return ctx.ui.notify("Nothing to undo: there is no message yet", "info");
      const checkpoint = checkpointBefore(branch, index);
      if (!checkpoint) return ctx.ui.notify("No checkpoint for your last message: it was sent before checkpoints were on", "warning");
      const { changes, lines } = await review(checkpoint.data.commit, checkpoint.data.head);
      const ok = await ctx.ui.confirm("Undo the last turn?", [...lines, "", "The conversation returns to before your last message; /redo brings both back."].join("\n"));
      if (!ok) return;
      restoring = true;
      try {
        const { before } = await store.restore(checkpoint.data.commit);
        redo = { commit: before.commit, leafId: ctx.sessionManager.getLeafId(), prompt: checkpoint.data.prompt };
        await ctx.navigateTree(branch[index].id, { summarize: false });
      } catch (error) {
        return ctx.ui.notify(`Undo failed: ${errorText(error)}`, "error");
      } finally {
        restoring = false;
      }
      ctx.ui.notify(`Undid the last turn: ${changes.length} file${changes.length === 1 ? "" : "s"} restored. /redo brings it back.`, "info");
    },
  });

  pi.registerCommand("redo", {
    description: "Undo the last /undo or restore: files and conversation together",
    handler: async (_args, ctx) => {
      if (!store) return ctx.ui.notify(off(), "warning");
      if (!redo) return ctx.ui.notify("Nothing to redo", "info");
      if (!ctx.isIdle()) return ctx.ui.notify("Wait for the run to finish, or press esc, before /redo", "warning");
      const { commit, leafId, prompt } = redo;
      const { lines } = await review(commit, undefined);
      if (!(await ctx.ui.confirm("Redo?", lines.join("\n")))) return;
      restoring = true;
      try {
        await store.restore(commit);
        if (leafId && leafId !== ctx.sessionManager.getLeafId()) {
          await ctx.navigateTree(leafId, { summarize: false });
          // The rewind put your message back in the editor; the conversation now contains it again.
          if (prompt && promptLabel(ctx.ui.getEditorText()) === prompt) ctx.ui.setEditorText("");
        }
        redo = undefined;
      } catch (error) {
        return ctx.ui.notify(`Redo failed: ${errorText(error)}`, "error");
      } finally {
        restoring = false;
      }
      ctx.ui.notify("Redone.", "info");
    },
  });

  pi.registerCommand("checkpoints", {
    description: "Restore the files to the snapshot taken before any earlier message of this branch",
    handler: async (_args, ctx) => {
      if (!store) return ctx.ui.notify(off(), "warning");
      if (!ctx.isIdle()) return ctx.ui.notify("Wait for the run to finish, or press esc, before /checkpoints", "warning");
      const entries = ctx.sessionManager.getBranch().filter(isCheckpoint).reverse().slice(0, 25);
      if (entries.length === 0) return ctx.ui.notify("No checkpoints on this branch yet", "info");
      const labels = entries.map((entry, n) => `${String(entries.length - n).padStart(2)} · ${relativeTime(entry.data.takenAt)} · ${entry.data.prompt || "(no text)"}`);
      const choice = await ctx.ui.select("Restore the files to the snapshot before…", labels);
      if (!choice) return;
      const entry = entries[labels.indexOf(choice)];
      const { changes, lines } = await review(entry.data.commit, entry.data.head);
      if (changes.length === 0) return ctx.ui.notify("The files already match that snapshot", "info");
      if (!(await ctx.ui.confirm("Restore these files?", [...lines, "", "The conversation stays where it is; /redo puts the files back."].join("\n")))) return;
      restoring = true;
      try {
        const { before } = await store.restore(entry.data.commit);
        redo = { commit: before.commit, leafId: ctx.sessionManager.getLeafId() };
      } catch (error) {
        return ctx.ui.notify(`Restore failed: ${errorText(error)}`, "error");
      } finally {
        restoring = false;
      }
      ctx.ui.notify(`Restored ${changes.length} file${changes.length === 1 ? "" : "s"}. /redo puts them back.`, "info");
    },
  });

  // Navigating the tree moves the conversation to an earlier point; the files should match it.
  pi.on("session_tree", async (event, ctx) => {
    if (restoring || options.restoreOnTree === "never" || !store || !ctx.hasUI) return;
    const branch = ctx.sessionManager.getBranch();
    const checkpoint = checkpointBefore(branch, branch.length - 1);
    if (!checkpoint) return;
    try {
      const { changes, lines } = await review(checkpoint.data.commit, checkpoint.data.head);
      if (changes.length === 0) return;
      if (!(await ctx.ui.confirm("Restore the files to match this point?", [...lines, "", "Keep them as they are to leave the working tree alone."].join("\n")))) return;
      restoring = true;
      const { before } = await store.restore(checkpoint.data.commit);
      redo = { commit: before.commit, leafId: event.oldLeafId };
      ctx.ui.notify(`Restored ${changes.length} file${changes.length === 1 ? "" : "s"}. /redo puts them back.`, "info");
    } catch (error) {
      ctx.ui.notify(`Restore failed: ${errorText(error)}`, "error");
    } finally {
      restoring = false;
    }
  });
}

export default function checkpoints(pi: ExtensionAPI) {
  createCheckpoints(pi, {
    git: "git",
    dataDir: `${process.env.XDG_DATA_HOME ?? `${process.env.HOME}/.local/share`}/pi/checkpoints`,
    maxFiles: 50000,
    maxFileBytes: 5 * 1024 * 1024,
    maxAgeDays: 14,
    restoreOnTree: "ask",
  });
}
