// Rules read straight from the addon's source, beside the mock-game tests:
// Edit Mode and Blizzard's panels are never opened from addon code (only a
// click on the Raid Timers page's secure button runs the game's own
// /editmode), and the only sizes set on Blizzard's frames are Raid Timers'
// (one scale call, for the countdown, and one text height call, for raid
// warning lines). Tools/TestSkin.lua and Tools/TestRaidTimers.lua check what
// those calls do; this checks there are no others. Also: the .toc loads every
// file once, in order, and the Cooldown pulse only hands cooldowns on (it
// never reads one's times, only whether it's on hold) and never takes the
// mouse but for the box that moves it. And the pulse's link with Forever
// Enhanced Cooldown Pulse: one shared global, made only when missing, its
// code the same as that addon's Link.lua when it's beside this one.
// Run with: node --test Tools/TestRules.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';

const root = new URL('../', import.meta.url);
const files = readdirSync(root).filter(name => name.endsWith('.lua'));
// Code without its comments, so notes about these calls don't count.
const bare = text => text.replace(/--\[\[[\s\S]*?\]\]/g, '').replace(/--[^\n]*/g, '');
const code = Object.fromEntries(files.map(name => [name, bare(readFileSync(new URL(name, root), 'utf8'))]));
const count = (text, pattern) => (text.match(pattern) || []).length;
const where = pattern => files.filter(name => pattern.test(code[name]));

test('the addon files are all read', () => {
  assert.ok(files.includes('RaidTimers.lua') && files.includes('RaidTimersPage.lua') && files.length >= 20);
});

test('the .toc loads every file once, each after what it needs', () => {
  const toc = readFileSync(new URL('ForeverEnhancedCooldownManager.toc', root), 'utf8').split(/\r?\n/)
    .filter(line => line.endsWith('.lua'));
  assert.deepEqual([...toc].sort(), [...files].sort(), 'every .lua file in the folder, and no other');
  assert.equal(new Set(toc).size, toc.length, 'each once');
  const at = name => toc.indexOf(name);
  // The pulse watches with the bars' spell list; its page follows Raid Timers' under More, both before the window.
  assert.ok(at('Spells.lua') < at('Pulse.lua') && at('Bars.lua') < at('Pulse.lua'), 'Pulse.lua after Spells.lua and Bars.lua');
  // A share string's keys are checked with Spells.lua's own reading of a pinned key.
  assert.ok(at('Spells.lua') < at('ProfileShare.lua'), 'ProfileShare.lua after Spells.lua');
  assert.ok(at('RaidTimersPage.lua') < at('PulsePage.lua') && at('PulsePage.lua') < at('Window.lua'),
    'PulsePage.lua after RaidTimersPage.lua, before Window.lua');
  assert.equal(at('Core.lua'), 0, 'Core.lua first');
});

test('the Cooldown pulse hands cooldowns on, never reads one, and takes no mouse but to move it', () => {
  const pulse = code['Pulse.lua'];
  // A duration object or a cooldown frame is never asked anything.
  for (const pattern of [/IsActive/, /IsZero/, /GetRemaining/, /GetElapsed/, /GetTotal/, /Evaluate/, /GetCooldownTimes/,
    /GetCooldownDuration\b/, /cooldown:IsShown/, /cooldown:IsVisible/, /startTime/, /modRate/, /isActive/]) {
    assert.equal(pattern.test(pulse), false, `${pattern} in Pulse.lua`);
  }
  // One plain question, whether a spell's cooldown is on hold: only its field
  // that's never secret is read, and nothing else of it.
  assert.equal(count(pulse, /GetSpellCooldown\(/g), 1, 'C_Spell.GetSpellCooldown, once');
  assert.equal(count(pulse, /C_Spell\.GetSpellCooldown and C_Spell\.GetSpellCooldown\(watch\.spellID\)/g), 1);
  assert.deepEqual([...new Set(pulse.match(/\binfo\.\w+/g))], ['info.isEnabled'], 'only isEnabled is read');
  assert.equal(count(pulse, /GetSpellCooldownDuration\(watch\.spellID, true\)/g), 1, 'asked for once, without the global cooldown');
  assert.equal(count(pulse, /SetCooldownFromDurationObject\(duration\)/g), 1, 'and handed straight on');
  // The one frame that takes the mouse: the box that moves it.
  assert.equal(count(pulse, /EnableMouse\(true\)/g), 1);
  assert.match(pulse, /mover = CreateFrame\("Frame", "FECMPulseMover", UIParent, "BackdropTemplate"\)[\s\S]*?mover:EnableMouse\(true\)/);
  assert.equal(count(pulse, /EnableMouse\(false\)/g), 4, 'the pulse, its icon, the watchers and their frame');
  assert.deepEqual(where(/FECMPulse\b/), ['Pulse.lua']);
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

// The pulse link's shared part, from "local link = _G.ForeverPulseLink" to
// the end of the block that puts its functions in: each line trimmed, blank
// ones left out, and each copy's name for its version number made the same.
function linkBlock(text, version) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex(line => line.startsWith('local link = _G.ForeverPulseLink'));
  const open = lines.findIndex((line, i) => i > start && line.startsWith('if type(link.version)'));
  const end = lines.findIndex((line, i) => i > open && line.trimEnd() === 'end');
  assert.ok(start >= 0 && open > start && end > open, 'the link\'s shared part found');
  return lines.slice(start, end + 1).map(line => line.trim().split(version).join('VERSION')).filter(Boolean);
}
const pulseLink = new URL('../../ForeverEnhancedCooldownPulse/Link.lua', import.meta.url);

test('the pulse link: one shared global, made only when missing, its functions only from a newer version', () => {
  const pulse = code['Pulse.lua'];
  assert.deepEqual(where(/ForeverPulseLink/), ['Pulse.lua'], 'only the pulse uses it');
  assert.match(pulse, /local link = _G\.ForeverPulseLink\r?\nif type\(link\) ~= "table" then\r?\n\s+link = \{\}\r?\n\s+_G\.ForeverPulseLink = link\r?\nend/,
    'made only when missing, never replaced');
  assert.equal(count(pulse, /_G\.ForeverPulseLink\s*=/g), 1, 'set in one place');
  assert.match(pulse, /local LINK_VERSION = 1\b/);
  assert.match(pulse, /local LINK_RANK = 2\b/, 'rank 2: with both on, this one wins');
  const block = linkBlock(pulse, 'LINK_VERSION');
  assert.equal(block[3 + block.indexOf('if type(link) ~= "table" then')], 'end');
  assert.ok(block.includes('if type(link.version) ~= "number" or link.version < VERSION then'), 'its functions only from a newer version');
  for (const name of ['Register(key, owner)', 'Notify(from)', 'Runner()']) {
    assert.ok(block.includes(`function link:${name}`), `link:${name} in the shared part`);
  }
  // Registered once, by its folder name, as the contract has it.
  assert.equal(count(pulse, /pcall\(link\.Register, link, ADDON, \{/g), 1);
  assert.match(pulse, /local ADDON, ns = \.\.\./);
});

test('the pulse link is the same code as Forever Enhanced Cooldown Pulse\'s Link.lua, when it\'s there',
  { skip: !existsSync(pulseLink) && 'not beside this addon' }, () => {
    const theirs = bare(readFileSync(pulseLink, 'utf8'));
    const ours = code['Pulse.lua'];
    assert.deepEqual(linkBlock(ours, 'LINK_VERSION'), linkBlock(theirs, 'L.VERSION'), 'the shared part matches, line for line');
    assert.equal(theirs.match(/L\.VERSION = (\d+)/)[1], ours.match(/local LINK_VERSION = (\d+)/)[1], 'the same version');
    // That addon knows this one by its folder name and rank, and ranks itself lower.
    assert.match(theirs, /L\.MANAGER = "ForeverEnhancedCooldownManager"/);
    const rank = Number(ours.match(/local LINK_RANK = (\d+)/)[1]);
    assert.equal(Number(theirs.match(/L\.MANAGER_RANK = (\d+)/)[1]), rank, 'this one\'s rank as that one expects it');
    assert.ok(Number(theirs.match(/L\.RANK = (\d+)/)[1]) < rank, 'that one\'s rank lower, so this one wins with both on');
  });

// Never the game's tooltip: an addon writing into it taints it, and in
// Forever it then breaks on your hidden health every frame it shows a player
// (thousands of errors, 2026-10-06). The addon's own (Theme.lua T:ShowTip).
// Every way in: GameTooltip and its helpers (GameTooltip_SetDefaultAnchor),
// the one the game picks (GetAppropriateTooltip), and the item, comparison,
// embedded and shared ones.
test("never the game's tooltip", () => {
  const ways = [/\bGameTooltip/, /GetAppropriateTooltip/, /ItemRefTooltip/, /ShoppingTooltip/, /EmbeddedItemTooltip/,
    /SharedTooltip/, /TooltipDataProcessor/, /\bTooltipUtil\b/, /NamePlateTooltip/, /\b\w*Tooltip_\w+\s*\(/];
  for (const pattern of ways) assert.deepEqual(where(pattern), [], `${pattern} in addon code`);
  // What the old rule (\bGameTooltip\b) let through is caught now.
  for (const sample of ['GameTooltip_SetDefaultAnchor(tip, UIParent)', 'GetAppropriateTooltip():SetOwner(self)', 'ItemRefTooltip:Hide()']) {
    assert.ok(ways.some(pattern => pattern.test(sample)), sample);
  }
});

// The game's settings (CVars) are only ever changed by a click of yours: the
// Turn on buttons for Blizzard's Cooldown Manager and Personal Resource
// Display (Window.lua) and the Layout page's display tick, through
// ns.TurnOn and ns.TurnOff (Core.lua), which only ever set those two.
// Tools/TestBars.lua checks nothing is written as the addon loads.
test("the game's settings change only through ns.TurnOn and ns.TurnOff, from your clicks", () => {
  const writers = /\b(SetCVar\w*|ConsoleExec|RegisterCVar|SetCVarToDefault|ResetTestCVars)\b/;
  assert.deepEqual(where(writers), ['Core.lua'], 'files writing CVars');
  const core = code['Core.lua'];
  const body = name => core.match(new RegExp(`\\nfunction ns\\.${name}\\(cvar\\)\\r?\\n([\\s\\S]*?)\\r?\\nend\\r?\\n`))?.[1] ?? '';
  const on = body('TurnOn'), off = body('TurnOff');
  assert.equal(count(on, /pcall\(C_CVar\.SetCVar, cvar, "1"\)/g), 1, 'TurnOn sets the one it is given to 1');
  assert.equal(count(off, /pcall\(C_CVar\.SetCVar, cvar, "0"\)/g), 1, 'TurnOff sets it to 0');
  assert.ok(/InCombatLockdown\(\)/.test(on) && /InCombatLockdown\(\)/.test(off), 'never in a fight');
  const outside = core.replace(on, '').replace(off, '');
  assert.equal(count(outside, new RegExp(`${writers.source}\\s*[,(]`, 'g')), 0, 'no CVar written anywhere else in Core.lua');
  // Who asks, and for what: the three switches, each a click of yours.
  const calls = files.flatMap(name => [...code[name].matchAll(/(?<!function )ns\.(TurnOn|TurnOff)\(([^)]*)\)/g)]
    .map(match => `${name} ${match[1]}(${match[2]})`)).sort();
  assert.deepEqual(calls, ['LayoutPage.lua TurnOff("nameplateShowSelf")', 'LayoutPage.lua TurnOn("nameplateShowSelf")',
    'Window.lua TurnOn("cooldownViewerEnabled")', 'Window.lua TurnOn("nameplateShowSelf")']);
  const window = code['Window.lua'], layout = code['LayoutPage.lua'];
  assert.match(window, /local function TurnOnManager\(\)\r?\n\s+local on, why = ns\.TurnOn\("cooldownViewerEnabled"\)/);
  assert.match(window, /managerOn:SetScript\("OnClick", TurnOnManager\)/, "the Cooldown Manager's Turn on button");
  assert.match(window, /personalOn:SetScript\("OnClick", function\(\)\r?\n\s+local on, why = ns\.TurnOn\("nameplateShowSelf"\)/,
    "the display's Turn on button");
  assert.match(layout, /local shown = Tick\("Show the Personal Resource Display", \d+,\r?\n[^\n]*function\(self\)\r?\n\s+local on, why\r?\n\s+if self:GetChecked\(\) then on, why = ns\.TurnOn/,
    "the Layout page's tick");
});

// Answers the game may keep secret in a fight are never compared, tested or
// used in sums until Open() (or issecretvalue) says they can be read: a
// secret compared errors in the game ("attempt to compare ... a secret
// number value, while execution tainted by ..."). The mock game's secrets
// catch most of this as the tests run, but Lua can't make `secret == true`
// or `if secret then` error, so this reads it from the source: after each
// answer is taken, every comparison, test or sum with it within its
// function needs an Open() of it first: on the same line, in the `if` it
// sits in, or in an `if not Open(...) then return` before it.
// Keybinds.lua's Call(fn, ...) runs one of these for it (GetActionInfo,
// GetMacroItem, C_ActionBar's questions).
const SECRET_ANSWERS = ['GetInventoryItemCooldown', 'C_Item.GetItemCooldown', 'C_Item.GetItemCount', 'C_Item.IsUsableItem',
  'C_Item.IsEquippedItem', 'C_Spell.IsSpellUsable', 'C_Spell.IsSpellInRange', 'C_Spell.SpellHasRange', 'UnitCanAttack',
  'IsSpellOverlayed', 'UnitCastingInfo', 'UnitChannelInfo', 'GetInventoryItemCount', 'UnitPower', 'Call'];
// Answers the game's events hand on, which can be secret too: the cast bar's
// cast ID and who broke the channel (UNIT_SPELLCAST_*, secret when the
// unit's casts are), and the swing's time and hand (PLAYER_SWING).
const SECRET_PARAMETERS = { 'CastBar.lua': { 'C:Event': ['id', 'interruptedBy'], 'C:Swing': ['duration', 'kind'] } };
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const indent = line => line.match(/^\s*/)[0].length;
// From line i to the end of its function, each compare, test or sum with
// `name` needs an Open() of it first.
function follow(lines, i, name, found) {
  const v = escape(name);
  // Compared, in a sum or joined, or tested (if x, not x, x and, x or).
  const use = new RegExp(`(?<![\\w.:])${v}\\s*(==|~=|<=|>=|<|>|\\.\\.|[-+*/%^])|(==|~=|<=|>=|<|>|\\.\\.|[-+*/%^])\\s*${v}(?![\\w(])`
    + `|\\bnot\\s+${v}\\b|(?<![\\w.:])${v}\\s+(and|or)\\b|\\b(if|elseif|while)\\s+${v}\\s+(then|do)\\b`);
  const check = new RegExp(`(Open|issecretvalue|Secret)\\(${v}\\)`);
  // Made safe in place: x = Word(x) or Number(x) (Keybinds.lua, both Open() first).
  const cleaned = new RegExp(`^\\s*${v}\\s*=\\s*(Word|Number)\\(${v}\\)\\s*$`);
  let always = false, block = -1; // guarded from here on; guarded while deeper than this
  for (let j = i + 1; j < lines.length && !/^(end|function|local function)\b/.test(lines[j]); j++) {
    const text = lines[j];
    if (block >= 0 && text.trim() && indent(text) <= block) block = -1;
    const at = text.search(use);
    if (at >= 0 && !always && block < 0 && !check.test(text.slice(0, at + 1))) {
      found.push(`line ${j + 1}: ${name} (${text.trim()})`);
    }
    if (cleaned.test(text)) always = true;
    if (check.test(text) && !/\bor\b/.test(text)) {
      // Leaves early unless it's open, or puts a plain value in its place:
      // `if not Open(x) then return`, `if not (Open(x) and ...) then` with a
      // return in its block, `if not Open(x) then x = true end`. Not
      // `if not other and Open(x) and x == y then`: that tests other.
      let exits = /\bthen\s+return\b/.test(text) || new RegExp(`\\bthen\\s+${v}\\s*=(?!=)`).test(text);
      if (!exits && /\bthen\s*$/.test(text)) {
        const body = [];
        for (let k = j + 1; k < lines.length && (!lines[k].trim() || indent(lines[k]) > indent(text)); k++) body.push(lines[k]);
        const depth = body.find(line => line.trim()) ? indent(body.find(line => line.trim())) : -1;
        exits = body.some(line => line.trim() && indent(line) === depth && /^\s*return\b/.test(line));
      }
      if (/^\s*if not\s*(\(|(Open|issecretvalue|Secret)\()/.test(text) && exits) always = true;
      else if (/^\s*if\b.*\bthen\s*$/.test(text)) block = indent(text);
    }
  }
}
function unguarded(source, parameters = {}) {
  // Each line with its strings emptied, so "usable %s" in a report isn't a sum.
  const lines = source.split(/\r?\n/).map(line => line.replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""')), found = [];
  let taken = 0;
  lines.forEach((line, i) => {
    for (const api of SECRET_ANSWERS) {
      const left = line.match(new RegExp(`((?:\\b\\w+\\s*,\\s*)*\\b\\w+)\\s*=(?!=)\\s*(?:[\\w.()" ,]+?\\s+and\\s+)?(?:\\w+\\.)?${escape(api)}\\(`));
      if (!left) continue;
      taken++;
      for (const name of left[1].split(',').map(part => part.trim()).filter(part => part && part !== '_')) {
        follow(lines, i, name, found);
      }
    }
  });
  for (const [fn, names] of Object.entries(parameters)) {
    const i = lines.findIndex(line => new RegExp(`^function ${escape(fn)}\\(`).test(line));
    if (i < 0) {
      found.push(`function ${fn} not found`);
      continue;
    }
    taken++;
    for (const name of names) {
      if (!new RegExp(`\\b${escape(name)}\\b`).test(lines[i])) found.push(`${fn} has no ${name}`);
      follow(lines, i, name, found);
    }
  }
  return { found, taken };
}

test('answers the game may keep secret are read with Open() first', () => {
  let taken = 0;
  const found = files.flatMap(name => {
    const result = unguarded(code[name], SECRET_PARAMETERS[name]);
    taken += result.taken;
    return result.found.map(problem => `${name} ${problem}`);
  });
  assert.ok(taken >= 20, `the answers found (${taken})`);
  assert.deepEqual(found, [], 'compared or summed before Open()');
  // Word and Number only ever give back an answer Open() passed.
  assert.match(code['Keybinds.lua'], /local function Number\(v\) if Open\(v\) and /);
  assert.match(code['Keybinds.lua'], /local function Word\(v\) if Open\(v\) and /);
  // The check finds what the mock game can't.
  const sample = 'local function Lit(id)\n    local usable = C_Spell.IsSpellUsable(id)\n    return usable == true\nend\n';
  assert.equal(unguarded(sample).found.length, 1, 'usable == true with no Open() first');
  assert.equal(unguarded(sample.replace('return usable', 'return Open(usable) and usable')).found.length, 0, 'and fine with one');
  const event = 'function C:Event(event, id)\n    if id == cast.id then Done() end\nend\n';
  assert.equal(unguarded(event, { 'C:Event': ['id'] }).found.length, 1, "an event's cast ID compared with no Open() first");
  assert.equal(unguarded(event.replace('if id', 'if Open(id) and id'), { 'C:Event': ['id'] }).found.length, 0, 'and fine with one');
  const kept = 'local function Read()\n    local _, link = Call(GetMacroItem, 1)\n    link = Word(link)\n    return link and link:match("x")\nend\n';
  assert.equal(unguarded(kept).found.length, 0, 'made safe in place by Word()');
  assert.equal(unguarded(kept.replace('    link = Word(link)\n', '')).found.length, 1, 'and caught without it');
});

// Escape closes the addon's windows through the game's own list of windows
// it closes (UISpecialFrames), never by changing key bindings: a binding
// changed from addon code has the game rebuild your action bars and state
// inside the addon's code, which then breaks on your hidden health
// (thousands of errors, 2026-10-06). Tools/TestBars.lua checks Escape closes
// them, and its mock game stops on any binding call.
test('no key binding is ever changed from addon code', () => {
  assert.deepEqual(where(/\b(SetOverrideBinding\w*|ClearOverrideBindings?|SetBinding\w*|SaveBindings|LoadBindings)\b/), [],
    'files changing key bindings');
  assert.deepEqual(where(/EscUpdate|EscButton/), [], 'nothing left of the old Escape button');
});

test("Escape closes the windows through the game's own list", () => {
  assert.equal(count(code['Core.lua'], /table\.insert\(UISpecialFrames, name\)/g), 1, 'ns.CloseOnEscape lists a window by name');
  assert.equal(count(code['Window.lua'], /ns\.CloseOnEscape\(window\)/g), 1, 'the /ccm window');
  assert.equal(count(code['Notes.lua'], /ns\.CloseOnEscape\(window\)/g), 1, "What's new");
  assert.equal(count(code['Debug.lua'], /table\.insert\(UISpecialFrames, "FECMDebugFrame"\)/g), 1, 'the debug report');
});

// Blizzard's aura containers never run the addon's code while they update.
// The only addon code a container runs is a slot's or group's look
// (initializeFrame), on each icon it makes: one as a slot is added, ten as a
// group is added, and more mid-update only for a group showing more than it
// has. So slots and groups are only added through Buffs.lua's F.Add, every
// look goes through F.Guard (it only works during that add), no group asks
// for more than ten, and AddGroup holds a group to the icons made.
// Tools/TestBars.lua checks it runs that way.
test("Blizzard's aura containers never run the addon's code while they update", () => {
  assert.deepEqual(where(/CustomAuraContainerTemplate/).sort(), ['Buffs.lua', 'IconAuras.lua'], 'the only containers');
  assert.deepEqual(where(/:AddAura(Slot|Group)\(/), [], 'no slot or group added but through F.Add');
  const looks = files.flatMap(name => (code[name].match(/initializeFrame\s*=\s*[^,}]+/g) || []).map(look => `${name}: ${look.trim()}`));
  assert.equal(looks.length, 4, 'four looks: Buffs bar spots, packed entries, your debuffs, buff and debuff times');
  assert.deepEqual(looks.filter(look => !/: initializeFrame = (F|ns\.BuffBar)\.Guard\(/.test(look)), [], 'every look guarded');
  const buffs = code['Buffs.lua'];
  assert.match(buffs, /function F\.Add\(container, method, \.\.\.\)\r?\n\s+adding = true\r?\n\s+local ok, result = pcall\(container\[method\], container, \.\.\.\)\r?\n\s+adding = false\r?\n/);
  assert.match(buffs, /function F\.Guard\(look\)\r?\n\s+return function\(button\)\r?\n\s+if adding then look\(button\) end/);
  assert.equal(count(buffs, /\badding = true/g), 1, 'looks opened in F.Add only');
  assert.deepEqual([...buffs.matchAll(/maxFrameCount = (\w+)/g)].map(match => match[1]).sort(), ['1', 'SELF_MAX']);
  assert.ok(Number(buffs.match(/local SELF_MAX = (\d+)/)[1]) <= 10, 'your debuffs: no more than the ten made up front');
  assert.match(buffs, /local function AddGroup\(container, key, filter, options\)\r?\n\s+F\.Add\(container, "AddAuraGroup", key, filter, options\)[\s\S]*?container:SetAuraGroupMaxFrameCount\(key, made\)/);
  assert.equal(count(buffs, /AddGroup\(container, "/g), 2, 'both kinds of group added through AddGroup');
});

// Nothing the addon reads is ever run as code: a shared profile is taken
// apart a character at a time (ProfileShare.lua). No way of running text is
// anywhere in what it ships, nor named in a string, and the share strings'
// reader never looks a global up by name. Tools/TestShare.lua also traps
// every such call while strings are read and imported.
test('no text is ever run as code', () => {
  const ways = /\b(loadstring|load|dofile|loadfile|require|setfenv|getfenv|getglobal|setglobal|RunScript|RunMacroText|RunMacro)\b/;
  assert.deepEqual(files.filter(name => ways.test(code[name])).map(name => `${name}: ${code[name].match(ways)[0]}`), [],
    'a way to run text');
  const named = /["'](loadstring|load|dofile|loadfile|RunScript|RunMacroText|RunMacro)["']|["'](load|Run)["']\s*\.\./;
  assert.deepEqual(where(named), [], 'a way to run text, named in a string');
  assert.ok(code['ProfileShare.lua'], 'the share strings are read in ProfileShare.lua');
  assert.doesNotMatch(code['ProfileShare.lua'], /\b_G\b|\brawget\b/, 'the reader looks nothing up by name');
});

// Nothing left behind: every function the shipped files define is used by
// them (T:Panel was left over until 2026-10-07). A few read the addon's own
// state for the tests and say "For the tests" in the note just above them;
// the public API (ForeverEnhancedCooldownManagerAPI, which EraUI calls)
// counts as used.
test('every function the addon defines is used, or says it is for the tests', () => {
  const unused = [];
  const all = files.map(name => code[name]).join('\n');
  for (const name of files) {
    const lines = readFileSync(new URL(name, root), 'utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      const method = line.match(/^\s*function\s+([\w.]+)[:.](\w+)\s*\(/);
      const local = line.match(/^\s*local\s+function\s+(\w+)\s*\(/);
      if (!method && !local) return;
      let uses;
      if (method) {
        if (method[1] === 'api') return;
        uses = count(all, new RegExp(`[:.]${method[2]}\\b|["']${method[2]}["']`, 'g')) - 1;
      } else uses = count(code[name], new RegExp(`\\b${local[1]}\\b`, 'g')) - 1;
      if (uses > 0) return;
      let note = '';
      for (let j = i - 1; j >= 0 && /^\s*--/.test(lines[j]); j--) note = lines[j] + note;
      if (!/for the tests/i.test(note)) unused.push(`${name}:${i + 1} ${line.trim()}`);
    });
  }
  assert.deepEqual(unused, [], 'defined but never used');
  assert.match(code['RaidTimers.lua'], /ForeverEnhancedCooldownManagerAPI = setmetatable\(\{\}, \{\s*__index = api,/, 'api is the public API');
});
