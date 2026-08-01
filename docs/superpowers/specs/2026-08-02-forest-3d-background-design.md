# Forest 3D Background + Check-in Progress Tree

- **Date:** 2026-08-02
- **Status:** Approved (design), pending implementation plan
- **Scope:** app background across the 5 screens that use a static image today,
  plus the Home growing-tree gimmick. Nothing else on those screens changes.
- **Repos:** `wbw-ios-fontend` (iOS) **and** `~/Student-Union-Server` (SUS, Go)
- **Not in this spec:** post-scan evaluation + feedback collection — that is
  spec 2 (`2026-08-02-checkin-feedback-design.md`, to be written).

## Context

The app paints its background with three static images: `bg_welcome`
(`WelcomeView.swift:46`), `bg_login` (`LoginView.swift:79`), and `bg_forest`
(`HomeView.swift:67`, `MyQRCodeView.swift:26`, `MainTabView.swift:145` in
`ForestBlank`).

The companion website `~/su-wbw-website` renders a real 3D forest instead. One
`<Canvas>` lives in the layout (`components/scene/SceneHost.tsx`) and never
unmounts, so navigating between pages does not rebuild WebGL. Pages only push
config into it: where the camera parks, what time of day it is, and how far the
participant's tree has grown (`components/register/GrowingPlant.tsx`). The
forest itself (`components/landing/TrailScene.tsx` + `trail.ts`, ~49 KB of TS)
is procedural: 440 instanced trees in two depth layers, 2,400 grass tufts, 155
rocks, 21 mountains, a procedural terrain mesh, ponds, 700 stars, 420 dust
motes, canvas-generated noise textures, and a 6-key sun cycle. Eight GLB models
under `public/models/` (5–31 KB each) feed all of it.

The app should look like that website, and Home should show the participant's
own tree growing one stage per base checked in.

SUS already records check-ins: `check_in` (unique on `participant_id,
checkpoint_id`) and `checkpoint` (`requires_checkin` flag, `sequence`). The seed
ships 8 activity bases plus 4 service points. `POST /wbw/staff/checkin` writes
the rows. **Nothing lets a participant read their own check-ins** — that is the
one backend gap this spec closes.

Deployment target is iOS 18.0, so RealityKit is available. SceneKit is
deprecated (WWDC25) and is not used.

## Goal

1. All five screens that use a static image share **one persistent 3D forest**
   that survives welcome → login → home and every tab switch.
2. Home shows **one tree** that grows a stage per base checked in, and the
   scene's time of day advances with the same progress.
3. The background tilts with the phone (gyroscope parallax), the mobile
   equivalent of the website's pointer parallax.

## Non-Goals (YAGNI)

- No walking/scrolling scene like the website landing page — the camera parks.
- No dynamic ponds, stars, or dust. If they are wanted, bake them in.
- No runtime download of the model — it ships in the app bundle.
- No changes to `~/su-wbw-website`, and no new dependency in any repo.
- No changes to the Map tab (it has its own paused spec,
  `2026-07-31-map3d-glb-design.md`).
- No HUD on Home: no "3/8" counter, no base names, no progress bar.
- No realtime growth at the moment of scanning — spec 2 owns that signal.

## Approach (decided)

**Bake the forest to a single USDZ offline; do lighting, gyro, and the growing
tree natively in RealityKit.**

Two alternatives were rejected:

- **Port `trail.ts` + `TrailScene.tsx` to Swift 1:1.** Highest native fidelity
  and fully dynamic, but ~2,000+ lines of Swift, no direct RealityKit
  equivalent for three.js instancing, and the procedural textures would have to
  be rewritten in Core Graphics. The camera never moves more than ±1.1 units,
  so almost none of that dynamism is observable. Not worth the cost or risk.
- **A transparent `WKWebView` running the real web scene.** Perfect parity and
  the least scene work, but WebGL in a WebView costs noticeably more battery
  and memory than native, needs a static build bundled for offline use, and
  needs a JS bridge for `plantStep`. The Map3D spec already rejected this
  approach for the same reasons.

### Layout fidelity: "looks like", not "numbers match"

An earlier draft dumped the exact scatter layout out of the website (extracting
`useLayout` into a pure module, running it under Node, feeding the JSON to
Blender). That is dropped. The scene is static and decorative, so matching the
website's exact object positions buys nothing and costs a cross-repo contract.

`scripts/bake-forest.py` scatters its own objects, imitating the website's
*proportions*: trees in a near-dense / far-sparse pair of layers, grass packed
along the trail edge, rocks sprinkled, mountains closing the backdrop. Starting
counts to tune from: ~90 trees, ~450 grass, ~35 rocks, ~6 mountains, 1 signpost.

## Architecture

### One scene, five screens

```
RootView
  └── ForestSceneHost            ← owns the only RealityView; survives phase changes
        ├── ForestSceneView      ← RealityView: forest.usdz + tree.usdz + camera + gyro
        ├── SunCycle             ← day 0..1 → light colour/direction, fog tint
        └── GrowingTree          ← tree.usdz scaled to stage n, wind sway

WelcomeView · LoginView · HomeView · MyQRCodeView · ForestBlank
  └── .forestBackground(day:plantStep:)   ← all these screens know about the scene
```

`ForestSceneHost` is an `@Observable` holding `enabled`, `day`, and
`plantStep`, mirroring `SceneConfig` in `SceneHost.tsx`. Screens push config on
appear and clear `enabled` on disappear. No screen imports RealityKit.

`plantStep` is optional and defaults to nil, exactly as on the website: nil
means no tree in the scene. Only Home passes a value.

### New files

| File | Role |
|---|---|
| `WBW/Scene3D/ForestSceneHost.swift` | Config state, lifecycle, render gating |
| `WBW/Scene3D/ForestSceneView.swift` | `RealityView`, `PerspectiveCamera` (fov 55), gyro offset |
| `WBW/Scene3D/SunCycle.swift` | Port of `SUN_KEYS` + `sunAt()` from `trail.ts` |
| `WBW/Scene3D/GrowingTree.swift` | Stage → height, growth lerp, wind sway |
| `WBW/Scene3D/ForestOverlay.swift` | Gradient scrim, film grain, model credit |
| `WBW/CheckinProgressStore.swift` | Fetch + cache check-in progress |
| `scripts/bake-forest.py` | Blender headless: GLB → scattered scene → USDZ |
| `WBW/Resources/forest.usdz`, `WBW/Resources/tree.usdz` | Baked assets |

### Changed files

| File | Change |
|---|---|
| `WBW/RootView.swift` | Host the scene beneath every phase |
| `WBW/HomeView.swift` | Drop `bg_forest`; **drop the DinDin mascot** |
| `WBW/WelcomeView.swift`, `LoginView.swift`, `MyQRCodeView.swift` | Static image → `.forestBackground(day:)` |
| `WBW/MainTabView.swift` | Same, for `ForestBlank`; also loads `CheckinProgressStore` alongside the profile |
| `project.yml` | Verify the regenerated project copies `*.usdz` into the bundle — `sources: [WBW]` already sweeps the directory, but xcodegen must classify the files as resources, not unknown |

`Image("dindin")` is used only at `HomeView.swift:57`. After this change the
asset has no consumer; it stays in `Assets.xcassets` (harmless, and the mascot
may return elsewhere).

## Asset pipeline

`scripts/bake-forest.py` runs under Blender 5.1.2 (installed at
`/Applications/Blender.app`) via `--background --python`:

1. Copy the eight GLBs from `~/su-wbw-website/public/models/` into the app repo
   (with `CREDITS.md` — the models are CC BY and attribution is mandatory).
2. Import each GLB once; place linked duplicates so instances share mesh data.
3. Scatter within the camera frustum **widened by 25% on every side** so
   tilting the phone never reveals an empty edge.
4. Keep a clearing on the camera's line of sight, 6 units ahead, for the
   growing tree. (The website offsets its tree 2.9 units left because a form
   floats over the right side; the app has no such form, so the tree is
   centred.)
5. Group objects into ~8 distance bands, each with its own material, and
   disable material merging on export. Swift retints these 8 materials per
   frame to fake distance fog — RealityKit has no exponential fog, and since
   the camera is fixed each object's distance is constant, so per-band tinting
   is enough.
6. Build ground, trail, and any pond geometry from Blender's own noise nodes;
   bake to PNG on export. The website's `makeNoiseTexture` is not ported.
7. Export `forest.usdz` with USD instancing enabled. Export `tree.usdz`
   separately — it is scaled every frame and must stay independent.

**Gate before any Swift is written:** open the USDZ in Quick Look. If materials
are broken or the file exceeds 25 MB, reduce counts or drop the far layer and
re-bake. Do not start app code until this passes.

## Time of day

`SunCycle.swift` ports the six `SUN_KEYS` entries and the smoothstep
interpolation from `trail.ts`, producing light colour, light direction,
hemisphere colours, and fog tint for a `day` value in 0..1.

| Screen | `day` |
|---|---|
| Welcome | 0.20 (early morning) |
| Login | 0.46 (`DAY_STILL`) |
| MyQRCode, ForestBlank | 0.46 |
| Home | `0.14 + 0.64 × (n / total)` |

The 0.14–0.78 window is `DAY_FROM`/`DAY_TO` from `lib/dayCycle.ts`: outside it,
both ends are too dark to read overlaid UI. So Home runs dawn at zero bases to
golden late afternoon at every base — the same device the website's
registration form uses to make progress felt.

## The tree

`tree.usdz` sits in the clearing, centred, 6 units ahead of the camera.

Stage height: `h(n) = 0.7 × (5.0 / 0.7) ^ (n / total)`.

The website uses a fixed five-entry table `[0.7, 1.3, 2.2, 3.4, 5.0]`, a near
constant ratio of ~1.65. Porting it as a formula instead of a table matters
because **`total` comes from the database, not a constant**: admins can add and
remove checkpoints through the existing `/wbw/admin/checkpoints` endpoints, so
hardcoding 8 would break the tree the first time a base is edited on event day.
At `total = 8` the formula gives 0.70, 0.90, 1.14, 1.46, 1.87, 2.39, 3.06,
3.91, 5.00.

Growth lerps toward the target (website uses `dt * 1.7`) so the tree visibly
rises rather than snapping. Wind sway uses the website's amplitude falloff,
`amp = 0.05 / (1 + h × 0.8)` — saplings sway, mature trees barely move. Both
animations stop under Reduce Motion.

Four grass tufts around the base are baked into `forest.usdz`; they never
scale, so they do not need to be separate.

## Data flow

### New SUS endpoint

`GET /wbw/me/progress` (participant role):

```json
{
  "total": 8,
  "checked_in": [
    { "checkpoint_id": 1, "name": "วิหารพระเจ้าล้านทอง", "sequence": 1,
      "at": "2026-08-29T09:12:03Z" }
  ]
}
```

```sql
SELECT c.checkpoint_id, c.name, c.sequence, ci.server_received_at
FROM check_in ci
JOIN checkpoint c USING (checkpoint_id)
WHERE ci.participant_id = $1 AND c.requires_checkin
ORDER BY c.sequence;
```

`total` is `SELECT count(*) FROM checkpoint WHERE requires_checkin`, computed
per request.

Go placement: query in `internal/repository/wbw_checkpoint_repository.go` (it
already owns checkpoint reads), new `internal/service/wbw_progress_service.go`
and `internal/handler/wbw_progress_handler.go`, route registered inside the
participant-authenticated block in `cmd/main.go`.

### iOS store

`CheckinProgressStore` mirrors `ProfileStore`: `@MainActor`,
`ObservableObject`, `load(token:)`, published progress, plus a `UserDefaults`
cache so the tree is the right size on launch without waiting for the network.

**The cache key must be namespaced by `Config.backend`.** Each backend has its
own `checkpoint_id` space; a shared key means switching backends silently
renders the wrong tree with no error and no log — the same failure mode the
chat cursor already hit (`docs/sus-test-backend.md`).

Loaded on `MainTabView.task` alongside the profile, and again when
`scenePhase` becomes `.active`. Realtime growth at scan time is spec 2.

## Lifecycle and performance

The website gates its render loop with `frameloop={active ? "always" :
"never"}`. The app gates on the same idea. Rendering **and** CoreMotion stop
when:

- `scenePhase != .active`
- the selected tab does not use the scene (Map, SU RUN, Group)
- the full-screen chat overlay is open
- the logged-in user is staff or admin — `RootView` shows `StaffScanView`,
  which paints an opaque `Color.wbwInk` and a camera preview over everything

The Map tab already runs MapLibre on the GPU; leaving the forest rendering
behind it burns battery for something nobody can see. The staff case matters
more than it looks: staff hold the scanner open for hours on event day.

First load parses the USDZ from the bundle, which is not free. The Welcome
splash already covers that window. While loading, the screen shows the deep
forest green the website uses (`forestdeep`), never white.

## Failure handling

| Failure | Behaviour |
|---|---|
| USDZ fails to load | Fall back to `Image("bg_forest")`. The asset must not be deleted. |
| `/wbw/me/progress` fails | Use the cached value |
| No cache | Stage 0 — a sapling |
| Any of the above | No error UI. This is a background; the user did not come here to look at a tree. |

The `.forestBackground(day:)` modifier exists precisely so the implementation
behind it can be swapped without touching any of the five screens.

## Testing

- **Swift unit (`WBWTests`):** `h(n)` across several `total` values, `day(n)`,
  `sunAt()` against values read off the website's `SUN_KEYS` table, and that
  the progress cache key actually differs per `Config.backend`.
- **Go unit:** the progress query with no check-ins, some check-ins, and a
  checkpoint deleted after a check-in referenced it.
- **Screenshots:** simulator at stages 0 / 4 / 8 via a debug launch argument
  `-uitestProgress N`, following the existing `uitestTab` / `uitestChat`
  pattern.
- **Not automated:** whether the scene looks good (human judgement), and the
  gyroscope (the simulator has no motion sensors, so it needs a physical device
  pointed at a LAN backend — see `docs/sus-test-backend.md`).
