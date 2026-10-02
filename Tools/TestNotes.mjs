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
const ADDED_NO_STEPS = ['1.2.1', '1.3.0', '1.4.0'];

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
