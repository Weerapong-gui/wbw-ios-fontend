# Forest 3D background — verification notes

**Date:** 2026-08-02
**Branch:** `feature/forest-3d`
**Scope:** the whole 10-task forest background feature (plan at
`docs/superpowers/plans/2026-08-02-forest-3d-background.md`), written at Task 10 — the task
whose entire job is to look at the finished thing with real screenshots and say plainly what
was and wasn't checked. Per-task detail lives in `.superpowers/sdd/2026-08-02-forest-3d-background/`
(`task-N-report.md`, `progress.md`); this document pulls forward what a future reader needs
without re-reading all of it.

This is a status report, not a guarantee. Several claims below are explicitly "judged by eye"
or "never exercised" — that wording is deliberate, see the sections named for it.

## What Task 10 added

`HomeView.swift` gained a `#if DEBUG` launch-argument override, `-uitestProgress <n>`, following
the existing pattern (`-uitestTab` in `MainTabView.swift`, `-uitestChat`/`-uitestProfile`
elsewhere). When `UserDefaults.standard.object(forKey: "uitestProgress")` is present, `stage`
returns its integer value and `total` is forced to `8`, both bypassing the real
`CheckinProgressStore` fetch; otherwise behavior is unchanged. This exists because the seeded
test account (`6931900011`) has real progress that changes as people check-in-test against it,
so a fixed set of stages is needed to get repeatable, comparable screenshots. Confirmed by
`curl` against the running local SUS stack on this date:

```
GET /wbw/me/progress → {"total": 8, "checked_in": [1,2,3,4,5,6]}   (6 of 8, unforced)
```

matching what Task 9 found on the same date. Without the override, Home currently shows stage 6.

## The three stage screenshots

**Method.** `xcodegen generate`, then `xcodebuild -scheme WBW -configuration Debug -destination
'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <fresh path> build` — a **fresh**
`-derivedDataPath` under the scratch directory, not the default one, and not a plain `build`
against an existing DerivedData folder (see "The stale-DerivedData build trap" below for why
that distinction is load-bearing). Then, for `n` in `0 4 8`: `simctl terminate`, `simctl launch
… -uitestToken <jwt for 6931900011> -uitestUser 6931900011 -uitestRole participant -uitestTab 0
-uitestProgress $n`, a wait, `simctl io booted screenshot`. All three images were opened with an
image-reading tool and looked at directly, not inferred from file size or assumed from the code.

**Two things went wrong on the first pass, both worth recording so the next person doesn't
repeat them:**

1. At a 6-second wait (the brief's suggested figure, copied from earlier tasks' steady-state
   screens), the **stage-0 capture came back solid black** — no forest, no sky, nothing — while
   stage 4 and 8 rendered fine. This looked alarming at first (a stage-0-specific bug) but was a
   cold-start artifact: stage 0 was the *first* launch after a fresh install (first RealityKit
   scene load, shader compilation, Firebase init all paying their one-time cost at once), and
   6 seconds wasn't enough for that specific launch. Re-run at a 10-second wait with a
   checksum-verified fresh build: all three captures came back the same order of magnitude in
   file size (925 KB / 957 KB / 922 KB, vs. the first stage-0 attempt's 100 KB), confirming all
   three now show real rendered content. Lesson: the *first* launch after install needs more
   time than steady-state launches; give it a wide margin or do a throwaway warm-up launch first.
2. **Every launch of a freshly-installed build shows iOS's "‘เดินรอบดอย’ Would Like to Send You
   Notifications" system permission alert**, covering roughly the vertical middle third of the
   screen, because `AppDelegate.application(_:didFinishLaunchingWithOptions:)` requests
   notification authorization on launch and this environment has no way to answer the alert —
   there is no tap tooling here, a limitation every earlier task in this feature also hit (see
   Task 5/6/9's reports on the same point). I tried a temporary `#if DEBUG` skip in
   `AppDelegate.swift` gated on a new UserDefaults flag; it did not reliably suppress the prompt
   (Firebase's own configuration path appears to trigger it independently of the app's explicit
   `requestAuthorization` call, and a diagnostic `NSLog` I added to confirm this printed nothing
   findable in `log show`, so I couldn't even fully diagnose it within a reasonable amount of
   time). I reverted that attempt completely — confirmed by `git diff WBW/AppDelegate.swift`
   showing no changes and `grep -rn "TEMP-TASK10-VERIFY\|uitestSkipPushPrompt" WBW/` returning
   nothing — rather than keep spending time on a testing-only obstacle. The three screenshots
   used for evidence below have the dialog in them. The sky (top of frame, above the dialog) and
   the tree/ground/credit (bottom of frame, below the dialog) remain fully legible around it, so
   the comparison below is still valid, just not a clean product screenshot.

**What the three images actually show**, read stage by stage (the dialog gives an incidental
size ruler: at stage 0 the canopy sits entirely below it, at stage 4 the canopy is wide enough
to bulge past both of its edges, at stage 8 the canopy fills the entire visible background above
it):

- **Stage 0** (`day = 0.14`, `treeHeight = 0.70`, the formula's minimum): a small, thin brown
  trunk with a sparse tuft of green canopy, entirely contained in the strip below the dialog.
  Sky above the mountains reads muted, desaturated, dusty mauve-gray — a dawn tone, clearly
  dimmer/less saturated than the other two stages.
- **Stage 4** (`day = 0.46`, `treeHeight ≈ 1.87`): visibly thicker trunk, and a canopy — layered
  dark/light green facets — wide and tall enough to extend past both sides of the dialog and
  peek above its top edge. Sky is distinctly brighter and bluer, with a visible pale-blue gap
  between the mountain peaks; mountains read crisper, whiter-capped.
- **Stage 8** (`day = 0.78`, `treeHeight = 5.00`, the formula's maximum): the canopy has grown
  large enough to fill nearly the entire visible background above the dialog, leaving only small
  slivers of pale sky at the top corners. Trunk is the thickest of the three.

Tree growth across the three stages is unambiguous — this is the easy part to confirm and it
holds up. **Sky colour is more nuanced than "three different times of day" suggests**, and I
want to be precise rather than wave at it: dawn (stage 0) vs. either of the other two is a large,
obvious difference. Stage 4 vs. stage 8 is a much smaller difference in sky tone specifically —
consistent with Task 8b's own recorded minor finding that "afternoon (0.78) reads close to
dayStill (0.46) — both cool blue." I hand-computed `SunCycle.state(at:)`'s smoothstep
interpolation for all three `day` values as a cross-check against the screenshots (not a
replacement for looking at them):

| stage | `day` | interpolates between keys | `skyColor` (R,G,B) |
|---|---|---|---|
| 0 | 0.14 | p=0.00 → p=0.18 | (0.51, 0.46, 0.47) — muted, warm-gray |
| 4 | 0.46 | p=0.36 → p=0.56 | (0.73, 0.83, 0.96) — bright, cool blue |
| 8 | 0.78 | p=0.56 → p=0.79 | (0.72, 0.78, 0.86) — bright, cool blue, slightly dimmer than stage 4 |

This matches what's on screen: stage 0 is unmistakably different from the other two; stages 4
and 8's *sky dome* colour are close to each other by construction (both keyframe pairs sit in
the same "blue daytime" region of the curve — there is no keyframe near 0.7–0.8 that reads warm
or golden the way "golden afternoon" implies; the closest warm/orange keyframe is at `p = 1.00`,
past `dayTo = 0.78`). At stage 8, the progress signal that actually reads clearly is **tree
size**, not sky colour — the canopy filling the frame is the dominant, unambiguous cue; the sky
shift between 4 and 8 is real but subtle and is mostly hidden anyway once the tree is that large.
Screenshots were not committed (per instructions) and were only captured to a scratch directory,
so this description is the durable record of what they showed.

## The stale-DerivedData build trap

Task 8b's reviewer hit this directly and it's the reason the brief calls it out as "not
optional": **`xcodebuild build` (no `clean`, default or reused `-derivedDataPath`) can print
`** BUILD SUCCEEDED **` while running zero compile and zero resource-copy steps**, silently
serving whatever `.usdz` was already sitting in that DerivedData folder from a previous build —
even a build from *before* the fix a screenshot is meant to verify. Task 8b's reviewer's first
screenshot reproduced an already-fixed black-sky bug this way.

For every build in this task I used a **fresh** `-derivedDataPath` (never the default, never
reused across a source change without re-verifying), and independently confirmed — by SHA-256,
not by trusting the build log — that the `.usdz` files inside the built `.app` bundle are
byte-identical to the ones in `WBW/Resources/`:

```
4d6e44ae218ccdc04bae6e4c6c97391335d902f0eecdd382c431b35341ee8192  forest.usdz (built + source, match)
33e2fece0f45e288a4e8b38d23e092b95684861d20ac72582f838f1b6af3ffa6  tree.usdz   (built + source, match)
```

and grepped the build log for the actual `CpResource … forest.usdz` / `CpResource … tree.usdz`
lines to confirm the resource-copy phase genuinely ran rather than being skipped. Both checks
passed on the build used for the screenshots above. This is mechanical and cheap to redo —
whoever verifies this feature next should do the same rather than trust `BUILD SUCCEEDED` alone.

## Bake pipeline — concrete numbers

Current committed state (`WBW/Resources/`, unchanged by this task):

| file | size |
|---|---|
| `forest.usdz` | 647,401 bytes (≈ 632 KiB / 0.62 MB) |
| `tree.usdz` | 11,830 bytes (≈ 11.6 KiB) |

`forest.usdz`'s size is Task 8b's post-fix figure exactly (their report records `649,090 →
647,401 bytes` after narrowing `tree_near`'s scatter range); `tree.usdz` is untouched since
Task 1 ("byte-identical" per Task 8b's own re-check). Scatter counts printed by
`scripts/bake-forest.py` on the bake that produced the current file (from Task 8b's report,
re-confirmed against the committed file via `usdcat` in that same task, not merely read from the
script):

```
SCATTER STATS: {'tree_near': 34, 'tree_far': 30, 'grass': 450, 'rock_small': 25,
                 'rock_large': 10, 'mountain': 6, 'signpost': 1}
MATERIAL BANDS: 23
```

556 placed objects total (34+30+450+25+10+6+1). `tree_near` requested 60 but placed 34 — the
scatter/cull loop's frustum+clearing culling, expected behavior, not a bug (Task 1's finding).
23 material bands present (bands 0,1,3,4,5,6,7 — **band 2 is legitimately absent**, ruled on
twice: Task 1 established that band 2's entire visible volume sits inside the radius-3.2
clearing so it can never be populated, and Task 8b's `usdcat` re-check after the composition
change confirmed the same 7-band set still holds).

Models: 8 `.glb` files under `WBW/Resources/models/`, credited via `CREDITS.md` and the on-screen
line `"โมเดล 3 มิติ: ดู WBW/Resources/models/CREDITS.md · CC BY"` (`ForestOverlay.swift`). Worth
being precise since the on-screen credit is a blanket line: 5 of the 8 are actually **CC BY
4.0** (`tree`, `mountain-snow`, `mountain-ridge`, `snowy-hills`, `grass`) and require the credit;
3 are **CC0** (`rock-small`, `rock-large`, `signpost`) and don't strictly need it, but get the
same blanket credit anyway for simplicity. Do not remove the credit while any CC BY file remains
in the bundle.

## Quick Look never rendered this file — still true

Task 1 could not get Apple's actual Quick Look USDZ renderer to draw `forest.usdz` in this
environment: `qlmanage -t` hung indefinitely (confirmed twice, ~18–23s each, no output, no
error); `qlmanage -m` lists 85 registered generators covering images/PDFs/Office docs, none for
USD/USDZ — macOS's native USDZ preview is a newer system extension that appears to need a full
interactive GUI session this environment doesn't have. `qlmanage -p` (interactive) was never
attempted (out of scope for Task 1). Nothing in Tasks 2 through 10 changed this. Everything that
has "verified" `forest.usdz`'s or `tree.usdz`'s appearance — Task 1's Blender render-check
script, `usdcat` structural dumps, and this task's own RealityKit screenshots in the Simulator —
is a **different renderer** standing in for the one that actually matters for things like
Files.app previews, Messages/AirDrop previews, and `<model-viewer>`-adjacent contexts: none of
those have ever drawn either file. RealityKit rendering it correctly in-app (which today's
screenshots do show) is good evidence the USD content is well-formed, but it is not the same
claim as "Quick Look can preview it," and that claim remains unverified.

## Gyroscope parallax has never been exercised

Stated plainly because it's easy to lose in a pile of green checkmarks: **nobody has ever seen
the gyro parallax effect run.** `GyroParallax.swift`'s `isAvailable` is a direct passthrough to
`CMMotionManager.isDeviceMotionAvailable`, which is `false` on every iOS Simulator, always, by
construction (no motion hardware to report). As a direct result:

- `start()` guards on `motion.isDeviceMotionAvailable` and returns immediately without setting
  `running = true` or arming any callback.
- `stop()` guards on `running`, which is therefore always already `false`; also a no-op.
- The `offset` published property never leaves `SIMD2(0, 0)` in this environment.

`GyroParallaxTests`' 6 tests (all passing, see below) cover only `mapAttitude(roll:pitch:)`, the
pure math that turns a roll/pitch reading into a screen-space offset — real, useful coverage of
the *formula*, but it has never been fed a real sensor sample, and the actual camera-offset
visual effect on screen has literally never been seen by anyone on this feature, implementer,
reviewer, or this task.

Physical-device testing of this app is not unprecedented — a working recipe exists from chat-v2
testing on an iPhone 13 (2026-08-01/02), and the same recipe would apply here: point a temporary
`Backend` case at the Mac's LAN IP (`localhost` on a phone means the phone itself), forward the
SUS container's loopback-only port to the LAN with a throwaway `socat` container, launch via
`xcrun devicectl device process launch --device <id> --console <bundle> -- -uitestToken …` (the
`--` separator is required or `devicectl` misparses `-uitestToken` as its own `-t` timeout flag),
and expect a reinstall to wipe the notification-permission grant again. `project.yml` already
sets automatic signing, so no provisioning work is needed. **Nobody has run this recipe against
the forest scene specifically** — it was built and proven for chat sync, not for gyro. Whoever
picks this up next should expect to spend real time on it, not treat it as a formality.

## Which screens were screenshotted, on which devices

| Screen | `bottomClearance` | iPhone 17 | iPhone SE (3rd gen) | When |
|---|---|---|---|---|
| `WelcomeView` | `0` | yes | yes | Task 9 |
| `LoginView` | `0` | yes | yes | Task 9 |
| `HomeView` (real progress) | default (89) | yes | yes | Task 9 |
| `HomeView` (stages 0/4/8, forced) | default (89) | yes | — | Task 10 (this task) |
| `MyQRCodeView` | default (89) | yes | yes | Task 9 |
| `MainTabView`'s `ForestBlank` | default (89) | — | — | never — unreachable, see below |

`ForestBlank` (in `MainTabView.swift`, reserved for future Event/Voucher tabs the DOI-APP scope
hasn't built yet) has never been screenshotted on any device, because nothing currently
navigates to it — Task 9 confirmed this with `grep -rn "ForestBlank" WBW/`, finding only its own
definition. It is verified by code review and by the fact that it compiles and the full test
suite passes, not by anyone looking at it.

Task 8 and 8b's screenshots (the black-sky discovery, the sky-fix confirmation, the composition
fix) were taken on iPhone 17 unless their reports say otherwise; the SE pass for the credit
position specifically was Task 8's fix round.

## Judged by eye, not measured

Two different kinds of claim have been made about this scene across all ten tasks, and they are
not the same strength of evidence:

- **Geometry was measured.** The 89pt tab-bar clearance (`ForestSceneHost.tabBarClearance`) came
  from scanning actual pixel rows on real screenshots on two devices to find the tab bar's true
  edge, not a guess — this one has numbers behind it.
- **Appearance was judged by eye, not measured, everywhere else.** "The sky looks brighter,"
  "the canopy looks larger," "dawn reads muted" (including in this document's own stage
  descriptions above) are visual impressions from looking at PNGs, not colorimetric diffs, not
  pixel sampling, and not a side-by-side comparison against the companion website
  (`~/su-wbw-website`) taken at the same moment. Task 8's camera-composition complaint ("trees
  fill the frame from the very foreground, no sense of standing on a trail") and Task 8b's fix
  for it were both eye judgments on both ends — nobody screenshotted the website's `/landing`
  page and the app side by side and compared them pixel-for-pixel. If the bar for "matches the
  website" needs to be higher than "looks similar to a person," that comparison still needs to
  be done.

## Known gaps and carried-forward findings, by task

Distilled from `.superpowers/sdd/2026-08-02-forest-3d-background/progress.md` and the individual
task reports — the items a future reader would otherwise have to re-derive:

- **Task 1** — `forest.usdz` is not byte-reproducible run-to-run (prim serialization order
  depends on Python `set()` iteration order); the *scene content* is fully deterministic, but a
  re-bake will not checksum-match the committed file even with no intended change. Don't treat a
  changed hash alone as evidence of a content change — diff the `usdcat` dump instead.
- **Task 2 (SUS repo)** — no DB-backed test harness exists there, so its query was verified by
  `curl` against the running stack, not by unit tests. The total-count and check-in-list queries
  are two round trips with no transaction, so a concurrent admin edit to `requires_checkin`
  between them could theoretically mix snapshots (minor, deferred, never seen in practice).
- **Task 4** — `ForestMath.swift`'s doc comment claims the website's fixed height table has a
  "constant ratio ~1.65" between steps; the real consecutive ratios are 1.86 / 1.69 / 1.55 / 1.47
  (geometric mean ≈1.64). The comment is cosmetically wrong (inherited from the plan text, not
  introduced by any implementer) — the code itself was hand-checked scalar-by-scalar against the
  website's `trail.ts` and found exactly correct.
- **Task 5** — required a real fix, not just review commentary: the scene originally unmounted
  and reloaded all 571 objects every time Home left and re-entered the screen (SwiftUI's
  per-tab-root `TabView` behavior), contradicting the spec's "one persistent scene." Fixed with
  an `everEnabled` + opacity pattern instead of structural `if enabled`; re-verified live, not
  just re-read.
- **Task 8** — found by the controller's own screenshot read, not by any scoped review: **the
  sky rendered solid black** because nothing ever set the RealityView's environment/background
  despite `SunCycle` computing a `skyColor` every frame. Fixed in Task 8b (a radius-500
  inward-facing sky dome). Also flagged, and only partially addressed: camera composition didn't
  match the website's sense of depth — Task 8b pulled `tree_near` and `rock_large` further from
  camera, improving it, but this was never re-measured against the website, only re-judged by
  eye (see above).
- **Task 8** — minor, unresolved, worth flagging for whoever hits it again: one SE launch during
  testing fell back to the static `bg_forest` image instead of loading the 3D scene. Two
  different agents tried to reproduce it afterward and neither could. Cause unknown; the
  load-error path treats *any* `Entity(named:)` failure as permanent-for-process with no
  transient/permanent distinction and no retry.
- **Task 8b** — established the stale-DerivedData build trap (see its own section above) and
  recorded that stage-4-equivalent (`dayStill`, 0.46) and stage-8-equivalent (0.78) sky tones
  read close to each other, both "cool blue" — independently reproduced by this task's own
  screenshots and hand-computed keyframe math, see "The three stage screenshots" above.
- **Task 9** — the seeded check-in data for `6931900011` drifted from the original plan's
  assumption (checkpoints 1/2/3 = stage 3) to checkpoints 1–6 = stage 6, from real interactive
  testing during Tasks 5–8. Reported rather than reset, since the DB is shared state Park edits
  directly. Still true today (re-confirmed by this task's own `curl`, see above) — this is
  exactly why the `-uitestProgress` override this task adds is necessary rather than cosmetic.
  Also: the controller changed `Config.backend` from `.susLan` (pointing at a dead address) to
  `.susLocal`, uncommitted, local-dev-only — this is the pre-existing ` M WBW/Config.swift` you
  will see in `git status` around this feature; it is intentionally not part of any commit here.
- **Task 9** — `updateSceneGate()`'s `chatOpen` half is currently unreachable in a release build
  (every real `chatOpen = true` call site already also sets `tab = 3`); it's defensive code
  exercised only through the DEBUG `-uitestChat` flag.

## Test suite

Full suite, not a single target, run against the same freshly-built, checksum-verified binary
used for the screenshots above:

```
xcodebuild -scheme WBW -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath <fresh path> test
```

**Result: 72 tests, 0 failures, 0 unexpected**, across 9 suites — `ChatDTOTests` (2),
`ChatRowTests` (19), `ChatSessionPersistenceTests` (7), `ChatSessionTests` (8),
`CheckinProgressStoreTests` (6), `FlexibleStringTests` (4), `ForestMathTests` (14),
`GyroParallaxTests` (6), `PendingPushTests` (4), `QRCodeTests` (2). `** TEST SUCCEEDED **`. Same
count as Task 9's last run (72/72) — this task added no new tests, only the DEBUG launch hook
and this document.

## What this document does not close

To be explicit about the boundary, since the point of this document is to not let gaps go quiet:

- No physical device was used at any point in this feature. Gyro parallax remains unseen.
- No Quick Look / Files.app / AirDrop preview of either `.usdz` has ever been captured.
- No pixel-level or colorimetric comparison against the website was performed, today or in any
  earlier task — every appearance claim, including the ones in this document, is a human (or
  model) looking at a PNG and describing it.
- The Task 8 "SE fell back to the static image once" gap was not investigated further here — it
  wasn't reproducible then and wasn't re-attempted now, since reproducing an intermittent failure
  wasn't in scope for this task.
