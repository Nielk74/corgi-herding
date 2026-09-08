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

# Pre-Cloud Oasis compatibility reference

`pre-cloud-oasis.jsonl.gz.b64` contains 700 complete, unrounded world snapshots
from `applyOasisTraceTick`. Both herders and both dogs take north/south bypasses,
reverse destinations, use Come/Go/Stay, and sit while the same sheep simulate.
The reference was captured from pre-Cloud commit
`8485e80097d289709f0a585383c6950d8cdbd80b`, with independently compiled sources:

- `world.go` Git blob `0e5ec238dd0e263e0898c6fb14c85ca8ceca845d`
- `forage.go` Git blob `ccb9fe25591a3c8409f5b11a9feb2764594f6bca`
- `rock.go` Git blob `10fd7270bc66f89d13ed659060a405721db07cd2`

Those frozen files were verified against the commit's Git blobs before capture.
With Go 1.26.7, the frozen simulator and Cloud implementation produced
byte-identical JSONL independently on linux/amd64 and darwin/arm64. The Linux
test binary was cross-compiled natively, then executed under the existing Docker
amd64 emulation with GOMAXPROCS=1, GOGC=off and GODEBUG=asyncpreemptoff=1.

Uncompressed linux/amd64 reference SHA-256, pinned by the test:

`de177e2df5f1201225169cfa89244a3e196f83fd837b04e776e546627f7fa2fe`

The equivalent darwin/arm64 trace SHA-256 was
`79ff9803b7c9ee99bc106a3efa9fc6a34f1f9f8e85635bde68904c35f9480083`.
Across architectures all discrete fields, object/array structure, layout and
route anchors matched exactly. Maximum actor-coordinate divergence was
`4.618527782440651e-13`, in sheep s2 velocity.y at tick 237. First divergence was
sheep s7 position.y at tick 6 (`0.23114996923212575` vs `0.23114996923212572`).
No rounding or quantization is used. The same narrowly scoped 1e-12 coordinate
comparator and negative controls as Orchard apply; route anchor coordinates
remain exact, with additional negative controls rejecting tiny anchor changes,
removed queues or an unexpected ridge field. Tests never regenerate references.
