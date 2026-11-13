// Prints Spells.lua's two trinket tables from Forever's game tables: what the
// use of each trinket puts on you, for the Trinket 1 and Trinket 2 entries on
// the Buffs bar.
//   node Tools/MakeTrinketBuffs.mjs [folder of the build's wago.tools CSVs]
// Needs Item, ItemEffect, ItemXItemEffect, ItemSparse, SpellEffect,
// SpellMisc, SpellDuration and SpellName, each from
// https://wago.tools/db2/<Table>/csv?build=<build>.
//
// A trinket is an item worn in a trinket slot (Item InventoryType 12); its
// use is its ItemEffect with TriggerType 0 (on use), whose SpellID is the
// spell the game casts (what C_Item.GetItemSpell names). That spell's buff
// is on you when it applies an aura (SpellEffect Effect 6, or an area aura)
// on its caster (ImplicitTarget_0 1) lasting a second or more (or until it's
// cancelled, Duration -1). For almost every trinket the buff is the use
// spell itself, so Spells.lua needs no table for those. Printed:
// * TRINKET_BUFFS: uses that put no aura on you themselves but cast another
//   spell that does (SpellEffect Effect 32 or 64, EffectTriggerSpell): that
//   spell is the buff. Also the uses in SCRIPTED below, whose buff the
//   game's own script casts (their use is a Dummy, Effect 3, so the tables
//   don't link the two): kept by hand.
// * TRINKET_NO_BUFF: uses that put no buff on you at all (a summon, a heal,
//   mana, a debuff or stun on your target, a buff on your pet, a 0.1 second
//   immunity), so the entry stays missing and says why.
// Not the test or deprecated items.
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2] || 'C:/AddonDev/_ForeverData/changes-2026-11-10/wago-70888';

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

const TRINKET = '12';
const ON_USE = '0';
const CASTER = '1';
const APPLY_AURA = '6';
const AREA_AURAS = new Set(['35', '65', '119', '128', '129', '143']);
const TRIGGERS = new Set(['32', '64']);
const SKIP = name => /test|deprecated/i.test(name || '');
// Uses whose buff is cast by the game's script, not linked in the tables:
// Lifegiving Gem's Gift of Life (23725, a Dummy) puts 23782 on you (more
// max health, 20 s); 467499 is the same for item 230249.
const SCRIPTED = { 23725: ['23782'], 467499: ['467498'] };

const spellName = new Map(csv('SpellName.csv').map(r => [r.ID, r.Name_lang]));
const durationOf = new Map(csv('SpellDuration.csv').map(r => [r.ID, Number(r.Duration)]));
const misc = new Map();
for (const r of csv('SpellMisc.csv')) if (!misc.has(r.SpellID)) misc.set(r.SpellID, r);
const effects = new Map();
for (const r of csv('SpellEffect.csv')) {
  if (!effects.has(r.SpellID)) effects.set(r.SpellID, []);
  effects.get(r.SpellID).push(r);
}
const itemEffect = new Map(csv('ItemEffect.csv').map(r => [r.ID, r]));
const items = new Map(csv('Item.csv').map(r => [r.ID, r]));
const itemName = new Map(csv('ItemSparse.csv').map(r => [r.ID, r.Display_lang]));

// Whether a spell puts a buff on its caster: an aura there lasting a second
// or more, or until it's cancelled.
function Buffs(spell) {
  const row = misc.get(spell);
  const lasts = row ? durationOf.get(row.DurationIndex) : undefined;
  if (!(lasts === -1 || lasts >= 1000)) return false;
  return (effects.get(spell) || []).some(e => (e.Effect === APPLY_AURA && e.ImplicitTarget_0 === CASTER)
    || (AREA_AURAS.has(e.Effect) && (e.ImplicitTarget_0 === CASTER || e.ImplicitTarget_0 === '0')));
}

// Each use spell, with the trinkets that cast it.
const uses = new Map();
for (const link of csv('ItemXItemEffect.csv')) {
  const item = items.get(link.ItemID), effect = itemEffect.get(link.ItemEffectID);
  if (!item || item.InventoryType !== TRINKET || !effect || effect.TriggerType !== ON_USE) continue;
  const name = itemName.get(link.ItemID);
  if (SKIP(name) || effect.SpellID === '0') continue;
  if (!uses.has(effect.SpellID)) uses.set(effect.SpellID, []);
  uses.get(effect.SpellID).push(name || `item ${link.ItemID}`);
}

const differs = [], none = [];
let same = 0;
for (const spell of [...uses.keys()].sort((a, b) => a - b)) {
  if (Buffs(spell)) { same++; continue; }
  const cast = (effects.get(spell) || []).filter(e => TRIGGERS.has(e.Effect)).map(e => e.EffectTriggerSpell)
    .concat(SCRIPTED[spell] || []).filter(Buffs);
  if (cast.length) differs.push({ spell, cast: [...new Set(cast)], by: uses.get(spell) });
  else none.push(Number(spell));
}

const lines = differs.map(({ spell, cast, by }) => `    [${spell}] = { ${cast.join(', ')} }, -- ${[...new Set(by)].join(', ')}`);
console.log(`local TRINKET_BUFFS = {\n${lines.join('\n')}\n}`);
const rows = [];
for (let i = 0; i < none.length; i += 10) rows.push(`    ${none.slice(i, i + 10).join(', ')},`);
console.log(`local TRINKET_NO_BUFF = {}\nfor _, id in ipairs({\n${rows.join('\n')}\n}) do TRINKET_NO_BUFF[id] = true end`);
console.error(`${uses.size} trinket uses: ${same} buff you themselves, ${differs.length} through another spell, ${none.length} put no buff on you`);
