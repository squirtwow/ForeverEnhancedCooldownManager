// Runs every test the addon has and fails (exit code 1) if any does: each
// Lua suite (Tools/Test*.lua, in fengari), the node tests (Tools/Test*.mjs)
// and the Lua 5.1 parser over every .lua file. fengari exits 0 even when a
// suite stops half-way, so a Lua suite only passes when it ends with its
// "checks passed: N assertions." line and shows no traceback.
//
//   node Tools/RunTests.mjs              everything (about 6 minutes: TestBars)
//   node Tools/RunTests.mjs --skip TestBars
//   node Tools/RunTests.mjs --only TestPulse,TestRules
//
// The Lua kit (fengari, luaparse and its check.js) is looked for in
// LUA_CHECK, then C:\AddonDev\_Toolchain\lua-check (beside the addons, safe
// from Windows' Temp clean-up), then %TEMP%\opencode\lua-check.
import { spawn } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const root = fileURLToPath(new URL('../', import.meta.url));
const tools = join(root, 'Tools');

// The first Lua kit found: its fengari runner and parser check.
export function luaKit() {
  const places = [process.env.LUA_CHECK, join(root, '..', '_Toolchain', 'lua-check'), join(tmpdir(), 'opencode', 'lua-check')];
  for (const place of places.filter(Boolean)) {
    const cli = join(place, 'node_modules', 'fengari-node-cli', 'src', 'lua-cli.js');
    if (existsSync(cli)) return { place, cli, check: join(place, 'check.js'), fengari: join(place, 'node_modules', 'fengari') };
  }
  return null;
}

// Runs a command and gives back its exit code and everything it printed.
// One still running after `timeout` ms is stopped and fails, so a suite
// stuck in a loop can't hold the run up for ever.
function run(command, args, { timeout, ...options } = {}) {
  return new Promise(resolve => {
    const child = spawn(command, args, { cwd: root, ...options });
    let output = '', timedOut = false;
    const timer = timeout ? setTimeout(() => { timedOut = true; child.kill(); }, timeout) : null;
    child.stdout.on('data', chunk => { output += chunk; });
    child.stderr.on('data', chunk => { output += chunk; });
    child.on('error', error => { clearTimeout(timer); resolve({ code: -1, output: output + String(error) }); });
    child.on('close', code => {
      clearTimeout(timer);
      resolve(timedOut ? { code: -1, output: `${output}\ntimed out after ${Math.round(timeout / 1000)}s` } : { code, output });
    });
  });
}

// The longest a Lua suite may take: TestBars takes about 6 minutes alone.
export const LUA_TIMEOUT = 30 * 60 * 1000;

// A Lua suite's result: passed only with its closing line and no traceback.
export function judgeLua(code, output) {
  const lines = output.trim().split(/\r?\n/);
  const last = lines.at(-1) ?? '';
  const match = last.match(/checks passed: (\d+) assertions\.$/);
  const broken = /stack traceback:|^\S+\.lua:\d+: /m.test(output);
  return { ok: code === 0 && !!match && !broken, count: match ? Number(match[1]) : 0, last };
}

export async function runLua(kit, file, timeout = LUA_TIMEOUT) {
  // TestBars needs far more than node's default heap; the rest are small.
  const env = { ...process.env, NODE_OPTIONS: `${process.env.NODE_OPTIONS ?? ''} --max-old-space-size=8192`.trim() };
  const started = Date.now();
  const { code, output } = await run(process.execPath, [kit.cli, file], { env, timeout });
  return { name: file, ...judgeLua(code, output), output, seconds: Math.round((Date.now() - started) / 1000) };
}

// The parser's report: "checked N files, M failed".
export function judgeParser(code, output) {
  const match = output.match(/checked (\d+) files, (\d+) failed/);
  return { ok: code === 0 && !!match && match[2] === '0' && Number(match[1]) > 0, last: match ? match[0] : output.trim().split(/\r?\n/).at(-1) };
}

async function main() {
  const argv = process.argv.slice(2);
  const list = flag => {
    const at = argv.indexOf(flag);
    return at >= 0 ? (argv[at + 1] ?? '').split(',').map(name => name.replace(/\.(lua|mjs)$/, '')).filter(Boolean) : null;
  };
  const only = list('--only'), skip = list('--skip') ?? [];
  const wanted = name => (!only || only.includes(name)) && !skip.includes(name);
  const kit = luaKit();
  const results = [];
  if (!kit) {
    console.log('FAIL  the Lua kit (fengari, check.js) was not found: set LUA_CHECK, or put it in C:\\AddonDev\\_Toolchain\\lua-check');
    process.exit(1);
  }
  console.log(`Lua kit: ${kit.place}`);
  const suites = readdirSync(tools).filter(name => /^Test\w*\.lua$/.test(name)).map(name => name.slice(0, -4)).filter(wanted);
  const nodeTests = readdirSync(tools).filter(name => /^Test\w*\.mjs$/.test(name)).map(name => name.slice(0, -4)).filter(wanted);
  // A name typed wrong runs nothing: that's a failure, not a pass.
  if (!suites.length && !nodeTests.length && !wanted('parser')) {
    console.log(`FAIL  nothing to run: no suite matches ${only ? `--only ${only.join(',')}` : 'the names given'}`);
    process.exit(1);
  }
  // Lua suites side by side, TestBars first (it takes longest), four at a time.
  suites.sort((a, b) => (b === 'TestBars') - (a === 'TestBars'));
  const queue = [...suites];
  await Promise.all(Array.from({ length: Math.min(4, queue.length) }, async () => {
    while (queue.length) {
      const result = await runLua(kit, `Tools/${queue.shift()}.lua`);
      results.push(result);
      console.log(`${result.ok ? 'pass' : 'FAIL'}  ${result.name} (${result.seconds}s): ${result.last}`);
      if (!result.ok) console.log(result.output.trim().split(/\r?\n/).slice(-12).map(line => `      ${line}`).join('\n'));
    }
  }));
  if (nodeTests.length) {
    const { code, output } = await run(process.execPath, ['--test', ...nodeTests.map(name => `Tools/${name}.mjs`)],
      { env: { ...process.env, FENGARI: kit.fengari } });
    const passed = output.match(/^(?:ℹ|#) pass (\d+)/m)?.[1] ?? '?', failed = output.match(/^(?:ℹ|#) fail (\d+)/m)?.[1] ?? '?';
    const ok = code === 0 && failed === '0';
    results.push({ name: `node --test (${nodeTests.length} files)`, ok });
    console.log(`${ok ? 'pass' : 'FAIL'}  node --test ${nodeTests.join(', ')}: ${passed} passed, ${failed} failed`);
    if (!ok) console.log(output.split(/\r?\n/).filter(line => /^✖|not ok|Error|expected|actual/.test(line)).slice(0, 30).join('\n'));
  }
  if (wanted('parser')) {
    const files = [...readdirSync(root).filter(name => name.endsWith('.lua')), ...readdirSync(tools).filter(name => name.endsWith('.lua'))
      .map(name => `Tools/${name}`)];
    const { code, output } = await run(process.execPath, [kit.check, ...files]);
    const result = { name: 'Lua 5.1 parser', ...judgeParser(code, output) };
    results.push(result);
    console.log(`${result.ok ? 'pass' : 'FAIL'}  ${result.name}: ${result.last}`);
    if (!result.ok) console.log(output.trim());
  }
  const failed = results.filter(result => !result.ok);
  const assertions = results.reduce((sum, result) => sum + (result.count ?? 0), 0);
  console.log(failed.length ? `\nFAILED: ${failed.map(result => result.name).join(', ')}`
    : `\nAll passed: ${results.length} runs, ${assertions} Lua assertions.`);
  process.exit(failed.length ? 1 : 0);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) await main();
