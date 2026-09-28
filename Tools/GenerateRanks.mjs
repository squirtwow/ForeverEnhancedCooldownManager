// Builds Ranks.lua: every class spell and active racial in the WoW Forever
// client with the spell IDs of all its ranks, so a buff cast by another player
// at a rank you don't know still matches, a racial's buff matches whichever ID
// it carries (Walk on Air has two), and spells can be added by name.
// Reads Blizzard's own game tables for build 1.60.1.70009 (wago.tools db2
// exports of SpellName, Spell and SkillLineAbility). Pass a cache directory;
// missing tables are downloaded into it. No addon code or data is an input.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const BUILD = '1.60.1.70009';
const root = dirname(dirname(fileURLToPath(import.meta.url)));
const cache = process.argv[2];
assert(cache, 'Pass a cache directory');
await mkdir(cache, { recursive: true });

async function table(name) {
    const file = join(cache, `${name}.csv`);
    let text;
    try {
        text = await readFile(file, 'utf8');
    } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        const response = await fetch(`https://wago.tools/db2/${name}/csv?build=${BUILD}`);
        assert(response.ok, `${name}: ${response.status}`);
        text = await response.text();
        await writeFile(file, text);
    }
    return parse(text);
}

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

const names = new Map((await table('SpellName')).map(r => [+r.ID, r.Name_lang]));
const subtext = new Map((await table('Spell')).map(r => [+r.ID, r.NameSubtext_lang]));
const abilities = (await table('SkillLineAbility')).filter(r => +r.ClassMask > 0);

// name -> Map(spellID -> rank)
const groups = new Map();
for (const row of abilities) {
    const id = +row.Spell;
    const name = names.get(id);
    // Hidden helper spells (stance and form passives) and test dummies can't
    // be tracked, and rune engraving spells aren't anything you'd put on a bar.
    if (!name || /[\\"\n]/.test(name) || /passive|dummy/i.test(name) || /^Engrave /.test(name)) continue;
    const match = (subtext.get(id) || '').match(/^Rank (\d+)$/);
    if (!groups.has(name)) groups.set(name, new Map());
    groups.get(name).set(id, match ? +match[1] : 0);
}

// Active racials: every spell the client marks "Racial" (not "Racial Passive").
let racials = 0;
for (const [id, sub] of subtext) {
    const name = names.get(id);
    if (sub !== 'Racial' || !name || /[\\"\n]/.test(name)) continue;
    if (!groups.has(name)) groups.set(name, new Map());
    groups.get(name).set(id, 0);
    racials++;
}

const lines = [...groups.keys()].sort().map(name => {
    const ids = [...groups.get(name).entries()].sort((a, b) => a[1] - b[1] || a[0] - b[0]).map(([id]) => id);
    return ` [${JSON.stringify(name)}]={${ids.join(',')}},`;
});

// Each class's debuffs, for the Layout page's search: its spells that put an
// aura on an enemy (SpellEffect: Effect 6 APPLY_AURA or 128
// APPLY_AREA_AURA_ENEMY, at an enemy target: the one you target, or enemies
// in an area or cone). ClassMask bits name the class.
const CLASSES = { 1: 'WARRIOR', 2: 'PALADIN', 4: 'HUNTER', 8: 'ROGUE', 16: 'PRIEST', 64: 'SHAMAN',
    128: 'MAGE', 256: 'WARLOCK', 1024: 'DRUID' };
const AURA_EFFECTS = new Set([6, 128]);
const ENEMY_TARGETS = new Set([6, 15, 16, 24, 53, 54, 104]);
const debuffIDs = new Set();
for (const row of await table('SpellEffect')) {
    if (AURA_EFFECTS.has(+row.Effect) && (ENEMY_TARGETS.has(+row.ImplicitTarget_0) || ENEMY_TARGETS.has(+row.ImplicitTarget_1))) {
        debuffIDs.add(+row.SpellID);
    }
}
const debuffs = new Map(Object.values(CLASSES).map(token => [token, new Set()]));
for (const row of abilities) {
    const name = names.get(+row.Spell);
    if (!groups.has(name) || !debuffIDs.has(+row.Spell)) continue;
    for (const [bit, token] of Object.entries(CLASSES)) {
        if (+row.ClassMask & +bit) debuffs.get(token).add(name);
    }
}
const debuffLines = [...debuffs.entries()].sort().map(([token, set]) =>
    ` ${token}={${[...set].sort().map(name => JSON.stringify(name)).join(',')}},`);

// The classes each spell belongs to, so a profile shared across classes can
// pass over another class's spells. Spells every class has, and racials,
// belong to everyone and aren't listed.
const owners = new Map();
for (const row of abilities) {
    const name = names.get(+row.Spell);
    if (!groups.has(name)) continue;
    if (!owners.has(name)) owners.set(name, new Set());
    for (const [bit, token] of Object.entries(CLASSES)) {
        if (+row.ClassMask & +bit) owners.get(name).add(token);
    }
}
const classCount = Object.keys(CLASSES).length;
const ownerLines = [...owners.entries()].filter(([, set]) => set.size > 0 && set.size < classCount).sort()
    .map(([name, set]) => ` [${JSON.stringify(name)}]="${[...set].sort().join(' ')}",`);

const out = [
    `-- Generated by Tools/GenerateRanks.mjs from Blizzard game data for build ${BUILD}.`,
    '-- Every class spell and active racial with the spell IDs of all its ranks,',
    '-- each class\'s spells that leave a debuff on an enemy, and the classes each',
    '-- class spell belongs to. Do not edit.',
    'local _, ns = ...',
    'ns.RANKS = {',
    ...lines,
    '}',
    'ns.DEBUFFS = {',
    ...debuffLines,
    '}',
    'ns.SPELL_CLASSES = {',
    ...ownerLines,
    '}',
    '',
].join('\n');
await writeFile(join(root, 'Ranks.lua'), out);
const debuffCount = [...debuffs.values()].reduce((sum, set) => sum + set.size, 0);
console.log(`Ranks.lua: ${groups.size} spells, ${abilities.length} class ability rows, ${racials} racial spells, ${debuffCount} class debuffs, ${ownerLines.length} spells with their classes.`);
