// Tools/TestRaidTimers.lua runs on the same mock game as Tools/TestBars.lua: a
// copy of everything TestBars.lua builds before its first test, so each file
// runs on its own. This checks the copy still matches. After changing
// TestBars' mocks, copy them across with: node Tools/TestMockSync.mjs --write
// Run with: node --test Tools/TestMockSync.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';

const path = name => new URL(`./${name}`, import.meta.url);
// Where each file's own tests start, after the mock game.
const BARS_TESTS = '-- Spellbook: one entry per spell';
const RAID_TESTS = "-- Blizzard's raid timer frames";

// A test file in three: its opening comment, the mock game, then its tests.
function parts(name, marker) {
  const text = readFileSync(path(name), 'utf8');
  const lines = text.split(/\r?\n/);
  const mocks = lines.findIndex(line => !line.startsWith('--'));
  const tests = lines.findIndex(line => line.startsWith(marker));
  assert.ok(mocks > 0 && tests > mocks, `${name}: an opening comment, the mock game, then "${marker}"`);
  return {
    eol: text.includes('\r\n') ? '\r\n' : '\n',
    intro: lines.slice(0, mocks),
    mocks: lines.slice(mocks, tests),
    tests: lines.slice(tests),
  };
}

if (process.argv.includes('--write')) {
  const bars = parts('TestBars.lua', BARS_TESTS);
  const raid = parts('TestRaidTimers.lua', RAID_TESTS);
  writeFileSync(path('TestRaidTimers.lua'), [...raid.intro, ...bars.mocks, ...raid.tests].join(raid.eol));
  console.log(`TestRaidTimers.lua: ${bars.mocks.length} lines of mock game copied from TestBars.lua`);
} else {
  test('TestRaidTimers.lua runs on the same mock game as TestBars.lua', () => {
    const bars = parts('TestBars.lua', BARS_TESTS);
    const raid = parts('TestRaidTimers.lua', RAID_TESTS);
    const length = Math.max(bars.mocks.length, raid.mocks.length);
    let first = -1;
    for (let i = 0; i < length && first < 0; i++) if (bars.mocks[i] !== raid.mocks[i]) first = i;
    assert.equal(first, -1, first < 0 ? '' : `TestRaidTimers.lua line ${raid.intro.length + first + 1} `
      + `differs from TestBars.lua line ${bars.intro.length + first + 1}:\n  ${raid.mocks[first]}\n  ${bars.mocks[first]}\n`
      + 'Copy the mock game across with: node Tools/TestMockSync.mjs --write');
    assert.ok(bars.mocks.length > 300, 'the whole mock game compared');
  });
}
