// Prints Buffs.lua's ns.HAND_ENCHANTS table from Forever's game tables: every
// temporary enchant a player can put on a weapon, by its enchant ID, with the
// name and icon the Main hand and Off hand enchant entries show while it's on.
//   node Tools/MakeHandEnchants.mjs [folder of the build's wago.tools CSVs]
// Needs SpellEffect, SpellName, SpellMisc, SpellEquippedItems, ItemEffect,
// ItemXItemEffect, Item and ItemSparse, each from
// https://wago.tools/db2/<Table>/csv?build=<build>.
//
// What counts: a spell with effect 54 or 360 (a temporary enchant on an item,
// EffectMiscValue_0 its enchant) that goes on a weapon (SpellEquippedItems
// class 2; two shield coatings come in that way too, which can only sit on
// the off hand), and either an item with a name casts it (an oil, a stone, a
// poison, a scroll, a lure) or it's a shaman's own (no item casts those).
// Not the test ones, Season of Discovery's runes and souls (Forever has
// none), nor what only NPCs carry (misc items, class 15: Instant Toxin).
// Named for the item that casts it (Lesser Firestone, Wound Poison II), but
// a scroll by the imbue it puts on (Imbue Flame); the item's icon, else the
// spell's. Where several items or spells give one enchant, a consumable's
// first, then the lowest item ID.
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2] || 'C:/AddonDev/_ForeverData/changes-2026-11-06/wago-70790';

function csv(file) {
  const text = fs.readFileSync(path.join(dir, file), 'utf8');
  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      rows.push(row); row = [];
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.filter(r => r.length === head.length).map(r => Object.fromEntries(head.map((key, i) => [key, r[i]])));
}

const TEMPORARY = new Set(['54', '360']);
const WEAPON = '2';
const SCROLL = { classID: '0', subclassID: '4' };
const CONSUMABLE = '0';
const NPC_ONLY = '15'; // misc items: Instant Toxin, Creeping Anguish
// A shaman's weapon spells: no item casts them.
const CLASS_SPELLS = new Set(['Rockbiter Weapon', 'Flametongue Weapon', 'Frostbrand Weapon', 'Windfury Weapon']);
const SKIP = name => /test/i.test(name) || /DONOTREUSE/.test(name) || /^(Engrave|Soul of) /.test(name);

const spellName = new Map(csv('SpellName.csv').map(r => [r.ID, r.Name_lang]));
const spellIcon = new Map();
for (const r of csv('SpellMisc.csv')) if (!spellIcon.has(r.SpellID)) spellIcon.set(r.SpellID, Number(r.SpellIconFileDataID));
const equipped = new Map(csv('SpellEquippedItems.csv').map(r => [r.SpellID, r.EquippedItemClass]));
const itemEffect = new Map(csv('ItemEffect.csv').map(r => [r.ID, r]));
const items = new Map(csv('Item.csv').map(r => [r.ID, r]));
const itemName = new Map(csv('ItemSparse.csv').map(r => [r.ID, r.Display_lang]));
const castBy = new Map(); // spell ID -> the items that cast it
for (const link of csv('ItemXItemEffect.csv')) {
  const effect = itemEffect.get(link.ItemEffectID);
  if (!effect) continue;
  if (!castBy.has(effect.SpellID)) castBy.set(effect.SpellID, []);
  castBy.get(effect.SpellID).push(link.ItemID);
}

// Each enchant's candidates: { rank (lower wins), name, icon }.
const best = new Map();
function Offer(enchant, rank, name, icon) {
  const now = best.get(enchant);
  if (!now || rank < now.rank) best.set(enchant, { rank, name, icon });
}
for (const effect of csv('SpellEffect.csv')) {
  if (!TEMPORARY.has(effect.Effect)) continue;
  const spell = effect.SpellID, name = spellName.get(spell) || '';
  const enchant = Number(effect.EffectMiscValue_0);
  if (!enchant || !name || SKIP(name) || equipped.get(spell) !== WEAPON) continue;
  for (const id of castBy.get(spell) || []) {
    const item = items.get(id), shown = itemName.get(id);
    if (!item || !shown || item.ClassID === NPC_ONLY) continue;
    const scroll = item.ClassID === SCROLL.classID && item.SubclassID === SCROLL.subclassID;
    const icon = Number(item.IconFileDataID) || spellIcon.get(spell) || 0;
    // A consumable's (an oil, a lure) before anything else's (a fishing hat's).
    Offer(enchant, (item.ClassID === CONSUMABLE ? 0 : 1e7) + Number(id), scroll ? name : shown, icon);
  }
  if (CLASS_SPELLS.has(name)) Offer(enchant, 2e7 + Number(spell), name, spellIcon.get(spell) || 0);
}

const lua = text => JSON.stringify(text);
const lines = [...best.keys()].sort((a, b) => a - b)
  .map(id => `    [${id}] = { ${lua(best.get(id).name)}, ${best.get(id).icon} },`);
console.log(`ns.HAND_ENCHANTS = {\n${lines.join('\n')}\n}`);
console.error(`${lines.length} enchants`);
