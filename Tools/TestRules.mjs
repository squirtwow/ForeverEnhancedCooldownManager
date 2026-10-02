// Rules read straight from the addon's source, beside the mock-game tests:
// Edit Mode and Blizzard's panels are never opened from addon code (only a
// click on the Raid Timers page's secure button runs the game's own
// /editmode), and the only sizes set on Blizzard's frames are Raid Timers'
// (one scale call, for the countdown, and one text height call, for raid
// warning lines). Tools/TestSkin.lua and Tools/TestRaidTimers.lua check what
// those calls do; this checks there are no others.
// Run with: node --test Tools/TestRules.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const root = new URL('../', import.meta.url);
const files = readdirSync(root).filter(name => name.endsWith('.lua'));
// Each file's code without its comments, so notes about these calls don't count.
const code = Object.fromEntries(files.map(name => [name, readFileSync(new URL(name, root), 'utf8')
  .replace(/--\[\[[\s\S]*?\]\]/g, '').replace(/--[^\n]*/g, '')]));
const count = (text, pattern) => (text.match(pattern) || []).length;
const where = pattern => files.filter(name => pattern.test(code[name]));

test('the addon files are all read', () => {
  assert.ok(files.includes('RaidTimers.lua') && files.includes('RaidTimersPage.lua') && files.length >= 20);
});

test('nothing opens Edit Mode, a panel or Cooldown Settings from addon code', () => {
  for (const pattern of [/ShowUIPanel/, /HideUIPanel/, /EnterEditMode/, /ExitEditMode/, /C_EditMode/, /CooldownViewerSettings/,
    /OpenToCategory/, /RunMacroText/, /SlashCmdList\s*(\.\s*EDITMODE|\[\s*["']EDITMODE)/, /ChatEdit_SendText/]) {
    assert.deepEqual(where(pattern), [], `${pattern} in addon code`);
  }
  // Blizzard's Edit Mode frame is only watched: hooked and asked whether it
  // shows (Bars.lua), and asked whether it shows after a click on the Raid
  // Timers page's secure button, to close the window over it.
  assert.deepEqual(where(/EditModeManagerFrame/).sort(), ['Bars.lua', 'RaidTimersPage.lua']);
  const calls = code['Bars.lua'].match(/\beditor:(\w+)/g);
  assert.deepEqual([...new Set(calls)].sort(), ['editor:HookScript', 'editor:IsShown']);
  const page = code['RaidTimersPage.lua'];
  assert.equal(count(page, /EditModeManagerFrame/g), 1);
  assert.match(page, /local editor = _G\.EditModeManagerFrame\r?\n/);
  assert.deepEqual([...new Set(page.match(/\beditor\b\s*[:.[]\s*\w*/g))], ['editor:IsShown'], 'only asked whether it shows');
  assert.equal(count(page, /\beditor\s*=[^=]/g), 1, 'set once, from Blizzard\'s, and never written on');
});

test('/editmode runs only from the secure button, a click of yours', () => {
  assert.deepEqual(where(/\/editmode/i).sort(), ['RaidTimersPage.lua']);
  const page = code['RaidTimersPage.lua'];
  assert.equal(count(page, /SetAttribute\("macrotext", "\/editmode"\)/g), 1);
  assert.equal(count(page, /"\/editmode"/g), 1, 'only as the macro text');
  assert.equal(count(page, /SetAttribute\("type", "macro"\)/g), 1);
  // One secure button, UIParent's (never a child of the window).
  assert.deepEqual(where(/SecureActionButtonTemplate|SecureActionButton|SecureHandler|SecureFrameTemplate/), ['RaidTimersPage.lua']);
  assert.equal(count(page, /CreateFrame\("Button", "FECMEditModeButton", UIParent, "SecureActionButtonTemplate"\)/g), 1);
  assert.equal(count(page, /SecureActionButtonTemplate/g), 1);
});

test('the only sizes set on Blizzard\'s frames are Raid Timers\' own two calls', () => {
  const timers = code['RaidTimers.lua'];
  assert.equal(count(timers, /:SetScale\(/g), 1, 'one scale call, in Resize');
  assert.match(timers, /local function Resize\(region, scale\)[\s\S]*?region:SetScale\(scale\)[\s\S]*?\nend/);
  // Resize is used only for the countdown's bar and big digits.
  const uses = timers.match(/Resize\(([^)]*)\)/g).filter(use => !use.startsWith('Resize(region'));
  assert.deepEqual(uses.map(use => use.replace(/,.*$/, '')).sort(),
    ['Resize(timer.bar', 'Resize(timer.digit1', 'Resize(timer.digit2'].sort());
  assert.equal(count(timers, /:SetTextHeight\(/g), 1, 'one text height call, in Height');
  assert.match(timers, /local function Height\(line, scale\)[\s\S]*?line:SetTextHeight\(height \* scale\)[\s\S]*?\nend/);
  // Nowhere else in the addon.
  assert.deepEqual(where(/SetTextHeight/), ['RaidTimers.lua']);
  // No other way to size anything: text scale, font height, ignoring the parent's scale.
  assert.deepEqual(where(/SetTextScale|SetFontHeight|SetIgnoreParentScale/), []);
  // The only other scale call is on the addon's own frame, its Buffs bar's
  // container (B:SetScale is the addon's own All bars size, in Bars.lua).
  assert.deepEqual(where(/(?<!\bB):SetScale\(/).sort(), ['Buffs.lua', 'RaidTimers.lua']);
});
