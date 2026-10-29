import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { readFile, realpath, unlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const execute = promisify(execFile);
type Environment = Record<string, string | undefined>;
type Launch = { cwd: string; machine?: unknown; signal?: AbortSignal; processEnv?: Environment; runtime?: { parentSessionId?: string } };
type Factory<L extends Launch, T> = { create: (launch: L) => Promise<T>; dispose: () => Promise<void> };
type Configuration = {
  adapters: Array<{ urlEnv: string; requiredEnv: string }>;
  gitCommand?: string; pythonCommand?: string; implementation?: string; startupTimeout?: number;
};
let opening: Promise<unknown> = Promise.resolve();

function configuration(env: Environment): Configuration {
  if (!env.HEADROOM_PI_CONFIG || !env.HEADROOM_PI_STATE_DIR) throw new Error("Start Pi through the managed Headroom launcher");
  return JSON.parse(readFileSync(env.HEADROOM_PI_CONFIG, "utf8"));
}
function contract(env: Environment): Environment {
  const config = configuration(env);
  const keys = ["HEADROOM_PI_CONFIG", "HEADROOM_PI_STATE_DIR", "HEADROOM_PI_INSTANCE", "HEADROOM_PI_PROJECT",
    "HEADROOM_PI_MEMORY_DB", "HEADROOM_PROXY_URL", "PI_SUBAGENTS_TEMP_ROOT",
    ...config.adapters.flatMap(adapter => [adapter.urlEnv, adapter.requiredEnv])];
  return Object.fromEntries(keys.filter(key => env[key] !== undefined).map(key => [key, env[key]]));
}
function contextPath(sessionId: string, env: Environment) {
  return join(dirname(env.HEADROOM_PI_STATE_DIR!), "contexts", createHash("sha256").update(sessionId).digest("hex") + ".json");
}

/** Runtime-only routing metadata, not credentials. Retain it for admitted/nested and resumed runs. */
export function registerHeadroomContext(sessionId: string, env: Environment) {
  const file = contextPath(sessionId, env), temporary = file + "." + randomUUID();
  mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
  writeFileSync(temporary, JSON.stringify(contract(env)), { flag: "wx", mode: 0o600 });
  renameSync(temporary, file);
}
async function parentContext(sessionId: string | undefined, inherited: Environment) {
  if (!sessionId) return inherited;
  try { return contract(JSON.parse(await readFile(contextPath(sessionId, inherited), "utf8"))); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return inherited; throw error; }
}
async function repository(cwd: string, git: string) {
  try {
    const { stdout } = await execute(git, ["-C", cwd, "rev-parse", "--show-toplevel"], { timeout: 10_000 });
    return await realpath(stdout.trim());
  } catch { throw new Error("Managed Headroom children require a readable Git repository"); }
}
async function common(cwd: string, git: string) {
  try {
    const { stdout } = await execute(git, ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], { timeout: 10_000 });
    return await realpath(stdout.trim());
  } catch { return undefined; }
}

/** Acquires the invoking child's routing identity before native providers and MCPs initialize. */
export function createHeadroomChildFactory<L extends Launch, T>(createFactory: () => Factory<L, T>): Factory<L, T> {
  const inherited = contract(process.env), factories = new Map<string, Factory<L, T>>();
  let closed = false;
  return {
    create(launch) {
      const open = async () => {
        if (closed) throw new Error("The managed Headroom child factory is disposed");
        if (launch.machine) throw new Error("Managed Headroom children require a local native runner");
        launch.signal?.throwIfAborted();
        const parent = await parentContext(launch.runtime?.parentSessionId, inherited);
        const config = configuration(parent), git = config.gitCommand ?? "git";
        const state = JSON.parse(await readFile(join(parent.HEADROOM_PI_STATE_DIR!, "state.json"), "utf8"));
        const cwd = await realpath(launch.cwd);
        const target = cwd === state.project ? cwd : await repository(cwd, git);
        const [left, right] = await Promise.all([common(target, git), common(state.project, git)]);
        const sameRepository = target === state.project || (left !== undefined && left === right);
        let available = false;
        try {
          const started = (await readFile(`/proc/${state.managerPid}/stat`, "utf8")).split(")").slice(1).join(")").trim().split(/\s+/)[19];
          available = state.ready && !state.stopping && state.instance === parent.HEADROOM_PI_INSTANCE &&
            started === state.managerStarted && parent.HEADROOM_PROXY_URL === `http://127.0.0.1:${state.port}`;
        } catch {}
        const acquisitionRoot = sameRepository ? state.project : target;
        let env = parent, acquisition: string | undefined;
        try {
          if (!sameRepository || !available) {
            if (!config.pythonCommand || !config.implementation) throw new Error("Headroom child acquisition is not configured");
            const { stdout } = await execute(config.pythonCommand,
              ["-E", config.implementation, "--config", parent.HEADROOM_PI_CONFIG!, "--acquire", String(process.pid)],
              { cwd: acquisitionRoot, env: { ...process.env, ...parent }, timeout: ((config.startupTimeout ?? 90) + 10) * 1000 });
            const owned = JSON.parse(stdout);
            if (owned.project !== acquisitionRoot || !/^http:\/\/127\.0\.0\.1:\d+$/.test(owned.proxyURL) ||
                ![owned.stateDir, owned.instance, owned.memoryDB, owned.leasePath].every(value => typeof value === "string" && value)) {
              throw new Error("Invalid Headroom child acquisition result");
            }
            acquisition = owned.leasePath;
            env = { ...parent, HEADROOM_PI_STATE_DIR: owned.stateDir, HEADROOM_PI_INSTANCE: owned.instance,
              HEADROOM_PI_PROJECT: owned.project, HEADROOM_PI_MEMORY_DB: owned.memoryDB, HEADROOM_PROXY_URL: owned.proxyURL };
            for (const adapter of config.adapters) { env[adapter.urlEnv] = owned.proxyURL; env[adapter.requiredEnv] = "1"; }
          }
          launch.signal?.throwIfAborted();
          const values = { ...launch.processEnv, ...env };
          const previous = Object.fromEntries(Object.keys(values).map(key => [key, process.env[key]]));
          const key = env.HEADROOM_PI_STATE_DIR + ":" + env.HEADROOM_PI_INSTANCE;
          let factory = factories.get(key);
          if (!factory) { factory = createFactory(); factories.set(key, factory); }
          try { return await factory.create({ ...launch, processEnv: values }); }
          finally {
            for (const [name, value] of Object.entries(previous)) {
              if (value === undefined) delete process.env[name]; else process.env[name] = value;
            }
          }
        } finally {
          // session_start installs an independent session lease before the native factory returns.
          if (acquisition) await unlink(acquisition).catch(error => { if (error.code !== "ENOENT") throw error; });
        }
      };
      const result = opening.catch(() => {}).then(open);
      opening = result;
      return result;
    },
    async dispose() {
      closed = true;
      await opening.catch(() => {});
      await Promise.all([...factories.values()].map(factory => factory.dispose()));
      factories.clear();
    },
  };
}
