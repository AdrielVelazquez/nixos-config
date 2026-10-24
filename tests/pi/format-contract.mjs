// Runs the generated Nix entry (real formatter binaries, real Pi file-queue helper) over one sample per language.
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const [entryPath] = process.argv.slice(2);
const piRoot = process.env.PI_TEST_PACKAGE_DIR;
assert.ok(entryPath && piRoot, 'usage: PI_TEST_PACKAGE_DIR=<pi> node format-contract.mjs <entry.ts>');
const requirePi = createRequire(join(piRoot, 'package.json'));
const jiti = requirePi('jiti').createJiti(import.meta.url, { alias: { '@earendil-works/pi-coding-agent': join(piRoot, 'dist/index.js') } });

const handlers = new Map();
(await jiti.import(entryPath)).default({ on: (name, handler) => handlers.set(name, handler) });
const notices = [];

const samples = [
  ['gofumpt', 'a.go', 'package main\nfunc main(){\nx:=1\n_ = x}\n', 'package main\n\nfunc main() {\n\tx := 1\n\t_ = x\n}\n'],
  ['jq', 'a.json', '{"b":1,"a":[1,2]}', '{\n  "b": 1,\n  "a": [\n    1,\n    2\n  ]\n}\n'],
  ['nixfmt', 'a.nix', '{a=1;b=[1 2];}', '{\n  a = 1;\n  b = [\n    1\n    2\n  ];\n}\n'],
  ['ruff', 'a.py', 'x = {"a":1}\nprint( x )\n', 'x = {"a": 1}\nprint(x)\n'],
  ['ruff', 'a.pyi', 'def f( x:int )->int: ...\n', 'def f(x: int) -> int: ...\n'],
  ['stylua', 'a.lua', 'local x = {a=1}\nprint( x )\n', 'local x = { a = 1 }\nprint(x)\n'],
  ['shfmt', 'a.sh', 'if true; then\necho hi\nfi\n', 'if true; then\n  echo hi\nfi\n'],
  ['rustfmt', 'src/lib.rs', 'fn main(){let x=1;println!("{}",x);}\n', 'fn main() {\n    let x = 1;\n    println!("{}", x);\n}\n'],
  ['zig', 'a.zig', 'pub fn main() void {const x=1; _ = x;}\n', 'pub fn main() void {\n    const x = 1;\n    _ = x;\n}\n'],
  ['opentofu', 'a.tf', 'resource "a" "b" {\nname="x"\n  other   = 1\n}\n', 'resource "a" "b" {\n  name  = "x"\n  other = 1\n}\n'],
  ['biome', 'a.ts', 'const x = {a:1}\nfunction f( ){return x}\n', 'const x = { a: 1 };\nfunction f() {\n\treturn x;\n}\n'],
];

const project = await realpath(await mkdtemp(join(tmpdir(), 'pi-format-contract-')));
const bare = await realpath(await mkdtemp(join(tmpdir(), 'pi-format-bare-')));
try {
  await mkdir(join(project, 'src'));
  await writeFile(join(project, 'Cargo.toml'), '[package]\nname = "p"\nedition = "2021"\n');
  await writeFile(join(project, 'biome.json'), '{}');
  await writeFile(join(project, '.editorconfig'), 'root = true\n[*.sh]\nindent_style = space\nindent_size = 2\n');

  const call = (cwd, path) => handlers.get('tool_result')({
    type: 'tool_result', toolCallId: 'contract', toolName: 'edit', input: { path }, isError: false,
    content: [{ type: 'text', text: 'ok' }], details: undefined,
  }, { cwd, ui: { notify: message => notices.push(message) } });

  for (const [name, file, input, expected] of samples) {
    await writeFile(join(project, file), input);
    const reply = await call(project, file);
    assert.equal(await readFile(join(project, file), 'utf8'), expected, `${name} formatted ${file}`);
    assert.match(reply.content.at(-1).text, new RegExp(`^Formatted with ${name}:`), `${name} reported`);
    assert.equal(await call(project, file), undefined, `${name} is idempotent`);
  }

  // Formatters whose defaults would rewrite other styles stay out of unconfigured projects.
  await mkdir(join(bare, 'src'));
  for (const [name, file, input] of samples.filter(([name]) => name === 'shfmt' || name === 'biome')) {
    await writeFile(join(bare, file), input);
    assert.equal(await call(bare, file), undefined, `${name} needs project configuration`);
    assert.equal(await readFile(join(bare, file), 'utf8'), input);
  }

  // A syntax error leaves the file as written, with no note and no crash.
  await writeFile(join(project, 'bad.go'), 'package main\nfunc {{{\n');
  assert.equal(await call(project, 'bad.go'), undefined);
  assert.equal(await readFile(join(project, 'bad.go'), 'utf8'), 'package main\nfunc {{{\n');
  assert.deepEqual(notices, []);
  console.log(`format-contract: ${samples.length} samples formatted, gated formatters skipped without config`);
} finally {
  await rm(project, { recursive: true, force: true });
  await rm(bare, { recursive: true, force: true });
}
