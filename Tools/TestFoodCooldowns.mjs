// Food and drink stay off the Items list (Spells.lua NoCooldown): they only
// wait out the game's short shared cooldown. But for the Food & Drink items
// whose own item data sets a cooldown of their own (Thistle Tea), listed in
// Spells.lua's COOLDOWN_FOOD. That list must be exactly what Blizzard's game
// tables for Forever give (Item, ItemSparse, ItemEffect and
// ItemXItemEffect): every item of class 0 (Consumable) subclass 5 (Food &
// Drink) with an on-use effect whose CoolDownMSec or CategoryCoolDownMSec is
// over the 1.5 second global cooldown, and a name in ItemSparse (an item
// with none isn't in the game). Each line's name is the item's. Checked
// against build 1.60.1.70374's tables, read from the installed game client
// (nothing downloaded) by
// C:\AddonDev\_Toolchain\gamedata\forever-70374-client\extract.js, and
// against 1.60.1.70245's wago.tools export in ...\forever-70245: both give
// the same five. The client can't read rows in its encrypted sections
// (content not in the game yet), so those are checked once a build has
// them. Each build on this computer is checked; skipped when none is.
// Run with: node --test Tools/TestFoodCooldowns.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const TABLES = ['Item', 'ItemSparse', 'ItemEffect', 'ItemXItemEffect', 'SpellCooldowns'];
// The builds whose tables are on this computer, newest first.
const BUILDS = [['1.60.1.70374', 'forever-70374-client'], ['1.60.1.70245', 'forever-70245']]
  .map(([build, dir]) => ({ build, dir: join(root, '..', '_Toolchain', 'gamedata', dir) }))
  .filter(({ dir }) => TABLES.every(name => existsSync(join(dir, `${name}.csv`))));
const here = BUILDS.length > 0;
const NEWEST = here ? BUILDS[0].dir : null;
const CONSUMABLE = 0, FOOD_AND_DRINK = 5, ON_USE = 0, GLOBAL_COOLDOWN = 1500;

// A small CSV reader: quoted fields, doubled quotes, CRLF line ends.
function parse(text) {
  const rows = [];
  let row = [], value = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { value += '"'; i++; } else quoted = !quoted;
    } else if (!quoted && (c === ',' || c === '\n')) {
      row.push(value.replace(/\r$/, ''));
      value = '';
      if (c === '\n') { rows.push(row); row = []; }
    } else value += c;
  }
  if (value || row.length) { row.push(value); rows.push(row); }
  const header = rows.shift();
  return rows.filter(r => r.length > 1).map(r => {
    assert.equal(r.length, header.length, 'CSV width');
    return Object.fromEntries(header.map((h, i) => [h, r[i]]));
  });
}
const table = (name, dir = NEWEST) => parse(readFileSync(join(dir, `${name}.csv`), 'utf8'));

// Spells.lua's list: each ID with the name its line gives.
function listed() {
  const text = readFileSync(join(root, 'Spells.lua'), 'utf8');
  const block = text.match(/^local COOLDOWN_FOOD = \{\r?\n([\s\S]*?)^\}/m);
  assert.ok(block, 'Spells.lua has its COOLDOWN_FOOD list');
  const items = new Map();
  for (const line of block[1].split(/\r?\n/).filter(Boolean)) {
    const m = line.match(/^ {4}\[(\d+)\] = true, -- ([^:]+): .+$/);
    assert.ok(m, `a line of the list: ${line}`);
    assert.ok(!items.has(+m[1]), `${m[1]} listed once`);
    items.set(+m[1], m[2]);
  }
  return items;
}

// What a build's tables say (the newest here unless given): every Food &
// Drink item, and the longest cooldown its own on-use effects set (0 for
// none), with its name.
function fromTables(dir = NEWEST) {
  const foods = new Map(table('Item', dir).filter(r => +r.ClassID === CONSUMABLE && +r.SubclassID === FOOD_AND_DRINK)
    .map(r => [+r.ID, { own: 0, spells: [] }]));
  const names = new Map(table('ItemSparse', dir).map(r => [+r.ID, r.Display_lang]));
  const effects = new Map(table('ItemEffect', dir).map(r => [+r.ID, r]));
  for (const link of table('ItemXItemEffect', dir)) {
    const food = foods.get(+link.ItemID), effect = effects.get(+link.ItemEffectID);
    if (!food || !effect || +effect.TriggerType !== ON_USE) continue;
    food.own = Math.max(food.own, +effect.CoolDownMSec, +effect.CategoryCoolDownMSec);
    food.spells.push(+effect.SpellID);
  }
  for (const [id, food] of foods) food.name = names.get(id) || '';
  return foods;
}

// The items with a cooldown of their own and a name, by ID.
const withCooldown = foods => [...foods].filter(([, food]) => food.own > GLOBAL_COOLDOWN && food.name !== '').map(([id]) => id)
  .sort((a, b) => a - b);

test('the list is every Food & Drink item with a cooldown of its own, by its name', { skip: !here }, () => {
  const foods = fromTables(), items = listed();
  const expected = withCooldown(foods);
  assert.deepEqual([...items.keys()].sort((a, b) => a - b), expected);
  for (const [id, name] of items) assert.equal(name, foods.get(id).name, `${id}'s name`);
  assert.deepEqual(expected, [1072, 6522, 6657, 7676, 11951], 'the items as checked on 2026-10-15');
});

test('every build here gives the same list', { skip: !here }, () => {
  for (const { build, dir } of BUILDS) assert.deepEqual(withCooldown(fromTables(dir)), [1072, 6522, 6657, 7676, 11951], build);
});

// Food and drink 1.60.1.70374 has that 1.60.1.70245 didn't: ordinary, with
// no cooldown of their own.
test("the newer build's food and drink have no cooldown of their own", { skip: !BUILDS.some(b => b.build === '1.60.1.70374') }, () => {
  const foods = fromTables(BUILDS.find(b => b.build === '1.60.1.70374').dir);
  for (const [id, name] of [[287963, 'Roasted Quail'], [287964, 'Morning Glory Dew'], [287972, 'Rumsey Rum Dark'],
    [287973, 'Tender Wolf Steak'], [287974, 'Grilled Squid']]) {
    assert.equal(foods.get(id).name, name);
    assert.ok(foods.get(id).own <= GLOBAL_COOLDOWN, `${name} sets no cooldown of its own`);
  }
});

test("Thistle Tea's cooldown, and ordinary food and drink with none of their own", { skip: !here }, () => {
  const foods = fromTables();
  const tea = foods.get(7676);
  assert.equal(tea.name, 'Thistle Tea');
  assert.equal(tea.own, 300000, 'five minutes of its own');
  assert.deepEqual(tea.spells, [9512], 'Restore Energy');
  // Tough Jerky, Refreshing Spring Water and Thunder Ale (alcohol): their
  // items set nothing, so they only wait out the shared food or drink one.
  const spellWait = new Map(table('SpellCooldowns').filter(r => +r.DifficultyID === 0)
    .map(r => [+r.SpellID, Math.max(+r.RecoveryTime, +r.CategoryRecoveryTime)]));
  for (const [id, name, wait] of [[117, 'Tough Jerky', 1000], [159, 'Refreshing Spring Water', 1000], [2686, 'Thunder Ale', 10000]]) {
    const food = foods.get(id);
    assert.equal(food.name, name);
    assert.ok(food.own <= GLOBAL_COOLDOWN, `${name} sets no cooldown of its own`);
    assert.deepEqual(food.spells.map(spell => spellWait.get(spell)), [wait], `${name} only waits out the shared one`);
  }
  // The one with a cooldown but no name: not an item in the game.
  assert.equal(foods.get(23683).own, 120000);
  assert.equal(foods.get(23683).name, '', 'no ItemSparse row, so left out');
});

test('Spells.lua lets only the listed Food & Drink items through', () => {
  const text = readFileSync(join(root, 'Spells.lua'), 'utf8');
  const body = text.match(/^local function NoCooldown\(itemID\)\r?\n([\s\S]*?)^end$/m);
  assert.ok(body, 'NoCooldown is there');
  assert.match(body[1], /subclassID == FOOD_AND_DRINK and not COOLDOWN_FOOD\[itemID\]/);
  assert.ok(listed().has(7676), 'Thistle Tea listed');
});
