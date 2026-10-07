// What's new in the game (Notes.lua) must say what CHANGELOG.txt says, version
// by version, nothing unused ships in Media/, and the footer's heart is drawn
// right. Run with: node --test Tools/TestNotes.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';

const read = name => readFile(new URL(`../${name}`, import.meta.url), 'utf8');
const STRING = '"((?:[^"\\\\]|\\\\.)*)"'; // a Lua string in double quotes
const unquote = text => text.replace(/\\(.)/g, '$1');

// The ns.NOTES table: each version's sections, then their bullets.
function gameNotes(lua) {
  const lines = lua.split(/\r?\n/);
  const start = lines.findIndex(line => line.trim() === 'ns.NOTES = {');
  const end = lines.findIndex((line, i) => i > start && line === '}');
  assert.ok(start >= 0 && end > start, 'ns.NOTES found in Notes.lua');
  const entries = [];
  for (const line of lines.slice(start + 1, end)) {
    let match;
    if ((match = line.match(new RegExp(`^\\s*version = ${STRING},\\s*$`)))) {
      entries.push({ version: unquote(match[1]), sections: [] });
    } else if ((match = line.match(new RegExp(`^\\s*\\{ ${STRING}, \\{\\s*$`)))) {
      entries.at(-1).sections.push({ title: unquote(match[1]), items: [] });
    } else if ((match = line.match(new RegExp(`^\\s*${STRING},\\s*$`)))) {
      entries.at(-1).sections.at(-1).items.push(unquote(match[1]));
    }
  }
  return entries;
}

// CHANGELOG.txt: "## version", then "### section" and "- bullet" lines.
function changelogNotes(text) {
  const entries = [];
  for (const line of text.split(/\r?\n/)) {
    let match;
    if ((match = line.match(/^## (.+)$/))) entries.push({ version: match[1].trim(), sections: [] });
    else if ((match = line.match(/^### (.+)$/))) entries.at(-1).sections.push({ title: match[1].trim(), items: [] });
    else if ((match = line.match(/^- (.+)$/))) entries.at(-1).sections.at(-1).items.push(match[1].trim());
  }
  return entries;
}

test('What\'s new in the game matches CHANGELOG.txt, version by version', async () => {
  const game = gameNotes(await read('Notes.lua'));
  assert.ok(game.length > 0 && game[0].sections.length > 0, 'notes to show');
  assert.deepEqual(game, changelogNotes(await read('CHANGELOG.txt')));
});

test('only the newest notes can wait for their version number', async () => {
  gameNotes(await read('Notes.lua')).forEach((entry, index) => {
    if (index === 0 && entry.version === 'Unreleased') return;
    assert.match(entry.version, /^\d+\.\d+(\.\d+)?$/, `"${entry.version}" is a version number`);
  });
});

// Tour.lua's steps, the full tour's then What's new's: each one's title and
// the version lines on it ([line, number, placeholder] for each).
async function tourSteps() {
  const lua = (await read('Tour.lua')).replace(/\r\n/g, '\n');
  const steps = [];
  for (const list of ['STEPS', 'NEWS']) {
    const start = lua.indexOf(`\nlocal ${list} = {\n`);
    assert.ok(start >= 0, `${list} found in Tour.lua`);
    const block = lua.slice(start, lua.indexOf('\n}\n', start));
    for (const step of block.split(/\n    \{\n/).slice(1)) {
      const title = step.match(/^        title = "([^"]+)",$/m);
      steps.push({
        title: title ? title[1] : step.trim().split('\n')[1],
        versions: [...step.matchAll(/^        version = (?:"([^"]+)"|(ns\.UNRELEASED)),$/gm)],
      });
    }
  }
  return steps;
}

// -1, 0 or 1 as version a is older than, the same as or newer than b, part by
// part as numbers ("1.10" after "1.9", "1.1" is "1.1.0").
function compareVersions(a, b) {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const difference = (x[i] ?? 0) - (y[i] ?? 0);
    if (difference) return Math.sign(difference);
  }
  return 0;
}

// Tour.lua: each step says the version it arrived in, so What's new can tour
// just an update's steps. A numbered one must be a version with notes; the
// next update's wait as ns.UNRELEASED until the release gives them its number.
test('every tour step has the version it arrived in', async () => {
  const released = new Set(gameNotes(await read('Notes.lua')).map(entry => entry.version));
  const steps = await tourSteps();
  for (const step of steps) {
    assert.equal(step.versions.length, 1, `one version on: ${step.title}`);
    const [, number, placeholder] = step.versions[0];
    if (!placeholder) assert.ok(released.has(number), `"${number}" has notes in Notes.lua`);
  }
  assert.ok(steps.length >= 19, 'every step checked');
});

// Releases that added no tour steps. Steps written after one of these wait
// for the next update's number while its notes are still the newest.
const ADDED_NO_STEPS = ['1.2.1', '1.3.0', '1.4.0', '1.4.2', '1.4.3', '1.4.4'];

// A release never shows steps still waiting for their number, so it gives
// them its number when its notes get it. Once the newest notes are a release
// newer than every numbered step, a step still waiting was left behind,
// unless that release added no steps: then it's the next update's.
test('tour steps waiting for their number get it with the notes', async () => {
  const newest = gameNotes(await read('Notes.lua'))[0].version;
  const steps = await tourSteps();
  const waiting = steps.filter(step => step.versions[0]?.[2]).map(step => step.title);
  const numbered = steps.map(step => step.versions[0]?.[1]).filter(Boolean);
  if (!/^\d+(\.\d+)*$/.test(newest) || waiting.length === 0) return;
  const stepless = ADDED_NO_STEPS.some(version => compareVersions(version, newest) === 0);
  assert.ok(stepless || numbered.some(number => compareVersions(number, newest) >= 0),
    `${waiting.join(', ')} still wait as ns.UNRELEASED, but the newest notes are ${newest}, newer than every numbered step:`
    + ` give them ${newest} if they shipped in it, or add the next update's notes as Unreleased first.`
    + ` Only if ${newest} added no tour steps at all, list it in ADDED_NO_STEPS`);
});

// A release listed as adding no tour steps really added none.
test('releases listed as adding no tour steps added none', async () => {
  const numbered = (await tourSteps()).map(step => step.versions[0]?.[1]).filter(Boolean);
  for (const version of ADDED_NO_STEPS) {
    assert.match(version, /^\d+\.\d+(\.\d+)?$/, `"${version}" is a version number`);
    assert.ok(!numbered.some(number => compareVersions(number, version) === 0),
      `${version} has tour steps: take it off ADDED_NO_STEPS`);
  }
});

test('every section has bullets, and none use em dashes', async () => {
  for (const entry of gameNotes(await read('Notes.lua'))) {
    for (const section of entry.sections) {
      assert.ok(section.items.length > 0, `${entry.version} ${section.title} has bullets`);
      for (const item of section.items) assert.doesNotMatch(item, /—/, item);
    }
  }
});

// A Lua file's strings, comments skipped: [{ text, line }] (text as written,
// escapes and all). Quoted strings and [[long]] or [==[long]==] ones.
function luaStrings(lua) {
  const found = [];
  const open = /\[(=*)\[/y;
  let i = 0, line = 1;
  const lines = (from, to) => (lua.slice(from, to).match(/\n/g) || []).length;
  // A long string or comment opening at `at`: where its text starts and ends, and where it all stops.
  const long = at => {
    open.lastIndex = at;
    const match = open.exec(lua);
    if (!match) return null;
    const close = `]${match[1]}]`, end = lua.indexOf(close, at + match[0].length);
    return { start: at + match[0].length, end: end < 0 ? lua.length : end, stop: end < 0 ? lua.length : end + close.length };
  };
  while (i < lua.length) {
    const c = lua[i];
    if (c === '\n') { line++; i++; continue; }
    if (c === '-' && lua[i + 1] === '-') {
      const block = long(i + 2);
      const end = lua.indexOf('\n', i);
      const stop = block ? block.stop : end < 0 ? lua.length : end;
      line += lines(i, stop);
      i = stop;
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < lua.length && lua[j] !== c && lua[j] !== '\n') j += lua[j] === '\\' ? 2 : 1;
      found.push({ text: lua.slice(i + 1, j), line });
      line += lines(i, j);
      i = j + 1;
      continue;
    }
    const block = c === '[' && long(i);
    if (block) {
      found.push({ text: lua.slice(block.start, block.end), line });
      line += lines(i, block.stop);
      i = block.stop;
      continue;
    }
    i++;
  }
  return found;
}

test('the string reader finds strings and skips comments', () => {
  const sample = 'local a = "one" -- "not this"\n--[[ "nor\nthis" ]]\nb = \'two\\\'s\' .. [==[three\n]]four]==] --[=[x]=] c = "five"';
  assert.deepEqual(luaStrings(sample).map(s => `${s.line}:${s.text}`), ['1:one', "4:two\\'s", '4:three\n]]four', '5:five']);
});

// The .toc lines players read in the game's AddOns list: its Title and Notes
// (any language). Its file list isn't text for players.
const TOC = 'ForeverEnhancedCooldownManager.toc';
const tocText = async () => (await read(TOC)).split(/\r?\n/)
  .map((text, i) => ({ name: TOC, where: `${TOC}:${i + 1}`, text }))
  .filter(({ text }) => /^##\s*(Title|Notes)\b/i.test(text));

// Players are only ever told /ccm. /fecm still works (an old habit), but
// nothing they read says it: the changelog and What's new, the README, the
// CurseForge description, the .toc's Title and Notes, and every string in
// the addon's code. Comments can say either.
test('players are told /ccm, never /fecm', async () => {
  for (const name of ['CHANGELOG.txt', 'README.md', 'Tools/CurseForgeDescription.html']) {
    assert.doesNotMatch(await read(name), /\/fecm\b/i, name);
  }
  const toc = await tocText();
  assert.ok(toc.length >= 2, "the .toc's Title and Notes found");
  for (const { where, text } of toc) assert.doesNotMatch(text, /\/fecm\b/i, where);
  const files = (await readdir(new URL('../', import.meta.url))).filter(name => /\.lua$/i.test(name));
  assert.ok(files.length > 20, "the addon's Lua files found");
  const told = [];
  let registered = 0;
  for (const name of files) {
    const lua = await read(name);
    const lines = lua.split(/\r?\n/);
    for (const { text, line } of luaStrings(lua)) {
      if (!/\/fecm\b/i.test(text)) continue;
      // The command itself, kept working.
      if (/^SLASH_FECM\d+ = "\/fecm"$/.test(lines[line - 1].trim())) registered++;
      else told.push(`${name}:${line}: ${text}`);
    }
  }
  assert.deepEqual(told, [], 'strings that tell players /fecm');
  assert.equal(registered, 1, '/fecm still registered, once');
});

// Everything players read, line by line: the changelog, the README, the
// CurseForge description, the .toc's Title and Notes, and every string in
// the addon's code.
const PLAYER_FILES = ['CHANGELOG.txt', 'README.md', 'Tools/CurseForgeDescription.html'];
async function playerText() {
  const out = [];
  for (const name of PLAYER_FILES) {
    (await read(name)).split(/\r?\n/).forEach((text, i) => out.push({ name, where: `${name}:${i + 1}`, text }));
  }
  out.push(...await tocText());
  const files = (await readdir(new URL('../', import.meta.url))).filter(name => /\.lua$/i.test(name));
  assert.ok(files.length > 20, "the addon's Lua files found");
  for (const name of files) {
    for (const { text, line } of luaStrings(await read(name))) out.push({ name, where: `${name}:${line}`, text });
  }
  return out;
}

// An em dash however it's written: the character, an HTML entity (the
// CurseForge description is HTML), or a Lua escape (strings are read as
// written).
const EM_DASH = new RegExp([String.fromCharCode(0x2014), '&mdash;', '&#0*8212;', '&#x0*2014;', '\\\\226\\\\128\\\\148',
  '\\\\u\\{0*2014\\}', '\\\\x[eE]2\\\\x80\\\\x94'].join('|'), 'i');

test('nothing players read has an em dash', async () => {
  for (const sample of [`a ${String.fromCharCode(0x2014)} b`, 'a &mdash; b', 'a &#8212; b', 'a &#x2014; b',
    'a \\226\\128\\148 b', 'a \\u{2014} b', 'a \\xE2\\x80\\x94 b']) {
    assert.match(sample, EM_DASH, `the check sees ${sample}`);
  }
  assert.doesNotMatch('a - b, a &ndash; b, 1:2', EM_DASH);
  const found = (await playerText()).filter(({ text }) => EM_DASH.test(text)).map(({ where, text }) => `${where}: ${text}`);
  assert.deepEqual(found, []);
});

// Ideas can come from anywhere, but the words are our own: no other addon is
// ever named (Forever Enhanced Cooldown Pulse and EraUI are the same
// author's). The two this addon was once compared with first.
const OTHER_ADDONS = [/Forever Cooldown Manager/i, /Doom ?Cooldown ?Pulse/i, /\bWeakAuras\b/i, /\bElvUI\b/i, /\bBartender\d*\b/i,
  /\bDominos\b/i, /\bOmniCC\b/i, /\bTellMeWhen\b/i, /\bPlater\b/i, /\bQuestie\b/i, /\bMasque\b/i, /\bDetails!/i, /\bBigWigs\b/i,
  /Deadly Boss Mods/i, /\bDBM\b/, /\bLeatrix\b/i, /\bBagnon\b/i, /\bHealBot\b/i, /\bVuhDo\b/i, /\bGrid2\b/i,
  /Shadowed Unit Frames/i, /\bAuctionator\b/i, /\bSexyMap\b/i, /\bCooldown ?Manager ?Centered\b/i, /\bNeedToKnow\b/i];

test('nothing players read names another addon', async () => {
  const found = (await playerText()).filter(({ text }) => OTHER_ADDONS.some(name => name.test(text)))
    .map(({ where, text }) => `${where}: ${text}`);
  assert.deepEqual(found, []);
  assert.ok(OTHER_ADDONS.some(name => name.test('Like Forever Cooldown Manager does')), 'the check works');
});

// The /ccm debug report is a hidden support tool: nothing players read
// mentions it. Only its own file's strings and the slash command's match
// for it say "debug".
test('the hidden /ccm debug report is never mentioned', async () => {
  const found = (await playerText()).filter(({ name, text }) => /debug/i.test(text) && name !== 'Debug.lua')
    .map(({ where, text }) => `${where}: ${text}`);
  assert.equal(found.length, 1, found.join('\n'));
  assert.match(found[0], /^Core\.lua:\d+: \^%s\*debug%s\*\$$/, "only /ccm's own match for it");
});

// A button first, /ccm second: typing a command was tied to the hidden-code
// errors of 2026-10-06, and clicking never was. Each sentence players read
// that mentions /ccm names a way to click before it (the minimap button,
// Options > AddOns, or a button or page in the settings), or is the note of
// a button that does the same ("... too."). The README's list of typed
// commands comes after its buttons. The release history shipped before this
// rule (CHANGELOG.txt and What's new's entries up to 1.5.2) is left as it
// was; What's new's entries for later versions follow it, and CHANGELOG.txt
// says the same word for word (checked above).
const CLICKS = /minimap|Options (>|&gt;) AddOns|\bbutton\b|General page|What's new|click below|in the settings/i;
const SHIPPED_BEFORE_RULE = '1.5.2';
const TYPED = "If you'd rather type:";
const sentences = text => text.split(/(?<=[.!?])\s+/);
const clickFirst = text => sentences(text).every(sentence => {
  const at = sentence.search(/\/ccm\b/);
  return at < 0 || CLICKS.test(sentence.slice(0, at)) || /\btoo\.$/.test(sentence.trim());
});

test('players are pointed to a button first, and to /ccm second', async () => {
  assert.equal(clickFirst('Type /ccm, click the minimap button, or click below, for the settings.'), false, 'the check works');
  assert.equal(clickFirst('Close the window. Escape closes it too, and /ccm opens it again.'), false, 'sentence by sentence');
  assert.equal(clickFirst('A short tour. /ccm tour starts it too.'), true, "a button's own note");
  const told = [];
  // The addon's strings, but for What's new's entries shipped before this rule, the command itself and the hidden debug report.
  const entries = gameNotes(await read('Notes.lua'));
  // (Notes still "Unreleased" are new, so they follow it too.)
  const history = new Set(entries.filter(entry => /^\d+(\.\d+)*$/.test(entry.version)
    && compareVersions(entry.version, SHIPPED_BEFORE_RULE) <= 0).flatMap(entry => entry.sections.flatMap(section => section.items)));
  assert.ok(history.size > 50, "What's new's entries found");
  assert.ok(entries.some(entry => entry.version === SHIPPED_BEFORE_RULE), `${SHIPPED_BEFORE_RULE}'s entry found`);
  const files = (await readdir(new URL('../', import.meta.url))).filter(name => /\.lua$/i.test(name) && name !== 'Debug.lua');
  for (const name of files) {
    for (const { text, line } of luaStrings(await read(name))) {
      if (text === '/ccm' || history.has(unquote(text)) || clickFirst(unquote(text))) continue;
      told.push(`${name}:${line}: ${text}`);
    }
  }
  // The README and the CurseForge page, a bullet or paragraph at a time.
  const readme = (await read('README.md')).split(/\r?\n(?:\s*\r?\n|(?=- ))/).map(unit => unit.replace(/\s+/g, ' ').trim());
  const typed = readme.findIndex(unit => unit.startsWith(TYPED));
  assert.ok(typed > readme.findIndex(unit => /minimap button/.test(unit)) && readme.some(unit => /Options > AddOns/.test(unit)),
    'the README: the minimap button and Options > AddOns, then the typed commands');
  readme.forEach((unit, i) => { if (i !== typed && !clickFirst(unit)) told.push(`README.md: ${unit}`); });
  const html = (await read('Tools/CurseForgeDescription.html')).split(/<\/(?:li|p|h\d)>/)
    .map(unit => unit.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim());
  html.forEach(unit => { if (!clickFirst(unit)) told.push(`Tools/CurseForgeDescription.html: ${unit}`); });
  assert.deepEqual(told, [], 'sentences that send players to /ccm before a button');
});

// The README (in the download and on GitHub) keeps up with the CurseForge
// page: every bold name in its Highlights is in the README, in the README's
// own words where they differ.
const README_WORDS = {
  "A new look for Blizzard's Cooldown Manager": "## Blizzard's Cooldown Manager",
  'Procs and reactive abilities glow': "the game's proc glow",
  'Debuff search': "a search that lists your class's debuffs",
  'Borders and shadows': 'borders and soft shadows',
  'Keybinds on icons': 'keybinds on the icons',
  'Healthstones and potions': 'healthstones, healing potions and mana potions',
  "Show me what's new": 'a short tour of just the new features',
  '?': "the ? in the window's title bar",
};

test('the README covers every highlight on the CurseForge page', async () => {
  const html = await read('Tools/CurseForgeDescription.html');
  const start = html.indexOf('Highlights');
  const list = html.slice(start, html.indexOf('</ul>', start));
  const readme = (await read('README.md')).replace(/\s+/g, ' ').toLowerCase();
  const names = [...list.matchAll(/<strong>(.*?)<\/strong>/g)].map(match => match[1].replace(/&amp;/g, '&'));
  assert.ok(names.length > 20, 'the highlights found');
  const missing = names.filter(name => !readme.includes((README_WORDS[name] ?? name).toLowerCase()));
  assert.deepEqual(missing, [], 'highlights the README leaves out (add them, or their README words to README_WORDS)');
});

// The swing timer shows the main hand for everyone, hunters too, and ranged
// swings for any class: Auto Shot for hunters, Ranged for the rest.
test('the swing timer is described as it works wherever players read about it', async () => {
  for (const name of ['CHANGELOG.txt', 'README.md', 'Tools/CurseForgeDescription.html']) {
    const text = (await read(name)).replace(/\s+/g, ' ');
    assert.match(text, /main hand and ranged swings \(Auto Shot for hunters\)/, name);
    assert.doesNotMatch(text, /main hand for everyone else/, name);
  }
});

// The footer's credit draws its heart from Media: a 32x32 uncompressed 32-bit
// TGA like the addon's other textures, white so the accent can tint it, the
// right way up (TGA rows start at the bottom unless the header says not).
test('the footer heart is a white 32x32 TGA, point down', async () => {
  const name = (await read('Window.lua')).match(/local HEART = "([^"]+)"/)?.[1];
  assert.equal(name, 'Heart.tga', 'Window.lua names the heart');
  const tga = await readFile(new URL(`../Media/${name}`, import.meta.url));
  const size = 32;
  assert.deepEqual([tga[2], tga.readUInt16LE(12), tga.readUInt16LE(14), tga[16], tga[17]], [2, size, size, 32, 8],
    'uncompressed true colour, 32x32, 32 bits a pixel, 8 of them alpha, bottom row first');
  assert.equal(tga.length, 18 + size * size * 4, 'nothing after the pixels');
  const widths = [];
  let white = true;
  for (let row = 0; row < size; row++) {
    let solid = 0;
    for (let col = 0; col < size; col++) {
      const at = 18 + (row * size + col) * 4;
      if (tga[at] !== 255 || tga[at + 1] !== 255 || tga[at + 2] !== 255) white = false;
      if (tga[at + 3] > 127) solid++;
    }
    widths.push(solid);
  }
  assert.ok(white, 'white everywhere, so the tint is the accent');
  const widest = widths.indexOf(Math.max(...widths));
  assert.ok(widest > size / 2 && widths[1] < widths[widest] / 4, 'the lobes at the top, the point at the bottom');
  assert.ok(widths[0] === 0 && widths[size - 1] === 0, 'clear of the top and bottom edges');
});

test('every file in Media is used by the addon, so none ship unused', async () => {
  const files = await readdir(new URL('../', import.meta.url));
  const code = (await Promise.all(files.filter(name => /\.(lua|toc|xml)$/i.test(name)).map(read))).join('\n').toLowerCase();
  const media = await readdir(new URL('../Media/', import.meta.url));
  assert.ok(media.length > 0, 'media to check');
  for (const name of media) {
    assert.ok(code.includes(name.replace(/\.[^.]+$/, '').toLowerCase()), `Media/${name} is used`);
  }
});
