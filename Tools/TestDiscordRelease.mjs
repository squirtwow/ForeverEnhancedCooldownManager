// Run with: node --test Tools/TestDiscordRelease.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  discordPayload, findFile, releaseNotes, sendDiscord, validVersion, validateWebhook, waitForCurseForge,
} from '../.github/scripts/discord-release.mjs';

const changelog = await readFile(new URL('../CHANGELOG.txt', import.meta.url), 'utf8');
const PROJECT = 4242;
const links = { curseforge: 'https://www.curseforge.com/wow/addons/fecm-test', github: 'https://github.com/squirtwow/ForeverEnhancedCooldownManager' };
const file = (displayName, extra = {}) => ({ projectId: PROJECT, displayName, fileName: `ForeverEnhancedCooldownManager-${displayName}.zip`, status: 4, ...extra });

test('only plain version tags are announced', () => {
  assert.equal(validVersion('1.0.0'), true);
  assert.equal(validVersion('1.0'), true);
  assert.equal(validVersion('v1.0.0'), false);
  assert.equal(validVersion('1.0.0; rm -rf'), false);
  assert.equal(validVersion(undefined), false);
});

test('the version\'s own changelog section, by heading, and nothing after it', () => {
  const notes = releaseNotes(changelog, '1.0.0');
  assert.deepEqual(notes.map(section => section.title), ["Blizzard's Cooldown Manager", 'Your own bars', 'Settings']);
  assert.match(notes[0].items[0], /^A new look:/);
  assert.equal(releaseNotes(changelog, '9.9.9'), null);
  assert.equal(releaseNotes('## 1.0.0\n\nNothing listed.', '1.0.0'), null);
});

test('CurseForge counts once the file for that version is available', () => {
  assert.equal(findFile([file('0.9.0'), file('1.0.0')], '1.0.0', PROJECT).displayName, '1.0.0');
  assert.equal(findFile([file('1.0.0', { status: 1 })], '1.0.0', PROJECT), null, 'still processing');
  assert.equal(findFile([file('1.0.0', { projectId: 12 })], '1.0.0', PROJECT), null, 'another project');
  assert.equal(findFile([file('1.0.0', { displayName: 'FECM 1.0.0' })], '1.0.0', PROJECT).fileName,
    'ForeverEnhancedCooldownManager-1.0.0.zip', 'matched by file name too');
  assert.equal(findFile(undefined, '1.0.0', PROJECT), null);
});

test('waits for CurseForge, checking again after errors, and gives up after the limit', async () => {
  let clock = 0, calls = 0;
  const sleep = async ms => { clock += ms; };
  const pages = [new Error('CurseForge: HTTP 503'), { data: [file('0.9.0')] }, { data: [file('1.0.0')] }];
  const found = await waitForCurseForge('1.0.0', {
    projectId: PROJECT,
    getFiles: async () => { const page = pages[calls++]; if (page instanceof Error) throw page; return page; },
    sleep, now: () => clock, log: () => {},
  });
  assert.equal(found.displayName, '1.0.0');
  assert.equal(calls, 3);
  assert.equal(clock, 120000, 'a minute between checks');
  clock = 0;
  const missing = await waitForCurseForge('1.1.0', { projectId: PROJECT, getFiles: async () => ({ data: [] }), sleep, now: () => clock, log: () => {} });
  assert.equal(missing, null);
  assert.equal(clock, 3600000, 'an hour at most');
});

test('the Discord post: @here, the notes in sections, and where to get it', () => {
  const payload = discordPayload('1.0.0', releaseNotes(changelog, '1.0.0'), true, links);
  assert.equal(payload.content, '@here');
  assert.deepEqual(payload.allowed_mentions, { parse: ['everyone'] });
  const [embed] = payload.embeds;
  assert.equal(embed.title, 'Forever Enhanced Cooldown Manager 1.0.0 is out');
  assert.match(embed.description, /^\*\*Blizzard's Cooldown Manager\*\*\n• A new look:/);
  assert.match(embed.description, /\*\*Settings\*\*\n• The first time you log in/);
  assert.match(embed.description, /Update through the CurseForge app, or download it from \[CurseForge\]\(https:\/\/www\.curseforge\.com\/wow\/addons\/fecm-test\) or \[GitHub\]\(https:\/\/github\.com\/squirtwow\/ForeverEnhancedCooldownManager\)\.$/);
  assert.ok(embed.description.length <= 4096);
  const late = discordPayload('1.0.0', releaseNotes(changelog, '1.0.0'), false, links);
  assert.match(late.embeds[0].description, /It'll be on CurseForge shortly/);
});

test('very long notes stop at a whole bullet, within Discord\'s limit', () => {
  const notes = [{ title: 'Added', items: Array.from({ length: 200 }, (_, i) => `Feature ${i} with a longer description to fill the space.`) }];
  const { description } = discordPayload('2.0.0', notes, true, links).embeds[0];
  assert.ok(description.length <= 4096);
  assert.match(description, /…and more in the changelog\./);
  assert.doesNotMatch(description, /Feature 199/);
});

test('only a real Discord webhook, and Discord has to acknowledge the post', async () => {
  assert.equal(validateWebhook('https://discord.com/api/webhooks/123/abc_DEF-9').searchParams.get('wait'), 'true');
  for (const bad of ['http://discord.com/api/webhooks/1/a', 'https://evil.example/api/webhooks/1/a', 'https://discord.com/api/webhooks/1/a?x=1', '', undefined]) {
    assert.throws(() => validateWebhook(bad), undefined, `refused: ${bad}`);
  }
  await sendDiscord(new URL('https://discord.com/api/webhooks/1/a'), {}, async () => ({ id: '99' }));
  await assert.rejects(sendDiscord(new URL('https://discord.com/api/webhooks/1/a'), {}, async () => ({})), /did not acknowledge/);
});
