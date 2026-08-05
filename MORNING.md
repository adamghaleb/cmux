# Morning report — Fadicode as a daily driver

Built and tested while you were asleep, on branch `driver/morning-build`
(off `fadi/daemon-seam-1`, PR #71). Nothing was merged. Your live tree at
`~/Documents/windsurf projects/fadicode-v2` was never checked out, reset, or
cleaned — I only read from it.

**Verdict up front: not yet.** The shaders are real and fast, the pet is
honest now, the app builds and runs — but the app develops multi-second
freezes after a task-completion cycle, and a terminal that stalls for 3-6
seconds is not something you can live in. Details in "The blocker".

---

## What actually works

- **Release builds green.** It didn't before — see "What I fixed" #1.
- **It runs.** Opens, spawns a shell, runs commands, splits, new tabs, closes
  surfaces. No crash logs in `~/Library/Logs/DiagnosticReports` across the
  whole session.
- **All 61 Metal shader files compile — 63 entry points, and every one of them
  genuinely renders.** Not "compiles". Renders. Proven on the GPU, see below.
- **Shaders are fast.** Slowest of 63 is 1.79 ms/frame. Nothing is a perf
  problem.
- **The pixel pet no longer lies.** It is now gated on a real `claude` process
  instead of guessing from terminal text.

## What's broken

- **The freezing.** See "The blocker".
- **Two shaders look static** on a 2.5 s window: `CelestialClockwork` and
  `SpiritMolecule`. Both scale time by `0.2`, so they animate very slowly
  rather than being broken. Cosmetic, listed for completeness.
- **You cannot pick a shader in a Release build.** Every shader-selection
  control (`debugSelectShader`, `debugCycleShader`, tier controls, the whole
  debug HUD) is inside `#if DEBUG`, and there is no socket command for shaders.
  In Release the shader is whatever `ShaderDirector` auto-picks. If you want a
  shader picker in the app you actually use, that has to be built — it does not
  exist outside Debug today.
- **`scripts/download-xcframework.sh` is still dead** (points at an upstream
  release tag that does not exist). Building needs zig + ~5 min. Pre-existing,
  already filed as orchestrator #44's neighbour.

---

## Gate 1 — do the shaders actually render?

Yes. This had never been verified, so I verified it two independent ways.

**1. Offscreen GPU harness (all 63 entry points, by name).** Compiled every
`.metal` source into a metallib, invoked each `[[stitchable]]` entry point in a
real compute pass over a 1024×1024 texture at t=0.0 and t=2.5 s, and measured
GPU time with `MTLCommandBuffer` GPU timestamps averaged over 30+ iterations.

| Measure | Result |
| --- | --- |
| Entry points compiled | **63 / 63** |
| Produce non-flat output (actually render) | **63 / 63** |
| Animate over 2.5 s | 59 / 61 time-driven |
| Flagged broken / black / NaN / Inf | **0** |
| Median GPU frame time | **0.31 ms** |
| Mean | 0.41 ms |
| Slowest | **1.79 ms** (MetatronsCube) |
| Shaders below 60 fps | **0** |
| Shaders below 120 fps | **0** |

Slowest ten: MetatronsCube 1.79, FlowerOfLife 1.76, AkashicField 1.67,
NebulaCloud 1.30, CrystalCavern 1.22, StringTheory 0.91, Combined 0.83,
MachineElves 0.81, CosmicWeb 0.75, DreamCatcher 0.75 (ms/frame).

Four entry points have non-standard signatures and were adapted rather than
called verbatim — `lumaRevealEffect`, `lumaDissolveOut`, `glowDilateEffect`,
`posterizePixelateEffect`. These take a `SwiftUI::Layer`, which cannot be
constructed outside the SwiftUI compositor. Their bodies were exercised against
an equivalent texture read. **So: their logic runs and produces structured
output, but they are not proven against the real compositor input.** Being
straight with you about that one.

PNG of every shader: `~/.claude/jobs/7f77dd94/tmp/driver/shaderharness/out/`
(63 files). Raw numbers: `.../shaderharness/results.json`.

**2. Live, in the running app.** Measured the app's own main-thread
responsiveness with the shader off vs on (the socket `ping` is answered on the
main actor, so its round-trip is a direct proxy for "does this feel alive"):

| State | min | p50 | p90 | max |
| --- | --- | --- | --- | --- |
| Fresh launch, shader OFF | 0.4 ms | **0.6 ms** | 1.4 ms | 2.6 ms |
| Shader ON (OSC 7778;start) | 0.2 ms | **1.0 ms** | 4.3 ms | 5.7 ms |

**Running a shader costs almost nothing.** That is the good news, and it means
the visual layer is not what's wrong with this app.

**What I could not do: screenshots of the live window.** `screencapture`
returns "could not create image from display" because this session has no
Screen Recording permission, and the app's own `debug.window.screenshot` socket
command is `#if DEBUG`-only. I did not want to trip a permission prompt on your
machine while you were asleep. So the live proof is instrumented, not visual;
the visual proof is the 63 offscreen PNGs.

---

## The blocker

When the shader / task-completion machinery is exercised (OSC 7778 start-stop,
OSC 7777 completion — the normal "Claude is working / Claude finished" path),
the app intermittently stalls its main thread for **seconds**.

Measured on the first build (agent scan still on the main thread):

| When | min | p50 | p90 | max |
| --- | --- | --- | --- | --- |
| Fresh, shader off | 0.4 ms | 0.6 ms | 1.4 ms | 2.6 ms |
| Shader on | 0.2 ms | 1.0 ms | 4.3 ms | 5.7 ms |
| **After completion cycle** | 0.4 ms | **240 ms** | **3.9 s** | **5.8 s** |
| +20 s idle | 0.4 ms | 15.5 ms | 96.6 ms | 242 ms |
| +50 s idle | 2.0 ms | **806 ms** | 2.5 s | **7.0 s** |

I moved my process scan off the main thread and re-measured. It got **much**
better — one full start/stop cycle came back completely clean
(p50 0.5 ms, p90 1.8 ms, max 2.5 ms).

**But it is not fixed.** On a harder soak (five back-to-back
start → completion cycles) the app still wedged: a `surface.send_text` call
timed out after **20 seconds**. It recovered on its own, and a follow-up
40-sample run read p50 0.8 ms / p90 9.6 ms but with a **5.16 s** worst case.

So the honest shape of it: *usually* fast, *intermittently* frozen for
multiple seconds, occasionally wedged for 20 s. That is not a terminal you can
live in, and it's intermittent enough that you'd never quite trust it.

**What it is not:** it is not the shaders (shader-on alone is 1.0-1.5 ms p50,
and all 63 render in under 1.8 ms on the GPU), and it is not primarily my
agent-presence scan (a full cold scan measures 1.2 ms). Moving that scan
off-main clearly helped, which suggests main-thread contention around the
lifecycle poll is *part* of it — but something in the completion fan-out
(`onResponseComplete` → completion popup, sound, task flash, celebration
animation, full terminal-content read, all on the main actor) is still
blocking.

I deliberately stopped short of a fix. It needs real profiling — `sample` on
the process timed out mid-stall, which is itself consistent with a wedged main
thread — and a guess at 4am that makes the app *feel* worse is a bad trade.
**This is the one thing standing between you and using it tomorrow.**

---

## The pixel pet — is it trustworthy now?

**Yes, more than it was — with one honest caveat.**

Before: the pet's state came from polling terminal **text** at 10 Hz and
hashing it. That fired on ordinary shell output (a big `ls`, a paste, a scroll)
and then, once it decided Claude was "working", the only ways out were an
OSC 7777 completion signal or a **5-minute** safety timeout. So it both
false-triggered and got stuck.

Now: state is gated on whether a **real agent process** is alive and bound to
that terminal. I transcribed the narrow slice of upstream
`manaflow-ai/cmux` **PR #6798** that does this — env var → process table →
classifier — with `// upstream: PR#6798` breadcrumbs throughout. No rebase
(7,436 commits diverged); this is a hand-carried slice:

- `KERN_PROCARGS2` reader to pull argv + environment out of another process
- `proc_listallpids` process table with ppid / name / start time
- basename-first agent classifier; argv needles only for script hosts
- scope cache keyed on `(pid, start time)` so PID reuse self-invalidates

The binding key is `CMUX_SURFACE_ID`, which this fork **already** injects into
every spawned shell, so a `claude` you start by hand inherits it for free.

I skipped upstream's full process-tree expansion on purpose: environment is
inherited by the whole subtree, so matching agent-shaped processes directly is
equivalent for the presence question and much cheaper. Rationale is in the file
header.

**Proven against a real session**, not asserted:

```
[  0.0s] agentLive=false
[  4.3s] agentLive=TRUE      <- real `claude` launched
[  8.5s] agentLive=false     <- claude exited
```

Detected within 0.3 s each way, no flapping in between.

**The caveat, stated plainly:** what I fixed is *presence* — "is an agent really
alive here". I did **not** transcribe upstream's busy/idle/needs-input state
machine (their hook-event `nextState`, transcript corroboration, and
`DispatchSource` process-exit watcher). So the pet can no longer claim Claude
is working when nothing is running, and it can no longer stay stuck for five
minutes after Claude exits — but the *distinction between* "thinking" and
"typing" still comes from the old text heuristics. Left deliberately; it's the
next slice, and it's bigger than one night.

Also: I could not run the full live pet-vs-real-claude visual confirmation,
for the same screenshot-permission reason above. The presence layer is proven
at the unit level and the wiring is three lines; the pixels are not proven.

---

## What I fixed

1. **Release did not compile at all.** `DebugStateOverlay` is wrapped entirely
   in `#if DEBUG`, but its call site in `FadiCodeOverlayHost` was not — so
   `-configuration Release` failed with `cannot find 'DebugStateOverlay' in
   scope`. Gate 0 only ever verified Debug, so nobody had hit this. Guarded the
   call site.
2. **Added the agent-presence slice** above, and registered the new file in the
   Xcode project (this project has no synchronized file groups, so a new
   `.swift` file is invisible until it's added to `project.pbxproj` in four
   places — worth knowing).
3. **Moved the process scan off the main thread.** It's only 1.2 ms, but
   upstream is explicit that nothing like it belongs on the main actor, and it
   was being called from a 10 Hz main-thread poll. This measurably improved the
   stalls (see "The blocker") without eliminating them.

---

## How to launch it

The app is at **`~/Applications/Fadicode.app`** — double-click it.

It is **ad-hoc signed** (`codesign -s -`), so Gatekeeper should let it open
directly. If macOS refuses ("cannot be opened because the developer cannot be
verified"), one line fixes it permanently:

```bash
xattr -dr com.apple.quarantine ~/Applications/Fadicode.app
```

Right-click → Open also works as a one-time bypass.

It uses its own bundle id (`com.fadicode.terminal`) and its own control socket,
so it runs side by side with anything else you have open.

## How to go back to stock Ghostty

Nothing was installed, replaced, or registered as a default. Stock Ghostty and
your existing cmux are untouched — just open them as normal.

To remove this build entirely:

```bash
rm -rf ~/Applications/Fadicode.app
```

That's the whole uninstall. `~/Applications` did not exist as a curated dir
before beyond your existing apps; I created nothing else there and touched
nothing in `/Applications`.

To drop the code too: the work is only on `driver/morning-build`, which is not
merged into anything. Delete the remote branch and it's gone.

## Rough edges you should know about

- Multi-second freezes after completion (the blocker).
- No shader picker in Release.
- Settings still expose socket-control modes that assume the cmux
  naming; `cmuxOnly` is the default, so external automation needs
  `CMUX_SOCKET_MODE=automation`.
- A custom bundle id that isn't `…terminal.debug*` or `…terminal.staging*`
  **silently ignores** `CMUX_SOCKET_PATH` and grabs the shared
  `/tmp/fadicode.sock`. I hit this and it's a real footgun for running two
  instances.
- 122 build warnings in Release, mostly deprecated `onChange(of:perform:)` and
  Swift 6 actor-isolation notes. None fatal, all pre-existing.

---

*Reproduce anything here from `~/.claude/jobs/7f77dd94/tmp/driver/`:
`shaderharness/` (GPU harness + 63 PNGs + results.json),
`verify/` (launch script, socket driver, latency measurements),
`ptest/` (agent-presence proof).*
