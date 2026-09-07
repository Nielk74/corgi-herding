# Corgi Herding

Build the smallest pleasant cooperative experience described in docs/design.md.
Preserve the no-combat, no-timer, soft-failure design. Both players control both dogs.
Android is portrait-first. Keep controls hidden until an animal or interaction is
tapped; no persistent command bars. Compose broad Alpine and cactus landscapes
behind readable playable ground, with natural boundaries rather than a board rim.

The Go server is authoritative at 20 Hz. The Godot client owns presentation,
interpolation and immediate movement feedback. Keep protocol/README.md in sync.
Never put session credentials, Android signing secrets, local paths or private
deployment credentials in public artifacts. Keep signing identity stable across releases.

Before shipping: Go tests with race detector and vet, Godot headless import and
scene smoke, signed APK verification, and verified server release checksums.
Release artifacts and a healthy running server are the definition of a shipped build.
The updater must only install completed releases and restore both the old binary
and its compatible checkpoint on failure.
