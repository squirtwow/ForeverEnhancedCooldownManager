// Builds Forms.lua, for a bar that swaps with your form (Swap with my form:
// a list of its own for each form; Core.lua): the forms a character can
// take, which share a list (Dire Bear Form keeps Bear Form's), the spells
// that put you in each (to tell which forms you know), and which forms each
// spell can be cast in (a new form's list starts as your normal one without
// what that form can't cast; Spells.lua). For every spell a Forever
// player can learn, the game's own rule (each spell's SpellShapeshift row
// and attributes, each form's SpellShapeshiftForm flags) is worked out for
// the forms its class can take (a druid's forms, a warrior's stances, a
// priest's Shadowform, a shaman's Ghost Wolf, a rogue's Stealth) and none;
// only the spells some of those forms can't cast, or that need stealth, are
// listed. Any other spell casts in every form, and so do the spells that
// put you in a form (Cat Form, a stance, Stealth): you change form with them.
// Rune-only spells (taught only by an engraving, which Forever doesn't have)
// are left out.
//
// The game's rule, for a spell in form F (0 for none; bit 1 << (F - 1)):
//   - F in its ShapeshiftExclude: no.
//   - F in its ShapeshiftMask: yes.
//   - F a shapeshift (a form without the Stance flag: Cat, Bear, Travel,
//     Ghost Wolf): only a spell with no mask and without the attribute
//     "not while shapeshifted".
//   - no form, or a stance (Stance flag: Battle Stance, Moonkin Form,
//     Shadowform, Stealth): a spell with no mask, or one marked "also in
//     caster form" (Moonfire, Healing Touch).
//   And a spell marked "only while stealthed" (Ambush, Pounce) needs stealth
//   as well, one that needs a form's aura on you (its SpellAuraRestrictions
//   row: Tiger's Fury, Cat Form's) needs that form, and one that can't be
//   cast with a form's aura on you (Penance, Shadowform's) not in that form.
//
// Reads Blizzard's own game tables for build 1.60.1.70374 (wago.tools db2
// exports of SpellName, Spell, SpellMisc, SpellShapeshift,
// SpellShapeshiftForm, SpellAuraRestrictions, SpellEffect, SkillLine,
// SkillLineAbility and TraitDefinition). No addon code or data is an input.
//
//   node Tools/GenerateForms.mjs [cache folder] [--out file]
//
// The cache folder (C:\AddonDev\_Toolchain\gamedata\forever-70374 when none
// is given) holds the tables as CSV; any missing is downloaded into it.
// Tools/TestForms.mjs checks Forms.lua is exactly what this makes.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const BUILD = '1.60.1.70374';
const root = dirname(dirname(fileURLToPath(import.meta.url)));
export const DEFAULT_CACHE = join(root, '..', '_Toolchain', 'gamedata', 'forever-70374');
const args = process.argv.slice(2);
let out = join(root, 'Forms.lua'), cache = DEFAULT_CACHE;
for (let i = 0; i < args.length; i++) {
    if (args[i] === '--out') out = args[++i];
    else if (!args[i].startsWith('--')) cache = args[i];
}
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

// Attributes: a spell's row for difficulty 0 when it has several.
const misc = new Map();
for (const row of await table('SpellMisc')) {
    const id = +row.SpellID;
    const kept = misc.get(id);
    if (!kept || (+row.DifficultyID === 0 && +kept.DifficultyID !== 0)) misc.set(id, row);
}
const PASSIVE = 0x40; // SPELL_ATTR0_PASSIVE: nothing to cast
const NOT_SHAPESHIFTED = 0x10000; // SPELL_ATTR0_NOT_SHAPESHIFTED: not while shapeshifted
const ONLY_STEALTHED = 0x20000; // SPELL_ATTR0_ONLY_STEALTHED: only while stealthed
const CASTER_FORM_TOO = 0x80000; // SPELL_ATTR2_ALLOW_WHILE_NOT_SHAPESHIFTED: also with no form
const attributes = (id, n) => (misc.has(id) ? +misc.get(id)[`Attributes_${n}`] >>> 0 : 0);

// Each spell's forms: the ones it needs (mask) and the ones it can't be cast in.
const shapes = new Map();
for (const row of await table('SpellShapeshift')) {
    const id = +row.SpellID;
    assert(!shapes.has(id), `${id} has two SpellShapeshift rows`);
    const bits = n => (BigInt(+row[`${n}_1`] >>> 0) << 32n) | BigInt(+row[`${n}_0`] >>> 0);
    shapes.set(id, { mask: bits('ShapeshiftMask'), exclude: bits('ShapeshiftExclude') });
}
const STANCE = 0x1; // SpellShapeshiftForm Flags: a stance, cast in as with no form
const formRows = new Map((await table('SpellShapeshiftForm')).map(r => [+r.ID, r]));

// The forms spells put you in (SpellEffect APPLY_AURA 6 with MOD_SHAPESHIFT
// 36, the form in MiscValue): Cat Form's aura is form 1, Shadowform's 28.
const APPLY_AURA = 6, MOD_SHAPESHIFT = 36;
const formOf = new Map();
for (const row of await table('SpellEffect')) {
    if (+row.Effect === APPLY_AURA && +row.EffectAura === MOD_SHAPESHIFT) formOf.set(+row.SpellID, +row.EffectMiscValue_0);
}

// Each spell's aura rule on you, where the aura is a form's: the form it
// needs (CasterAuraSpell) and the one it can't be cast in
// (ExcludeCasterAuraSpell). Auras that aren't a form (Forbearance, a quest's)
// aren't yours to change with your form, so they don't count here.
const auras = new Map();
for (const row of await table('SpellAuraRestrictions')) {
    const id = +row.SpellID;
    assert(!auras.has(id), `${id} has two SpellAuraRestrictions rows`);
    auras.set(id, { need: formOf.get(+row.CasterAuraSpell), not: formOf.get(+row.ExcludeCasterAuraSpell) });
}

function allowed(id, form) {
    const aura = auras.get(id);
    if (aura && aura.need !== undefined && form !== aura.need) return false;
    if (aura && aura.not !== undefined && form === aura.not) return false;
    const shape = shapes.get(id) ?? { mask: 0n, exclude: 0n };
    const bit = form ? 1n << BigInt(form - 1) : 0n;
    if (bit & shape.exclude) return false;
    if (bit & shape.mask) return true;
    if (form && !(+formRows.get(form).Flags & STANCE)) {
        return !(attributes(id, 0) & NOT_SHAPESHIFTED) && shape.mask === 0n;
    }
    return shape.mask === 0n || (attributes(id, 2) & CASTER_FORM_TOO) !== 0;
}
const stealthOnly = id => (attributes(id, 0) & ONLY_STEALTHED) !== 0;

// Who can learn what: trainer and talent spells by their SkillLineAbility
// rows (ClassMask, or else the class whose talent tab's skill line they're
// on), Forever's talent trees (TraitDefinition), and racials.
const CLASSES = { 1: 'WARRIOR', 2: 'PALADIN', 4: 'HUNTER', 8: 'ROGUE', 16: 'PRIEST', 64: 'SHAMAN',
    128: 'MAGE', 256: 'WARLOCK', 1024: 'DRUID' };
const rowsOf = new Map();
for (const row of await table('SkillLineAbility')) {
    const id = +row.Spell;
    if (!rowsOf.has(id)) rowsOf.set(id, []);
    rowsOf.get(id).push(row);
}
// The skill lines of the classes' talent tabs (class skills, CategoryID 7,
// with Flags 0x400: Arms, Feral Combat, Restoration and the rest), each one
// class's: the one its class-masked rows name. Many of their rows carry no
// class mask (Innervate, Swiftmend, Sweeping Strikes, Stormstrike, a
// talent's): those are that class's too. Pet, mount and rune lines are
// class skills without the flag, so their spells aren't counted this way.
const CLASS_SKILLS = '7', TALENT_TAB = 0x400;
const tabs = new Map(); // skill line -> class mask
for (const line of await table('SkillLine')) {
    if (line.CategoryID === CLASS_SKILLS && +line.Flags & TALENT_TAB) tabs.set(+line.ID, 0);
}
for (const rows of rowsOf.values()) {
    for (const row of rows) if (tabs.has(+row.SkillLine)) tabs.set(+row.SkillLine, tabs.get(+row.SkillLine) | +row.ClassMask);
}
assert.equal(tabs.size, 27, 'three talent tabs for each of the nine classes');
for (const [line, mask] of tabs) {
    assert(Object.keys(CLASSES).some(bit => mask === +bit), `talent tab skill line ${line} isn't one class's (class mask ${mask})`);
}
const classMask = row => +row.ClassMask > 0 ? +row.ClassMask : tabs.get(+row.SkillLine) ?? 0;
const talents = new Set((await table('TraitDefinition')).map(r => +r.SpellID).filter(Boolean));
// The seasonal realms' spells sit in this range of IDs (their runes among
// them). Taught only by an engraving: a seasonal spell whose every
// SkillLineAbility row is class-masked and taught by another spell
// (AcquireMethod 3), and no talent. (Forever keeps some of these spells as
// trainer or talent spells of its own: those stay.)
const SEASON_SPELL = id => id >= 395000 && id < 480000;
function runeOnly(id) {
    const rows = rowsOf.get(id) || [];
    return SEASON_SPELL(id) && rows.length > 0 && rows.every(r => +r.AcquireMethod === 3 && +r.ClassMask !== 0)
        && !talents.has(id);
}
// Each learnable spell's classes (an empty set: any class, a racial, or a
// talent of Forever's trees no skill line row gives a class: judged over
// every form a character takes, which is right whoever has it).
const learnable = new Map();
for (const [id, rows] of rowsOf) {
    const classes = new Set();
    for (const row of rows) {
        for (const [bit, token] of Object.entries(CLASSES)) if (classMask(row) & +bit) classes.add(token);
    }
    if (classes.size) learnable.set(id, classes);
}
for (const [id, sub] of subtext) if (sub === 'Racial' && !learnable.has(id)) learnable.set(id, new Set());
for (const id of talents) if (!learnable.has(id)) learnable.set(id, new Set());
for (const id of [...learnable.keys()]) {
    const name = names.get(id);
    if (!name || /[\\"\n]/.test(name) || /^Engrave /.test(name) || attributes(id, 0) & PASSIVE || runeOnly(id)) learnable.delete(id);
}

// The forms each class can take: the forms its spells put you in. And the
// spells that put you in each (every rank), to tell which forms a character
// knows.
const classForms = new Map(Object.values(CLASSES).map(token => [token, new Set()]));
const playerForms = new Set();
const givers = new Map(); // form -> the learnable spells that put you in it
for (const [id, classes] of learnable) {
    const form = formOf.get(id);
    if (!form) continue;
    assert(formRows.has(form) && formRows.get(form).Name_lang, `${names.get(id)} (${id}) puts you in form ${form}, which has no name`);
    playerForms.add(form);
    if (!givers.has(form)) givers.set(form, []);
    givers.get(form).push(id);
    for (const token of classes) classForms.get(token).add(form);
}

// Each form's list on a bar that swaps with your form (Core.lua): its own,
// or, for a form whose spell replaces another form's as you learn it (its
// SkillLineAbility row's SupercedesSpell: Dire Bear Form over Bear Form),
// that form's, so the two share one list. A rank replacing a rank of the
// same form (Stealth's) changes nothing.
const replaces = new Map(); // spell -> the spell it replaces
for (const [id, rows] of rowsOf) {
    for (const row of rows) if (+row.SupercedesSpell) replaces.set(id, +row.SupercedesSpell);
}
function listOf(form, seen = new Set()) {
    assert(!seen.has(form), `forms replace each other in a circle: ${[...seen].join(', ')}`);
    seen.add(form);
    for (const id of givers.get(form)) {
        const was = formOf.get(replaces.get(id));
        if (was !== undefined && was !== form && playerForms.has(was)) return listOf(was, seen);
    }
    return form;
}

// Each spell's rule over the forms that matter for it: none and its class's
// forms (every player form for a racial). Listed only when some can't cast
// it or it needs stealth; spells with one answer share one rule.
const rules = new Map(); // "0,31" or "1 stealth" -> spell IDs
for (const [id, classes] of learnable) {
    if (formOf.has(id)) continue; // a form's own spell: always yours to change form with
    const forms = new Set([0]);
    for (const token of classes.size ? classes : Object.values(CLASSES)) for (const form of classForms.get(token)) forms.add(form);
    const relevant = [...forms].sort((a, b) => a - b);
    const ok = relevant.filter(form => allowed(id, form));
    const stealth = stealthOnly(id);
    if (ok.length === relevant.length && !stealth) continue;
    const key = ok.join(',') + (stealth ? ' stealth' : '');
    if (!rules.has(key)) rules.set(key, []);
    rules.get(key).push(id);
}
// A rule no form can meet would hide its spell for good: none may be.
for (const [key, ids] of rules) {
    assert(!/^( stealth)?$/.test(key), `no form can cast ${ids.map(id => `${names.get(id)} (${id})`).join(', ')}`);
}

// Rules in a fixed order (by their forms), each spell by name then ID.
const ruleKeys = [...rules.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
const ruleLines = ruleKeys.map((key, i) => {
    const [forms, stealth] = key.split(' ');
    const example = [...new Set(rules.get(key).map(id => names.get(id)))].sort()[0];
    return ` {${forms}${stealth ? ',stealth=true' : ''}}, -- ${i + 1}: ${example}${rules.get(key).length > 1 ? ' and others' : ''}`;
});
const byName = new Map();
ruleKeys.forEach((key, i) => {
    for (const id of rules.get(key)) {
        const name = names.get(id);
        if (!byName.has(name)) byName.set(name, []);
        byName.get(name).push([id, i + 1]);
    }
});
const spellLines = [...byName.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0)).map(name => {
    const ids = byName.get(name).sort((a, b) => a[0] - b[0]);
    return ` ${ids.map(([id, rule]) => `[${id}]=${rule}`).join(',')}, -- ${name}`;
});
const sortedForms = [...playerForms].sort((a, b) => a - b);
const formLines = sortedForms.map(form => ` [${form}]=${JSON.stringify(formRows.get(form).Name_lang)},`);
const listLines = sortedForms.map(form => {
    const list = listOf(form);
    return ` [${form}]=${list},${list !== form ? ` -- ${formRows.get(form).Name_lang}: ${formRows.get(list).Name_lang}'s` : ''}`;
});
const giverLines = sortedForms.map(form => {
    const ids = givers.get(form).sort((a, b) => a - b);
    return ` [${form}]={${ids.join(',')}}, -- ${[...new Set(ids.map(id => names.get(id)))].sort().join(', ')}`;
});

const text = [
    `-- Generated by Tools/GenerateForms.mjs from Blizzard game data for build ${BUILD}.`,
    '-- The forms a character can take (GetShapeshiftFormID; none is 0); each',
    '-- one\'s list on a bar that swaps with your form (a form whose spell replaces',
    '-- another\'s as you learn it shares that one\'s); the spells that put you in',
    '-- each, to tell which you know; and for every spell some form of its class',
    '-- can\'t cast, or that needs stealth, the forms it can be cast in: a rule',
    '-- shared by every spell with that answer (stealth: only while stealthed',
    '-- too). Any other spell casts in every form. Do not edit.',
    'local _, ns = ...',
    'ns.FORMS = {',
    ...formLines,
    '}',
    'ns.FORM_LISTS = {',
    ...listLines,
    '}',
    'ns.FORM_GIVERS = {',
    ...giverLines,
    '}',
    'ns.FORM_RULES = {',
    ...ruleLines,
    '}',
    'ns.FORM_SPELLS = {',
    ...spellLines,
    '}',
    '',
].join('\n');
await writeFile(out, text);
if (!args.includes('--quiet')) {
    const count = [...rules.values()].reduce((sum, ids) => sum + ids.length, 0);
    console.log(`Forms.lua: ${playerForms.size} forms, ${ruleKeys.length} rules, ${count} spells of ${learnable.size} learnable.`);
}
