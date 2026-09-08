#!/usr/bin/env node
// Reproducible-input offline cooking. Only regeneratable named cache outputs are
// replaced. Source recipes/assets, saved herds and user preferences are read-only.
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runBoundedProcess } from './bounded-process.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const force = args.includes('--force');
const selfTest = args.includes('--self-test');
const godot = args.find(arg => !arg.startsWith('--'));
if (!checkOnly && !selfTest && !godot) throw new Error('Usage: node tools/build-landscapes.mjs /absolute/godot [--force], or --check');
const hash = data => createHash('sha256').update(data).digest('hex');
const verifies = (receipt, data, expected) => receipt &&
  receipt.format === 1 && receipt.id === expected.id && receipt.godot === '4.6.3' &&
  receipt.signature === expected.signature && receipt.sha256 === hash(data) && receipt.bytes === data.length &&
  JSON.stringify(receipt.inputs) === JSON.stringify(expected.inputs);
if (selfTest) {
  const data = Buffer.from('a prepared scene');
  const expected = { id: 'test', signature: 'input signature', inputs: { 'recipe.json': 'hash' } };
  const good = { ...expected, format: 1, godot: '4.6.3', sha256: hash(data), bytes: data.length };
  if (!verifies(good, data, expected)) throw new Error('Cache positive control failed');
  let rejected = 0;
  for (const field of Object.keys(good)) {
    for (const bad of [null, false, 'incorrect', {}, []]) {
      if (verifies({ ...good, [field]: bad }, data, expected)) throw new Error(`Cache accepted damaged ${field}`);
      rejected++;
    }
  }
  if (verifies(good, Buffer.from('a damaged scene!'), expected)) throw new Error('Cache accepted damaged bytes');
  console.log(`Landscape cache checks: valid cache accepted, ${rejected + 1} damaged cases rejected; no files changed`);
  process.exit(0);
}
if (!checkOnly) {
  fs.mkdirSync(path.join(root, '.tools'), { recursive: true });
  const probe = fs.mkdtempSync(path.join(root, '.tools/landscape-version-'));
  const version = await runBoundedProcess(path.resolve(godot), ['--version'], {
    cwd: root, timeoutMs: 10_000, logPath: path.join(probe, 'output.log'),
  });
  if (version.failure || version.code !== 0 || !version.stdout.startsWith('4.6.3.')) {
    throw new Error(`Prepared scenes require the pinned Godot 4.6.3 compiler. Log: ${version.logPath}`);
  }
}
const read = name => fs.readFileSync(path.join(root, name));
const sources = [
  'client/scripts/landscape_recipe.gd', 'client/scripts/strict_region_validator.gd',
  'client/scripts/landscape_chunk_builder.gd', 'client/scripts/landscape_backdrop.gd',
  'client/scripts/landscape_props.gd', 'client/scripts/landscape_scene_builder.gd',
  'client/scripts/landscape_scree.gd', 'client/scripts/region_navigation.gd',
  'client/scripts/dry_wash_landforms.gd',
  'client/shaders/meadow_grass.gdshader', 'client/shaders/landscape_surface.gdshader',
  'client/tools/build_landscape.gd', 'tools/build-landscapes.mjs',
  'tools/bounded-process.mjs', 'tools/run-godot-check.sh',
  'client/assets/materials/manifest.json',
];
for (const id of ['aerial_grass_rock', 'rock_01', 'coast_sand_03']) {
  for (const suffix of ['diff_1k.jpg', 'nor_gl_1k.png', 'rough_1k.jpg']) {
    const name = `client/assets/materials/${id}/${id}_${suffix}`;
    sources.push(name, name + '.import');
  }
}
const outputDirectory = path.join(root, 'client/generated');
if (!checkOnly) fs.mkdirSync(outputDirectory, { recursive: true });
for (const id of ['long_valley', 'dry_wash']) {
  const recipeName = `client/worlds/${id}.recipe.json`;
  const recipe = JSON.parse(read(recipeName));
  const files = [...sources, recipeName];
  if (recipe.region_file) files.push('client/' + recipe.region_file.replace(/^res:\/\//, ''));
  files.sort();
  const inputs = Object.fromEntries(files.map(name => [name, hash(read(name))]));
  const signature = hash(JSON.stringify({ godot: '4.6.3', inputs }));
  const scene = path.join(outputDirectory, id + '.scn');
  const receipt = path.join(outputDirectory, id + '.json');
  let current = false;
  try {
    const previous = JSON.parse(fs.readFileSync(receipt));
    const data = fs.readFileSync(scene);
    current = verifies(previous, data, { id, signature, inputs });
  } catch { /* A missing or damaged cache is rebuilt, never trusted. */ }
  if (checkOnly) {
    if (!current) throw new Error(`Missing/stale/damaged prepared landscape: ${id}`);
    console.log(`Verified prepared landscape: ${id}`);
    continue;
  }
  if (current && !force) {
    console.log(`Unchanged landscape, reused: ${id}`);
    continue;
  }
  fs.mkdirSync(path.join(root, '.tools'), { recursive: true });
  const scratch = fs.mkdtempSync(path.join(root, '.tools/landscape-cook-'));
  const temporaryScene = path.join(scratch, id + '.scn');
  const result = await runBoundedProcess('bash', [
    'tools/run-godot-check.sh', path.resolve(godot), '--headless', '--path', 'client',
    '--script', 'res://tools/build_landscape.gd', '--',
    '--recipe=res://worlds/' + id + '.recipe.json', '--out=' + temporaryScene, '--full',
  ], { cwd: root, logPath: path.join(scratch, 'output.log') });
  if (result.failure || result.code !== 0) throw new Error(`Landscape cook failed: ${id}. Log: ${result.logPath}`);
  const data = fs.readFileSync(temporaryScene);
  if (data.length < 1024) throw new Error(`Implausibly small landscape scene: ${id}`);
  const manifest = { format: 1, id, godot: '4.6.3', signature, sha256: hash(data), bytes: data.length, inputs };
  // Both names are fixed compiler-owned outputs under the ignored generated/
  // directory. The new scene exists completely before replacing the old cache.
  fs.copyFileSync(temporaryScene, scene + '.next');
  fs.renameSync(scene + '.next', scene);
  fs.writeFileSync(receipt + '.next', JSON.stringify(manifest, null, 2) + '\n');
  fs.renameSync(receipt + '.next', receipt);
  console.log(`Prepared ${id}: ${data.length} bytes; ${manifest.sha256}`);
}
