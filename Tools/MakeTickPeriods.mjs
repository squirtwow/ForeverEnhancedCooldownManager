// Prints Buffs.lua's ns.TICK_PERIODS table from Forever's spell data: every
// class debuff (Ranks.lua's ns.DEBUFFS) that ticks, by name, and how often in
// seconds (its periodic effect's EffectAuraPeriod), for Count ticks on the
// Debuffs bar. A name whose ranks tick at different paces takes the most
// common one.
//   node Tools/MakeTickPeriods.mjs [gamedata folder]
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2] || 'C:/AddonDev/_Toolchain/gamedata/forever-70425';
const here = path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, '$1');

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

// Periodic auras that tick on a target: damage, heal, leech, mana leech,
// damage by percent, and a periodic trigger (Insect Swarm's kind).
const PERIODIC = new Set(['3', '8', '23', '53', '64', '89']);

const ranks = fs.readFileSync(path.join(here, '..', 'Ranks.lua'), 'utf8');
const idsOf = new Map();
for (const m of ranks.matchAll(/^ \["([^"]+)"\]=\{([\d,]+)\},$/gm)) {
  if (!idsOf.has(m[1])) idsOf.set(m[1], m[2].split(',').map(Number));
}
const debuffBlock = ranks.match(/^ns\.DEBUFFS = \{\n([\s\S]*?)\n\}/m)[1];
const names = new Set();
for (const m of debuffBlock.matchAll(/"([^"]+)"/g)) names.add(m[1]);

// How long each spell's aura lasts (ms), to leave out one that ticks only
// once, as it ends (Bane of Doom): its count would read 0 the whole time.
const durationOf = new Map(); // duration index -> its row
for (const d of csv('SpellDuration.csv')) durationOf.set(d.ID, d);
const lasts = new Map(); // spell ID -> ms (the base length)
const allLasts = new Map(); // spell ID -> every length it can have (ms)
for (const m of csv('SpellMisc.csv')) {
  const d = durationOf.get(m.DurationIndex);
  const ms = d ? Number(d.Duration) : 0;
  if (!ms) continue;
  lasts.set(Number(m.SpellID), ms);
  // Longer with each combo point spent (Rupture 6 s to 16 s, 2 s a point).
  const all = [ms];
  const max = Number(d.MaxDuration), step = Number(d.DurationPerResource);
  if (step > 0 && max > ms) for (let x = ms + step; x <= max; x += step) all.push(x);
  allLasts.set(Number(m.SpellID), all);
}

const periodOf = new Map(); // spell ID -> ms
for (const e of csv('SpellEffect.csv')) {
  if (PERIODIC.has(e.EffectAura) && Number(e.EffectAuraPeriod) > 0) {
    const id = Number(e.SpellID), period = Number(e.EffectAuraPeriod);
    if (lasts.has(id) && lasts.get(id) / period < 2) continue;
    if (!periodOf.has(id)) periodOf.set(id, period);
  }
}

// Not a debuff you'd count: Tame Beast's channel on the beast.
const SKIP = new Set(['Tame Beast']);

const lines = [];
for (const name of [...names].sort()) {
  if (SKIP.has(name)) continue;
  const counts = new Map();
  for (const id of idsOf.get(name) || []) {
    const ms = periodOf.get(id);
    if (ms) counts.set(ms, (counts.get(ms) || 0) + 1);
  }
  if (counts.size === 0) continue;
  const ms = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0][0];
  lines.push(`    [${JSON.stringify(name)}] = ${ms / 1000},`);
}
console.log(`ns.TICK_PERIODS = {\n${lines.join('\n')}\n}`);

// And how long each debuff lasts (seconds, each length its ranks have), so a
// joined icon holding debuffs that tick at different paces counts only while
// one of the counted ones is up (told apart by length: Bane of Agony 24 s,
// Bane of Doom 60 s). Lasting forever or no time: left out.
const lastsLines = [];
for (const name of [...names].sort()) {
  const all = new Set();
  for (const id of idsOf.get(name) || []) {
    for (const ms of allLasts.get(id) || []) if (ms > 0) all.add(ms / 1000);
  }
  if (all.size === 0) continue;
  lastsLines.push(`    [${JSON.stringify(name)}] = { ${[...all].sort((a, b) => a - b).join(', ')} },`);
}
console.log(`ns.DEBUFF_LASTS = {\n${lastsLines.join('\n')}\n}`);
