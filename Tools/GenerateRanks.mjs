// Builds Ranks.lua: every class spell and active racial in the WoW Forever
// client with the spell IDs of all its ranks, so a buff cast by another player
// at a rank you don't know still matches, a racial's buff matches whichever ID
// it carries (Walk on Air has two), and spells can be added by name.
// Also notes which classes and races each spell belongs to, so a profile
// shared across characters only shows each one what it can have, and which
// spells are passive, so the bars pass over what has nothing to track, and
// which are reactive, for the gold edge when one becomes usable, and each
// spell's base cooldown, for the Cooldown pulse page. And the auras with
// another ID a spell leads to, and the auras that are one buff in several
// IDs, so the Buffs and Debuffs bars light for them, and which of those no
// one learns as a spell, which no one sees on a cooldown bar.
// Reads Blizzard's own game tables for build 1.60.1.70338 (wago.tools db2
// exports of SpellName, Spell, SpellEffect, SpellMisc, SkillLineAbility,
// ChrRaces, SpellAuraRestrictions, SpellPower, SpellCooldowns,
// TraitDefinition, Item, ItemEffect and ItemXItemEffect).
// Pass a cache directory; missing tables are downloaded into it. No addon
// code or data is an input.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const BUILD = '1.60.1.70338';
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

// A hunter learns each pet ability as a Beast Training spell that teaches it
// to the pet (SpellEffect 36 or 57, LEARN_SPELL or LEARN_PET_SPELL, aimed at
// the pet: ImplicitTarget 5), and only those rows carry the hunter's class.
// The teaching spell has no cooldown and puts no aura on anyone: the pet's
// own spell does both. So each teaching row stands for the spell it teaches,
// at that spell's rank, still the hunter's (a hunter's Dash is his pet's),
// and a pet ability's teaching rows with no class (Furious Howl's first
// three ranks) come with the rest of its ranks.
const BEAST_TRAINING = 261, PET = 5;
const teaches = new Map();
for (const row of await table('SpellEffect')) {
    if ((+row.Effect === 36 || +row.Effect === 57) && (+row.ImplicitTarget_0 === PET || +row.ImplicitTarget_1 === PET)) {
        teaches.set(+row.SpellID, +row.EffectTriggerSpell);
    }
}
const teaching = row => +row.SkillLine === BEAST_TRAINING && teaches.has(+row.Spell);
const skillRows = await table('SkillLineAbility');
const petNames = new Set(skillRows.filter(row => +row.ClassMask > 0 && teaching(row)).map(row => names.get(+row.Spell)));
const abilities = skillRows.filter(row => +row.ClassMask > 0 || (teaching(row) && petNames.has(names.get(+row.Spell))))
    .map(row => {
        if (!teaching(row)) return row;
        const pet = teaches.get(+row.Spell);
        assert.equal(names.get(pet), names.get(+row.Spell), `${names.get(+row.Spell)} (${row.Spell}) teaches a spell of another name`);
        return { ...row, Spell: String(pet) };
    });

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
// A pet's spell is learned through its Beast Training row (above), though
// some (Cobra Reflexes) have no row of their own.
for (const row of skillRows) if (teaching(row)) learnable.add(teaches.get(+row.Spell));
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
// Base cooldowns, for the Cooldown pulse page: every spell ID in ns.RANKS
// with a cooldown of its own, in seconds (SpellCooldowns at difficulty 0:
// the longer of its own RecoveryTime and its category's). The page picks
// the spells it watches by these, so it never has to ask the game, which
// keeps cooldowns secret in a fight.
const cooldownLines = [...new Set([...groups.values()].flatMap(ranks => [...ranks.keys()]))].sort((a, b) => a - b)
    .filter(id => (cooldowns.get(id) || 0) > 0).map(id => ` [${id}]=${cooldowns.get(id) / 1000},`);
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

// Spells whose aura has another ID, so a bar watching the spell alone never
// lights: Bloodrage's rage buff, Vanish's stealth, Arcane Blast's stacks,
// Prayer of Mending's buff, a totem's buff on everyone near it, a rogue's
// poison on the target (the spell in the data makes the poison) and a trap's
// on whatever springs it. The aura is a spell of the same name (or that name
// without its rank numeral: Crippling Poison II's debuff is called Crippling
// Poison) that the spell sets off (SpellEffect EffectTriggerSpell, and what
// that sets off in turn) or names in its description ($ID), shown (not
// hidden, nor passive but for a totem's buff) and a buff or debuff by the
// passives' test above, a buff also on anyone you target (ImplicitTarget 25)
// or a party or raid member you target (57: Prayer of Mending's), a debuff
// also on the enemies in an aura left on the ground (SpellEffect 27,
// PERSISTENT_AREA_AURA: Frost Trap's ice, Hurricane's slow). A totem's
// aura is its buff on everyone near it, not the moment's extra attack its
// description names too (Windfury). A spell that does nothing but set off a
// buff (the Skyborne's Read Ley Line and Skysight) is that buff, whatever its
// name, with the other spells of the buff's name its description names (the
// other Energized). Each aura brings its other ranks (below): Prayer of
// Mending's later ranks name only the first rank's buff. By the ID of every
// spell a character can learn (a talent too: TraitDefinition).
const LINK_FRIENDLY = new Set([...FRIENDLY_TARGETS, 25, 57]);
const GROUND = 27, SUMMON = 28, TRIGGER = 64, LEARN = new Set([36, 57]);
const reach = new Map(), triggers = new Map(), effectsOf = new Map(), auraSigns = new Map();
for (const row of await table('SpellEffect')) {
    const id = +row.SpellID, effect = +row.Effect, then = +row.EffectTriggerSpell;
    if (!effectsOf.has(id)) effectsOf.set(id, new Set());
    effectsOf.get(id).add(effect);
    if (then && !LEARN.has(effect)) {
        if (!triggers.has(id)) triggers.set(id, new Set());
        triggers.get(id).add(then);
    }
    if (!AURAS.has(effect) && effect !== GROUND) continue;
    if (!auraSigns.has(id)) auraSigns.set(id, new Set());
    auraSigns.get(id).add(`${effect}/${row.EffectAura}`);
    const targets = [+row.ImplicitTarget_0, +row.ImplicitTarget_1];
    const kind = reach.get(id) || { buff: false, debuff: false };
    if (effect === 129 || effect === GROUND || targets.some(target => ENEMY_TARGETS.has(target))) kind.debuff = true;
    else if (AREA_BUFFS.has(effect) || targets.some(target => LINK_FRIENDLY.has(target))) kind.buff = true;
    reach.set(id, kind);
}
const shownAura = id => {
    const kind = reach.get(id);
    return !!kind && (kind.buff || kind.debuff) && !(flags(id) & HIDDEN) && (!passive(id) || areaBuffs.has(id));
};
// Ranks of one aura: spells of one name, icon and auras (SpellEffect Effect
// and EffectAura), each "Rank N" and shown. Contingency Plan's ward, shield
// and heal share a name and icon but not their auras, so they stay apart,
// and the Skyborne's two Energized have no rank at all: two buffs.
const familyKey = id => {
    if (!/^Rank \d+$/.test(subtext.get(id) || '') || !shownAura(id)) return null;
    return `${names.get(id)}|${(misc.get(id) || {}).SpellIconFileDataID}|${[...auraSigns.get(id)].sort().join(' ')}`;
};
const rankFamilies = new Map();
for (const id of [...names.keys()].sort((a, b) => a - b)) {
    const key = familyKey(id);
    if (!key) continue;
    if (!rankFamilies.has(key)) rankFamilies.set(key, []);
    rankFamilies.get(key).push(id);
}
const ranksOf = id => (familyKey(id) ? rankFamilies.get(familyKey(id)) : [id]);
const traitSpells = new Set((await table('TraitDefinition')).map(row => +row.SpellID).filter(id => id > 0));
const withoutNumeral = name => name.replace(/ (?:I|II|III|IV|V|VI|VII|VIII|IX|X)$/, '');
const spellAuras = new Map(), aurasByName = new Map();
for (const id of [...new Set([...learnable, ...traitSpells])].sort((a, b) => a - b)) {
    const name = names.get(id);
    if (!name || /[\\"\n]/.test(name) || passive(id)) continue;
    const effects = effectsOf.get(id) || new Set();
    const setOff = new Set();
    for (const first of triggers.get(id) || []) {
        setOff.add(first);
        for (const second of triggers.get(first) || []) setOff.add(second);
    }
    const found = new Set(), sameName = new Set();
    for (const other of [...setOff, ...named(id)]) {
        const otherName = names.get(other);
        if (other === id || !shownAura(other) || (otherName !== name && otherName !== withoutNumeral(name))) continue;
        if (effects.has(SUMMON) && !areaBuffs.has(other)) continue;
        sameName.add(other);
    }
    for (const aura of sameName) for (const rank of ranksOf(aura)) found.add(rank);
    if (effects.size > 0 && [...effects].every(effect => effect === TRIGGER) && !auraSigns.has(id)) {
        for (const buff of triggers.get(id) || []) {
            if (!shownAura(buff) || !reach.get(buff).buff || passive(buff)) continue;
            found.add(buff);
            for (const other of named(id)) if (names.get(other) === names.get(buff) && shownAura(other)) found.add(other);
        }
    }
    if (found.size === 0) continue;
    spellAuras.set(id, [...found].sort((a, b) => a - b));
    for (const aura of found) {
        const auraName = names.get(aura);
        if (auraName !== name && auraName !== withoutNumeral(name)) continue;
        if (!aurasByName.has(auraName)) aurasByName.set(auraName, new Set());
        aurasByName.get(auraName).add(aura);
    }
}
const spellAuraLines = [...spellAuras.keys()].map(id => ` [${id}]={${spellAuras.get(id).join(',')}},`);
// The same auras by their own name, for a spell kept by name: every rank's
// poison for an entry named Wound Poison, whose later ranks are spells of
// other names (Wound Poison II...). Only those the name's own spells in
// ns.RANKS aren't, or don't lead to already.
const nameAuraLines = [];
for (const name of [...aurasByName.keys()].sort()) {
    const own = [...(groups.get(name)?.keys() || [])];
    const already = new Set([...own, ...own.flatMap(id => spellAuras.get(id) || [])]);
    const extra = [...aurasByName.get(name)].filter(aura => !already.has(aura)).sort((a, b) => a - b);
    if (extra.length > 0 && !/[\\"\n]/.test(name)) nameAuraLines.push(` [${JSON.stringify(name)}]={${extra.join(',')}},`);
}

// Auras that are one buff in several IDs, for a buff kept by one of them:
// the ranks of an aura the class spells don't list (above: a totem's buff,
// a talent's aura, a warlock's pet's), where one rank is a spell a
// character can learn, a totem's buff, or an aura a spell above leads to;
// and the buffs food and drink give (Item ClassID 0, SubclassID 5: an
// item's spell, ItemEffect, or what it sets off), by name. Every food's
// Well Fed is one buff, whichever food it came from, though each stat has
// an ID of its own; so are Food and Drink while you eat or drink. Left out
// when the entry of its name watches every rank already: its spells in
// ns.RANKS lead to them (the test ns.NAME_AURAS uses). Not just for having
// a name in ns.RANKS: another spell can hold it, as a hunter's pet's
// passives hold the names of a totem's Frost, Fire and Nature Resistance.
const rankedIDs = new Set([...groups.values()].flatMap(ranks => [...ranks.keys()]));
const linkedAuras = new Set([...spellAuras.values()].flat());
const families = [];
for (const ids of rankFamilies.values()) {
    if (ids.length < 2 || ids.some(id => rankedIDs.has(id))) continue;
    const reached = new Set([...(groups.get(names.get(ids[0]))?.keys() || [])].flatMap(id => spellAuras.get(id) || []));
    if (ids.every(id => reached.has(id))) continue;
    if (ids.some(id => learnable.has(id) || traitSpells.has(id) || linkedAuras.has(id) || (passive(id) && areaBuffs.has(id)))) {
        families.push(ids);
    }
}
const FOOD_AND_DRINK = { ClassID: 0, SubclassID: 5 };
const foods = new Set((await table('Item')).filter(row => +row.ClassID === FOOD_AND_DRINK.ClassID
    && +row.SubclassID === FOOD_AND_DRINK.SubclassID).map(row => +row.ID));
const itemSpells = new Map((await table('ItemEffect')).map(row => [+row.ID, +row.SpellID]));
const foodBuffs = new Map();
function eaten(id, depth) {
    if (shownAura(id) && reach.get(id).buff && !passive(id)) {
        const name = names.get(id);
        if (!foodBuffs.has(name)) foodBuffs.set(name, new Set());
        foodBuffs.get(name).add(id);
    }
    if (depth < 2) for (const then of triggers.get(id) || []) eaten(then, depth + 1);
}
for (const row of await table('ItemXItemEffect')) {
    const spell = foods.has(+row.ItemID) && itemSpells.get(+row.ItemEffectID);
    if (spell) eaten(spell, 0);
}
for (const [name, ids] of foodBuffs) {
    if (ids.size > 1 && !groups.has(name) && name && !/[\\"\n]/.test(name)) families.push([...ids].sort((a, b) => a - b));
}
const familyOf = new Map();
for (const ids of families) {
    for (const id of ids) {
        assert(!familyOf.has(id), `${names.get(id)} (${id}) is in two families`);
        familyOf.set(id, ids);
    }
}
families.sort((a, b) => (names.get(a[0]) < names.get(b[0]) ? -1 : names.get(a[0]) > names.get(b[0]) ? 1 : a[0] - b[0]));
const familyLines = families.map(ids => ` {${ids.join(',')}},`);

// Auras no one learns as a spell, by ID: every aura above (a passive's, one
// a spell leads to, one in several IDs, food's) that isn't a spell a
// character can learn (SkillLineAbility, a racial, a talent:
// TraitDefinition) or one taught to a pet. No one ever knows one, so on the
// Cooldowns or Utility bar it shows for no one (Energized, Well Fed), while
// a pet's ability (a bat's Sonic Blast, which no Beast Training row teaches)
// or a talent (Holy Shield) shows for whoever has it.
const taught = new Set(teaches.values());
const listedIDs = new Set([...listed.values()].flatMap(ids => [...ids]));
const auraOnly = new Set();
for (const ids of [...auraLinks.buff.values(), ...auraLinks.debuff.values(), ...spellAuras.values(), ...families]) {
    for (const id of ids) {
        if (!learnable.has(id) && !traitSpells.has(id) && !taught.has(id)) auraOnly.add(id);
    }
}
for (const id of auraOnly) assert(!rankedIDs.has(id) && !listedIDs.has(id), `${names.get(id)} (${id}) is a spell and an aura no one learns`);
const auraOnlyLines = [...auraOnly].sort((a, b) => a - b).map(id => ` [${id}]=true,`);

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
    '-- passives give or are (a totem\'s buff), by the passive\'s ID, the auras',
    '-- with another ID other spells lead to (Bloodrage\'s buff, a poison\'s',
    '-- debuff), by the spell\'s ID and by the aura\'s name, the auras that are',
    '-- one buff in several IDs (a totem buff\'s ranks, Well Fed from any food),',
    '-- which of those auras no one learns as a spell, by ID,',
    '-- the reactive abilities, usable only once something happens in the',
    '-- fight (Overpower, Execute), by name, and the base cooldown in seconds',
    '-- of every spell ID in ns.RANKS that has one. Do not edit.',
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
    'ns.SPELL_AURAS = {',
    ...spellAuraLines,
    '}',
    'ns.NAME_AURAS = {',
    ...nameAuraLines,
    '}',
    'ns.AURA_FAMILIES = {',
    ...familyLines,
    '}',
    'ns.AURA_ONLY = {',
    ...auraOnlyLines,
    '}',
    'ns.REACTIVE = {',
    ...reactiveLines,
    '}',
    'ns.COOLDOWNS = {',
    ...cooldownLines,
    '}',
    '',
].join('\n');
await writeFile(join(root, 'Ranks.lua'), out);
const debuffCount = [...debuffs.values()].reduce((sum, set) => sum + set.size, 0);
console.log(`Ranks.lua: ${groups.size} spells, ${abilities.length} class ability rows, ${racials} racial spells, ${debuffCount} class debuffs, ${ownerLines.length} spells with their classes, ${raceLines.length} with their races, ${passiveLines.length} passive, ${auraLinks.buff.size} passives with a buff and ${auraLinks.debuff.size} with a debuff of their own, ${spellAuraLines.length} spells and ${nameAuraLines.length} names leading to an aura with another ID, ${families.length} auras in several IDs, ${auraOnly.size} auras no one learns, ${reactive.size} reactive, ${cooldownLines.length} with a cooldown.`);
