# Natural material source kit

These nine original texture files are an approved, reusable source kit. They are
not yet a claim of integrated or profiled Android rendering. No Godot import,
renderer setting, existing terrain, or lighting bake was changed when adding them.

| Material | Intended use | Source-map bytes |
| --- | --- | ---: |
| [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) | Mixed grass, moss and stone ground | 7,395,390 |
| [Rock 01](https://polyhaven.com/a/rock_01) | Weathered grey rock faces | 2,985,274 |
| [Coast Sand 03](https://polyhaven.com/a/coast_sand_03) | Sand, pebbles and shore gravel | 4,444,637 |
| Total | Nine 1024 × 1024 maps | 14,825,301 |

All three materials are by **Rob Tuytel**, distributed by **Poly Haven**, and
licensed **CC0-1.0**. The license permits modification and redistribution,
including commercial products, without attribution. These credits are retained
for provenance; they do not imply endorsement. See the [provider's asset license](https://polyhaven.com/license)
and [CC0 legal text](https://creativecommons.org/publicdomain/zero/1.0/legalcode).
This kit does not include Poly Haven logos, preview renders or other website media.

## Exact sources and verification

[The manifest](../client/assets/materials/manifest.json) records each complete
download URL, author, upstream `files_hash` revision marker, metadata URL,
retrieval time, byte size, provider MD5 and independently computed SHA256.
`files_hash` is an opaque upstream marker, not a SHA256 checksum. Provider MD5
helps check the downloaded source against metadata; SHA256 pins the exact bytes
reviewed into this repository. Upstream metadata changes do not automatically
update this kit or cause network access during builds.

Each material contains its provider's 1K JPG diffuse/albedo, lossless PNG
OpenGL normal, and JPG roughness map. Files were not resized or recompressed.
All nine actual dimensions were checked as 1024 × 1024. The exact source payload
is 14.83 MB (14.14 MiB), below the 15,000,000-byte source budget; this is **not**
the imported GPU-memory or final APK-size measurement.

From the repository root, run the script with Node.js 18 or newer:

```sh
bash tools/verify-materials.sh
bash tools/verify-materials.sh --self-test
```

The verifier is offline and read-only. It checks the nine-file inventory,
provenance, byte budget, both hashes, format headers and dimensions. Its optional
self-test rejects altered/truncated data and wrong hashes using memory buffers;
it does not damage files. Adjacent Godot `.import` sidecars are allowed but do not
count as additional source maps. No dependency installation or image import occurs.

## Intended renderer integration

- Treat albedo as sRGB color; normals and roughness as linear data. The normal
  maps use OpenGL +X/+Y/+Z convention. Do not invert their green channel.
- Start with `StandardMaterial3D` using UV1 world-triplanar projection, metallic
  zero and restrained normal strength. Reserve real UV2 coordinates for optional
  lightmaps; leave UV2 triplanar disabled. Godot's normal-map basis must be retained
  if a custom blending shader later replaces the built-in material.
- Import at 1024 with mipmaps and VRAM compression, then inspect the actual
  Android export. Compatibility uses ETC2 on mobile; its high-quality ASTC option
  is unavailable. Source-file compression alone does not establish GPU memory.
- Any baked lighting requires offline-generated, saved static meshes with
  nonoverlapping UV2. Bake in the editor using RenderingDevice-capable hardware,
  then ship the mesh/lightmap resources. An exported Compatibility game can
  render pre-baked lightmaps but cannot bake newly generated worlds at runtime.

These integration choices follow the pinned Godot 4.6 documentation for
[standard materials](https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html),
[texture imports](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_images.html),
[renderer support](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html)
and [LightmapGI](https://docs.godotengine.org/en/4.6/classes/class_lightmapgi.html).
Visual acceptance, normal orientation, repetition, asset memory and frame cost
must still be checked on the actual Android build before calling this kit integrated.
