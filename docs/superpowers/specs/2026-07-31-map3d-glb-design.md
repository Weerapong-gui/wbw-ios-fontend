# Map Tab — Replace MapLibre with 3D GLB Model (maps3d.io export)

- **Date:** 2026-07-31
- **Status:** **ถูกแทนที่แล้วตั้งแต่ 2026-08-07** ด้วย `2026-08-07-map3d-usdz-design.md`
  ซึ่งทำเรื่องเดียวกันด้วยไฟล์ต้นทางคนละตัว (usdz ที่แปลงเสร็จแล้ว แทน GLB บนไดรฟ์นอกที่หายไป)
  เนื้อหาที่เหลือของไฟล์นี้ไม่แก้ เป็นบันทึกของตอนนั้น อย่าใช้เป็นคำสั่ง
- **Source asset:** `/Volumes/Untitled/MAP/maps3d-glb-2026-07-18_16-47-29/`
  (`.glb` 15 MB, `.blend` 20 MB, `.maps3d.json` settings)

## Context

The Map tab (`MapScreen.swift`, hosted at `MainTabView.swift:24`) currently
renders a live MapLibre satellite map with 3D terrain, bounded to the event
area. The user exported a stylized 3D model of the event area from maps3d.io
(buildings, roads, water, land cover, trees on real terrain) and wants that
model to **replace the Map tab entirely**.

Model facts (from `maps3d.json`):

- Area: hexagon, bounding box **SW 20.02371, 99.88272 / NE 20.06727, 99.92288**
- Projection **EPSG:3857**, `exportAbsoluteCoordinates: false` (local origin),
  `elevationExaggeration: 1`
- Imagery: `satlas-superes-2023` → attribution required: Satlas (Allen
  Institute for AI). Buildings/roads/water included → also
  "© OpenStreetMap contributors".

Deployment target is **iOS 18.0**, so RealityKit `RealityView` with built-in
camera controls is available. SceneKit is deprecated (WWDC25) — not used.

## Goal

A native 3D map screen on the Map tab:

1. **View the model** — orbit + pinch-zoom via RealityKit camera controls;
   initial camera tilted (~55°) like the old MapLibre camera.
2. **POI markers** — hardcoded list (name, lat/lng); pin + always-facing-camera
   label; tap shows a small callout card with the POI name.
3. **User location** — blue dot on the model tracking GPS; hidden when the
   user is outside the model's bounding box or permission is denied.
4. **Attribution** — small overlay text: "Satlas · Allen AI ·
   © OpenStreetMap contributors".

## Non-Goals (YAGNI)

- No live map tiles, no MapLibre — the dependency is removed.
- No POI data from the SUS backend (hardcoded list; backend later if needed).
- No routing/navigation, no search, no AR mode.
- No runtime model download — USDZ ships in the app bundle.
- No changes to the SUS/Node backend.

## Approach (decided)

**RealityKit `RealityView` + one-time offline GLB→USDZ conversion.**
Alternatives considered and rejected: SceneKit + GLTFKit2 (SceneKit
deprecated, extra dependency), WKWebView + three.js (non-native, JS bridge
complexity).

### 1. Asset pipeline (one-time, outside the app)

1. Convert the GLB to USDZ: try Reality Converter first; if materials break,
   open the `.blend` in Blender and export USDZ from there.
2. Visually verify textures/materials with Quick Look on macOS **before**
   writing app code — this is the main risk, so it goes first.
3. Bundle the USDZ (~15 MB) as an app resource.
4. Embed the `maps3d.json` bounding box + projection as Swift constants.

### 2. Files

| File | Role |
|---|---|
| `Map3DScreen.swift` (new) | `RealityView` loading the USDZ, `.realityViewCameraControls(.orbit)`, attribution overlay, marker callout card |
| `Map3DGeo.swift` (new) | lat/lng → EPSG:3857 → model-local coordinates. Linear map from the model's real bounding box (measured via `visualBounds` at load) to the json bounding box |
| `Map3DMarkers.swift` (new) | Hardcoded POI list: name, lat/lng, tint |
| `MainTabView.swift` | `MapScreen()` → `Map3DScreen()` |
| `MapScreen.swift` | Deleted; MapLibre removed from `project.yml`, project regenerated with xcodegen |

### 3. Markers & user location

- Marker entity = pin mesh + `BillboardComponent` text label +
  `InputTargetComponent`/`CollisionComponent` for tap.
- **Y (height) placement:** generate a static collision mesh from the model
  asynchronously at load, then raycast straight down per marker. If collision
  generation is too slow or fails on the 15 MB mesh, fall back to a manually
  tuned constant Y per marker.
- User location: `CLLocationManager` (when-in-use). Blue-dot entity updated on
  location changes via the same geo mapping. Outside bbox → hidden. Permission
  denied → no dot, screen otherwise fully functional.
  `NSLocationWhenInUseUsageDescription` added to `Info.plist` if missing.

### 4. Error handling

- USDZ load failure → message + retry button, no crash.
- Location errors are silent (dot hidden).

### 5. Testing

- Unit tests (`WBWTests`): geo conversion — the four bbox corners + center
  must land on the model bounding box corners/center within tolerance.
- Visual verification in the simulator (screenshots): model renders, camera
  controls work, markers sit on terrain, attribution visible.

## Risks

1. **USDZ conversion quality** (main risk) — mitigated by doing conversion +
   visual check first, with the Blender path as fallback.
2. **Collision mesh cost** on a 15 MB model — mitigated by async generation
   and the manual-Y fallback.
3. **Bbox mismatch with old map:** the GLB area (lng 99.883–99.923) sits east
   of the old MapLibre bounds (99.855–99.910). Markers/GPS use the GLB bbox;
   the old bounds die with `MapScreen.swift`.
