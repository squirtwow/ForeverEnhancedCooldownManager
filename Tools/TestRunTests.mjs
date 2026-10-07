// Tools/RunTests.mjs only calls a Lua suite passed when it really finished:
// fengari exits 0 even when a suite stops half-way. Run with:
// node --test Tools/TestRunTests.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { judgeLua, judgeParser, luaKit, runLua } from './RunTests.mjs';

test('a Lua suite passes only with its closing line and no traceback', () => {
  assert.equal(judgeLua(0, 'Bars and window checks passed: 2080 assertions.\n').ok, true);
  assert.equal(judgeLua(0, 'Bars and window checks passed: 2080 assertions.\n').count, 2080);
  assert.equal(judgeLua(0, 'lua: Tools/TestBars.lua:12: boom\nstack traceback:\n\t[JS]: in function \'assert\'\n').ok, false,
    'stopped half-way, exit code 0');
  assert.equal(judgeLua(0, '').ok, false, 'nothing printed');
  assert.equal(judgeLua(1, 'Raid Timers checks passed: 162 assertions.\n').ok, false, 'a failing exit code');
  assert.equal(judgeLua(0, 'Tools/TestX.lua:3: boom\nCooldown pulse checks passed: 3 assertions.\n').ok, false, 'an error on the way');
});

test("the parser passes only with files checked and none failed", () => {
  assert.equal(judgeParser(0, 'checked 33 files, 0 failed\n').ok, true);
  assert.equal(judgeParser(0, 'FAIL  Core.lua\n      [1:2] unexpected symbol\nchecked 33 files, 1 failed\n').ok, false);
  assert.equal(judgeParser(0, 'checked 0 files, 0 failed\n').ok, false, 'nothing checked');
  assert.equal(judgeParser(0, '').ok, false);
});

test('a real fengari run: a failing suite fails though fengari exits 0, a finished one passes',
  { skip: !luaKit() && 'the Lua kit is not on this machine' }, async () => {
    const folder = mkdtempSync(join(tmpdir(), 'fecm-runtests-'));
    try {
      const failing = join(folder, 'Failing.lua'), passing = join(folder, 'Passing.lua');
      writeFileSync(failing, 'assert(false, "boom")\nio.write("Never checks passed: 1 assertions.\\n")\n');
      writeFileSync(passing, 'local checks = 1\nio.write("Tiny checks passed: " .. checks .. " assertions.\\n")\n');
      const bad = await runLua(luaKit(), failing), good = await runLua(luaKit(), passing);
      assert.equal(bad.ok, false, bad.output);
      assert.match(bad.output, /boom/);
      assert.equal(good.ok, true, good.output);
      assert.equal(good.count, 1);
    } finally {
      rmSync(folder, { recursive: true, force: true });
    }
  });

test('a suite stuck in a loop is stopped and fails', { skip: !luaKit() && 'the Lua kit is not on this machine' }, async () => {
  const folder = mkdtempSync(join(tmpdir(), 'fecm-runtests-'));
  try {
    const stuck = join(folder, 'Stuck.lua');
    writeFileSync(stuck, 'while true do end\n');
    const result = await runLua(luaKit(), stuck, 1500);
    assert.equal(result.ok, false, result.output);
    assert.match(result.output, /timed out after 2s/);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});

test('a name that matches nothing fails instead of passing with nothing run', () => {
  const runner = fileURLToPath(new URL('./RunTests.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [runner, '--only', 'TestNoSuchSuite'], { encoding: 'utf8' });
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /nothing to run/);
});
