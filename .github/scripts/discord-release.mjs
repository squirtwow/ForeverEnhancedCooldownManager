// Forever Enhanced Cooldown Manager release announcements, by Squirt. No
// third-party runtime dependencies. When a version tag is pushed, waits until
// CurseForge lists that version as available, then posts its changelog to the
// Discord announcements channel.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// The CurseForge project, filled in once it exists.
export const PROJECT_ID = null;
export const LINKS = {
  curseforge: null,
  github: 'https://github.com/squirtwow/ForeverEnhancedCooldownManager',
};
const NAME = 'Forever Enhanced Cooldown Manager';
const PACKAGE = 'ForeverEnhancedCooldownManager';
const AVAILABLE = new Set([4, 10]); // CurseForge file statuses: approved, released
const COLOUR = 0xff8040; // the addon's orange accent
const headers = {
  Accept: 'application/json',
  'User-Agent': `${NAME} release announcer (${LINKS.github})`,
};
const pause = ms => new Promise(resolvePause => setTimeout(resolvePause, ms));

// JSON from a web service, trying again after rate limits and server errors.
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

export function validVersion(version) {
  return typeof version === 'string' && /^\d{1,2}\.\d{1,2}(\.\d{1,2})?$/.test(version);
}

// The version's own section of CHANGELOG.txt: each "### " heading with its
// bullets. Nothing else is read from the file.
export function releaseNotes(changelog, version) {
  const lines = String(changelog).split(/\r?\n/);
  const start = lines.findIndex(line => line.trim() === `## ${version}`);
  if (start < 0) return null;
  const sections = [];
  for (const line of lines.slice(start + 1)) {
    if (/^## /.test(line)) break;
    const heading = line.match(/^### (.+)$/);
    if (heading) sections.push({ title: heading[1].trim(), items: [] });
    else if (/^- /.test(line) && sections.length) sections.at(-1).items.push(line.slice(2).trim());
  }
  const filled = sections.filter(section => section.items.length);
  return filled.length ? filled : null;
}

// The version's file on CurseForge, once it can be downloaded.
export function findFile(files, version, projectId = PROJECT_ID) {
  if (!Array.isArray(files)) return null;
  return files.find(file => file && file.projectId === projectId && AVAILABLE.has(file.status)
    && (file.displayName === version || file.fileName === `${PACKAGE}-${version}.zip`)) || null;
}

// Checks CurseForge every minute, for up to an hour.
export async function waitForCurseForge(version, {
  projectId = PROJECT_ID,
  getFiles = async () => requestJson(`https://www.curseforge.com/api/v1/mods/${projectId}/files?pageIndex=0&pageSize=20&sort=dateCreated&sortDescending=true&removeAlphas=false`, { headers }, 'CurseForge'),
  sleep = pause, now = () => Date.now(), limitMs = 60 * 60 * 1000, everyMs = 60 * 1000, log = console.log,
} = {}) {
  const start = now();
  for (;;) {
    try {
      const file = findFile((await getFiles())?.data, version, projectId);
      if (file) return file;
    } catch (error) {
      log(`${error.message}; trying again.`);
    }
    if (now() - start >= limitMs) return null;
    await sleep(everyMs);
  }
}

// Discord allows 4096 characters in an embed; long notes end at a whole bullet.
export function discordPayload(version, notes, onCurseForge = true, links = LINKS) {
  const closing = (onCurseForge
    ? 'Update through the CurseForge app, or download it from'
    : "It'll be on CurseForge shortly. Download it from")
    + ` [CurseForge](${links.curseforge}) or [GitHub](${links.github}).`;
  const limit = 4000 - closing.length;
  const parts = [];
  let length = 0, cut = false;
  for (const section of notes) {
    for (const [index, item] of section.items.entries()) {
      const piece = `${index === 0 ? `${parts.length ? '\n' : ''}**${section.title}**\n` : ''}• ${item}\n`;
      if (length + piece.length > limit) { cut = true; break; }
      parts.push(piece);
      length += piece.length;
    }
    if (cut) break;
  }
  const description = `${parts.join('')}${cut ? '…and more in the changelog.\n' : ''}\n${closing}`;
  return {
    content: '@here',
    allowed_mentions: { parse: ['everyone'] },
    embeds: [{
      title: `${NAME} ${version} is out`,
      url: links.curseforge,
      color: COLOUR,
      description,
      footer: { text: `${NAME} ${version} • Your cooldowns and resource display, for WoW Forever` },
      timestamp: new Date().toISOString(),
    }],
  };
}

async function main() {
  if (!PROJECT_ID || !LINKS.curseforge) throw new Error('Fill in the CurseForge project ID and page first');
  const version = process.env.RELEASE_VERSION;
  if (!validVersion(version)) throw new Error('Expected a version tag such as 1.0.0');
  const webhook = validateWebhook(process.env.DISCORD_RELEASE_WEBHOOK);
  const notes = releaseNotes(await readFile('CHANGELOG.txt', 'utf8'), version);
  if (!notes) throw new Error(`CHANGELOG.txt has no notes for ${version}`);
  const file = await waitForCurseForge(version);
  console.log(file ? `CurseForge has ${version}.` : `CurseForge doesn't list ${version} after an hour; announcing anyway.`);
  await sendDiscord(webhook, discordPayload(version, notes, Boolean(file)));
  console.log(`Announced ${NAME} ${version} on Discord.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
