# DOI-APP — Missing Screens (QR, SU RUN, Ranking)

- **Date:** 2026-07-24
- **Status:** Approved (design), pending implementation plan
- **Figma:** `EKkcnLzTFz8zGjtO8ay70U` (DOI-APP)

## Context

The WBW iOS app (SwiftUI, theme "DOI-APP") already implements most screens in
the DOI-APP Figma: Welcome, Login, Home, Map, Group, Chat, Settings,
Profile/Ticket (`TicketView`), and Medical ID (`MedicalIdView`). Three Figma
screens have no counterpart in the app. This work adds those three and leaves
every existing screen untouched.

## Goal

Build the three missing screens to match the Figma layout:

1. **My QR Code** (Figma node `16:229`) — the participant's own check-in QR.
   Real data (`me.qrToken`).
2. **SU RUN** (Figma node `163:36`) — step/activity dashboard. UI only, mock data.
3. **SU RUN RANKING** (Figma node `179:59`) — leaderboard. UI only, mock data.

Screens 2 and 3 are drawn dark in Figma; per the request they are built in
**light mode first** (dark mode deferred — Settings already has a dark-mode
toggle for later).

## Non-Goals (YAGNI)

- No real step counting (HealthKit / CMPedometer), no run session, no backend
  sync, no real leaderboard data — SU RUN and Ranking use mock constants.
- No dark mode for the new screens (light first).
- No restyling or behavior change to existing screens beyond the minimal
  navigation edits in §5.
- No changes to the SUS/Node backend.

## Design Principles

- **Native Liquid Glass.** Any surface the Figma renders as liquid glass
  (floating buttons, translucent panels, the QR scan frame's chrome, the
  self-rank pill) uses the native SwiftUI Liquid Glass API — never a faux
  `.ultraThinMaterial`/blur imitation. The deployment target is iOS 18 but the
  glass API is iOS 26, so glass is applied behind `if #available(iOS 26, *)`
  with a `.regularMaterial` fallback for older systems (§6). The native
  `TabView` already renders its bar as Liquid Glass on iOS 26 automatically and
  is left as-is.
- **Light palette from the existing theme.** Reuse `Color` extensions in
  `Config.swift`: background `wbwCream` / white, text `wbwInk`, accents
  `wbwGreen` (primary) and `wbwGold` (highlight). Keep the Figma layout and
  spacing; invert only the color scheme (dark → light).
- **Match existing patterns.** Follow `TicketView` for CoreImage code
  generation, `ProfileStore`/`Session` for the current user, and the existing
  view file conventions (one screen per file, Thai doc comments).

## 1. My QR Code (`MyQRCodeView.swift`, new)

Replaces the `ForestBlank()` placeholder in `MainTabView` Tab 4 (the QR tab,
`role: .search`).

- Background: `bg_forest` image, `scaledToFill`, `ignoresSafeArea`.
- Title "My QR Code" centered near the top.
- QR image generated from `me.qrToken` via `CIFilter.qrCodeGenerator`
  (mirrors `TicketView.barcode(_:)`; add a sibling `static func qr(_:) -> UIImage?`).
  Render `interpolation(.none)`, white QR on a rounded card, framed by the
  Figma's corner-bracket scan frame (a `Shape` drawing four L brackets).
- If `me.qrToken` is nil (not loaded), show the same neutral placeholder
  rectangle `TicketView` uses; `.task` loads the profile via
  `ProfileStore.load(token:)` when `me == nil`.
- As a tab root it needs no back button (the Figma frame's back chevron is
  dropped — it existed only because the mock was a standalone frame).

## 2. SU RUN (`SURunView.swift`, new — light)

Root of Tab 2 (replaces Notifications; icon `figure.run`), wrapped in a
`NavigationStack` so Ranking can push.

Layout mirrors Figma `163:36`, recolored light:

- Header: "SUSU RUN" wordmark/logo text (placeholder text logo — no asset yet).
- Self-rank pill (glass): `1ˢᵗ  BANLANG · ADT` on the left, a `RANKING ›`
  button on the right that pushes `SURunRankingView`.
- Four stat tiles (white cards, green accent icons), 2×2:
  - Total steps — `1,555,500`
  - Total distance — `480 km.`
  - Activity Time — `80 hr.`
  - Cal burn — `75,000 Cal`
- A "MAP" block (large card, bottom) — placeholder; tapping it is a no-op for
  now (a future revision may switch to the Map tab). State this in a code comment.
- "Start now!" primary button (glass / `.glassProminent` on iOS 26) — no-op
  placeholder (no run session yet).

All numbers come from `SURunMock` (§7). As a tab root, SU RUN has no back button.

## 3. SU RUN RANKING (`SURunRankingView.swift`, new — light)

Pushed from SU RUN via `NavigationStack` (system back button).

Layout mirrors Figma `179:59`, recolored light:

- Title "RANKING".
- Self-standing banner (glass pill): `1ˢᵗ  You on the podium`.
- Leaderboard rows from `SURunMock.leaderboard` — each row: rank (`1ˢᵗ`,
  `2ⁿᵈ`, …), name, faculty code, step count, and a right-aligned green
  **gradient bar** (`wbwGreen` → lighter) whose width scales to the row's steps
  relative to the top entry. Dark text on the light bar.

## 4. Mock data (`SURunMock.swift`, new)

A plain Swift enum/struct with static constants — the single source for the
placeholder numbers so both screens agree:

```
struct SURunStat { let steps, distanceKm, activityHr, calBurn ... }  // display strings
struct RankRow { let rank: Int; let name: String; let faculty: String; let steps: Int }
enum SURunMock {
  static let selfStat = ...           // 1,555,500 / 480 km / 80 hr / 75,000 Cal
  static let selfRankFaculty = "ADT"; static let selfName = "BANLANG"
  static let leaderboard: [RankRow] = [
    (1, "BANLANG",      "ADT", 1_200_000),
    (2, "WEERAPONG",    "ADT", 1_000_000),
    (3, "MANATSANAN",   "SOM",   900_000),
    (4, "KANTIMA",      "SOM",   500_000),
    (5, "PATCHARAPOND", "SOM",   500_000),
    (6, "CHINAVORN",    "SOM",   100_000),
    (7, "THANANYA",     "SOM",    90_000),
    (8, "PHATTARANAREE","CSC",         3),
  ]
}
```

(The Figma mock double-labels a "4th" row; the list above renumbers 1–8 for a
self-consistent placeholder.)

## 5. Navigation changes

### `MainTabView.swift` (modify)
- Tab 2: replace `NotificationsView(...)` + `.badge(...)` with `SURunView()`,
  label `Image(systemName: "figure.run")`.
- Add `@State private var showNotifications = false`.
- Present notifications independent of tabs:
  `.fullScreenCover(isPresented: $showNotifications) { NotificationsView(store: noti, token: session.token ?? "") }`.
- Change the push-tap handler: `.onReceive(...openNotificationsTab)` sets
  `showNotifications = true` instead of `tab = 2`.
- Keep the existing `@StateObject noti` (still loaded in `.task` for the badge).

### `HomeView.swift` (modify — minimal)
- Add a bell button with an unread badge in the header (near the existing
  greeting/avatar), styled as native glass.
- The bell triggers notifications. Inject what Home needs:
  `HomeView(noti: noti, onOpenNotifications: { showNotifications = true })`
  — Home reads `noti.unreadCount` for the badge and calls the closure on tap.
- No other Home layout change.

This keeps Notifications fully functional (manual bell + push-tap both present
`NotificationsView`) after it loses its tab slot.

## 6. Liquid Glass helper (`GlassSurface.swift`, new)

A `ViewModifier` + `View` extension so glass is applied consistently and only
where iOS 26 supports it:

```
extension View {
  @ViewBuilder func glassSurface<S: Shape>(_ shape: S) -> some View {
    if #available(iOS 26, *) { self.glassEffect(.regular, in: shape) }
    else { self.background(.regularMaterial, in: shape) }
  }
}
```

- Glass buttons ("Start now!", `RANKING ›`, bell): `.buttonStyle(.glass)` /
  `.glassProminent` on iOS 26, a styled `Capsule` fallback below 26 (guarded).
- Group adjacent glass shapes in `GlassEffectContainer` (iOS 26) per Apple
  guidance where two or more glass surfaces sit together.
- Do not touch the `TabView` bar — it is native glass already.

## 7. Files

- **New:** `WBW/MyQRCodeView.swift`, `WBW/SURunView.swift`,
  `WBW/SURunRankingView.swift`, `WBW/SURunMock.swift`, `WBW/GlassSurface.swift`.
- **Modify:** `WBW/MainTabView.swift`, `WBW/HomeView.swift`.
- New files are added to the `WBW` target automatically (XcodeGen `sources:
  - WBW`); run `xcodegen generate` after adding them.

## 8. Testing

- A SwiftUI `#Preview` for each new screen (light appearance), so layout is
  verifiable in Xcode canvas without a full run.
- One unit test in `WBWTests` for the QR generator helper: a non-empty token
  produces a non-nil `UIImage`; an empty token returns nil (matching the
  `TicketView` barcode helper's contract).
- Build green: `xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`.
- Manual smoke on the iPhone 17 simulator (iOS 26.5): QR tab shows the code,
  Tab 2 shows SU RUN, `RANKING ›` pushes the leaderboard, the Home bell opens
  Notifications, and glass surfaces render as Liquid Glass.

## 9. Open Items / Future

- Real step tracking, backend sync, and a real leaderboard replace the mock
  data in a later phase (see the project's SUS integration watch-items).
- Dark mode for these screens once the light versions are approved.
- "Start now!" and the "MAP" block are placeholders until the run feature lands.

## Acceptance Criteria

- Three new screens render in light mode matching the Figma layout/spacing.
- My QR Code shows a scannable QR generated from `me.qrToken` (placeholder when
  absent).
- Tab 2 is SU RUN (`figure.run`); `RANKING ›` pushes the leaderboard.
- Notifications remain reachable via the Home bell and via push-tap.
- Glass surfaces use native Liquid Glass on iOS 26 with a material fallback
  below; the app still builds against the iOS 18 deployment target.
- Existing screens are unchanged except the minimal edits in §5.
