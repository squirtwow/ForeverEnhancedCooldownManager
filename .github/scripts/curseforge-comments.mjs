// Forever Enhanced Cooldown Manager CurseForge comment notifications, by Squirt.
// No third-party runtime dependencies. About every 30 minutes, forwards new
// comments and replies on the CurseForge page to a private Discord channel.
import { appendFile, mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// The CurseForge project.
export const PROJECT_ID = 1717227;
export const LINKS = {
  comments: 'https://www.curseforge.com/wow/addons/forever-enhanced-cooldown-manager/comments',
  github: 'https://github.com/squirtwow/ForeverEnhancedCooldownManager',
};
const NAME = 'Forever Enhanced Cooldown Manager';
const ARTIFACT_NAME = 'curseforge-comment-state';
const COLOUR = 0xff8040; // the addon's orange accent
const PAGE_SIZE = 20;
const MAX_PAGES = 500;
const pause = ms => new Promise(resolvePause => setTimeout(resolvePause, ms));
const headers = {
  Accept: 'application/json',
  'User-Agent': `${NAME} comment notifier (${LINKS.github})`,
};

// JSON from a web service, trying again after rate limits and server errors.
// Error messages deliberately omit request URLs, response bodies and credentials.
export async function requestJson(url, options = {}, label = 'Remote service', fetcher = fetch, sleep = pause) {
  for (let attempt = 0; attempt < 4; attempt++) {
    let response;
    try {
      response = await fetcher(url, { ...options, signal: AbortSignal.timeout(30000) });
    } catch {
      throw new Error(`${label}: network failure or timeout`);
    }
    const retryable = response.status === 429 || (!options.method && response.status >= 500);
    if (retryable && attempt < 3) {
      const retryAfter = Number(response.headers.get('retry-after'));
      await sleep(Math.min(60000, Math.max(1000 * 2 ** attempt, Number.isFinite(retryAfter) ? retryAfter * 1000 : 0)));
      continue;
    }
    if (!response.ok) throw new Error(`${label}: HTTP ${response.status}`);
    try {
      return await response.json();
    } catch {
      throw new Error(`${label}: expected JSON, received an unsupported response`);
    }
  }
}

function commentID(value) {
  if (!((typeof value === 'number' && Number.isSafeInteger(value)) || typeof value === 'string') || !/^[1-9]\d*$/.test(String(value))) {
    throw new Error('Invalid CurseForge comment ID');
  }
  return String(value);
}

// One flat list of comments and replies, each reply knowing its parent.
export function flattenComments(items, projectID = PROJECT_ID, parentID = null) {
  if (!Array.isArray(items)) throw new Error('Unsupported CurseForge comment list');
  const result = [];
  for (const item of items) {
    if (!item || item.projectId !== projectID || typeof item.text !== 'string' || !Number.isFinite(item.datePosted)
      || item.datePosted <= 0 || Number.isNaN(new Date(item.datePosted).getTime())) {
      throw new Error('Unsupported CurseForge comment format');
    }
    const id = commentID(item.id);
    result.push({
      id,
      parentID: item.parentId ? commentID(item.parentId) : parentID,
      text: item.text,
      author: item.author?.displayName || item.author?.username || 'CurseForge member',
      datePosted: item.datePosted,
    });
    if (item.replies !== undefined) result.push(...flattenComments(item.replies, projectID, id));
  }
  return result;
}

// Scan all pages, not just the newest page: replies can be attached to old posts.
export async function collectComments(getPage = async page => requestJson(
  `https://www.curseforge.com/api/v1/mods/${PROJECT_ID}/comments?page=${page}&size=${PAGE_SIZE}`,
  { headers }, 'CurseForge',
)) {
  const found = new Map();
  let pages = 1;
  for (let page = 0; page < pages; page++) {
    const payload = await getPage(page);
    const pagination = payload?.pagination;
    if (!pagination || !Number.isSafeInteger(pagination.totalCount) || pagination.totalCount < 0
      || !Number.isSafeInteger(pagination.pageSize) || pagination.pageSize <= 0 || pagination.index !== page) {
      throw new Error('Unsupported CurseForge pagination');
    }
    pages = Math.max(pages, Math.ceil(pagination.totalCount / pagination.pageSize));
    if (pages > MAX_PAGES) throw new Error('CurseForge exceeds the scan limit; raise it deliberately before continuing');
    for (const comment of flattenComments(payload.data)) found.set(comment.id, comment);
  }
  return [...found.values()].sort((a, b) => a.datePosted - b.datePosted || a.id.localeCompare(b.id));
}

export function validateState(state) {
  if (state?.version !== 1 || state.projectId !== PROJECT_ID || !Array.isArray(state.seen) || !Number.isFinite(Date.parse(state.initializedAt))) {
    throw new Error('Invalid saved notification state; refusing to reset it automatically');
  }
  state.seen.forEach(commentID);
  if (state.seen.some(id => typeof id !== 'string')) throw new Error('Saved comment IDs must be strings');
  return state;
}

// Comment text is untrusted: it can never ping anyone, and fits Discord's limits.
export function discordPayload(comment) {
  return {
    allowed_mentions: { parse: [] },
    embeds: [{
      title: comment.parentID ? 'New CurseForge reply' : 'New CurseForge comment',
      url: LINKS.comments,
      color: COLOUR,
      author: { name: String(comment.author).slice(0, 256) },
      description: comment.text.length > 3500 ? `${comment.text.slice(0, 3497)}...` : (comment.text || '(Empty comment)'),
      timestamp: new Date(comment.datePosted).toISOString(),
      footer: { text: `${NAME} • Comment ${comment.id}${comment.parentID ? ` • Reply to ${comment.parentID}` : ''}` },
    }],
  };
}

// Only a real Discord webhook address, and never anything else.
export function validateWebhook(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Missing or invalid Discord webhook secret'); }
  if (url.protocol !== 'https:' || url.hostname !== 'discord.com' || url.port || url.username || url.password
    || url.search || url.hash || !/^\/api\/webhooks\/\d+\/[A-Za-z0-9_-]+$/.test(url.pathname)) {
    throw new Error('Unexpected Discord webhook URL');
  }
  url.searchParams.set('wait', 'true');
  return url;
}

export async function sendDiscord(webhook, payload, request = requestJson) {
  const message = await request(webhook, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
  }, 'Discord');
  if (typeof message?.id !== 'string') throw new Error('Discord did not acknowledge the message');
}

// Checkpoint each acknowledged delivery. A later failure does not replay the batch.
export async function notify({ comments, state, initialize = false, save, send, now = new Date().toISOString(), limit = 100 }) {
  if (!state) {
    if (!initialize) throw new Error('Notification state is missing. Run manually with initialize_state only for first setup or an intentional new baseline');
    state = { version: 1, projectId: PROJECT_ID, initializedAt: now, seen: comments.map(comment => comment.id), lastCheckedAt: now };
    await save(state);
    return { sent: 0, baseline: comments.length, pending: 0 };
  }
  validateState(state);
  const seen = new Set(state.seen);
  const pending = comments.filter(comment => !seen.has(comment.id));
  let sent = 0;
  for (const comment of pending.slice(0, limit)) {
    await send(discordPayload(comment));
    seen.add(comment.id);
    state.seen = [...seen];
    await save(state);
    sent++;
  }
  state.lastCheckedAt = now;
  await save(state);
  return { sent, baseline: null, pending: pending.length - sent };
}

export function testPayload() {
  return {
    allowed_mentions: { parse: [] },
    content: `✅ **${NAME} CurseForge connection test**\nThe GitHub-hosted checker reached CurseForge and restored or initialized its saved state. New comments and replies will be checked about every 30 minutes and delivered to this private channel.`,
  };
}

async function saveState(file, state) {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(`${file}.tmp`, `${JSON.stringify(state)}\n`);
  await rename(`${file}.tmp`, file);
}

async function findState() {
  const repo = process.env.GITHUB_REPOSITORY;
  const token = process.env.GITHUB_TOKEN;
  if (!repo || !/^[\w.-]+\/[\w.-]+$/.test(repo) || !token || !process.env.GITHUB_OUTPUT) throw new Error('Missing GitHub Actions environment');
  const response = await requestJson(`https://api.github.com/repos/${repo}/actions/artifacts?name=${ARTIFACT_NAME}&per_page=100`, {
    headers: { ...headers, Authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' },
  }, 'GitHub artifact lookup');
  if (!Array.isArray(response.artifacts)) throw new Error('Unsupported GitHub artifact response');
  const artifact = response.artifacts.filter(item => item.name === ARTIFACT_NAME && !item.expired && String(item.workflow_run?.id) !== process.env.GITHUB_RUN_ID)
    .sort((a, b) => b.id - a.id)[0];
  const runID = artifact ? commentID(artifact.workflow_run.id) : '';
  await appendFile(process.env.GITHUB_OUTPUT, `run_id=${runID}\n`);
  console.log(artifact ? 'Found saved notification state.' : 'No saved notification state found.');
}

async function main(command) {
  if (command === 'find-state') return findState();
  if (command === 'probe') {
    const comments = await collectComments();
    console.log(`CurseForge reachable: ${comments.length} comments/replies found. No messages sent.`);
    return;
  }
  if (command !== 'check') throw new Error('Expected command: find-state, probe or check');
  const webhook = validateWebhook(process.env.CURSEFORGE_DISCORD_WEBHOOK);
  const file = process.env.CF_STATE_FILE;
  if (!file) throw new Error('Missing notification state path');
  let state = null;
  try {
    state = validateState(JSON.parse(await readFile(file, 'utf8')));
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error('Cannot read notification state; refusing to reset it');
  }
  const comments = await collectComments();
  const result = await notify({
    comments, state, initialize: process.env.CF_INITIALIZE_STATE === 'true',
    save: next => saveState(file, next), send: payload => sendDiscord(webhook, payload),
  });
  if (process.env.CF_TEST_NOTIFICATION === 'true') await sendDiscord(webhook, testPayload());
  console.log(`Scanned ${comments.length} comments/replies; sent ${result.sent}; pending ${result.pending}${result.baseline !== null ? `; initial baseline ${result.baseline}` : ''}.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv[2]).catch(error => { console.error(error.message); process.exitCode = 1; });
}
