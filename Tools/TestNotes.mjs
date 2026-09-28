// What's new in the game (Notes.lua) must say what CHANGELOG.txt says, version
// by version. Run with: node --test Tools/TestNotes.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

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

test('every section has bullets, and none use em dashes', async () => {
  for (const entry of gameNotes(await read('Notes.lua'))) {
    for (const section of entry.sections) {
      assert.ok(section.items.length > 0, `${entry.version} ${section.title} has bullets`);
      for (const item of section.items) assert.doesNotMatch(item, /—/, item);
    }
  }
});
