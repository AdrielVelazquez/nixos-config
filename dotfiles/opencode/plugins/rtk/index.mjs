// Rewrites OpenCode shell commands through `rtk rewrite` before they run, mirroring Pi's rtk extension
// (modules/home-manager/pi/rtk.nix + dotfiles/pi/extensions/rtk.ts): all rewrite logic stays in the rtk binary.
// Exit codes from `rtk rewrite`: 0 = rewrite (stdout), 1 = no equivalent (pass through), 3 = advisory rewrite.
export default {
  id: "local.rtk",
  async setup(context) {
    const bin = (context.options && context.options.bin) || "rtk";
    const { execFile } = await import("node:child_process");

    function rewrite(command) {
      return new Promise((resolve) => {
        execFile(bin, ["rewrite", command], { timeout: 2000 }, (error, stdout) => {
          if (error && error.code !== 0 && error.code !== 3) {
            resolve(null);
            return;
          }
          resolve(stdout || "");
        });
      });
    }

    await context.shell.hook("create.before", async (event) => {
      const command = typeof event.command === "string" ? event.command.trim() : "";
      if (!command) return;
      if (command.startsWith("rtk ")) return;
      if (command === "rtk") return;
      if (process.env.RTK_DISABLED === "1") return;
      const stdout = await rewrite(command);
      if (stdout === null) return; // fail open
      const rewritten = stdout.trim();
      if (rewritten && rewritten !== command) event.command = rewritten;
    });
  },
};
