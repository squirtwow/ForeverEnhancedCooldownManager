// The game runs Lua 5.1, which refuses to load a file with a function that
// sees more than 60 of the locals around it (upvalues) or keeps more than 200
// locals alive at once. The tests run in fengari (Lua 5.3, 255 upvalues), so
// they'd load such a file anyway; this checks every file the addon ships the
// way the game would, from fengari's compiled functions. _ENV is 5.3's own
// upvalue and isn't counted. Tools never ships, so its tests aren't checked.
// Run with: node --test Tools/TestLuaLimits.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// fengari from the local Lua check kit: FENGARI, else C:\AddonDev\_Toolchain
// (beside the addons), else the old copy in %TEMP% (Tools/RunTests.mjs).
const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));
const kits = [process.env.FENGARI, join(root, '..', '_Toolchain', 'lua-check', 'node_modules', 'fengari'),
  join(tmpdir(), 'opencode', 'lua-check', 'node_modules', 'fengari')].filter(Boolean);
const { lua, lauxlib, to_luastring } = require(kits.find(kit => existsSync(kit)) ?? kits.at(-1));
const MAX_UPVALUES = 60, MAX_LOCALS = 200;

function luaFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) { if (name !== '.git' && name !== 'Tools') luaFiles(full, out) }
    else if (name.toLowerCase().endsWith('.lua')) out.push(full);
  }
  return out;
}

const text = s => s ? Buffer.from(s.realstring).toString() : '?';

function overLimits(file) {
  const L = lauxlib.luaL_newstate();
  const status = lauxlib.luaL_loadbuffer(L, readFileSync(file), null, to_luastring('@' + file));
  if (status !== 0) return [`does not load: ${lua.lua_tojsstring(L, -1)}`];
  const problems = [];
  (function visit(p) {
    const upvalues = p.upvalues.map(u => text(u.name)).filter(name => name !== '_ENV').length;
    if (upvalues > MAX_UPVALUES) problems.push(`function at line ${p.linedefined} has ${upvalues} upvalues`);
    let live = 0;
    for (const start of new Set(p.locvars.map(v => v.startpc))) {
      live = Math.max(live, p.locvars.filter(v => v.startpc <= start && start < v.endpc).length);
    }
    if (live > MAX_LOCALS) problems.push(`function at line ${p.linedefined} has ${live} locals at once`);
    p.p.forEach(visit);
  })(L.stack[L.top - 1].value.p);
  return problems;
}

test('every file the addon ships loads under the game\'s Lua limits (60 upvalues, 200 locals)', () => {
  const files = luaFiles(root);
  assert.ok(files.length > 20, 'found the addon\'s files');
  const found = files.flatMap(file => overLimits(file).map(problem => `${file.slice(root.length)}: ${problem}`));
  assert.deepEqual(found, []);
});
