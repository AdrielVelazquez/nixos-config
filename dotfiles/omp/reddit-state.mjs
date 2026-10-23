import { constants } from 'node:fs';
import { chmod, lstat, mkdir, open, readFile, realpath, rename, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { isAbsolute, join } from 'node:path';
import { isProjectId } from './provider-core.mjs';

const initial = () => ({ version: 1, directories: {} });
const owns = info => !process.getuid || info.uid === process.getuid();
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

function validate(value) {
  if (!value || value.version !== 1 || Object.keys(value).some(key => !['version', 'directories'].includes(key)) ||
      !value.directories || typeof value.directories !== 'object' || Array.isArray(value.directories)) throw new Error('Invalid OMP project state');
  for (const [cwd, choice] of Object.entries(value.directories)) {
    if (!isAbsolute(cwd) || !choice || Object.keys(choice).some(key => key !== 'projectId') || !isProjectId(choice.projectId)) {
      throw new Error('Invalid OMP directory project state');
    }
  }
  return value;
}

async function privateDirectory(agentDir, create = false) {
  const directory = join(agentDir, 'reddit');
  if (create) await mkdir(directory, { recursive: true, mode: 0o700 });
  const info = await lstat(directory).catch(error => {
    if (error.code === 'ENOENT' && !create) return null;
    throw error;
  });
  if (info && (!info.isDirectory() || info.isSymbolicLink() || !owns(info))) throw new Error('OMP project state requires a private non-symlink directory');
  if (create) await chmod(directory, 0o700);
  return info ? directory : null;
}

async function load(agentDir) {
  const directory = await privateDirectory(agentDir);
  if (!directory) return initial();
  let file;
  try {
    file = await open(join(directory, 'projects.json'), constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const info = await file.stat();
    if (!info.isFile() || !owns(info) || info.size > 1024 * 1024) throw new Error('Invalid OMP project state file');
    return validate(JSON.parse(await file.readFile('utf8')));
  } catch (error) {
    if (error.code === 'ENOENT') return initial();
    throw new Error('Cannot read private OMP project state', { cause: error });
  } finally { await file?.close(); }
}

async function lock(directory) {
  const name = join(directory, 'projects.lock'), deadline = Date.now() + 5000;
  for (;;) {
    try {
      const handle = await open(name, 'wx', 0o600);
      try { await handle.writeFile(String(process.pid)); } finally { await handle.close(); }
      return () => unlink(name);
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const info = await lstat(name).catch(() => null);
      if (info && (!info.isFile() || info.isSymbolicLink() || !owns(info))) throw new Error('Invalid OMP project state lock');
      if (info && Date.now() - info.mtimeMs > 60_000) {
        const pid = Number(await readFile(name, 'utf8'));
        if (Number.isSafeInteger(pid) && pid > 0) {
          try { process.kill(pid, 0); } catch (probe) {
            if (probe.code === 'ESRCH') { await unlink(name).catch(() => {}); continue; }
          }
        }
      }
      if (Date.now() >= deadline) throw new Error('OMP project choices are busy; retry after the other session finishes');
      await delay(10);
    }
  }
}

export async function readProjectSelection(agentDir, cwd, configured) {
  if (configured.locked) return { ...configured };
  const directory = await realpath(cwd);
  const state = await load(agentDir);
  const choice = state.directories[directory];
  return choice ? { id: choice.projectId, source: 'directory', locked: false } : { ...configured };
}

export async function saveProjectSelection(agentDir, cwd, projectId) {
  if (projectId !== null && !isProjectId(projectId)) throw new Error('Invalid OMP project selection');
  const canonical = await realpath(cwd);
  const directory = await privateDirectory(agentDir, true);
  const release = await lock(directory);
  const temporary = join(directory, `.projects-${randomUUID()}.tmp`);
  try {
    const state = await load(agentDir);
    if (projectId === null) delete state.directories[canonical];
    else state.directories[canonical] = { projectId };
    validate(state);
    const handle = await open(temporary, 'wx', 0o600);
    try { await handle.writeFile(JSON.stringify(state, null, 2) + '\n'); await handle.sync(); }
    finally { await handle.close(); }
    const destination = join(directory, 'projects.json');
    const info = await lstat(destination).catch(error => { if (error.code === 'ENOENT') return null; throw error; });
    if (info && (!info.isFile() || info.isSymbolicLink() || !owns(info))) throw new Error('Invalid non-regular OMP project state destination');
    await rename(temporary, destination);
  } finally { await unlink(temporary).catch(() => {}); await release(); }
}
