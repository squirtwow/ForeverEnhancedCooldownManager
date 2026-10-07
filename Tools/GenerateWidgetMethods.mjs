// Builds Tools/WidgetMethods.lua: the methods each kind of widget has in WoW
// Forever, for the mock game the tests run in (Tools/TestBars.lua and its
// copies, Tools/TestSkin.lua). A call to a method Forever lacks (a retail-only
// one, or a typo) then fails a test instead of erroring in game.
//
// Reads Blizzard's own UI source for Forever (the forever branch of
// Gethe/wow-ui-source): the generated widget API docs
// (Blizzard_APIDocumentationGenerated/Simple*API and FrameAPI* files) and,
// for the templates the addon makes frames from, their Lua mixins. No addon
// code is an input. Run it again when Forever's API changes:
//
//   node Tools/GenerateWidgetMethods.mjs <wow-ui-source checkout, forever branch>
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const source = process.argv[2];
assert(source, 'Pass the wow-ui-source checkout (forever branch)');
const addons = join(source, 'Interface', 'AddOns');
const docs = join(addons, 'Blizzard_APIDocumentationGenerated');
const out = fileURLToPath(new URL('./WidgetMethods.lua', import.meta.url));

// Each API doc's functions, by the doc's name without "API"/"Documentation".
function api(name) {
  const text = readFileSync(join(docs, `${name}Documentation.lua`), 'utf8');
  assert.match(text, new RegExp(`Name = "${name}"`), `${name}: the doc names itself`);
  const parts = text.split(/\n\tFunctions\s*=/);
  assert.equal(parts.length, 2, `${name}: one Functions list`);
  const functions = parts[1].split(/\n\t(Events|Tables)\s*=/)[0];
  const names = [...functions.matchAll(/\n\t\t\{\s*\n\t\t\tName = "(\w+)",\s*\n\t\t\tType = "Function"/g)].map(m => m[1]);
  // Every entry read (a MaskTexture has none of its own).
  assert.equal(names.length, (functions.match(/\n\t\t\tName = "/g) || []).length, `${name}: every function read`);
  return names;
}

// Forever's widget types, each as the APIs it has (Blizzard's widget
// hierarchy: every object, then script regions, regions and frames).
const APIS = {
  FrameScriptObject: 'SimpleFrameScriptObjectAPI', Object: 'SimpleObjectAPI',
  ScriptRegion: 'SimpleScriptRegionAPI', ScriptRegionResizing: 'SimpleScriptRegionResizingAPI',
  AnimatableObject: 'SimpleAnimatableObjectAPI', Region: 'SimpleRegionAPI',
  TextureBase: 'SimpleTextureBaseAPI', Texture: 'SimpleTextureAPI', MaskTexture: 'SimpleMaskTextureAPI',
  Line: 'SimpleLineAPI', FontString: 'SimpleFontStringAPI', Font: 'SimpleFontAPI', Frame: 'SimpleFrameAPI',
  Button: 'SimpleButtonAPI', CheckButton: 'SimpleCheckboxAPI', EditBox: 'SimpleEditBoxAPI',
  ScrollFrame: 'SimpleScrollFrameAPI', Slider: 'SimpleSliderAPI', StatusBar: 'SimpleStatusBarAPI',
  Cooldown: 'FrameAPICooldown', AnimationGroup: 'SimpleAnimGroupAPI', Animation: 'SimpleAnimAPI',
  Alpha: 'SimpleAnimAlphaAPI', Scale: 'SimpleAnimScaleAPI', Translation: 'SimpleAnimTranslationAPI',
  Rotation: 'SimpleAnimRotationAPI',
};
const BASE = ['FrameScriptObject', 'Object'];
const SCRIPT_REGION = [...BASE, 'ScriptRegion', 'ScriptRegionResizing', 'AnimatableObject'];
const REGION = [...SCRIPT_REGION, 'Region'];
const FRAME = [...SCRIPT_REGION, 'Frame'];
const ANIMATION = [...BASE, 'Animation'];
const KINDS = {
  Texture: [...REGION, 'TextureBase', 'Texture'],
  MaskTexture: [...REGION, 'TextureBase', 'MaskTexture'],
  Line: [...REGION, 'TextureBase', 'Line'],
  FontString: [...REGION, 'FontString'],
  Font: [...BASE, 'Font'],
  Frame: FRAME,
  Button: [...FRAME, 'Button'],
  CheckButton: [...FRAME, 'Button', 'CheckButton'],
  EditBox: [...FRAME, 'EditBox'],
  ScrollFrame: [...FRAME, 'ScrollFrame'],
  Slider: [...FRAME, 'Slider'],
  StatusBar: [...FRAME, 'StatusBar'],
  Cooldown: [...FRAME, 'Cooldown'],
  // Blizzard's intrinsic aura container is a frame (Blizzard_AuraContainer.xml).
  AuraContainer: FRAME,
  AnimationGroup: [...BASE, 'AnimationGroup'],
  Animation: ANIMATION,
  Alpha: [...ANIMATION, 'Alpha'],
  Scale: [...ANIMATION, 'Scale'],
  Translation: [...ANIMATION, 'Translation'],
  Rotation: [...ANIMATION, 'Rotation'],
};

// Every Lua table in Blizzard's addons, mixins among them: its functions and
// the mixins it's made from (X = CreateFromMixins(A, B)), from every
// flavour's copy.
const mixins = new Map();
function mixin(name) {
  if (!mixins.has(name)) mixins.set(name, { own: new Set(), from: new Set() });
  return mixins.get(name);
}
function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) walk(path);
    else if (entry.endsWith('.lua')) {
      const text = readFileSync(path, 'utf8');
      for (const m of text.matchAll(/^function (\w+)[:.](\w+)\s*\(/gm)) mixin(m[1]).own.add(m[2]);
      for (const m of text.matchAll(/^(\w+)\.(\w+)\s*=/gm)) mixin(m[1]).own.add(m[2]);
      for (const m of text.matchAll(/^(\w+)\s*=\s*CreateFromMixins\(([^)]*)\)/gm)) {
        for (const from of m[2].split(',').map(s => s.trim()).filter(Boolean)) mixin(m[1]).from.add(from);
      }
    }
  }
}
// Every named element in Blizzard's XML (templates, intrinsics and frames):
// its tag, its mixin= and inherits= lists, and the mixins listed inside it
// (<Mixins><Mixin key=.../>, as intrinsics do; the public ones only).
const elements = new Map();
function element(name) {
  if (!elements.has(name)) elements.set(name, { tags: new Set(), mixins: new Set(), inherits: new Set() });
  return elements.get(name);
}
const list = text => (text || '').split(',').map(s => s.trim()).filter(Boolean);
function readXml(text) {
  const stack = [];
  for (const m of text.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<(\/?)(\w+)([^>]*?)(\/?)>/g)) {
    const [, closing, tag, attributes, empty] = m;
    if (closing) {
      stack.pop();
      continue;
    }
    const attr = key => (attributes.match(new RegExp(`\\b${key}="([^"]*)"`)) || [])[1];
    const name = attr('name');
    if (tag === 'Mixin') {
      // Only a mixin the frame's own code sees: no source, or a public partition.
      const owner = stack.findLast(entry => entry.name);
      if (owner && (!attr('source') || attr('targetPartition') === 'public')) element(owner.name).mixins.add(attr('key'));
    } else if (name) {
      const e = element(name);
      e.tags.add(tag);
      for (const mixin of list(attr('mixin'))) e.mixins.add(mixin);
      for (const from of list(attr('inherits'))) e.inherits.add(from);
    }
    if (!empty) stack.push({ tag, name });
  }
}
function walkXml(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) walkXml(path);
    else if (entry.endsWith('.xml')) readXml(readFileSync(path, 'utf8'));
  }
}
walk(addons);
walkXml(addons);
function methods(name, seen = new Set()) {
  assert(mixins.has(name), `${name}: no such mixin in the source`);
  if (seen.has(name)) return [];
  seen.add(name);
  const m = mixins.get(name);
  return [...m.own, ...[...m.from].flatMap(from => methods(from, seen))];
}
// A template's or frame's Lua methods: its mixins', what it inherits', and
// those of its tag when that's an intrinsic (AuraContainer, AuraButton).
function resolve(name, seen = new Set()) {
  assert(elements.has(name), `${name}: not in Blizzard's XML`);
  if (seen.has(name)) return [];
  seen.add(name);
  const e = elements.get(name);
  return [
    ...[...e.mixins].flatMap(mixin => methods(mixin)),
    ...[...e.inherits].flatMap(from => resolve(from, seen)),
    ...[...e.tags].filter(tag => !KINDS[tag] && elements.has(tag)).flatMap(tag => resolve(tag, seen)),
  ];
}

// The templates the addon and the mock make frames from (the icons a custom
// aura container makes are CustomAuraButtonTemplate).
const TEMPLATES = ['BackdropTemplate', 'ActionButtonSpellAlertTemplate', 'UIPanelButtonTemplate',
  'UIPanelScrollFrameTemplate', 'SecureActionButtonTemplate', 'CooldownFrameTemplate',
  'CustomAuraContainerTemplate', 'CustomAuraButtonTemplate'];
// Blizzard's own frames the tests stand in for.
const BLIZZARD = ['PersonalResourceDisplayFrame', 'PlayerCastingBarFrame', 'EditModeManagerFrame',
  'TimerTracker', 'RaidWarningFrame'];

const words = list => [...new Set(list)].filter(n => /^[A-Z]/.test(n)).sort().join(' ');
const lines = [
  '-- Made by Tools/GenerateWidgetMethods.mjs from Blizzard\'s UI source for WoW',
  '-- Forever (the generated widget API docs, and the templates\' Lua mixins).',
  '-- Don\'t edit by hand: run the generator again when Forever\'s API changes.',
  '-- The mock game gives each kind of widget only these methods, as the game',
  '-- does, so a call to one Forever lacks fails a test.',
  'return {',
  '    -- The methods of each API, by name.',
  '    apis = {',
  ...Object.entries(APIS).map(([key, name]) => `        ${key} = "${words(api(name))}",`),
  '    },',
  '    -- Each kind of widget: the APIs it has.',
  '    kinds = {',
  ...Object.entries(KINDS).map(([kind, list]) => `        ${kind} = "${list.join(' ')}",`),
  '    },',
  '    -- What each template adds: its public mixins\' methods.',
  '    templates = {',
  ...TEMPLATES.map(name => `        ${name} = "${words(resolve(name))}",`),
  '    },',
  '    -- Blizzard\'s own frames the tests stand in for: their Lua methods.',
  '    blizzard = {',
  ...BLIZZARD.map(name => `        ${name} = "${words(resolve(name))}",`),
  '    },',
  '}',
  '',
];
writeFileSync(out, lines.join('\n'));
console.log(`Tools/WidgetMethods.lua: ${Object.keys(KINDS).length} kinds, ${Object.keys(TEMPLATES).length} templates`);
