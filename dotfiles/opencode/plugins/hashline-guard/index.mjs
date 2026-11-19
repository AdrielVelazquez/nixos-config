// Checks the hashline tools against the same read and edit permission rules as OpenCode's built-in tools. The hashline
// plugin serves explicit reads without consulting those rules, so this plugin asserts them before each call. It also
// refuses OpenCode's built-in edit and apply_patch, which bypass anchors, so models use the anchored tools instead.
import { resolve } from "node:path";

const READ_TOOLS = new Set(["read", "anchor_grep"]);
const EDIT_TOOLS = new Set(["replace", "replace_match", "insert", "copy", "move", "undo_last_change"]);
const REFUSED_NATIVE = new Set(["edit", "apply_patch"]);

export default {
  id: "local.hashline-guard",
  async setup(context) {
    const directory = context.location.directory;
    const registration = await context.tool.hook("execute.before", async (event) => {
      if (REFUSED_NATIVE.has(event.tool)) {
        throw new Error(
          `${event.tool} is disabled in this project. Use hashline replace, replace_match or insert with the anchors from read.`,
        );
      }
      if (!READ_TOOLS.has(event.tool) && !EDIT_TOOLS.has(event.tool)) return;
      const files = [event.input?.file, event.input?.destFile].filter((value) => typeof value === "string");
      if (files.length === 0) return;
      await context.permission.assert({
        sessionID: event.sessionID,
        agent: event.agent,
        source: { type: "tool", messageID: event.messageID, id: event.id },
        action: READ_TOOLS.has(event.tool) ? "read" : "edit",
        resources: files.flatMap((file) => [file, resolve(directory, file)]),
      });
    });
    return async () => {
      await registration.dispose();
    };
  },
};
