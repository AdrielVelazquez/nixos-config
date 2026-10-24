// Working-tree checkpoints for Pi, kept in a private git repository so the project's own repository, index and
// refs are never touched. A snapshot is everything git would add (`git add -A`, honouring .gitignore) written as a
// tree; restoring one makes the working tree match it, removing what was created since and bringing back what was
// deleted. No Pi runtime state lives here, so the whole module is exercised by a plain node test against real git.
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

export interface CheckpointConfig {
  /** The git executable. */
  git: string;
  /** Directory holding one private repository per project. */
  dataDir: string;
  /** A project with more files than this is not checkpointed (a first snapshot would hash them all). */
  maxFiles: number;
  /** A file larger than this is left out of snapshots. */
  maxFileBytes: number;
}

export interface Taken {
  /** A commit in the private repository whose tree is the snapshot; kept alive by a ref. */
  commit: string;
  tree: string;
  /** The project repository's HEAD when the snapshot was taken: history that a restore cannot rewind. */
  head?: string;
}

/** A path that differs between two trees, as `git diff-tree` reports it. */
export interface Change {
  status: "A" | "M" | "D";
  path: string;
}

export class CheckpointError extends Error {}

const split0 = (output: string): string[] => output.split("\0").filter(Boolean);
const escapePattern = (path: string): string => path.replace(/[\\*?[\]!#]/g, "\\$&").replace(/^ | $/g, (space) => `\\${space}`);

/** Env of a git call that must not see the caller's repository: the variables git itself would obey are dropped. */
function cleanEnv(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env };
  for (const key of Object.keys(env)) if (key.startsWith("GIT_")) delete env[key];
  return { ...env, GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0", ...extra };
}

function exec(file: string, args: string[], options: { cwd?: string; env: NodeJS.ProcessEnv; timeout?: number; label?: string }): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(file, args, { cwd: options.cwd, env: options.env, timeout: options.timeout ?? 120_000, maxBuffer: 512 * 1024 * 1024, encoding: "utf8" }, (error, stdout, stderr) => {
      if (error) reject(new CheckpointError(`git ${options.label ?? args.slice(0, 2).join(" ")}: ${(stderr || error.message).trim().split("\n")[0]}`));
      else resolve(stdout);
    });
  });
}

/** The directory a project's work tree is rooted at: its git top level, or the directory itself outside git. */
async function projectRoot(cwd: string, git: string): Promise<string> {
  try {
    const top = (await exec(git, ["rev-parse", "--show-toplevel"], { cwd, env: cleanEnv() })).trim();
    if (top) return realpathSync(top);
  } catch {
    // Not a git work tree: the directory is the project.
  }
  return realpathSync(cwd);
}

const OVERRIDES = [
  "core.hooksPath=/dev/null",
  "commit.gpgsign=false",
  "core.autocrlf=false",
  "core.safecrlf=false",
  "core.quotepath=false",
  "core.fsmonitor=false",
  "core.untrackedCache=false",
  "gc.auto=0",
].flatMap((setting) => ["-c", setting]);

export class Checkpoints {
  readonly root: string;
  /** The private repository. */
  readonly dir: string;
  private readonly sessionKey: string;
  private readonly config: CheckpointConfig;

  // No parameter properties: the module is imported by plain node in the tests, which only strips types.
  private constructor(root: string, dir: string, sessionKey: string, config: CheckpointConfig) {
    this.root = root;
    this.dir = dir;
    this.sessionKey = sessionKey;
    this.config = config;
  }

  /** The checkpoints of the project that contains `cwd`; each session has its own index so concurrent sessions never collide. */
  static async open(cwd: string, sessionId: string, config: CheckpointConfig): Promise<Checkpoints> {
    const root = await projectRoot(cwd, config.git);
    if (root === "/" || root === process.env.HOME) throw new CheckpointError(`${root} is not a project directory`);
    const dir = join(config.dataDir, `${basename(root)}-${createHash("sha1").update(root).digest("hex").slice(0, 12)}`);
    const store = new Checkpoints(root, dir, createHash("sha1").update(sessionId).digest("hex").slice(0, 16), config);
    if (!existsSync(join(dir, "HEAD"))) {
      mkdirSync(dir, { recursive: true, mode: 0o700 });
      await store.git(["init", "--quiet", "--template="]);
    }
    mkdirSync(join(dir, "info"), { recursive: true });
    return store;
  }

  /** The ref namespace of this session's snapshots. */
  get name(): string {
    return this.sessionKey;
  }

  private get indexFile(): string {
    return join(this.dir, `index-${this.sessionKey}`);
  }

  private git(args: string[], extra: Record<string, string> = {}, timeout?: number): Promise<string> {
    return exec(this.config.git, [...OVERRIDES, ...args], {
      cwd: this.root,
      timeout,
      label: args.slice(0, 2).join(" "),
      env: cleanEnv({
        GIT_DIR: this.dir,
        GIT_WORK_TREE: this.root,
        GIT_INDEX_FILE: this.indexFile,
        GIT_AUTHOR_NAME: "pi",
        GIT_AUTHOR_EMAIL: "pi@localhost",
        GIT_COMMITTER_NAME: "pi",
        GIT_COMMITTER_EMAIL: "pi@localhost",
        ...extra,
      }),
    });
  }

  /** The project repository's HEAD, when there is one. */
  async head(): Promise<string | undefined> {
    try {
      return (await exec(this.config.git, ["rev-parse", "--verify", "HEAD"], { cwd: this.root, env: cleanEnv() })).trim() || undefined;
    } catch {
      return undefined;
    }
  }

  /**
   * Stage the working tree into the session's index and return its tree. Nested repositories and files over the size
   * limit are excluded first: `git add -A` fails outright on a nested repository without a commit, and one large
   * file would cost every snapshot.
   */
  async tree(): Promise<string> {
    const first = !existsSync(this.indexFile);
    const others = split0(await this.git(["ls-files", "-o", "--exclude-standard", "-z"]));
    if (first && others.length > this.config.maxFiles) {
      throw new CheckpointError(`${others.length} files; checkpoints stop at ${this.config.maxFiles} (a first snapshot would hash them all)`);
    }
    const excludeFile = join(this.dir, "info", "exclude");
    const known = new Set(existsSync(excludeFile) ? readFileSync(excludeFile, "utf8").split("\n") : []);
    const fresh: string[] = [];
    for (const entry of others) {
      let pattern: string | undefined;
      if (entry.endsWith("/")) pattern = `/${escapePattern(entry)}`;
      else {
        try {
          if (statSync(join(this.root, entry)).size > this.config.maxFileBytes) pattern = `/${escapePattern(entry)}`;
        } catch {
          // Gone between listing and stat: the add below sees the same.
        }
      }
      if (pattern && !known.has(pattern)) {
        known.add(pattern);
        fresh.push(pattern);
      }
    }
    if (fresh.length) appendFileSync(excludeFile, `${fresh.join("\n")}\n`);
    await this.git(["add", "-A", "--ignore-errors"], {}, 300_000);
    return (await this.git(["write-tree"])).trim();
  }

  /** Snapshot the working tree and keep it under `refs/pi/<name>/…`. */
  async snapshot(label: string, name: string = this.sessionKey): Promise<Taken> {
    const tree = await this.tree();
    const commit = (await this.git(["commit-tree", tree, "-m", label.slice(0, 200)])).trim();
    await this.git(["update-ref", `refs/pi/${name}/${Date.now()}-${commit.slice(0, 8)}`, commit]);
    return { commit, tree, head: await this.head() };
  }

  /** What differs between two commits (or trees), in the direction `from` to `to`. */
  async diff(from: string, to: string): Promise<Change[]> {
    const fields = split0(await this.git(["diff-tree", "-r", "--name-status", "--no-renames", "-z", from, to]));
    const changes: Change[] = [];
    for (let i = 0; i + 1 < fields.length; i += 2) {
      const status = fields[i][0];
      if (status === "A" || status === "M" || status === "D") changes.push({ status, path: fields[i + 1] });
    }
    return changes;
  }

  /** What restoring `target` would change in the working tree right now. */
  async preview(target: string): Promise<Change[]> {
    return this.diff(await this.tree(), target);
  }

  /**
   * Make the working tree match `target`. The tree as it is now is snapshotted first, so the restore can itself be
   * undone: the returned `before` is what to restore to go back.
   */
  async restore(target: string, name: string = this.sessionKey): Promise<{ before: Taken; changes: Change[] }> {
    const before = await this.snapshot("before restore", name);
    const targetTree = (await this.git(["rev-parse", `${target}^{tree}`])).trim();
    const changes = await this.diff(before.tree, targetTree);
    if (changes.length > 0) await this.git(["read-tree", "--reset", "-u", targetTree], {}, 300_000);
    return { before, changes };
  }

  /** The tree of a commit, or undefined when it is not (or no longer) in the repository. */
  async treeOf(commit: string): Promise<string | undefined> {
    try {
      return (await this.git(["rev-parse", "--verify", `${commit}^{tree}`])).trim();
    } catch {
      return undefined;
    }
  }

  /** Drop snapshots older than `maxAgeMs` and the indexes of sessions that have not run for as long. */
  async prune(maxAgeMs: number, now = Date.now()): Promise<number> {
    const cutoff = Math.floor((now - maxAgeMs) / 1000);
    const listing = await this.git(["for-each-ref", "--format=%(refname) %(committerdate:unix)", "refs/pi/"]);
    let removed = 0;
    for (const line of listing.split("\n").filter(Boolean)) {
      const [ref, stamp] = line.split(" ");
      if (Number(stamp) < cutoff) {
        await this.git(["update-ref", "-d", ref]);
        removed++;
      }
    }
    for (const file of readdirSync(this.dir)) {
      if (!file.startsWith("index-") || file === basename(this.indexFile)) continue;
      try {
        if (statSync(join(this.dir, file)).mtimeMs < now - maxAgeMs) unlinkSync(join(this.dir, file));
      } catch {
        // Another session removed it first.
      }
    }
    // Unreferenced objects go too, but never ones young enough to belong to a snapshot another session is writing.
    if (removed > 0) await this.git(["gc", "--quiet", "--prune=1.hour.ago"], {}, 600_000).catch(() => undefined);
    return removed;
  }
}

/** `3m ago`, `2h ago`, `5d ago`. */
export function relativeTime(then: number, now = Date.now()): string {
  const seconds = Math.max(0, Math.round((now - then) / 1000));
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

/**
 * The changes a restore would make, as the lines of a confirmation. `changes` run from the working tree to the
 * snapshot, so a path the snapshot has and the tree lacks is brought back, and one the tree has and the snapshot lacks
 * is removed.
 */
export function describeRestore(changes: Change[], limit = 12): string[] {
  const mark = { A: "+ restore", M: "↺ revert ", D: "− remove " } as const;
  const order = { M: 0, A: 1, D: 2 } as const;
  const sorted = [...changes].sort((a, b) => order[a.status] - order[b.status] || a.path.localeCompare(b.path));
  const lines = sorted.slice(0, limit).map((change) => `${mark[change.status]} ${change.path}`);
  if (sorted.length > limit) lines.push(`… and ${sorted.length - limit} more`);
  return lines;
}

/** The first line of a prompt, shortened, for the checkpoint list. */
export function promptLabel(prompt: string, max = 72): string {
  const line = prompt.trim().split("\n")[0].replace(/\s+/g, " ");
  return line.length > max ? `${line.slice(0, max - 1)}…` : line;
}
