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

# Pre-Juniper Cloud compatibility reference

`pre-juniper-cloud.jsonl.gz.b64` holds all 700 unrounded snapshots from
`applyCloudTraceTick`, captured before the Juniper implementation from commit
`9bf12b0`. It exercises both herders/dogs, outward/return destinations, moving
Come callers, Go/Stay/Sit, and a disconnected herder whose retained route pauses.
The exact pre-change source blobs were:

- `world.go`: `cf860db0572a08bc53f33f456cd73dceb1ca2db5`
- `cloud.go`: `bce04f383e51d5d9119f1e824b3e0c55881344e8`
- `rock.go`: `70f1100b0a03c2611b3ef9af00cb8febf1b65788`
- `forage.go`: `ccb9fe25591a3c8409f5b11a9feb2764594f6bca`

With Go 1.26.7, the unchanged source was compiled/captured before editing the
simulation. The Juniper implementation subsequently produced byte-identical
complete JSONL independently on darwin/arm64 and linux/amd64. Linux test binaries
were cross-compiled with CGO disabled and executed in existing Docker amd64
emulation with GOMAXPROCS=1, GOGC=off, GODEBUG=asyncpreemptoff=1.

Uncompressed linux/amd64 reference SHA-256 (pinned by the test):

`b0f11dbe927632631266a844ba27de4bcedef88104fd49e4a37c35301cb82fb4`

The darwin/arm64 equivalent was
`ce769897b7c6738d8f0c6f2708b3f4eac37ebb2d3d7d2e10a1cab95e985e4bb9`.
Maximum cross-architecture coordinate difference was `2.4868995751603507e-13`
at tick 448, sheep s4 velocity.x. All discrete fields and structure matched.
The existing comparator permits only actor coordinates an absolute error of
1e-12; route anchors, geometry (including the old rest disk), state, sequence,
ticks, and field presence remain exact. No rounding or signed-zero hash workaround
is used. Twelve additional negative controls demonstrate rejection of altered
routes/geometry/behavior and coordinates outside the bound. Tests only read this
compressed reference; capture helpers are not part of the source or test suite.

# Released Juniper compatibility reference before Bellflower

`pre-bellflower-juniper.jsonl.gz.b64` contains all 700 unrounded snapshots from
`applyJuniperTraceTick`, independently captured from released build 13 commit
`c21f75f8c73923df9832035aea65ce5adf999239` before changing server source. The
capture exercises both herders/dogs, both directions, changing Come callers,
Go/Stay/Sit and a disconnected herder with a retained route. Source blobs were:

- `world.go`: `1c8a4831f23dbae777957e08c0b4eb5d7b8f27a8`
- `shore.go`: `9226107291ef5fdb8b624178866f33cf4f508b8c`
- `cloud.go`: `c81a5d165578538228db24c169d1cc8c909358da`
- `rock.go`: `41e0725190909ddc702178b13ecfd82a5c799f26`
- `forage.go`: `ccb9fe25591a3c8409f5b11a9feb2764594f6bca`

Go 1.26.7 pre-change native and Linux test binaries were compiled before editing.
Bellflower produced byte-identical complete JSONL to those frozen binaries on
darwin/arm64, linux/arm64 and linux/amd64 separately. Linux builds used CGO=0;
amd64 ran in existing Docker emulation, with GOMAXPROCS=1, GOGC=off and
GODEBUG=asyncpreemptoff=1. No fixtures are regenerated by normal tests.

Uncompressed linux/amd64 SHA-256 (pinned by the test):
`980eeb37864063cdc521985a974b9b8507596b0d16eb37744870dccc429e863d`.
Both arm64 equivalents: `da946b3dd1ef2a7dca4fc6628d673f667471c3087c48841ed1c5b92d79e6edcb`.
Across architectures, all structure/discrete fields matched. Maximum continuous
coordinate difference was `7.105427357601002e-14`, sheep s5 velocity.x at tick 260.
The existing 1e-12 actor-only comparison remains unchanged: geometry, route
anchors, states, sequences, ticks and field presence stay exact. Twelve negative
controls reject modified routes, tiny geometry changes, missing/new fields,
changed behavior and positions beyond that bound. The reference is about 1.9 MB
uncompressed and 465 KB as base64/gzip; no rounded hash or signed-zero workaround
is used.

# Pre-Dry Wash Bellflower and Alpine Valley references

`pre-drywash-bellflower.jsonl.gz.b64` and
`pre-drywash-alpine_valley.jsonl.gz.b64` contain 700 complete unrounded snapshots
each from `applyDryWashLegacyTraceTick`. A separate detached checkout of
pre-v8 commit `7f68be2` was compiled independently with Go 1.26.7 darwin/arm64.
Only an ignored test overlay supplied the input/capture helper; no control
simulation file was changed. Relevant frozen Git blobs were:

- `world.go`: `628f4b62374f8f6accb6e02324fccbbac5922317`
- `region.go`: `e047906bd96e81765779679c1a7b106394d43f42`
- `commons.go`: `ca9a7607bc743336fd165874141330eda0d7d602`

The pre-change binary and v8 implementation produced byte-identical complete
JSONL on this target, including the per-landscape immutable-cache change.
Bellflower SHA-256 (1,901,913 uncompressed bytes):
`a4daab02c9c6d454d00d1b0f4b04a24bcf85d2b03acd9cf437962da6b3d22a86`.
Alpine Valley SHA-256 (3,001,157 uncompressed bytes):
`82427a0a94ae1417864630b80bf0fe3054096bcadd0bc597ed665cfda0825b92`.

Both humans and both shared dogs move, reverse, change commands, stop and retain
an accepted route through a disconnect while the same sheep continue simulating.
Tests only read the compressed references. All fields, routes, geometry, ticks,
sequences, IDs and object structure remain exact; only actor coordinates use the
existing 1e-12 cross-platform bound. Twenty-six negative controls reject changed
geometry, state, routes, identity, sequence and out-of-bound coordinates. Existing
v1-v5 references and their comparison semantics are unchanged; the larger v7
snapshot uses a separately bounded 4 MiB reference decoder limit.

Independent Go 1.26.7 Linux/arm64 and Linux/amd64 control binaries were also
built from that detached commit. On each target, their complete JSONL hashes
exactly matched the v8 implementation. Linux/arm64 matched the two native hashes
above. Linux/amd64 Bellflower was
`5d4a5847b98f337baa07b0e12fa5473f6711d222ed628df28f498ad810a150f1`
and Alpine Valley was
`7a2d2248ea4aa474ec66f34a92f1cb53c023978dc705b6de6c9f518c394eab2a`.
Both passed the existing actor-only 1e-12 comparison against the arm64 fixtures;
no new expected hash was substituted to accept a failed regression. Static Linux
test binaries used the existing Docker runtime with no network; amd64 emulation
used GOMAXPROCS=1, GOGC=off and GODEBUG=asyncpreemptoff=1 as in earlier audits.
Production code and runtime GC settings were not changed.
