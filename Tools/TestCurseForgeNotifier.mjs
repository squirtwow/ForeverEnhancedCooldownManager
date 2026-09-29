// Run with: node --test Tools/TestCurseForgeNotifier.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  LINKS, PROJECT_ID, collectComments, discordPayload, flattenComments, notify, requestJson, sendDiscord, testPayload, validateState, validateWebhook,
} from '../.github/scripts/curseforge-comments.mjs';

const raw = (id, extra = {}) => ({ id, projectId: PROJECT_ID, text: `Comment ${id}`, datePosted: 1700000000000 + id, author: { displayName: 'Tester' }, ...extra });
const page = (index, data, totalCount = 40) => ({ data, pagination: { index, totalCount, pageSize: 20 } });
const state = (seen = []) => ({ version: 1, projectId: PROJECT_ID, initializedAt: '2026-09-29T00:00:00Z', seen });

test('the notifier watches Forever Enhanced Cooldown Manager on CurseForge', () => {
  assert.equal(PROJECT_ID, 1717227);
  assert.equal(LINKS.comments, 'https://www.curseforge.com/wow/addons/forever-enhanced-cooldown-manager/comments');
  const embed = discordPayload(flattenComments([raw(5)])[0]).embeds[0];
  assert.equal(embed.url, LINKS.comments);
  assert.equal(embed.title, 'New CurseForge comment');
  assert.equal(embed.footer.text, 'Forever Enhanced Cooldown Manager • Comment 5');
});

test('all pages include nested replies to old comments and duplicate IDs only once', async () => {
  const requested = [];
  const comments = await collectComments(async index => {
    requested.push(index);
    return index === 0 ? page(0, [raw(1), raw(2)]) : page(1, [raw(1, { replies: [raw(9, { replies: [raw(10)] })] })]);
  });
  assert.deepEqual(requested, [0, 1]);
  assert.deepEqual(comments.map(c => [c.id, c.parentID]), [['1', null], ['2', null], ['9', '1'], ['10', '9']]);
});

test('an empty project is one page with nothing to send', async () => {
  const requested = [];
  const comments = await collectComments(async index => { requested.push(index); return page(index, [], 0); });
  assert.deepEqual(requested, [0]);
  assert.deepEqual(comments, []);
});

test('a growing page count is scanned; wrong indexes and malformed comments fail closed', async () => {
  const requested = [];
  await collectComments(async index => { requested.push(index); return page(index, [], index === 0 ? 40 : 60); });
  assert.deepEqual(requested, [0, 1, 2]);
  await assert.rejects(collectComments(async () => page(1, [])), /pagination/);
  await assert.rejects(collectComments(async () => page(0, [raw(1, { projectId: 1709918 })])), /format/);
  await assert.rejects(collectComments(async () => page(0, [], 10001)), /scan limit/);
  assert.throws(() => flattenComments([raw(1, { datePosted: 1e99 })]), /format/);
});

test('initialization records the baseline without flooding Discord; missing state requires explicit setup', async () => {
  const comments = flattenComments([raw(1), raw(2)]);
  let saved;
  const options = { comments, state: null, save: async next => { saved = structuredClone(next); }, send: async () => assert.fail('Unexpected post') };
  await assert.rejects(notify(options), /state is missing/);
  const result = await notify({ ...options, initialize: true });
  assert.equal(result.baseline, 2);
  assert.deepEqual(saved.seen, ['1', '2']);
  validateState(saved);
});

test('only new comments/replies are delivered, edits are ignored, and repeat runs are silent', async () => {
  const comments = flattenComments([raw(1, { text: 'edited', replies: [raw(3)] }), raw(2)]);
  let saved = state(['1', '2']);
  const sent = [];
  const options = { comments, save: async next => { saved = structuredClone(next); }, send: async payload => sent.push(payload) };
  assert.equal((await notify({ ...options, state: saved })).sent, 1);
  assert.equal(sent[0].embeds[0].title, 'New CurseForge reply');
  assert.equal(sent[0].embeds[0].footer.text, 'Forever Enhanced Cooldown Manager • Comment 3 • Reply to 1');
  assert.equal((await notify({ ...options, state: saved })).sent, 0);
  assert.equal(sent.length, 1);
});

test('partial failures retain successful deliveries while leaving failed IDs pending', async () => {
  const comments = flattenComments([raw(1), raw(2), raw(3)]);
  let saved = state();
  let calls = 0;
  await assert.rejects(notify({ comments, state: saved, save: async next => { saved = structuredClone(next); }, send: async () => { if (++calls === 2) throw new Error('Discord unavailable'); } }), /unavailable/);
  assert.deepEqual(saved.seen, ['1']);
  const sent = [];
  assert.equal((await notify({ comments, state: saved, save: async () => {}, send: async payload => sent.push(payload) })).sent, 2);
  assert.equal(sent[0].embeds[0].footer.text, 'Forever Enhanced Cooldown Manager • Comment 2');
});

test('batch limit leaves unsent comments pending and invalid state is never reset', async () => {
  let saved;
  const result = await notify({ comments: flattenComments([raw(1), raw(2)]), state: state(), limit: 1, save: async next => { saved = structuredClone(next); }, send: async () => {} });
  assert.equal(result.pending, 1);
  assert.deepEqual(saved.seen, ['1']);
  assert.throws(() => validateState({ ...state(), seen: [1] }), /strings/);
  assert.throws(() => validateState({ ...state(), projectId: 1709918 }), /Invalid/);
});

test('untrusted comment text cannot ping members and fits Discord embed limits', () => {
  const payload = discordPayload(flattenComments([raw(1, { text: '@everyone <@123> ' + 'x'.repeat(5000), author: { displayName: 'a'.repeat(300) } })])[0]);
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.ok(payload.embeds[0].description.length <= 3500);
  assert.equal(payload.embeds[0].author.name.length, 256);
  assert.equal(validateWebhook('https://discord.com/api/webhooks/123/example_token').search, '?wait=true');
  for (const url of ['http://discord.com/api/webhooks/123/token', 'https://other.example/api/webhooks/123/token', 'https://discord.com/api/webhooks/123/token/github', undefined]) assert.throws(() => validateWebhook(url), /webhook/);
});

test('the connection test names the addon, pings no one and has no dashes', () => {
  const payload = testPayload();
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.match(payload.content, /^✅ \*\*Forever Enhanced Cooldown Manager CurseForge connection test\*\*/);
  assert.doesNotMatch(payload.content, /[\u2013\u2014]|@everyone|@here/);
});

test('Discord must acknowledge each message', async () => {
  const webhook = validateWebhook('https://discord.com/api/webhooks/123/example_token');
  let posted;
  await sendDiscord(webhook, { content: 'hi' }, async (url, options) => { posted = { url: String(url), options }; return { id: '1' }; });
  assert.equal(posted.options.method, 'POST');
  assert.equal(posted.url.endsWith('?wait=true'), true);
  await assert.rejects(sendDiscord(webhook, {}, async () => ({})), /acknowledge/);
});

test('GET retries transient errors, POST retries only rate limits, errors never expose secrets', async () => {
  let calls = 0;
  const result = await requestJson('https://example.invalid/secret', {}, 'Source', async () => ++calls === 1 ? new Response('', { status: 503 }) : Response.json({ ok: true }), async () => {});
  assert.equal(calls, 2);
  assert.equal(result.ok, true);
  calls = 0;
  await assert.rejects(requestJson('https://example.invalid/secret', { method: 'POST' }, 'Discord', async () => { calls++; return new Response('secret response', { status: 503 }); }, async () => {}), { message: 'Discord: HTTP 503' });
  assert.equal(calls, 1);
  calls = 0;
  await requestJson('https://example.invalid/secret', { method: 'POST' }, 'Discord', async () => ++calls === 1 ? new Response('', { status: 429, headers: { 'retry-after': '1' } }) : Response.json({ id: '123' }), async () => {});
  assert.equal(calls, 2);
});
