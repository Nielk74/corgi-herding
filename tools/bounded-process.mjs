// POSIX child ownership for offline cooks. Do not signal processes by name: each
// invocation owns one detached process group, including the wrapper's tee/Godot.
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';

export const COOK_TIMEOUT_MS = 120_000;
const fatalOutput = /ERROR:|Parse Error|Failed to load script/;

export async function runBoundedProcess(command, args, {
  cwd, logPath, timeoutMs = COOK_TIMEOUT_MS, terminateGraceMs = 1_000,
  stdout = process.stdout, stderr = process.stderr,
} = {}) {
  if (process.platform === 'win32') throw new Error('Offline cook supervision requires POSIX process groups');
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 ||
      !Number.isSafeInteger(terminateGraceMs) || terminateGraceMs < 1) {
    throw new Error('Child deadlines must be positive integer milliseconds');
  }
  const log = fs.openSync(logPath, 'wx', 0o600);
  const child = spawn(command, args, { cwd, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let failure = null;
  let stopping = null;
  let deadline;
  let stdoutHead = '';
  let stderrHead = '';
  const tails = { stdout: '', stderr: '' };
  const writeLog = bytes => fs.writeFileSync(log, bytes);
  const groupAlive = () => {
    if (!child.pid) return false;
    try { process.kill(-child.pid, 0); return true; }
    catch (error) { if (error.code === 'ESRCH') return false; throw error; }
  };
  const signalGroup = signal => {
    if (!child.pid) return;
    try { process.kill(-child.pid, signal); }
    catch (error) { if (error.code !== 'ESRCH') throw error; }
  };
  const stop = reason => {
    if (stopping) return stopping;
    failure = reason;
    const message = `\nCook child stopped: ${reason}. Full log: ${logPath}\n`;
    stopping = (async () => {
      signalGroup('SIGTERM');
      // Do not cancel escalation when the shell exits: an ignored TERM in a
      // remaining Godot/tee descendant must not outlive its owner.
      if (groupAlive()) await delay(terminateGraceMs);
      if (groupAlive()) signalGroup('SIGKILL');
    })();
    // Cleanup takes precedence if the log disk or output consumer itself fails.
    try { stderr.write(message); } catch { /* The failure remains in the result. */ }
    try { writeLog(message); } catch { /* Do not orphan children on a full disk. */ }
    return stopping;
  };
  const receive = (stream, bytes) => {
    try {
      writeLog(bytes);
      (stream === 'stdout' ? stdout : stderr).write(bytes);
    } catch (error) {
      void stop(`output handling failed: ${error.message}`);
      return;
    }
    const text = bytes.toString('utf8');
    if (stream === 'stdout') stdoutHead = (stdoutHead + text).slice(0, 8192);
    else stderrHead = (stderrHead + text).slice(0, 8192);
    const joined = tails[stream] + text;
    tails[stream] = joined.slice(-128);
    if (fatalOutput.test(joined)) void stop('Godot reported a fatal error');
  };
  child.stdout.on('data', bytes => receive('stdout', bytes));
  child.stderr.on('data', bytes => receive('stderr', bytes));
  const interrupt = () => { void stop('interrupted'); };
  const outputError = error => { void stop(`output stream failed: ${error.message}`); };
  stdout.on?.('error', outputError);
  stderr.on?.('error', outputError);
  process.on('SIGINT', interrupt);
  process.on('SIGTERM', interrupt);
  try {
    deadline = setTimeout(() => { void stop(`deadline exceeded (${timeoutMs} ms)`); }, timeoutMs);
    const result = await new Promise(resolve => {
      child.once('error', error => { void stop(`could not start child: ${error.message}`); });
      child.once('close', (code, signal) => resolve({ code, signal }));
    });
    clearTimeout(deadline);
    if (!failure && result.code !== 0) void stop(`child exited ${result.code ?? result.signal}`);
    if (!failure && groupAlive()) void stop('child exited with live descendants');
    if (stopping) await stopping;
    return { ...result, failure, stdout: stdoutHead, stderr: stderrHead, logPath };
  } finally {
    clearTimeout(deadline);
    process.removeListener('SIGINT', interrupt);
    process.removeListener('SIGTERM', interrupt);
    stdout.removeListener?.('error', outputError);
    stderr.removeListener?.('error', outputError);
    fs.closeSync(log);
  }
}
