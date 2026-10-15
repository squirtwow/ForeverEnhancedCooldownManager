// Forms.lua is generated, never edited by hand: rebuilding it from the game's
// tables (Tools/GenerateForms.mjs, build 1.60.1.70374) must give the file
// byte for byte. Skipped when the tables aren't on this computer
// (C:\AddonDev\_Toolchain\gamedata\forever-70374). What the file says is also
// checked straight from it (no tables needed): the forms, each one's list on
// a bar that swaps with your form (Dire Bear Form's is Bear Form's) and the
// spells that put you in each, and the rule each
// sample spell gets from the game's own data for the druid's forms, the
// warrior's stances, the rogue's Stealth, the priest's Shadowform and the
// shaman's Ghost Wolf (spells a talent tab's skill line gives no class mask,
// and those tied to a form's aura, among them); no rule that no form can
// meet, the spells that change your form never held back, and no rune-only
// spell.
// Run with: node --test Tools/TestForms.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const cache = join(root, '..', '_Toolchain', 'gamedata', 'forever-70374');
const TABLES = ['SpellName', 'Spell', 'SpellMisc', 'SpellShapeshift', 'SpellShapeshiftForm', 'SpellAuraRestrictions', 'SpellEffect',
  'SkillLine', 'SkillLineAbility', 'TraitDefinition'];
const text = readFileSync(join(root, 'Forms.lua'), 'utf8');

test('Forms.lua is exactly what the build makes', { skip: !TABLES.every(name => existsSync(join(cache, `${name}.csv`))) }, () => {
  const out = join(tmpdir(), `fecm-forms-${process.pid}.lua`);
  try {
    const run = spawnSync(process.execPath, ['Tools/GenerateForms.mjs', cache, '--out', out, '--quiet'], { cwd: root, encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    assert.equal(readFileSync(out, 'utf8'), text, 'rebuild with: node Tools/GenerateForms.mjs');
  } finally {
    rmSync(out, { force: true });
  }
});

// The file read back: its forms, each form's list and the spells that put
// you in it, its rules (forms and whether stealth is needed) and each
// spell's rule.
function read() {
  const block = name => text.match(new RegExp(`^ns\\.${name} = \\{\\n([\\s\\S]*?)^\\}$`, 'm'))[1].split('\n').filter(Boolean);
  const forms = Object.fromEntries(block('FORMS').map(line => line.match(/^ \[(\d+)\]="([^"]+)",$/)).map(m => [+m[1], m[2]]));
  const lists = Object.fromEntries(block('FORM_LISTS').map(line => {
    const m = line.match(/^ \[(\d+)\]=(\d+),( -- .+)?$/);
    assert.ok(m, `a form's list: ${line}`);
    return [+m[1], +m[2]];
  }));
  const givers = Object.fromEntries(block('FORM_GIVERS').map(line => {
    const m = line.match(/^ \[(\d+)\]=\{([\d,]+)\}, -- .+$/);
    assert.ok(m, `a form's spells: ${line}`);
    return [+m[1], m[2].split(',').map(Number)];
  }));
  const rules = block('FORM_RULES').map(line => {
    const m = line.match(/^ \{([\d,]+)(,stealth=true)?\}, -- \d+: .+$/);
    assert.ok(m, `a rule: ${line}`);
    return { forms: m[1].split(',').map(Number), stealth: !!m[2] };
  });
  const spells = new Map();
  for (const line of block('FORM_SPELLS')) {
    const m = line.match(/^ ((?:\[\d+\]=\d+,)+) -- (.+)$/);
    assert.ok(m, `a spell line: ${line}`);
    for (const [, id, rule] of m[1].matchAll(/\[(\d+)\]=(\d+),/g)) {
      assert.ok(!spells.has(+id), `${id} listed once`);
      spells.set(+id, { rule: +rule, name: m[2] });
    }
  }
  return { forms, lists, givers, rules, spells };
}

test('the forms a character can take', () => {
  const { forms } = read();
  assert.deepEqual(forms, { 1: 'Cat Form', 3: 'Travel Form', 4: 'Aquatic Form', 5: 'Bear Form', 8: 'Dire Bear Form', 16: 'Ghost Wolf',
    17: 'Battle Stance', 18: 'Defensive Stance', 19: 'Berserker Stance', 28: 'Shadowform', 30: 'Stealth', 31: 'Moonkin Form' },
    'the druid\'s forms (no Tree of Life: a rune), Ghost Wolf, the stances, Shadowform and Stealth; none is 0');
});

test('each form\'s list, and the spells that put you in it', () => {
  const { forms, lists, givers } = read();
  assert.deepEqual(lists, { 1: 1, 3: 3, 4: 4, 5: 5, 8: 5, 16: 16, 17: 17, 18: 18, 19: 19, 28: 28, 30: 30, 31: 31 },
    'each form its own list, but Dire Bear Form, whose spell replaces Bear Form\'s: Bear Form\'s');
  for (const [form, list] of Object.entries(lists)) assert.equal(lists[list], list, `form ${form}'s list is a form's own`);
  assert.deepEqual(givers, { 1: [768], 3: [783], 4: [1066], 5: [5487], 8: [9634], 16: [2645], 17: [2457], 18: [71], 19: [2458],
    28: [15473], 30: [1784, 1785, 1786, 1787], 31: [24858] }, 'Cat Form, Travel Form and the rest, every rank of Stealth');
  assert.deepEqual(Object.keys(lists), Object.keys(forms), 'a list for every form');
  assert.deepEqual(Object.keys(givers), Object.keys(forms), 'and the spells for every form');
});

test('each spell\'s rule, from the game\'s own data', () => {
  const { rules, spells } = read();
  const rule = id => {
    const at = spells.get(id);
    if (!at) return 'any';
    const r = rules[at.rule - 1];
    return r.forms.join(',') + (r.stealth ? ' stealthed' : '');
  };
  const expect = {
    // Druid: none (0), Cat 1, Travel 3, Aquatic 4, Bear 5, Dire Bear 8, Moonkin 31.
    8924: '0,31', // Moonfire: no form or Moonkin ("also in caster form")
    5185: '0', // Healing Touch: not in Moonkin
    1082: '1', 5221: '1', 5215: '1', 1850: '1', // Claw, Shred, Prowl, Dash: cat
    6807: '5,8', 779: '5,8', 5211: '5,8', 6795: '5,8', // Maul, Swipe, Bash, Growl: bear and dire bear
    9005: '1 stealthed', 6785: '1 stealthed', // Pounce, Ravage: cat, prowling
    770: '0,1,5,8,31', // Faerie Fire: not in travel or aquatic form
    1238122: '1,5,8', // Feral Charge
    22812: 'any', // Barkskin
    // On a druid talent tab's skill line with no class mask of their own:
    // Innervate (also in Moonkin), Swiftmend and Nature's Swiftness (no form),
    // Feral Charge (Bear) (bear and dire bear).
    29166: '0,31', 18562: '0', 17116: '0', 16979: '5,8',
    5217: '1', // Tiger's Fury: needs Cat Form's aura on you (SpellAuraRestrictions)
    // Warrior: Battle 17, Defensive 18, Berserker 19.
    100: '17', 7384: '17', 871: '18', 2565: '18', 355: '18', 20252: '19', 1680: '19', 18499: '19',
    5308: '17,19', 772: '17,18', 72: '17,18', 78: 'any', 6673: 'any', // Execute, Rend, Shield Bash, Heroic Strike, Battle Shout
    12292: '17', // Sweeping Strikes: on the Arms tab's line with no class mask
    // Rogue: Stealth 30.
    8676: '30 stealthed', 1833: '30 stealthed', 6770: '30 stealthed', 703: '30 stealthed', 921: '30 stealthed',
    1752: 'any', 5277: 'any', // Sinister Strike, Evasion
    // Priest: Shadowform 28. Shaman: Ghost Wolf 16.
    2050: '0', 528: '0', 8092: 'any', 17: 'any', // Lesser Heal, Cure Disease; Mind Blast, Power Word: Shield
    1240720: '0', 1240721: '0', 1316995: '0', // Penance: not with Shadowform's aura on you (SpellAuraRestrictions)
    331: '0', 403: '0', // Healing Wave, Lightning Bolt: not as a wolf
    17364: '0', 16188: '0', // Stormstrike, Nature's Swiftness: on a shaman tab's line with no class mask, not as a wolf
    // Racials: any form but a shapeshift (Cat, Bear, Travel, Ghost Wolf), or any.
    20600: '0,17,18,19,28,30,31', // Perception
    20589: '0,17,18,19,28,30,31', // Escape Artist
    58984: 'any', 20549: 'any', // Shadowmeld, War Stomp
    // Spells that put you in a form: always yours to change form with.
    768: 'any', 5487: 'any', 9634: 'any', 783: 'any', 1066: 'any', 24858: 'any', 2457: 'any', 71: 'any', 2458: 'any',
    1784: 'any', 15473: 'any', 2645: 'any',
    // Mages, hunters, warlocks and paladins take no form.
    133: 'any', 2973: 'any', 686: 'any', 635: 'any',
  };
  const got = Object.fromEntries(Object.keys(expect).map(id => [id, rule(+id)]));
  assert.deepEqual(got, expect);
});

test('no rule no form can meet, none unused, and no rune-only spell', () => {
  const { forms, rules, spells } = read();
  const used = new Set([...spells.values()].map(s => s.rule));
  rules.forEach((r, i) => {
    assert.ok(r.forms.length > 0, `rule ${i + 1} has a form`);
    for (const form of r.forms) assert.ok(form === 0 || forms[form], `rule ${i + 1}: form ${form} is one a character takes`);
    assert.ok(used.has(i + 1), `rule ${i + 1} is used`);
  });
  for (const [id, { rule }] of spells) assert.ok(rule >= 1 && rule <= rules.length, `${id}: rule ${rule}`);
  // Season of Discovery runes Forever doesn't have: Skull Bash, Survival
  // Instincts, Mangle (cat), Shadowstrike, Metamorphosis, Gladiator Stance.
  for (const id of [410176, 408024, 409828, 399985, 403789, 412513]) assert.equal(spells.has(id), false, `${id} is a rune`);
  // Forever's own spells from that range stay: Lacerate, Primal Bite, Revive.
  for (const id of [414644, 407995, 437138]) assert.ok(spells.has(id), `${id} is Forever's`);
});
