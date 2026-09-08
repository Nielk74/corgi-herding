# Build 7 Orchard compatibility reference

`build7-orchard.jsonl.gz.b64` contains all 700 unrounded world snapshots from
the `TestOrchardBuild7PortableTrace` input sequence. It is gzip-compressed JSONL
encoded as base64; tests only read it and never regenerate it.

Source: released build 7, commit `522b818ec5ee343a0c5355819c7f0634f70d9ef6`.
The diagnostic simulator copied these source files without modifications:

- `world.go` Git blob `34f7d24c36b3a3fda3f08c0e05a9c9944aff061b`
- `forage.go` Git blob `ccb9fe25591a3c8409f5b11a9feb2764594f6bca`

Capture target: Go 1.26.7, linux/amd64, GOAMD64=v1, CGO_ENABLED=0. The Go test
binary was cross-compiled by that exact toolchain and executed under the existing
Docker amd64 emulation with GOMAXPROCS=1 and GODEBUG=asyncpreemptoff=1. The same
scenario built from Oasis commit `3113214` produced byte-identical unrounded
JSONL on this target. Build 7 and Oasis also produced byte-identical unrounded
JSONL on darwin/arm64, Go 1.27.1.

Uncompressed reference SHA-256, checked by the test:

`7e49ebeb9c95cb9f42d19db90734de0c2fc510b9081b173a5a76b6430de3dba4`

The equivalent arm64 unrounded trace SHA-256 was
`fa0e70eeef7a73bc2da99dccafcf78a88e7b3c3ed0a7797fc20076dfe9489fb1`.
Across architectures every discrete field and object/array structure matched.
Maximum continuous difference was `3.552713678800501e-14`, in sheep s10's
velocity.x at tick 208. First divergence was sheep s8 position.y at tick 9:
`0.24097315102894665` versus `0.24097315102894667`.

The old 1e-6-rounded JSON hash failed because at tick 69 player A's X was
`-3.4296095071104685e-18` on arm64 versus `0` on amd64. Rounding preserved the
negative zero, so JSON encoded `-0` versus `0`. Both old and new implementations
produced rounded hash `5f1dbe8e7a57443d0882a82ee31fe8739398ae1242397ff18a7516dd051a422c`
on arm64 and `f4d44f579f3ddf6c58192cc41f42271ddc2e8f5d05ec794a7977db46fb865648`
on amd64. No gameplay difference was introduced by Oasis.

The replacement checks every field at every tick. Only actor position, velocity,
and derived target coordinates permit absolute error <=1e-12; states, identities,
array order, ticks, sequences, geometry and feeding progress remain exact. This
continuous bound is stricter than the previous 1e-6 quantization. Negative
controls reject altered behavior, additional/missing fields and out-of-bound
coordinate changes; the three pre-Orchard hash regressions remain unchanged.
