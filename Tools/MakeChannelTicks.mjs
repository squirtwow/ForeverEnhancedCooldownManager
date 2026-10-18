// Prints CastBar.lua's CHANNEL_TICKS table from Forever's spell data: every
// class spell (and bandage) that's channelled with a periodic effect, and how
// many times it ticks (its duration over its period).
//   node Tools/MakeChannelTicks.mjs [gamedata folder]
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2] || 'C:/AddonDev/_Toolchain/gamedata/forever-70425';

function csv(file) {
  const lines = fs.readFileSync(path.join(dir, file), 'utf8').split(/\r?\n/).filter(Boolean);
  const head = lines[0].split(',');
  return lines.slice(1).map(line => {
    const values = line.match(/("([^"]|"")*"|[^,]*)(,|$)/g).map(v => v.replace(/,$/, '').replace(/^"|"$/g, ''));
    const row = {};
    head.forEach((key, i) => { row[key] = values[i]; });
    return row;
  });
}

const CHANNELLED = 0x4 | 0x40; // SpellMisc Attributes_1: channelled (either flag)
const CLASS = '7'; // SkillLine CategoryID for class spell lines

const classLines = new Set(csv('SkillLine.csv').filter(s => s.CategoryID === CLASS).map(s => s.ID));
const abilities = csv('SkillLineAbility.csv');
const classSpells = new Set(abilities.filter(a => classLines.has(a.SkillLine)).map(a => a.Spell));
// Rune-only spells, as Tools/GenerateForms.mjs judges them (Forever has no
// engravings): a seasonal spell whose every row is class-masked and taught by
// another spell, and no talent.
const talents = new Set(csv('TraitDefinition.csv').map(t => t.SpellID));
const rowsOf = new Map();
for (const a of abilities) {
  if (!rowsOf.has(a.Spell)) rowsOf.set(a.Spell, []);
  rowsOf.get(a.Spell).push(a);
}
function runeOnly(id) {
  const rows = rowsOf.get(id) || [];
  return Number(id) >= 395000 && Number(id) < 480000 && rows.length > 0
    && rows.every(r => Number(r.AcquireMethod) === 3 && Number(r.ClassMask) !== 0) && !talents.has(id);
}
const names = new Map(csv('SpellName.csv').map(n => [n.ID, n.Name_lang]));
const durations = new Map(csv('SpellDuration.csv').map(d => [d.ID, Number(d.Duration)]));
const periods = new Map();
for (const effect of csv('SpellEffect.csv')) {
  const period = Number(effect.EffectAuraPeriod);
  if (period > 0 && !periods.has(effect.SpellID)) periods.set(effect.SpellID, period);
}

const ticks = [];
for (const misc of csv('SpellMisc.csv')) {
  const id = misc.SpellID;
  if (!((Number(misc.Attributes_1) >>> 0) & CHANNELLED)) continue;
  if (!(classSpells.has(id) || names.get(id) === 'First Aid') || runeOnly(id)) continue;
  const period = periods.get(id), duration = durations.get(misc.DurationIndex);
  if (!(period > 0 && duration > 0)) continue;
  const count = Math.round(duration / period);
  if (count >= 2) ticks.push([Number(id), count, names.get(id)]);
}
ticks.sort((a, b) => a[0] - b[0]);

const byName = new Map();
for (const [id, count, name] of ticks) {
  if (!byName.has(name)) byName.set(name, []);
  byName.get(name).push(`[${id}] = ${count}`);
}
const out = ['local CHANNEL_TICKS = {'];
for (const [name, entries] of [...byName].sort((a, b) => a[0].localeCompare(b[0]))) {
  out.push(`    ${entries.join(', ')}, -- ${name}`);
}
out.push('}');
console.log(out.join('\n'));
console.error(`${ticks.length} spells, ${byName.size} names`);
