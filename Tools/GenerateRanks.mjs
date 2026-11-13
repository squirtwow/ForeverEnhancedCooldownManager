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
// Reads Blizzard's own game tables for build 1.60.1.70753 (wago.tools db2
// exports of SpellName, Spell, SpellEffect, SpellMisc, SkillLineAbility,
// ChrRaces, SpellAuraRestrictions, SpellPower, SpellCooldowns,
// TraitDefinition, Item, ItemEffect and ItemXItemEffect).
// Pass a cache directory; missing tables are downloaded into it. A table
// already there is used whatever its build, so give each build a new, empty
// one. No addon code or data is an input.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const BUILD = '1.60.1.70938';
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
// Spells Forever's trainers no longer teach need no list since build 70753:
// Salvation, Mass Salvation, Revoke and both Blessings of Light lost their
// names, so the rows they still have are nameless and go nowhere below.
// Spells.lua's GROUP pairs for Salvation and Blessing of Light went with them:
// put them back if one is taught again. Voice of Truth left the tree but
// trainers teach it (rows with a level, and Blizzard says nothing else), so
// it stays in the tables. Binding Heal did too until build 70790 dropped its
// rows (with Lava Burst's), so both are gone from the tables: a priest who
// still knows it keeps it on a cooldown bar, as any spell no table names.
// Talents gone from their class's tree, though the client data still gives
// each a SkillLineAbility row and a TraitDefinition: this script reads no
// tree (TraitNode), so it can't see that. Source: the data's trees, build
// 70707's for Piercing Ice and Arcane Focus (Mage,
// C:\AddonDev\_ForeverData\changes-70707\FACTS.md), build 70753's for the
// rest, with Blizzard's 3 Nov 2026 notes for Berserk. Their rows are left out
// here, as if the game had dropped them: no one learns these, so no table
// offers them, and they count as no talent below. All but Berserk are
// passives with no aura, so no bar ever showed them. Each with the ClassMask
// its row has. The build fails once a listed row is gone or changes hands, so
// the list goes when it isn't needed.
const OUT_OF_TREE = new Map([
    [11151, ['Piercing Ice', 128]], [11222, ['Arcane Focus', 0]],
    [417141, ['Berserk', 1024]], [1314103, ['Improved Seal of Fury', 2]], [20196, ['One-Handed Weapon Specialization', 0]],
]);
const allSkillRows = await table('SkillLineAbility');
for (const [id, [name, mask]] of OUT_OF_TREE) {
    const rows = allSkillRows.filter(row => +row.Spell === id);
    assert(names.get(id) === name && rows.length > 0 && rows.every(row => +row.ClassMask === mask),
        `${name} (${id}): its rows changed in this build's data, so drop it from OUT_OF_TREE`);
}
// Spells with a class's row that no one in Forever learns (2026-11-13, an
// audit of the Debuffs page's search after a player missed Shadow
// Vulnerability): Curse of Idiocy, whose one row says another spell teaches
// it (AcquireMethod 3) though no spell, talent or item does, and Enchanted
// Flare, which only a Season of Discovery tome teaches (Tome of Enchanted
// Flare, 237041; Forever has no runes). The Debuffs search offered Curse of
// Idiocy to every warlock, and would offer Enchanted Flare to hunters once
// ground auras count (below). Their rows are left out as OUT_OF_TREE's are,
// each with the items that teach it. The build fails once a row changes or
// something else teaches one (a talent, SpellLearnSpell, a spell's teaching
// effect or another item), so the list goes when it isn't needed.
const NOT_TAUGHT = new Map([[1010, ['Curse of Idiocy', 256, []]], [1221404, ['Enchanted Flare', 4, [237041]]]]);
{
    const talents = new Set((await table('TraitDefinition')).map(row => +row.SpellID));
    const learned = new Set((await table('SpellLearnSpell')).map(row => +row.LearnSpellID));
    const teachers = new Map([...NOT_TAUGHT.keys()].map(id => [id, new Set([id])]));
    for (const row of await table('SpellEffect')) {
        if ((+row.Effect === 36 || +row.Effect === 57) && teachers.has(+row.EffectTriggerSpell)) teachers.get(+row.EffectTriggerSpell).add(+row.SpellID);
    }
    const effectSpell = new Map((await table('ItemEffect')).map(row => [+row.ID, +row.SpellID]));
    const books = new Map([...NOT_TAUGHT.keys()].map(id => [id, []]));
    for (const row of await table('ItemXItemEffect')) {
        for (const [id, spells] of teachers) if (spells.has(effectSpell.get(+row.ItemEffectID))) books.get(id).push(+row.ItemID);
    }
    for (const [id, [name, mask, items]] of NOT_TAUGHT) {
        const rows = allSkillRows.filter(row => +row.Spell === id);
        assert(names.get(id) === name && rows.length > 0 && rows.every(row => +row.ClassMask === mask) && !talents.has(id)
            && !learned.has(id) && teachers.get(id).size === 1 && books.get(id).sort((a, b) => a - b).join() === items.join(),
            `${name} (${id}): its rows changed or something else teaches it in this build's data, so drop it from NOT_TAUGHT`);
    }
}
// Talents only a class's talent tree holds, with no SkillLineAbility row at
// all (build 70790: 84 of them, every class, from a mage's Missile Barrage
// and Fingers of Frost to a rogue's Boot Knife and Composure, a shaman's
// Maelstrom Weapon and a paladin's Infusion of Light). Without a row no table
// named them, so the Layout page's search never offered their procs. Each
// class has one tree (SkillLineXTraitTree to its skill line, whose
// SkillRaceClassInfo rows carry the class), and each node's entries lead to
// a TraitDefinition's spell. Such a spell stands here as a row of that class,
// learned from the tree, so the tables below treat it as they treat any
// other talent: its passive, its own buff or debuff, its cooldown. A talent
// with a row of its own (Adrenaline Rush, Poised) keeps its row and nothing
// is added.
const classOfLine = new Map();
for (const row of await table('SkillRaceClassInfo')) {
    const mask = +row.ClassMask;
    if (mask <= 0) continue;
    classOfLine.set(+row.SkillID, (classOfLine.get(+row.SkillID) || 0) | mask);
}
const classOfTree = new Map();
for (const row of await table('SkillLineXTraitTree')) {
    const mask = classOfLine.get(+row.SkillLineID);
    if (mask) classOfTree.set(+row.TraitTreeID, mask);
}
const treeOfNode = new Map((await table('TraitNode')).map(row => [+row.ID, +row.TraitTreeID]));
const definitionOfEntry = new Map((await table('TraitNodeEntry')).map(row => [+row.ID, +row.TraitDefinitionID]));
const spellOfDefinition = new Map((await table('TraitDefinition')).map(row => [+row.ID, +row.SpellID]));
const hasRow = new Set(allSkillRows.map(row => +row.Spell));
const treeRows = new Map();
for (const row of await table('TraitNodeXTraitNodeEntry')) {
    const mask = classOfTree.get(treeOfNode.get(+row.TraitNodeID));
    const id = spellOfDefinition.get(definitionOfEntry.get(+row.TraitNodeEntryID));
    if (!mask || !(id > 0) || hasRow.has(id) || OUT_OF_TREE.has(id)) continue;
    assert(!treeRows.has(id) || +treeRows.get(id).ClassMask === mask, `${names.get(id)} (${id}) is in two classes' trees`);
    treeRows.set(id, { Spell: String(id), ClassMask: String(mask), SkillLine: '0', AcquireMethod: '0', RaceMasks_0: '0', RaceMasks_1: '0' });
}
const skillRows = allSkillRows.filter(row => !OUT_OF_TREE.has(+row.Spell) && !NOT_TAUGHT.has(+row.Spell)).concat([...treeRows.values()]);
// Learnable class spells whose only SkillLineAbility rows carry no class
// (ClassMask 0): Curse of Exhaustion (a talent, TraitDefinition), Forever's
// four ranks of Curse of the Elements and Bane of Agony's rank 2 (from a
// Grimoire); Seal of Command (a talent) and its four ranks, Holy Light's
// rank 5 and Holy Shock's four ranks; Forever's ranks 2 to 4 of Arcane
// Wrath; Forever's four ranks of Shadow Word: Death. They count as the
// class's own. Most ClassMask-0 rows are talent ranks, hidden helpers, procs
// and pet passives (500 names and more), so only these are let in: not
// Lightning Shield's 26363-26370, its orbs' lightning bolts, nor the Season
// of Discovery IDs (402792, 11723, 11724), which have no row. The build fails
// once the game gives a listed row a class, so the list goes when it isn't
// needed.
// Then (2026-10-20, a player couldn't find Innervate before learning it):
// every class's talent abilities with no class (AcquireMethod 0 on the
// class's own skill lines, names not already listed), from Innervate,
// Swiftmend and Nature's Swiftness to Aimed Shot, Arcane Power, Holy Shield,
// Adrenaline Rush, Stormstrike, Fel Domination and Death Wish. Plus Sniper
// Shot's rank 3 (AcquireMethod 2), so the name keeps every rank its buff had.
// And (2026-11-01, matching Forever's current trainers) a hunter's Lacerate,
// ranks 1 to 4 (a bleed, trained at 30 to 60), which shares its name with
// the druid's, and Feral Charge (Bear), trained at 20, beside the talent's
// Feral Charge (1238122): which of the two the spellbook shows isn't known.
// And (build 70753) Holy Shield's rank 4 and the new talent Oath of Light.
// And (2026-11-13, an audit of the Debuffs page's search after a player
// missed Shadow Vulnerability) debuffs whose spells' rows carry no class, so
// no class's search offered them: a hunter's Intimidation (the talent and its
// stun, rows only on Pet - Generic) and Entrapment (the talent and its root,
// on Survival), and a warlock's succubus's Seduction (Pet - Succubus). Long
// Daze is gone from here: only Improved Pummel sets it off, which is in no
// warrior's tree and nothing teaches, so no warrior can give it.
const CLASSLESS = new Map([
    [18223, 256], [440892, 256], [1311676, 256], [1311677, 256], [1311680, 256], [1014, 256], // Warlock
    [20375, 2], [20915, 2], [20918, 2], [20919, 2], [20920, 2], [1042, 2], // Paladin
    [1311606, 2], [20473, 2], [20929, 2], [20930, 2],
    [1326080, 128], [1326081, 128], [1326082, 128], // Mage
    [1309595, 16], [1309633, 16], [1309635, 16], [1309636, 16], // Priest
    // Talent abilities (2026-10-20):
    [17116, 1024], [18562, 1024], [29166, 1024], // Druid
    [1299346, 4], [1299348, 4], [1310617, 4], [1310687, 4], [1310785, 4], [1310786, 4], [19263, 4], [19434, 4], [19503, 4], // Hunter
    [19506, 4], [19574, 4], [20900, 4], [20901, 4], [20902, 4], [20903, 4], [20904, 4], [20905, 4], [20906, 4],
    [12042, 128], [12043, 128], [12051, 128], [12536, 128], [24530, 128], // Mage
    [1310897, 2], [1311015, 2], [20216, 2], [20925, 2], [20927, 2], [20928, 2], // Paladin
    [14751, 16], // Priest
    [13750, 8], [13877, 8], [14093, 8], [14177, 8], [14183, 8], [14185, 8], [14251, 8], // Rogue
    [16166, 64], [16188, 64], [16269, 64], [17364, 64], // Shaman
    [18093, 256], [18288, 256], [18708, 256], [18788, 256], // Warlock
    [12281, 1], [12284, 1], [12292, 1], [12323, 1], [12328, 1], [12700, 1], [12809, 1], // Warrior
    // Trainer spells (2026-11-01):
    [16979, 1024], // Druid
    [24118, 4], [24119, 4], [24120, 4], [1299332, 4], // Hunter
    // Build 70753:
    [1239570, 2], [1328548, 2], // Paladin
    // Build 70790: Reckless Swings (15 sec, a buff of its own).
    [1329555, 1], // Warrior
    // Debuffs (2026-11-13):
    [19577, 4], [24394, 4], // Intimidation (the talent and its stun), Hunter
    [19184, 4], [19185, 4], // Entrapment (the talent and its root), Hunter
    [6358, 256], // Seduction (the succubus's), Warlock
]);
for (const id of CLASSLESS.keys()) {
    const rows = skillRows.filter(row => +row.Spell === id);
    assert(rows.length > 0 && rows.every(row => +row.ClassMask === 0), `${names.get(id)} (${id}): drop it from CLASSLESS`);
}
const petNames = new Set(skillRows.filter(row => +row.ClassMask > 0 && teaching(row)).map(row => names.get(+row.Spell)));
const abilities = skillRows.filter(row => +row.ClassMask > 0 || CLASSLESS.has(+row.Spell) || (teaching(row) && petNames.has(names.get(+row.Spell))))
    .map(row => {
        if (CLASSLESS.has(+row.Spell)) return { ...row, ClassMask: String(CLASSLESS.get(+row.Spell)) };
        if (!teaching(row)) return row;
        const pet = teaches.get(+row.Spell);
        assert.equal(names.get(pet), names.get(+row.Spell), `${names.get(+row.Spell)} (${row.Spell}) teaches a spell of another name`);
        return { ...row, Spell: String(pet) };
    });

// Debuffs a talent sets off under a name of its own, with no
// SkillLineAbility row at all, so no rule above offers them (a mage's Fire
// Vulnerability has a row and is offered). Each stands here as a row of its
// class, so the Layout page's search lists it: Shadow Vulnerability, from a
// warlock's Improved Shadow Bolt (2026-11-13, a player missed it). The build
// fails once one gets a row or stops being a debuff, so the list goes when it
// isn't needed.
// Then (2026-11-13, an audit of every class after that) the rest of the
// kind, each a debuff another spell gives that has no row: a talent's proc
// (Deep Wound, Blackout, Winter's Chill, Ignite), a stun, root or silence an
// ability sets off under another name (Charge Stun, Intercept Stun, Seal of
// Justice's Stun, Feral Charge, Starfire Stun), a weapon enchant's (a rogue's
// poisons, Frostbrand Attack), a pet's (Tainted Blood Effect, Spell Lock, a
// boar's Charge), one left on the ground or by an area the spell makes (Frost
// and Freezing Trap, Consecration, Flare, Hurricane), Turn Evil's (the talent
// turns Turn Undead into it) and Penance's on an enemy (not its heal's on a
// friend). And the IDs two listed names lacked: Chilled from Frost and Ice
// Armor, Entangling Roots from Nature's Grasp. Many were linked to their
// spell already (ns.PASSIVE_DEBUFFS, ns.SPELL_AURAS), so a bar lit for them,
// but no search named them. Each goes into ns.RANKS under its own name, so
// it isn't an aura no one learns (ns.AURA_ONLY, below).
const TALENT_DEBUFFS = new Map([
    [7922, 1], // Charge Stun (Charge), Warrior
    [20253, 1], [20614, 1], [20615, 1], // Intercept Stun (Intercept ranks 1 to 3), Warrior
    [412609, 1], // Deep Wound (Deep Wounds), Warrior
    [18498, 1], // Silenced (Improved Shield Bash), Warrior
    [23694, 1], // Improved Hamstring (Improved Hamstring), Warrior
    [20170, 2], // Stun (Seal of Justice), Paladin
    [429147, 2], // Stun (Holy Wrath), Paladin
    [20232, 2], // Judgement of Fury (judging Seal of Fury), Paladin
    [1328374, 2], [1328373, 2], [1328372, 2], // Turn Evil (the Turn Evil talent's Turn Undead, ranks 1 to 3), Paladin
    [1280353, 2], // Consecration (Consecration), Paladin
    [25999, 4], // Boar Charge (a boar's Charge), Hunter
    [1279692, 4], // Flare (Flare), Hunter
    [19410, 4], // Improved Concussive Shot (Improved Concussive Shot), Hunter
    [19229, 4], // Improved Wing Clip (Improved Wing Clip), Hunter
    [465230, 4], // Entrapment (Entrapment, from a trap), Hunter
    [1310536, 4], // Lacerating Strikes (Lacerating Strikes), Hunter
    [3355, 4], [14308, 4], [14309, 4], // Freezing Trap (Freezing Trap ranks 1 to 3), Hunter
    [13810, 4], // Frost Trap (Frost Trap), Hunter
    [18425, 8], // Silenced - Kick (Improved Kick), Rogue
    [2818, 8], [2819, 8], [11353, 8], [11354, 8], [25349, 8], // Deadly Poison to Deadly Poison V, Rogue
    [3409, 8], [11201, 8], // Crippling Poison (Crippling Poison, Crippling Poison II), Rogue
    [5760, 8], [8692, 8], [11398, 8], // Mind-numbing Poison to Mind-numbing Poison III, Rogue
    [13218, 8], [13222, 8], [13223, 8], [13224, 8], // Wound Poison (Wound Poison to Wound Poison IV), Rogue
    [15269, 16], // Blackout (Blackout), Priest
    [15258, 16], // Shadow Weaving (Shadow Weaving), Priest
    [402261, 16], [1240734, 16], [1240736, 16], [1316994, 16], // Penance (on an enemy, ranks 1 to 4), Priest
    [8034, 64], [8037, 64], [10458, 64], [16352, 64], [16353, 64], // Frostbrand Attack (Frostbrand Weapon ranks 1 to 5), Shaman
    [18469, 128], [1329552, 128], // Counterspell - Silenced (Improved Counterspell), Mage
    [6136, 128], // Chilled (Frost Armor), Mage
    [7321, 128], // Chilled (Ice Armor), Mage
    [12579, 128], // Winter's Chill (Winter's Chill), Mage
    [412538, 128], // Ignite (Ignite), Mage
    [17794, 256], // Shadow Vulnerability (Improved Shadow Bolt), Warlock
    [18118, 256], // Aftermath (Aftermath), Warlock
    [1293696, 256], // Demonic Brand (Demonic Brand), Warlock
    [24259, 256], // Spell Lock (the felhunter's Spell Lock), Warlock
    [19479, 256], [19652, 256], [19653, 256], [19654, 256], // Tainted Blood Effect (the felhunter's Tainted Blood ranks 1 to 4), Warlock
    [16922, 1024], // Starfire Stun (Improved Starfire), Druid
    [19975, 1024], [19974, 1024], [19973, 1024], [19972, 1024], [19971, 1024], [19970, 1024], // Entangling Roots (Nature's Grasp ranks 1 to 6), Druid
    [19675, 1024], // Feral Charge (Feral Charge), Druid
    [1278965, 1024], [1278968, 1024], [1278759, 1024], // Hurricane (Hurricane ranks 1 to 3), Druid
]);
for (const [id, mask] of TALENT_DEBUFFS) {
    assert(names.get(id) && !hasRow.has(id), `${names.get(id)} (${id}): drop it from TALENT_DEBUFFS`);
    abilities.push({ Spell: String(id), ClassMask: String(mask), SkillLine: '0', AcquireMethod: '0', RaceMasks_0: '0', RaceMasks_1: '0' });
}
// And the debuffs CLASSLESS (above) gives a class that no one casts either
// (2026-11-13, a review of that audit): the stun a hunter's pet gives with
// Intimidation, and the root Entrapment gives with a trap. No one casts
// these or TALENT_DEBUFFS' (Turn Evil's only through Turn Undead), so they
// go on the Debuffs bar alone: listed as ns.DEBUFF_AURAS (below), a
// cooldown bar never goes by one. Before that a Cooldowns bar took Charge
// Stun (an icon that never cools down) and Winter's Chill by its debuff
// (not the passive talent, which it turns away).
const CLASSLESS_DEBUFFS = new Set([24394, 19185]);
for (const id of CLASSLESS_DEBUFFS) assert(CLASSLESS.has(id), `${names.get(id)} (${id}): drop it from CLASSLESS_DEBUFFS`);

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
const racialIDs = new Set();
for (const [id, sub] of subtext) {
    const name = names.get(id);
    if (sub !== 'Racial' || !name || /[\\"\n]/.test(name)) continue;
    if (!groups.has(name)) groups.set(name, new Map());
    groups.get(name).set(id, 0);
    racialIDs.add(id);
    racials++;
}

// Rune-only spells are taught only by an engraving, which Forever doesn't
// have (Living Bomb, Starfall), so no one has them. The seasonal realms'
// spells sit in this range of IDs; one is rune-only when its every
// SkillLineAbility row is class-masked and taught by another spell
// (AcquireMethod 3) and it's no talent (Tools/GenerateForms.mjs has the same
// rule). A name goes only when all its IDs are: real names (Mutilate,
// Penance, Fire Blast) carry a seasonal helper ID of that kind too.
const SEASON_SPELL = id => id >= 395000 && id < 480000;
const traitSpells = new Set((await table('TraitDefinition')).map(row => +row.SpellID)
    .filter(id => id > 0 && !OUT_OF_TREE.has(id)));
const skillRowsOf = new Map();
for (const row of allSkillRows) {
    if (!skillRowsOf.has(+row.Spell)) skillRowsOf.set(+row.Spell, []);
    skillRowsOf.get(+row.Spell).push(row);
}
function runeOnly(id) {
    const rows = skillRowsOf.get(id) || [];
    return SEASON_SPELL(id) && rows.length > 0 && rows.every(row => +row.AcquireMethod === 3 && +row.ClassMask !== 0)
        && !traitSpells.has(id);
}
const runeNames = new Set([...groups].filter(([, ranks]) => [...ranks.keys()].every(runeOnly)).map(([name]) => name));
for (const name of runeNames) groups.delete(name);

const lines = [...groups.keys()].sort().map(name => {
    const ids = [...groups.get(name).entries()].sort((a, b) => a[1] - b[1] || a[0] - b[0]).map(([id]) => id);
    return ` [${JSON.stringify(name)}]={${ids.join(',')}},`;
});

// Each class's debuffs, for the Layout page's search: its spells that put an
// aura on an enemy (SpellEffect: Effect 6 APPLY_AURA or 129
// APPLY_AREA_AURA_ENEMY, at an enemy target: the one you target, or enemies
// in an area or cone). ClassMask bits name the class.
// And (2026-11-13, an audit after a player missed Shadow Vulnerability) an
// aura left on the ground for enemies (Effect 27 PERSISTENT_AREA_AURA at
// ImplicitTarget 28: Explosive and Frost Trap), and one on whoever you
// target (ImplicitTarget 25) that the game marks a debuff (SpellMisc
// Attributes_0 0x4000000, SPELL_ATTR0_AURA_IS_DEBUFF: Mind Vision). And a
// racial that puts an aura on an enemy (a tauren's War Stomp) goes in every
// class's list: the search leaves it off for other races (ns.SPELL_RACES).
const CLASSES = { 1: 'WARRIOR', 2: 'PALADIN', 4: 'HUNTER', 8: 'ROGUE', 16: 'PRIEST', 64: 'SHAMAN',
    128: 'MAGE', 256: 'WARLOCK', 1024: 'DRUID' };
const AURA_EFFECTS = new Set([6, 129]);
const ENEMY_TARGETS = new Set([6, 15, 16, 24, 53, 54, 104]);
const GROUND_AURA = 27, GROUND_ENEMIES = 28, ANY_TARGET = 25, AURA_IS_DEBUFF = 0x4000000;
// Each spell's SpellMisc row (its row for difficulty 0 when it has several)
// and its Attributes_0 flags.
const misc = new Map();
for (const row of await table('SpellMisc')) {
    const id = +row.SpellID;
    const kept = misc.get(id);
    if (!kept || (+row.DifficultyID === 0 && +kept.DifficultyID !== 0)) misc.set(id, row);
}
const flags = id => (misc.has(id) ? +misc.get(id).Attributes_0 >>> 0 : 0);
const debuffIDs = new Set();
for (const row of await table('SpellEffect')) {
    const effect = +row.Effect, targets = [+row.ImplicitTarget_0, +row.ImplicitTarget_1];
    if ((AURA_EFFECTS.has(effect) && targets.some(target => ENEMY_TARGETS.has(target)))
        || (effect === GROUND_AURA && targets.includes(GROUND_ENEMIES))
        || (effect === 6 && targets.includes(ANY_TARGET) && (flags(+row.SpellID) & AURA_IS_DEBUFF) !== 0)) {
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
for (const id of racialIDs) {
    const name = names.get(id);
    if (groups.has(name) && debuffIDs.has(id)) for (const set of debuffs.values()) set.add(name);
}
for (const [id, mask] of TALENT_DEBUFFS) {
    assert(debuffIDs.has(id), `${names.get(id)} (${id}) is no debuff: drop it from TALENT_DEBUFFS`);
    assert(debuffs.get(CLASSES[mask]).has(names.get(id)), `${names.get(id)} (${id}) didn't reach the ${CLASSES[mask]} debuffs`);
}
for (const id of CLASSLESS_DEBUFFS) assert(debuffIDs.has(id), `${names.get(id)} (${id}) is no debuff: drop it from CLASSLESS_DEBUFFS`);
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
// The class of each ID of a name two or more classes have under IDs of their
// own (a rogue's Poised and a druid's, each with its own icon; Track
// Humanoids), so the Layout page's search shows a spell you don't have yet
// with your class's icon. Only IDs that belong to some of the name's classes,
// not all of them, are listed.
const idClasses = new Map();
for (const row of abilities) {
    const id = +row.Spell, name = names.get(id), set = owners.get(name);
    if (!set || set.size < 2 || set.size >= classCount) continue;
    if (!idClasses.has(id)) idClasses.set(id, new Set());
    for (const [bit, token] of Object.entries(CLASSES)) if (+row.ClassMask & +bit) idClasses.get(id).add(token);
}
const idClassLines = [...idClasses.entries()]
    .filter(([id, set]) => set.size > 0 && set.size < owners.get(names.get(id)).size)
    .sort((a, b) => a[0] - b[0])
    .map(([id, set]) => ` [${id}]="${[...set].sort().join(' ')}",`);

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
for (const row of skillRows) {
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
// active, so the build fails unless every other passive one is. (SpellMisc
// is read above, for the class debuffs.)
const PASSIVE = 0x40, HIDDEN = 0x80; // SPELL_ATTR0_PASSIVE, SPELL_ATTR0_DO_NOT_DISPLAY
const passive = id => (flags(id) & PASSIVE) !== 0;
const learnable = new Set(skillRows.map(row => +row.Spell));
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
// Rune-only passives (Dance of the Wicked, a priest's Secrets of Elune) go
// too, by the same per-name rule as ns.RANKS above: no one has them. A
// name ns.RANKS still holds stays.
for (const [name, ids] of passives) {
    if (!groups.has(name) && [...ids].every(runeOnly)) passives.delete(name);
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
// Build 70790's data carries Blizzard's 3 Nov cooldowns itself (Slam 15 sec,
// Stormstrike 6, Riptide 12, Totemic Call 30), so the stopgap list that set
// them by hand for 70753 is gone.
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
// A passive talent gives the debuffs TALENT_DEBUFFS lists under its own name
// too, though its description doesn't name them (2026-11-13, a review of the
// debuff audit): the Turn Evil talent (1328370) turns Turn Undead into Turn
// Evil (1328372 to 1328374, through SpellEffect Aura 332). Unlinked, a
// paladin whose Turn Evil is kept by the talent (the one the game says he
// knows) was told on the Debuffs bar there was nothing to track.
for (const [name, ids] of passives) {
    const auras = [...(groups.get(name)?.keys() || [])].filter(id => TALENT_DEBUFFS.has(id));
    for (const id of ids) {
        if (auras.length > 0 && !auraLinks.debuff.has(id)) for (const aura of auras) link('debuff', id, aura);
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
// buff (the Skyborne's Read Leyline and Skysight) is that buff, whatever its
// name, with the other spells of the buff's name its description names (the
// other Energized). Each aura brings its other ranks (below): Prayer of
// Mending's later ranks name only the first rank's buff. By the ID of every
// spell a character can learn (a talent too: TraitDefinition).
// Build 70753 gave the Skyborne's lasting buffs names of their own, so that
// last rule no longer finds them: Attuned (Read Leyline at a leyline, was the
// other Energized) and Charged (Skysight at a convergence, was the other
// Elemental Blessing), an hour each. The game gives them by script and only
// the description names them, so they're linked by ID. The build fails once
// either changes.
const SCRIPT_AURAS = new Map([[1259705, [1259691, 'Attuned']], [1259686, [1270893, 'Charged']]]);
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
    if (SCRIPT_AURAS.has(id)) {
        const [aura, auraName] = SCRIPT_AURAS.get(id);
        assert(names.get(aura) === auraName && shownAura(aura) && reach.get(aura).buff && named(id).has(aura),
            `${auraName} (${aura}): no longer ${name}'s buff in this build's data, so drop it from SCRIPT_AURAS`);
        found.add(aura);
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
// ns.RANKS aren't, or don't lead to already. Not a rune-only name's: no one
// has it.
const nameAuraLines = [];
for (const name of [...aurasByName.keys()].sort()) {
    if (runeNames.has(name)) continue;
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
// or a talent (Holy Shield) shows for whoever has it. Nor is a debuff
// TALENT_DEBUFFS lists (2026-11-13, an audit after a player missed Shadow
// Vulnerability): it's in ns.RANKS under its own name, so its class's
// Debuffs search offers it, though a passive or spell already leads to it
// (Blackout, a rogue's poisons).
const taught = new Set(teaches.values());
const listedIDs = new Set([...listed.values()].flatMap(ids => [...ids]));
const auraOnly = new Set();
for (const ids of [...auraLinks.buff.values(), ...auraLinks.debuff.values(), ...spellAuras.values(), ...families]) {
    for (const id of ids) {
        if (!learnable.has(id) && !traitSpells.has(id) && !taught.has(id) && !TALENT_DEBUFFS.has(id)) auraOnly.add(id);
    }
}
for (const id of auraOnly) assert(!rankedIDs.has(id) && !listedIDs.has(id), `${names.get(id)} (${id}) is a spell and an aura no one learns`);
const auraOnlyLines = [...auraOnly].sort((a, b) => a - b).map(id => ` [${id}]=true,`);
// The debuffs ns.RANKS holds for the Debuffs bar alone, by ID: TALENT_DEBUFFS'
// and CLASSLESS_DEBUFFS' (above), which no one casts. The addon never goes by
// one on another bar (Spells.lua): a name with nothing else goes on the
// Debuffs bar only, and one with a spell or talent too goes by that.
const debuffAuras = [...TALENT_DEBUFFS.keys(), ...CLASSLESS_DEBUFFS].sort((a, b) => a - b);
for (const id of debuffAuras) assert(rankedIDs.has(id), `${names.get(id)} (${id}) isn't in ns.RANKS`);
const debuffAuraLines = debuffAuras.map(id => ` [${id}]=true,`);

// The pets' own abilities that a class list above names, by the class whose
// pet has them, each with the pet's spell IDs (ns.PET_SPELLS). The addon
// (Spells.lua) looks only in your class's: a druid's Growl and a warrior's
// Charge stay theirs.
// First a warlock's demons' (2026-11-13, Squirt's call once the debuff audit
// made two of them warlock names: "only show if that pet is out and it's on
// the bar"). A demon's ability is a spell on its skill line (Pet - Imp and the
// rest, rows with no class), not hidden or passive. Today that's the
// succubus's Seduction (CLASSLESS gives it the class) and the felhunter's
// Spell Lock (its silence, TALENT_DEBUFFS' 24259, carries the name): listed
// with the felhunter's two ranks, never the silence. Any other demon ability
// is in no class's list, so a bar already shows it only once you or your pet
// know it. The addon shows a listed one on a cooldown bar only while you or
// your pet know one of its IDs, so while that demon is out, and takes it on
// whichever demon is out, by these IDs; the Debuffs bar and its search go by
// the class list as before. The Felguard's line (2887) is left out: only a
// rune summons it (Summon Felguard has no row; Forever has no runes). The
// build fails once a row teaches Summon Felguard, a demon line's name
// changes, a demon's spell gets a class, or a listed name is another class's
// too.
const DEMON_LINES = new Map([[188, 'Pet - Imp'], [204, 'Pet - Voidwalker'], [205, 'Pet - Succubus'], [189, 'Pet - Felhunter'],
    [206, 'Pet - Infernal'], [207, 'Pet - Doomguard']]);
const FELGUARD_LINE = 2887;
const skillLines = await table('SkillLine');
const lineNames = new Map(skillLines.map(row => [+row.ID, row.DisplayName_lang]));
for (const [line, name] of DEMON_LINES) assert.equal(lineNames.get(line), name, `skill line ${line} isn't ${name}: check DEMON_LINES`);
assert(lineNames.get(FELGUARD_LINE) === 'Pet - Felguard' && !allSkillRows.some(row => names.get(+row.Spell) === 'Summon Felguard'),
    'a row teaches Summon Felguard now: put its line (2887) in DEMON_LINES');
const demonRanks = new Map();
for (const row of allSkillRows) {
    const id = +row.Spell, name = names.get(id);
    if (!DEMON_LINES.has(+row.SkillLine) || !name || /[\\"\n]/.test(name) || flags(id) & (PASSIVE | HIDDEN)) continue;
    assert.equal(+row.ClassMask, 0, `${name} (${id}), a demon's spell, has a class`);
    if (!demonRanks.has(name)) demonRanks.set(name, new Map());
    const match = (subtext.get(id) || '').match(/^Rank (\d+)$/);
    demonRanks.get(name).set(id, match ? +match[1] : 0);
}
const demonLines = [];
for (const name of [...demonRanks.keys()].sort()) {
    const classes = owners.get(name);
    if (!classes || classes.size === 0) continue;
    assert.deepEqual([...classes], ['WARLOCK'], `${name}, a demon's ability, is another class's name too`);
    const ids = [...demonRanks.get(name).entries()].sort((a, b) => a[1] - b[1] || a[0] - b[0]).map(([id]) => id);
    for (const id of ids) assert(!debuffAuras.includes(id), `${name} (${id}), a demon's spell, is a debuff no one casts`);
    demonLines.push(`  [${JSON.stringify(name)}]={${ids.join(',')}},`);
}
// Then a hunter's pets' (2026-11-13, Squirt for them too: "Yea plz same as
// lock"): every ability a Beast Training row teaches the pet (`teaching`,
// above), not hidden or passive (not its resistances, Great Stamina or
// Natural Armor), with the pet's own spell IDs: Growl, Bite, Cower, Dash,
// Dive, a boar's Charge, a cat's Claw and Prowl, a wolf's Furious Howl, a
// scorpid's Scorpid Poison, a turtle's Shell Shield, a gorilla's
// Thunderstomp, Forever's new ones (a crab's Pinch, a fox's Trickster's
// Dance...) and Harass, whose spells no line holds. Each pet's spell is on
// its family's skill line (Pet - Wolf and the rest, every family's Growl and
// Cower on Pet - Generic): a hunter pet's line is any "Pet - " line that's no
// demon's. A name a druid or a warrior shares (Growl, Claw, Cower, Dash,
// Prowl, Swipe; Charge) has only the pet's IDs here, and Trickster's Dance
// the fox's (ns.RANKS holds its Beast Training spell, from CLASSLESS). Not
// the hunter's own spells: Intimidation's rows are on Pet - Generic, but
// it's his talent and its stun no one casts; Mend Pet and Call Pet are on
// his own lines. The build fails once a hunter pet's line holds nothing
// Beast Training teaches, a pet's spell is on another line or has a class or
// is a talent, an active spell on a pet's line under a hunter's name isn't
// taught by Beast Training (unless it's a talent or a debuff no one casts),
// or a listed name isn't the hunter's.
const hunterLines = new Map(skillLines.filter(row => /^Pet - /.test(row.DisplayName_lang) && +row.CategoryID === 7
    && !DEMON_LINES.has(+row.ID) && +row.ID !== FELGUARD_LINE).map(row => [+row.ID, row.DisplayName_lang]));
const beastTaught = new Set(skillRows.filter(teaching).map(row => teaches.get(+row.Spell)));
for (const [line, name] of hunterLines) {
    assert(allSkillRows.some(row => +row.SkillLine === line && beastTaught.has(+row.Spell)),
        `${name} (${line}) holds nothing Beast Training teaches: is it a hunter pet's line?`);
}
const petRanks = new Map();
for (const row of skillRows) {
    if (!teaching(row)) continue;
    const id = teaches.get(+row.Spell), name = names.get(id);
    if (!name || /[\\"\n]/.test(name) || flags(id) & (PASSIVE | HIDDEN)) continue;
    for (const own of skillRowsOf.get(id) || []) {
        assert(hunterLines.has(+own.SkillLine) && +own.ClassMask === 0,
            `${name} (${id}), a hunter pet's spell, is on ${lineNames.get(+own.SkillLine)} with class mask ${own.ClassMask}`);
    }
    assert(!traitSpells.has(id) && !debuffAuras.includes(id), `${name} (${id}), a hunter pet's spell, is a talent or a debuff no one casts`);
    if (!petRanks.has(name)) petRanks.set(name, new Map());
    const match = (subtext.get(id) || '').match(/^Rank (\d+)$/);
    petRanks.get(name).set(id, match ? +match[1] : 0);
}
const petIDs = new Set([...petRanks.values()].flatMap(ranks => [...ranks.keys()]));
for (const row of allSkillRows) {
    const id = +row.Spell, name = names.get(id);
    if (!hunterLines.has(+row.SkillLine) || !name || flags(id) & (PASSIVE | HIDDEN) || !owners.get(name)?.has('HUNTER')) continue;
    assert(petIDs.has(id) || traitSpells.has(id) || debuffAuras.includes(id),
        `${name} (${id}) on ${lineNames.get(+row.SkillLine)}: no Beast Training row teaches it, so it isn't listed as a pet's`);
}
const hunterPetLines = [];
for (const name of [...petRanks.keys()].sort()) {
    const classes = owners.get(name);
    if (!classes || classes.size === 0) continue;
    assert(classes.has('HUNTER'), `${name}, a hunter pet's ability, is only another class's name`);
    const ids = [...petRanks.get(name).entries()].sort((a, b) => a[1] - b[1] || a[0] - b[0]).map(([id]) => id);
    hunterPetLines.push(`  [${JSON.stringify(name)}]={${ids.join(',')}},`);
}

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
// aren't listed. Nor are passives, which no cooldown bar shows: build 70790's
// priest talent Early Demise is gated at 20% health like Execute, read from
// its tree (above), but it's a passive that only works on such a target.
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
        if (REACTIVE_STATES[column].has(state) && !passive(id)) reactiveIDs.add(id);
    }
    for (const column of ['CasterAuraSpell', 'TargetAuraSpell']) {
        assert(!+row[column] || OWN_AURAS.has(+row[column]), `${name}: ${column} ${row[column]} isn't sorted`);
    }
    for (const column of ['CasterAuraType', 'TargetAuraType']) assert.equal(+row[column], 0, `${name}: ${column} isn't sorted`);
}
const classMasks = new Map();
for (const row of skillRows) classMasks.set(+row.Spell, (classMasks.get(+row.Spell) || 0) | +row.ClassMask);
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
    '-- class spell belongs to (and, for a name classes share under IDs of',
    '-- their own, each such ID\'s class), the races (race IDs) each racial or race-only',
    '-- spell belongs to, every passive spell a character can learn with nothing',
    '-- to track (its passive IDs), the buffs and debuffs of their own some',
    '-- passives give or are (a totem\'s buff), by the passive\'s ID, the auras',
    '-- with another ID other spells lead to (Bloodrage\'s buff, a poison\'s',
    '-- debuff), by the spell\'s ID and by the aura\'s name, the auras that are',
    '-- one buff in several IDs (a totem buff\'s ranks, Well Fed from any food),',
    '-- which of those auras no one learns as a spell, by ID, the debuffs',
    '-- in ns.RANKS no one casts (Charge Stun), for the Debuffs bar alone, by ID,',
    '-- the pets\' abilities a class list names (a demon\'s Seduction, a hunter',
    '-- pet\'s Growl), with the pet\'s own spell IDs, by class and name,',
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
    'ns.ID_CLASSES = {',
    ...idClassLines,
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
    'ns.DEBUFF_AURAS = {',
    ...debuffAuraLines,
    '}',
    'ns.PET_SPELLS = {',
    ' HUNTER={',
    ...hunterPetLines,
    ' },',
    ' WARLOCK={',
    ...demonLines,
    ' },',
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
console.log(`Ranks.lua: ${groups.size} spells, ${abilities.length} class ability rows, ${racials} racial spells, ${debuffCount} class debuffs, ${ownerLines.length} spells with their classes, ${raceLines.length} with their races, ${passiveLines.length} passive, ${auraLinks.buff.size} passives with a buff and ${auraLinks.debuff.size} with a debuff of their own, ${spellAuraLines.length} spells and ${nameAuraLines.length} names leading to an aura with another ID, ${families.length} auras in several IDs, ${auraOnly.size} auras no one learns, ${debuffAuras.length} debuffs no one casts, ${demonLines.length} demon and ${hunterPetLines.length} hunter pet abilities a class list names, ${reactive.size} reactive, ${cooldownLines.length} with a cooldown.`);
