#!/usr/bin/env bash
# Offline, read-only verification of the approved nine CC0 material source maps.
# Requires Node.js 18+; no npm packages, image decoder, Godot import or network.
set -euo pipefail
material_repository=$(cd "$(dirname "$0")/.." && pwd)
node - "$material_repository" "$@" <<'NODE'
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const args = process.argv.slice(3);
assert(args.length === 0 || (args.length === 1 && args[0] === '--self-test'), 'Usage: bash tools/verify-materials.sh [--self-test]');
const assetRoot = path.join(process.argv[2], 'client/assets/materials');
assert(!fs.lstatSync(assetRoot).isSymbolicLink(), 'Material directory must not be a symlink');
const manifest = JSON.parse(fs.readFileSync(path.join(assetRoot, 'manifest.json'), 'utf8'));
assert.equal(manifest.schema_version, 1, 'Unknown manifest version');
assert.equal(manifest.provider, 'Poly Haven');
assert.equal(manifest.license, 'CC0-1.0');
assert.equal(manifest.license_url, 'https://creativecommons.org/publicdomain/zero/1.0/');
assert.equal(manifest.provider_license_url, 'https://polyhaven.com/license');
assert.equal(manifest.source_budget_bytes, 15000000);
assert.deepEqual(manifest.materials.map(item => item.id).sort(), ['aerial_grass_rock', 'coast_sand_03', 'rock_01']);
const expected = new Set(['manifest.json']);
let total = 0;
let files = 0;
let negativeChecks = 0;

function dimensions(data, format) {
  if (format === 'png') {
    assert(data.length >= 33 && data.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')), 'Invalid PNG signature');
    assert.equal(data.readUInt32BE(8), 13, 'Invalid PNG IHDR');
    assert.equal(data.toString('ascii', 12, 16), 'IHDR');
    return [data.readUInt32BE(16), data.readUInt32BE(20)];
  }
  assert(format === 'jpg' && data.length >= 4 && data.readUInt16BE(0) === 0xffd8, 'Invalid JPEG signature');
  const startOfFrame = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  let offset = 2;
  while (offset < data.length) {
    assert.equal(data[offset], 0xff, 'Invalid JPEG marker');
    while (data[offset] === 0xff) offset++;
    const marker = data[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    assert(offset + 2 <= data.length, 'Truncated JPEG marker');
    const length = data.readUInt16BE(offset);
    assert(length >= 2 && offset + length <= data.length, 'Invalid JPEG marker size');
    if (startOfFrame.has(marker)) {
      assert(length >= 8, 'Truncated JPEG frame');
      return [data.readUInt16BE(offset + 5), data.readUInt16BE(offset + 3)];
    }
    offset += length;
  }
  throw new Error('JPEG has no supported dimensions');
}

function verifyPayload(entry, data) {
  assert.equal(data.length, entry.size_bytes, 'Byte-size mismatch: ' + entry.path);
  assert.equal(crypto.createHash('sha256').update(data).digest('hex'), entry.sha256, 'SHA256 mismatch: ' + entry.path);
  assert.equal(crypto.createHash('md5').update(data).digest('hex'), entry.provider_md5, 'Provider MD5 mismatch: ' + entry.path);
  assert.deepEqual(dimensions(data, entry.format), [1024, 1024], 'Source is not a 1024px map: ' + entry.path);
}

for (const material of manifest.materials) {
  assert.equal(material.source_page, 'https://polyhaven.com/a/' + material.id);
  assert.equal(material.info_metadata_url, 'https://api.polyhaven.com/info/' + material.id);
  assert.equal(material.files_metadata_url, 'https://api.polyhaven.com/files/' + material.id);
  assert.match(material.provider_files_hash, /^[0-9a-f]{40}$/, 'Missing upstream revision marker');
  assert.deepEqual(material.authors, [{name: 'Rob Tuytel', contribution: 'All'}]);
  assert.deepEqual(material.files.map(item => item.role).sort(), ['albedo', 'normal_opengl', 'roughness']);
  for (const entry of material.files) {
    const suffix = {albedo: 'diff_1k.jpg', normal_opengl: 'nor_gl_1k.png', roughness: 'rough_1k.jpg'}[entry.role];
    const relative = material.id + '/' + material.id + '_' + suffix;
    assert.equal(entry.path, relative, 'Unexpected material path');
    assert.equal(entry.format, entry.role === 'normal_opengl' ? 'png' : 'jpg');
    assert.equal(entry.color_space, entry.role === 'albedo' ? 'srgb' : 'linear');
    if (entry.role === 'normal_opengl') assert.equal(entry.normal_convention, 'OpenGL +X +Y +Z');
    assert.equal(entry.width, 1024);
    assert.equal(entry.height, 1024);
    assert(Number.isSafeInteger(entry.size_bytes) && entry.size_bytes > 0);
    assert.match(entry.sha256, /^[0-9a-f]{64}$/);
    assert.match(entry.provider_md5, /^[0-9a-f]{32}$/);
    assert.equal(entry.url, 'https://dl.polyhaven.org/file/ph-assets/Textures/' + entry.format + '/1k/' + relative);
    assert(!expected.has(relative), 'Duplicate material file');
    expected.add(relative);
    // A future Godot import may create these adjacent text sidecars; they are
    // not additional material source maps and are not part of this byte budget.
    expected.add(relative + '.import');
    const filename = path.join(assetRoot, relative);
    assert(!fs.lstatSync(path.dirname(filename)).isSymbolicLink(), 'Symlink material directory');
    assert(fs.lstatSync(filename).isFile() && !fs.lstatSync(filename).isSymbolicLink(), 'Material source must be a regular file');
    const data = fs.readFileSync(filename);
    verifyPayload(entry, data);
    total += data.length;
    files++;
    if (args[0] === '--self-test') {
      const corrupted = Buffer.from(data);
      corrupted[corrupted.length - 1] ^= 1;
      assert.throws(() => verifyPayload(entry, corrupted), /SHA256 mismatch/);
      assert.throws(() => verifyPayload(entry, data.subarray(0, data.length - 1)), /Byte-size mismatch/);
      assert.throws(() => verifyPayload({...entry, provider_md5: '0'.repeat(32)}, data), /Provider MD5 mismatch/);
      assert.throws(() => dimensions(Buffer.alloc(32), entry.format), /Invalid (PNG|JPEG) signature/);
      negativeChecks += 4;
    }
  }
}

function checkInventory(directory, prefix = '') {
  for (const name of fs.readdirSync(directory).sort()) {
    const filename = path.join(directory, name);
    const relative = prefix + name;
    const stat = fs.lstatSync(filename);
    assert(!stat.isSymbolicLink(), 'Unexpected symlink: ' + relative);
    if (stat.isDirectory()) checkInventory(filename, relative + '/');
    else assert(expected.has(relative), 'Unlisted material file: ' + relative);
  }
}
checkInventory(assetRoot);
assert.equal(files, 9);
assert.equal(total, manifest.source_total_bytes);
assert(total <= 15000000, 'Approved material source budget exceeded');
console.log('MATERIALS_OK: ' + files + ' original 1024x1024 maps, ' + total + ' bytes; SHA256/provider MD5/size/dimensions/provenance/inventory verified' + (negativeChecks ? '; ' + negativeChecks + ' in-memory corruption checks passed' : ''));
NODE
