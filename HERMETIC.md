# Hermetic build

This branch builds from a **fresh clone on any machine**. Nothing is borrowed
from a developer's home directory — no uncommitted submodule work, no locally
built `GhosttyKit.xcframework`.

Tracked as [fadi-orchestrator#42](https://github.com/adamghaleb/fadi-orchestrator/issues/42).

## Quick start

```bash
git clone https://github.com/adamghaleb/cmux.git
cd cmux
git checkout gate0/hermetic
git submodule update --init --recursive
./scripts/setup.sh
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux \
  -configuration Debug -destination 'platform=macOS' build
```

`setup.sh` downloads the pinned, checksum-verified `GhosttyKit.xcframework`.
No `zig` toolchain is needed on the happy path.

## The pins

| Submodule        | Repo                     | Branch | Commit     |
| ---------------- | ------------------------ | ------ | ---------- |
| `ghostty`        | `adamghaleb/ghostty`     | `fadi` | `fb45122e7951c4585d76ab9b2084479b6cc85edc` |
| `vendor/bonsplit`| `adamghaleb/bonsplit`    | `fadi` | `fb132d34311f50eb648e0f02ff98dbc00ac95001` |
| `homebrew-cmux`  | `manaflow-ai/homebrew-cmux` | —   | `dcfaa081e5b3e0ad62c5c1a5a4d58f4562f6be71` |

`ghostty` and `vendor/bonsplit` moved from `manaflow-ai` to **forks under
`adamghaleb`** because the Fadicode app layer links against API that existed
only as uncommitted working-tree edits on one machine:

- **bonsplit** — `tabColor: String?` on `Tab` / `TabItem` / `BonsplitController`,
  used to tint each tab's accent indicator per workspace.
- **ghostty** — `ghostty_surface_set_accent_color` /
  `ghostty_surface_clear_accent_color`, plus the OSC 7777 (task completion) and
  OSC 7778 (working state) apprt actions.

These are forks, not vendored copies. Upstream (`manaflow-ai`, and above it
`ghostty-org`) remains mergeable; the `fadi` branches sit directly on top of the
previously pinned upstream commits (`89a4fd1` for bonsplit, `7dd589824` for
ghostty), so rebasing forward later is a normal merge, not an archaeology
project.

We stay on the March cmux base. There is no re-pin forward in this change.

## Acquiring GhosttyKit.xcframework

The xcframework is **not** committed to this repo (541 MB expanded). It is
published as a GitHub release asset on the ghostty fork, tagged with the exact
ghostty commit it was built from:

```
https://github.com/adamghaleb/ghostty/releases/download/xcframework-<ghostty-sha>/GhosttyKit.xcframework.tar.gz
```

`scripts/download-xcframework.sh` derives `<ghostty-sha>` from the submodule
pointer, downloads with retries (exponential backoff + jitter, capped at 120 s),
and **verifies SHA-256 before extracting**. A mismatch deletes the download and
exits non-zero — it never extracts an artifact that does not match the pin.

Expected checksums live in [`ghostty-xcframework.sha256`](./ghostty-xcframework.sha256),
keyed by ghostty SHA:

```
<sha256>  <ghostty-submodule-sha>
```

Current pin:

```
c0bfe870cebf9286cef6d3efbedfda18b0b3c3e9d928ccdc7fcf727c75f563cf  fb45122e7951c4585d76ab9b2084479b6cc85edc
```

If the checksum file has no entry for the current ghostty SHA, the script fails
loudly rather than downloading something unverified.

### Provenance of the current artifact

This artifact was **not** rebuilt for Gate 0 — it is the existing prebuilt,
promoted after proving it corresponds to the committed source:

1. Its bundled `Headers/ghostty.h` is **byte-identical** to `include/ghostty.h`
   at `adamghaleb/ghostty@fb45122e7`.
2. Its macOS slice exports the accent-color API:

   ```
   $ nm -gU macos-arm64_x86_64/libghostty.a | grep accent
   T _ghostty_surface_set_accent_color
   T _ghostty_surface_clear_accent_color
   ```

Slices: `macos-arm64_x86_64`, `ios-arm64`, `ios-arm64-simulator`.

### Building it yourself instead

```bash
CMUX_FORCE_GHOSTTY_BUILD=1 ./scripts/setup.sh
```

This takes the `zig build -Demit-xcframework=true -Doptimize=ReleaseFast` path.
It requires `zig` on `PATH`. `setup.sh` also falls back to this automatically if
the download fails, so a machine with zig can always bootstrap unaided.

Note: the ghostty fork's `fadi` branch deliberately retains the full `src/build/`
Zig build system. Adam's working tree had those 296 files deleted; committing
those deletions would have made the fork unable to build from source, so they
were left out. See "What was deliberately excluded" below.

## Metal toolchain requirement

The app target compiles **61 `.metal` shaders** under `Sources/`. They stay in
the app target (they are not moved into the xcframework), so the Metal
toolchain must be present:

```bash
xcrun -f metal   # must resolve
```

It ships with Xcode; on a machine with only Command Line Tools installed you
will need the full Xcode. Shaders are **not** excluded from the build — a shader
that fails to compile fails the build, on purpose.

## Updating a submodule pin

1. Commit and push the submodule change to its fork branch first:

   ```bash
   cd ghostty            # or vendor/bonsplit
   git checkout fadi
   git commit -am "..."
   git push origin fadi
   ```

   Never leave the submodule on a detached HEAD — the commit will be orphaned
   and the pin will be unfetchable from a fresh clone. Verify with:

   ```bash
   git merge-base --is-ancestor HEAD origin/fadi
   ```

2. For **ghostty only**, publish a matching xcframework and record its checksum:

   ```bash
   cd ghostty && zig build -Demit-xcframework=true -Doptimize=ReleaseFast
   cd macos && COPYFILE_DISABLE=1 tar --exclude='.DS_Store' \
     -czf /tmp/GhosttyKit.xcframework.tar.gz GhosttyKit.xcframework
   shasum -a 256 /tmp/GhosttyKit.xcframework.tar.gz

   SHA=$(git -C ghostty rev-parse HEAD)
   gh release create "xcframework-$SHA" -R adamghaleb/ghostty --target "$SHA" \
     /tmp/GhosttyKit.xcframework.tar.gz
   ```

   Then append `<sha256>  <ghostty-sha>` to `ghostty-xcframework.sha256`.
   Keep old rows: they let you check out an older commit and still build.

3. Update the pointer in this repo:

   ```bash
   git add ghostty ghostty-xcframework.sha256
   git commit -m "Bump ghostty pin to $SHA"
   ```

4. Re-run the acceptance check below before merging.

## Acceptance check

The invariant this document exists to protect: **a fresh clone builds with zero
files read from any developer's home directory.**

```bash
xcodebuild ... build 2>&1 | tee /tmp/build.log
grep -c '/Users/[^/]*/Documents' /tmp/build.log   # must be 0
```

Build entirely inside a scratch directory with an isolated `-derivedDataPath`,
then grep the transcript. Any hit means something is still borrowing from a
developer's tree and the gate is red.

## What was deliberately excluded

Adam's working tree carried real API work mixed with a large automated
reformatting pass. Only the load-bearing changes were committed:

**bonsplit** — committed `Sources/**`, `Package.swift`, a hand-written
`CHANGELOG.md` entry. Excluded: a Mar 6 prettier pass over `README.md` and
`www/` (markdown table realignment plus ~4000 lines of `pnpm-lock.yaml` churn).
None of it affects the SwiftPM product.

**ghostty** — committed 11 modified + 2 new source files (the accent-color API
and the OSC 7777/7778 signals). Excluded:

- The same prettier pass over 25 `Assets.xcassets/**/Contents.json` files,
  `images/Ghostty.icon/icon.json`, two `example/**/index.html` files, and a
  trailing-newline change in `.clang-format`. Pure whitespace/quote-spacing.
- 296 **deletions** covering the entire `src/build/` Zig build system, `dist/`,
  and `src/apprt/gtk`. These were not intentional work — committing them would
  have removed `xcframework.zig`, `MetallibStep.zig`, and friends, permanently
  breaking `zig build` for the fork and destroying the from-source fallback.

The committed source is byte-identical to Adam's working tree for all 13
load-bearing ghostty files and all 5 bonsplit files.
