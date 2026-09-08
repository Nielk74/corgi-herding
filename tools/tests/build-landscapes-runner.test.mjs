#!/usr/bin/env node
// No Godot, shared caches, devices or live services: every cook runs inside an
// isolated minimal repository with a mock compiler and private old cache bytes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { runBoundedProcess } from '../bounded-process.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'corgi-cook-runner-test-'));
const write = (name, bytes) => {
  const destination = path.join(fixture, name);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, bytes);
};
const source = fs.readFileSync(path.join(root, 'tools/build-landscapes.mjs'), 'utf8');
const sourceList = source.match(/const sources = \[([\s\S]*?)\];/);
assert.ok(sourceList, 'fixture derives the exact production fingerprint inventory');
for (const match of sourceList[1].matchAll(/'([^']+)'/g)) write(match[1], 'private fixture input\n');
for (const id of ['aerial_grass_rock', 'rock_01', 'coast_sand_03']) {
  for (const suffix of ['diff_1k.jpg', 'nor_gl_1k.png', 'rough_1k.jpg']) {
    const name = `client/assets/materials/${id}/${id}_${suffix}`;
    write(name, 'private fixture pixels');
    write(name + '.import', 'private fixture import settings');
  }
}
for (const id of ['long_valley', 'dry_wash']) write(`client/worlds/${id}.recipe.json`, '{}');
write('tools/build-landscapes.mjs', source);
write('tools/run-godot-check.sh', fs.readFileSync(path.join(root, 'tools/run-godot-check.sh')));
const runnerSource = fs.readFileSync(path.join(root, 'tools/bounded-process.mjs'), 'utf8');
assert.equal((runnerSource.match(/COOK_TIMEOUT_MS = 120_000/g) || []).length, 1);
// Shorten ONLY this disposable copy. Production offers no environment/CLI
// escape hatch that could accidentally disable or lengthen the cook deadline.
write('tools/bounded-process.mjs', runnerSource.replace('COOK_TIMEOUT_MS = 120_000', 'COOK_TIMEOUT_MS = 600'));
write('mock-godot.mjs', `#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
if (process.argv.includes('--version')) { console.log('4.6.3.stable.fixture'); process.exit(0); }
const mode = fs.readFileSync('mode', 'utf8');
const output = process.argv.find(arg => arg.startsWith('--out=')).slice(6);
fs.writeFileSync(output, Buffer.alloc(4096, mode === 'good' ? 65 : 90));
process.stdout.write('compiler stdout before result\\n');
process.stderr.write('compiler stderr before result\\n');
if (mode === 'good') process.exit(0);
const descendant = spawn(process.execPath, ['-e', 'process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)'], { stdio: 'ignore' });
fs.writeFileSync('owned-pids.json', JSON.stringify([process.pid, descendant.pid]));
// The mock is the Bash pipeline's direct child; the detached wrapper PID is
// also its process-group ID, covering the real wrapper/tee as well as this mock.
fs.writeFileSync('owned-group.json', JSON.stringify(process.ppid));
if (mode === 'orphan') process.exit(0);
process.on('SIGTERM', () => {});
if (mode === 'fatal') {
  process.stdout.write('ERR');
  setTimeout(() => process.stdout.write('OR: fixture parse failure despite hanging compiler\\n'), 30);
}
setInterval(() => {}, 1000);
`);
fs.chmodSync(path.join(fixture, 'mock-godot.mjs'), 0o755);
const alive = pid => {
  try { process.kill(pid, 0); return true; }
  catch (error) { if (error.code === 'ESRCH') return false; throw error; }
};
const assertGone = async pids => {
  for (let attempt = 0; attempt < 80 && pids.some(alive); attempt++) await delay(25);
  assert.deepEqual(pids.filter(alive), [], 'all owned mock compiler descendants are reaped');
};
const groupAlive = group => {
  try { process.kill(-group, 0); return true; }
  catch (error) { if (error.code === 'ESRCH') return false; throw error; }
};
const assertGroupGone = async group => {
  for (let attempt = 0; attempt < 80 && groupAlive(group); attempt++) await delay(25);
  assert.equal(groupAlive(group), false, 'no wrapper, tee, compiler or descendant remains in the owned group');
};
const runCook = () => spawnSync(process.execPath, ['tools/build-landscapes.mjs', './mock-godot.mjs', '--force'], {
  cwd: fixture, encoding: 'utf8', timeout: 10_000,
});
const cacheFiles = ['long_valley.scn', 'long_valley.json', 'dry_wash.scn', 'dry_wash.json'];
const caches = () => cacheFiles.map(name => fs.readFileSync(path.join(fixture, 'client/generated', name)));
const sentinel = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
const sentinelClosed = new Promise(resolve => sentinel.once('close', resolve));
try {
  write('mode', 'good');
  const good = runCook();
  assert.equal(good.error, undefined);
  assert.equal(good.status, 0, good.stderr);
  assert.match(good.stdout, /compiler stdout before result/);
  assert.match(good.stdout, /compiler stderr before result/);
  const previous = caches();
  const verified = spawnSync(process.execPath, ['tools/build-landscapes.mjs', '--check'], { cwd: fixture, encoding: 'utf8' });
  assert.equal(verified.status, 0, verified.stderr);
  for (const mode of ['fatal', 'timeout', 'orphan']) {
    write('mode', mode);
    const before = Date.now();
    const failed = runCook();
    assert.equal(failed.error, undefined, 'supervisor exits before the test safety deadline');
    assert.notEqual(failed.status, 0, 'a partial scene can never make a failing cook successful');
    assert.ok(Date.now() - before < 5000, 'fatal/hanging cook is bounded');
    const expected = { fatal: /Godot reported a fatal error/, timeout: /deadline exceeded \(600 ms\)/, orphan: /child exited with live descendants/ };
    assert.match(failed.stderr, expected[mode]);
    assert.match(failed.stderr, /Full log:/);
    assert.match(failed.stdout, /compiler stdout before result/);
    assert.match(failed.stdout, /compiler stderr before result/);
    const logMatch = failed.stderr.match(/Full log: (.+\/output\.log)/);
    assert.ok(logMatch);
    const failureLog = fs.readFileSync(logMatch[1], 'utf8');
    assert.match(failureLog, /compiler stdout before result/);
    assert.match(failureLog, /compiler stderr before result/);
    if (mode === 'fatal') assert.match(failureLog, /ERROR: fixture parse failure/);
    caches().forEach((bytes, index) => assert.deepEqual(bytes, previous[index], `${cacheFiles[index]} survives failed cook exactly`));
    assert.equal(fs.readdirSync(path.join(fixture, 'client/generated')).some(name => name.endsWith('.next')), false);
    await assertGone(JSON.parse(fs.readFileSync(path.join(fixture, 'owned-pids.json'))));
    await assertGroupGone(JSON.parse(fs.readFileSync(path.join(fixture, 'owned-group.json'))));
    assert.ok(alive(sentinel.pid), 'unrelated process is not signaled');
  }

  // A normal nonzero exit, an exit-zero error, and a failed exec remain failures.
  // These direct checks also verify separate stdout/stderr forwarding.
  for (const [name, command, args, expected] of [
    ['nonzero', process.execPath, ['-e', 'process.stdout.write("out\\n"); process.stderr.write("err\\n"); process.exit(7)'], /child exited 7/],
    ['zero-error', process.execPath, ['-e', 'process.stderr.write("Parse Error: mock\\n")'], /fatal error/],
    ['missing', path.join(fixture, 'missing-compiler'), [], /could not start child/],
  ]) {
    let out = '', err = '';
    const result = await runBoundedProcess(command, args, {
      cwd: fixture, logPath: path.join(fixture, name + '.log'), timeoutMs: 600, terminateGraceMs: 50,
      stdout: { write(bytes) { out += bytes.toString(); } }, stderr: { write(bytes) { err += bytes.toString(); } },
    });
    assert.match(result.failure, expected);
    assert.ok(fs.statSync(result.logPath).size > 0);
    if (name === 'nonzero') { assert.match(out, /^out\n/); assert.match(err, /^err\n/); }
  }
  console.log(`Cook supervision regression passed: success, split fatal output, hanging compiler/descendant, deadline, early wrapper exit, nonzero/zero-error/exec failure, exact cache preservation. Evidence: ${fixture}`);
} finally {
  // Test cleanup only: exact fixture-recorded child IDs and this sentinel. Never
  // search by process name or touch a real Godot/server/device/cache directory.
  if (fs.existsSync(path.join(fixture, 'owned-group.json'))) {
    const group = JSON.parse(fs.readFileSync(path.join(fixture, 'owned-group.json')));
    if (groupAlive(group)) process.kill(-group, 'SIGKILL');
  }
  if (fs.existsSync(path.join(fixture, 'owned-pids.json'))) {
    for (const pid of JSON.parse(fs.readFileSync(path.join(fixture, 'owned-pids.json')))) {
      if (alive(pid)) process.kill(pid, 'SIGKILL');
    }
  }
  if (alive(sentinel.pid)) sentinel.kill('SIGTERM');
  await sentinelClosed;
}
