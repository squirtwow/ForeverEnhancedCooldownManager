// Builds Ranks.lua: every class spell and active racial in the WoW Forever
// client with the spell IDs of all its ranks, so a buff cast by another player
// at a rank you don't know still matches, a racial's buff matches whichever ID
// it carries (Walk on Air has two), and spells can be added by name.
// Also notes which classes and races each spell belongs to, so a profile
// shared across characters only shows each one what it can have, and which
// spells are passive, so the bars pass over what has nothing to track, and
// which are reactive, for the gold edge when one becomes usable.
// Reads Blizzard's own game tables for build 1.60.1.70170 (wago.tools db2
// exports of SpellName, Spell, SpellEffect, SpellMisc, SkillLineAbility,
// ChrRaces, SpellAuraRestrictions and SpellPower).
// Pass a cache directory; missing tables are downloaded into it. No addon
// code or data is an input.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const BUILD = '1.60.1.70170';
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
// aura on an enemy (SpellEffect: Effect 6 APPLY_AURA or 129
// APPLY_AREA_AURA_ENEMY, at an enemy target: the one you target, or enemies
// in an area or cone). ClassMask bits name the class.
const CLASSES = { 1: 'WARRIOR', 2: 'PALADIN', 4: 'HUNTER', 8: 'ROGUE', 16: 'PRIEST', 64: 'SHAMAN',
    128: 'MAGE', 256: 'WARLOCK', 1024: 'DRUID' };
const AURA_EFFECTS = new Set([6, 129]);
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

// The races each spell belongs to, so a profile shared across races can pass
// over another race's racials (active or passive) and the class spells only
// some races get (an undead priest's Touch of Weakness on a human priest).
// A name is listed only when every SkillLineAbility row of every spell with
// that name is limited to some races; one row any race can learn leaves it
// out. Race masks are PlayableRaceBit bits (ChrRaces); the list holds race
// IDs, as UnitRace gives them. The addon checks a name's classes and races
// apart, so the build fails unless that gives exactly the class and race
// pairs its rows do.
const raceOfBit = new Map((await table('ChrRaces')).filter(r => +r.PlayableRaceBit >= 0)
    .map(r => [+r.PlayableRaceBit, +r.ID]));
const playable = new Set(raceOfBit.values());
function rowRaces(row) {
    const races = new Set();
    [+row.RaceMasks_0 >>> 0, +row.RaceMasks_1 >>> 0].forEach((word, half) => {
        for (let bit = 0; bit < 32; bit++) {
            const id = (word >>> bit) & 1 ? raceOfBit.get(half * 32 + bit) : undefined;
            if (id) races.add(id);
        }
    });
    return races.size === 0 || races.size === playable.size ? null : races;
}
function rowClasses(row) {
    const mask = +row.ClassMask;
    const classes = new Set(Object.entries(CLASSES).filter(([bit]) => mask > 0 && mask & +bit).map(([, token]) => token));
    return classes.size === 0 || classes.size === classCount ? null : classes;
}
const rowsByName = new Map();
for (const row of await table('SkillLineAbility')) {
    const name = names.get(+row.Spell);
    if (!name || /[\\"\n]/.test(name)) continue;
    if (!rowsByName.has(name)) rowsByName.set(name, []);
    rowsByName.get(name).push(row);
}
const raceLines = [];
for (const [name, rows] of [...rowsByName.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
    const races = rows.map(rowRaces);
    if (races.some(set => set === null)) continue;
    const all = new Set(races.flatMap(set => [...set]));
    const classes = rows.map(rowClasses);
    const listed = owners.get(name);
    const limited = listed && listed.size > 0 && listed.size < classCount ? listed : null;
    for (const token of Object.values(CLASSES)) {
        for (const race of all) {
            const byRows = rows.some((_, i) => (classes[i] === null || classes[i].has(token)) && races[i].has(race));
            const byAddon = limited === null || limited.has(token);
            assert.equal(byAddon, byRows, `${name}: a ${token} of race ${race} ${byRows ? 'has' : "doesn't have"} it`);
        }
    }
    raceLines.push(` [${JSON.stringify(name)}]="${[...all].sort((a, b) => a - b).join(' ')}",`);
}

// Passive spells, so the bars can pass over what has nothing to track: an
// always-on passive (Underwater Breathing, a weapon specialization) never
// shows. SpellMisc Attributes_0 bit 0x40 is SPELL_ATTR0_PASSIVE (a spell's
// row for difficulty 0 when it has several). Listed by name with their IDs:
// every passive spell a character can learn (SkillLineAbility, and the
// client's "Racial" and "Racial Passive" spells). A name shared with an
// active spell (a troll's Regeneration and a mage's) is told apart by ID,
// so only the passive IDs are listed. A passive with a cooldown (a shaman's
// Reincarnation, an hour) isn't listed (below): its cooldown is worth
// tracking. The addon takes any ID in ns.RANKS that isn't listed here as
// active, so the build fails unless every other passive one is.
const misc = new Map();
for (const row of await table('SpellMisc')) {
    const id = +row.SpellID;
    const kept = misc.get(id);
    if (!kept || (+row.DifficultyID === 0 && +kept.DifficultyID !== 0)) misc.set(id, row);
}
const PASSIVE = 0x40, HIDDEN = 0x80; // SPELL_ATTR0_PASSIVE, SPELL_ATTR0_DO_NOT_DISPLAY
const flags = id => (misc.has(id) ? +misc.get(id).Attributes_0 >>> 0 : 0);
const passive = id => (flags(id) & PASSIVE) !== 0;
const learnable = new Set((await table('SkillLineAbility')).map(row => +row.Spell));
for (const [id, sub] of subtext) if (/^Racial/.test(sub)) learnable.add(id);
const passives = new Map();
for (const id of [...learnable].sort((a, b) => a - b)) {
    const name = names.get(id);
    if (!name || /[\\"\n]/.test(name)) continue;
    assert(misc.has(id), `${name} (${id}) has no SpellMisc row, so whether it's passive isn't known`);
    if (!passive(id)) continue;
    if (!passives.has(name)) passives.set(name, new Set());
    passives.get(name).add(id);
}
// A passive's own resurrection goes with it. Reincarnation lets you take
// 21169 on the death screen, a spell that brings you back (SpellEffect 94,
// SELF_RESURRECT) and holds the hour's cooldown. You never cast it, and the
// passive goes on no bar, so neither does it: it's listed with the
// passive's IDs, though the game doesn't mark it passive.
const SELF_RESURRECT = 94;
const resurrections = new Set((await table('SpellEffect')).filter(row => +row.Effect === SELF_RESURRECT)
    .map(row => +row.SpellID));
const ownResurrection = id => resurrections.has(id) && !passive(id) && passives.has(names.get(id));
// But a passive with a cooldown of its own, or on its own resurrection, has
// something to track: Reincarnation's hour shows whether a shaman can come
// back (the user's call, 2026-10-01). It isn't listed, so it goes on the
// cooldown bars like an active spell.
const cooldowns = new Map();
for (const row of await table('SpellCooldowns')) {
    if (+row.DifficultyID !== 0) continue;
    cooldowns.set(+row.SpellID, Math.max(+row.RecoveryTime || 0, +row.CategoryRecoveryTime || 0));
}
const timed = new Set();
for (const id of learnable) {
    if ((passive(id) || ownResurrection(id)) && (cooldowns.get(id) || 0) > 0) timed.add(names.get(id));
}
const listed = new Map([...passives].filter(([name]) => !timed.has(name)).map(([name, ids]) => [name, new Set(ids)]));
for (const id of [...learnable].sort((a, b) => a - b)) {
    if (ownResurrection(id) && listed.has(names.get(id))) listed.get(names.get(id)).add(id);
}
for (const [name, ranks] of groups) {
    for (const id of ranks.keys()) {
        assert.equal(listed.has(name) && listed.get(name).has(id), (passive(id) || ownResurrection(id)) && !timed.has(name),
            `${name} (${id}) in ns.RANKS`);
    }
}
assert.deepEqual([...timed].sort(), ['Reincarnation'], 'only Reincarnation is a passive with a cooldown');
const passiveLines = [...listed.keys()].sort()
    .map(name => ` [${JSON.stringify(name)}]={${[...listed.get(name)].sort((a, b) => a - b).join(',')}},`);

// A passive whose effect is an aura that comes and goes (Plainsrunning's
// speed buff, a talent's proc) can be tracked by that aura on the Buffs or
// Debuffs bar. Its aura: a spell of the same name that isn't passive or
// hidden and puts an aura (SpellEffect APPLY_AURA or an area aura) on you,
// your pet or an ally you target (a buff), or on an enemy (a debuff, as for
// the class debuffs above). The passive names it (its description's $ID:
// Inspiration's armor buff), or it has the passive's icon and the passive
// works through the game's own scripts (an APPLY_AURA effect with the dummy
// aura: Plainsrunning's speed buff). A passive that's simply always on
// (Parry, a pet's resistance) gives no aura of its own, so an NPC's Parry or
// a potion's Fire Resistance isn't its, and an NPC's Regeneration has
// another icon. Each passive's ID, with those auras' IDs.
// Area auras: 35 (party), 65 (raid), 119 (pet), 128 (friends) and 143
// (owner) land on your side, 129 on enemies.
const AURAS = new Set([6, 35, 65, 119, 128, 129, 143]);
const AREA_BUFFS = new Set([35, 65, 119, 128, 143]);
const DUMMY = 4; // SPELL_AURA_DUMMY
const FRIENDLY_TARGETS = new Set([1, 5, 21]);
const auraKinds = new Map(), scripted = new Set(), areaBuffs = new Set();
for (const row of await table('SpellEffect')) {
    const id = +row.SpellID, effect = +row.Effect;
    if (effect === 6 && +row.EffectAura === DUMMY) scripted.add(id);
    if (AREA_BUFFS.has(effect)) areaBuffs.add(id);
    if (!AURAS.has(effect)) continue;
    const targets = [+row.ImplicitTarget_0, +row.ImplicitTarget_1];
    const kind = auraKinds.get(id) || { buff: false, debuff: false };
    if (effect === 129 || targets.some(target => ENEMY_TARGETS.has(target))) kind.debuff = true;
    else if (targets.some(target => FRIENDLY_TARGETS.has(target))) kind.buff = true;
    auraKinds.set(id, kind);
}
const descriptions = new Map((await table('Spell')).map(row => [+row.ID, row.Description_lang || '']));
const named = id => new Set([...(descriptions.get(id) || '').matchAll(/\$(\d+)/g)].map(match => +match[1]));
const spellsNamed = new Map();
for (const [id, name] of names) {
    if (!spellsNamed.has(name)) spellsNamed.set(name, []);
    spellsNamed.get(name).push(id);
}
const auraLinks = { buff: new Map(), debuff: new Map() };
function link(bar, id, aura) {
    if (!auraLinks[bar].has(id)) auraLinks[bar].set(id, []);
    auraLinks[bar].get(id).push(aura);
}
for (const [name, ids] of passives) {
    for (const id of ids) {
        const gives = named(id);
        for (const other of spellsNamed.get(name)) {
            const kind = auraKinds.get(other);
            if (!kind || passive(other) || flags(other) & HIDDEN) continue;
            const looks = scripted.has(id) && misc.get(other).SpellIconFileDataID === misc.get(id).SpellIconFileDataID;
            if (!gives.has(other) && !looks) continue;
            for (const bar of ['buff', 'debuff']) if (kind[bar]) link(bar, id, other);
        }
    }
}
// The game marks some auras that come and go passive too: a totem's or a
// battle standard's buff on everyone near it (Strength of Earth, Mana
// Spring). Shown, with an area aura on your side, each is its own buff.
for (const id of [...areaBuffs].sort((a, b) => a - b)) {
    if (passive(id) && !(flags(id) & HIDDEN)) link('buff', id, id);
}
// The addon takes every passive these list as passive.
for (const bar of ['buff', 'debuff']) {
    for (const id of auraLinks[bar].keys()) assert(passive(id), `${names.get(id)} (${id}) isn't passive`);
}
const linkLines = bar => [...auraLinks[bar].keys()].sort((a, b) => a - b)
    .map(id => ` [${id}]={${auraLinks[bar].get(id).sort((a, b) => a - b).join(',')}},`);

// Reactive abilities, for the gold edge on the bars: spells a character can
// learn (any SkillLineAbility row, so talents like Riposte too) that can only
// be used once something happens in the fight, by name. The game gates them
// with an aura state (SpellAuraRestrictions): on you after you dodge, parry
// or block (1, and 7 for a hunter's parry), after a kill that gives
// experience or honor (10) or while Enraged (17); on your target at 20%
// health or less (2) or below 50% (25). Overpower has none: it costs a combo
// point (SpellPower PowerType 4), which a warrior only gets when the target
// dodges, so a spell with that cost that no Rogue or Druid learns counts too.
// Left out, as the edge would be noise: a Seal on you (5: Judgement, lit
// almost all the time), your own Rejuvenation or Regrowth on the target (15:
// Swiftmend), and the auras you put up yourself or a form (Cat Form for
// Tiger's Fury and Shifting Power, your Immolate for Conflagrate, your
// Temporal Beacon for Rewind Time). Rune abilities with no SkillLineAbility
// row (Rampage, Deep Freeze) have no way to be learned in this data, so they
// aren't listed.
// The build fails on any other gate on a learnable spell, so a new one is
// sorted before it ships, and unless every learnable spell of a listed name
// is gated (a rank without the gate would be lit whenever it's usable).
const REACTIVE_STATES = { CasterAuraState: new Set([1, 7, 10, 17]), TargetAuraState: new Set([2, 25]) };
const NOISY_STATES = { CasterAuraState: new Set([5]), TargetAuraState: new Set([15]) };
const OWN_AURAS = new Set([768, 1282590, 400735]); // Cat Form, Immolate, Temporal Beacon
const COMBO_POINTS = 4;
const COMBO_CLASSES = 8 | 1024; // Rogue, Druid
const reactiveIDs = new Set();
for (const row of await table('SpellAuraRestrictions')) {
    const id = +row.SpellID;
    if (!learnable.has(id)) continue;
    const name = `${names.get(id)} (${id})`;
    for (const column of Object.keys(REACTIVE_STATES)) {
        const state = +row[column];
        if (!state) continue;
        assert(REACTIVE_STATES[column].has(state) || NOISY_STATES[column].has(state), `${name}: ${column} ${state} isn't sorted`);
        if (REACTIVE_STATES[column].has(state)) reactiveIDs.add(id);
    }
    for (const column of ['CasterAuraSpell', 'TargetAuraSpell']) {
        assert(!+row[column] || OWN_AURAS.has(+row[column]), `${name}: ${column} ${row[column]} isn't sorted`);
    }
    for (const column of ['CasterAuraType', 'TargetAuraType']) assert.equal(+row[column], 0, `${name}: ${column} isn't sorted`);
}
const classMasks = new Map();
for (const row of await table('SkillLineAbility')) classMasks.set(+row.Spell, (classMasks.get(+row.Spell) || 0) | +row.ClassMask);
for (const row of await table('SpellPower')) {
    const id = +row.SpellID;
    if (+row.PowerType !== COMBO_POINTS || !learnable.has(id)) continue;
    const mask = classMasks.get(id) || 0;
    assert(mask > 0, `${names.get(id)} (${id}) costs combo points, but which class learns it isn't known`);
    if (!(mask & COMBO_CLASSES)) reactiveIDs.add(id);
}
const reactive = new Set([...reactiveIDs].map(id => names.get(id)));
for (const id of learnable) {
    const name = names.get(id);
    if (reactive.has(name)) assert(reactiveIDs.has(id), `${name} (${id}) isn't gated like the rest of its name`);
}
for (const name of reactive) assert(!/[\\"\n]/.test(name), `${name}: can't be written as a name`);
const reactiveLines = [...reactive].sort().map(name => ` [${JSON.stringify(name)}]=true,`);

const out = [
    `-- Generated by Tools/GenerateRanks.mjs from Blizzard game data for build ${BUILD}.`,
    '-- Every class spell and active racial with the spell IDs of all its ranks,',
    '-- each class\'s spells that leave a debuff on an enemy, the classes each',
    '-- class spell belongs to, the races (race IDs) each racial or race-only',
    '-- spell belongs to, every passive spell a character can learn with nothing',
    '-- to track (its passive IDs), the buffs and debuffs of their own some',
    '-- passives give or are (a totem\'s buff), by the passive\'s ID, and the',
    '-- reactive abilities, usable only once something happens in the fight',
    '-- (Overpower, Execute), by name. Do not edit.',
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
    'ns.SPELL_RACES = {',
    ...raceLines,
    '}',
    'ns.PASSIVES = {',
    ...passiveLines,
    '}',
    'ns.PASSIVE_BUFFS = {',
    ...linkLines('buff'),
    '}',
    'ns.PASSIVE_DEBUFFS = {',
    ...linkLines('debuff'),
    '}',
    'ns.REACTIVE = {',
    ...reactiveLines,
    '}',
    '',
].join('\n');
await writeFile(join(root, 'Ranks.lua'), out);
const debuffCount = [...debuffs.values()].reduce((sum, set) => sum + set.size, 0);
console.log(`Ranks.lua: ${groups.size} spells, ${abilities.length} class ability rows, ${racials} racial spells, ${debuffCount} class debuffs, ${ownerLines.length} spells with their classes, ${raceLines.length} with their races, ${passiveLines.length} passive, ${auraLinks.buff.size} passives with a buff and ${auraLinks.debuff.size} with a debuff of their own, ${reactive.size} reactive.`);
