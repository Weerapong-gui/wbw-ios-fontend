# DOI-APP Missing Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the three DOI-APP screens the app lacks — My QR Code (real data), SU RUN and SU RUN Ranking (UI-only, mock data, light mode) — and re-route Notifications so it survives losing its tab.

**Architecture:** Three new SwiftUI screens plus one shared Liquid-Glass helper. My QR Code replaces the `ForestBlank()` placeholder in the QR tab and renders a QR from `me.qrToken`. SU RUN takes the tab slot currently held by Notifications (`figure.run` icon), wrapped in a `NavigationStack` that pushes Ranking. Notifications moves to a bell button on Home plus a sheet presented on push-tap. All new glass surfaces use the native iOS 26 Liquid Glass API guarded for the iOS 18 deployment target, mirroring the existing `GlassRing` in `HomeView.swift`.

**Tech Stack:** SwiftUI, iOS 18 target (glass guarded to iOS 26), CoreImage (QR), XcodeGen, XCTest.

## Global Constraints

- Deployment target is **iOS 18.0**; every Liquid Glass call (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) MUST be behind `if #available(iOS 26.0, *)` with an `.ultraThinMaterial` fallback — mirror the existing `GlassRing` in `WBW/HomeView.swift:65`.
- Colors come only from the existing theme in `WBW/Config.swift`: `wbwCream`, `wbwInk`, `wbwGold`, `wbwGreen`. Do not invent new named colors.
- New screens are **light mode only** (dark deferred).
- Do not change any existing screen except `MainTabView.swift` (tab swap + notifications route) and `HomeView.swift` (bell). Leave all other views byte-unchanged.
- New `.swift` files under `WBW/` are picked up by XcodeGen (`sources: - WBW`); run `xcodegen generate` after adding files.
- Build check: `xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`. Test/run: `-destination 'platform=iOS Simulator,name=iPhone 17'` (iOS 26.5, the available booted simulator). Builds may take minutes — use a long Bash timeout (up to 600000 ms).
- Figma (fileKey `EKkcnLzTFz8zGjtO8ay70U`): My QR Code `16:229`, SU RUN `163:36`, Ranking `179:59`. Use these only to refine spacing/detail; the code below is the source of truth for structure and the light palette.

---

### Task 1: My QR Code screen + glass helper + QR generator

Add the shared glass helper, a QR generator with a unit test, the My QR Code screen, and wire it into the QR tab (replacing the blank placeholder).

**Files:**
- Create: `WBW/GlassSurface.swift`, `WBW/MyQRCodeView.swift`
- Modify: `WBW/MainTabView.swift:36` (the `Tab(value: 4, role: .search) { ForestBlank() }` line)
- Test: `WBWTests/QRCodeTests.swift`

**Interfaces:**
- Consumes: `Session`, `ProfileStore`, `Me` (existing). `Me.qrToken: String?`.
- Produces: `enum QRCode { static func image(from: String) -> UIImage? }`; `extension View { func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View }`; `struct MyQRCodeView: View`.

- [ ] **Step 1: Write the failing QR-generator test**

Create `WBWTests/QRCodeTests.swift`:

```swift
import XCTest
@testable import WBW

final class QRCodeTests: XCTestCase {
    func testTokenProducesImage() {
        XCTAssertNotNil(QRCode.image(from: "ebbbf619f27d509fd1d880d1"))
    }
    func testEmptyStringReturnsNil() {
        XCTAssertNil(QRCode.image(from: ""))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: compile failure — `cannot find 'QRCode' in scope`.

- [ ] **Step 3: Create the glass helper `WBW/GlassSurface.swift`**

```swift
import SwiftUI

extension View {
    /// พื้นผิว Liquid Glass เนทีฟ (iOS 26) · fallback .ultraThinMaterial สำหรับ < 26
    /// อ้างอิงแพทเทิร์นเดียวกับ GlassRing ใน HomeView
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }
}
```

- [ ] **Step 4: Create `WBW/MyQRCodeView.swift` (QR generator + screen)**

```swift
import SwiftUI
import CoreImage.CIFilterBuiltins

/// สร้าง QR จาก token (แพทเทิร์นเดียวกับ barcode ใน TicketView)
enum QRCode {
    static func image(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(string.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// My QR Code — QR ประจำตัวสำหรับเช็คอิน (Figma 16:229) · พื้นป่า + กรอบสแกน
struct MyQRCodeView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var profile: ProfileStore
    private var me: Me? { profile.me }

    var body: some View {
        ZStack {
            Image("bg_forest").resizable().scaledToFill().ignoresSafeArea()
            VStack(spacing: 28) {
                Text("My QR Code")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                qrCard
                Spacer()
            }
        }
        .task { if me == nil, let t = session.token { await profile.load(token: t) } }
    }

    private var qrCard: some View {
        ZStack {
            if let token = me?.qrToken, let img = QRCode.image(from: token) {
                Image(uiImage: img).resizable().interpolation(.none).scaledToFit()
                    .padding(28)
                    .frame(width: 300, height: 300)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24).fill(.white)
                    .frame(width: 300, height: 300)
                    .overlay(ProgressView())
            }
        }
        .overlay(ScanFrame().stroke(.white, lineWidth: 6).frame(width: 340, height: 340))
    }
}

/// กรอบสแกนมุม L 4 มุม
struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len = rect.width * 0.18
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        p.move(to: CGPoint(x: corners[0].x, y: corners[0].y + len)); p.addLine(to: corners[0]); p.addLine(to: CGPoint(x: corners[0].x + len, y: corners[0].y))
        p.move(to: CGPoint(x: corners[1].x - len, y: corners[1].y)); p.addLine(to: corners[1]); p.addLine(to: CGPoint(x: corners[1].x, y: corners[1].y + len))
        p.move(to: CGPoint(x: corners[2].x, y: corners[2].y - len)); p.addLine(to: corners[2]); p.addLine(to: CGPoint(x: corners[2].x + len, y: corners[2].y))
        p.move(to: CGPoint(x: corners[3].x - len, y: corners[3].y)); p.addLine(to: corners[3]); p.addLine(to: CGPoint(x: corners[3].x, y: corners[3].y - len))
        return p
    }
}

#Preview { MyQRCodeView().environmentObject(Session()).environmentObject(ProfileStore()) }
```

Note: if `Session()` / `ProfileStore()` have no no-arg init, drop the `.environmentObject(...)` chain from the `#Preview` and just write `#Preview { MyQRCodeView() }`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `Test Suite 'QRCodeTests' passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Wire My QR Code into the QR tab**

In `WBW/MainTabView.swift`, replace the placeholder tab line (currently `Tab(value: 4, role: .search) { ForestBlank() } label: { Image(systemName: "qrcode") }`) with:

```swift
                Tab(value: 4, role: .search) { MyQRCodeView() } label: { Image(systemName: "qrcode") }
```

Leave the `ForestBlank` struct definition in place (it is still referenced by other code paths if any; removing it is out of scope).

- [ ] **Step 7: Build green**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/GlassSurface.swift WBW/MyQRCodeView.swift WBW/MainTabView.swift WBWTests/QRCodeTests.swift
git commit -m "feat: My QR Code screen (real qrToken) + native glass helper"
```

---

### Task 2: SU RUN Ranking screen + mock data

Add the mock data source and the leaderboard screen (light mode, glass podium banner, green gradient bars). Verifiable standalone via its `#Preview`.

**Files:**
- Create: `WBW/SURunMock.swift`, `WBW/SURunRankingView.swift`

**Interfaces:**
- Consumes: `glassSurface(_:)` from Task 1; `Color.wbwCream/wbwInk/wbwGold/wbwGreen`.
- Produces: `struct RankRow`, `enum SURunMock`, `struct SURunRankingView: View`.

- [ ] **Step 1: Create `WBW/SURunMock.swift`**

```swift
import Foundation

struct RankRow: Identifiable {
    let rank: Int
    let name: String
    let faculty: String
    let steps: Int
    var id: Int { rank }
}

/// ข้อมูลจำลอง SU RUN / RANKING (UI-only; แทนด้วยข้อมูลจริงเฟสหน้า)
enum SURunMock {
    static let selfName = "BANLANG"
    static let selfFaculty = "ADT"
    static let totalSteps = "1,555,500"
    static let totalDistance = "480 km."
    static let activityTime = "80 hr."
    static let calBurn = "75,000 Cal"

    static let leaderboard: [RankRow] = [
        RankRow(rank: 1, name: "BANLANG",       faculty: "ADT", steps: 1_200_000),
        RankRow(rank: 2, name: "WEERAPONG",     faculty: "ADT", steps: 1_000_000),
        RankRow(rank: 3, name: "MANATSANAN",    faculty: "SOM", steps:   900_000),
        RankRow(rank: 4, name: "KANTIMA",       faculty: "SOM", steps:   500_000),
        RankRow(rank: 5, name: "PATCHARAPOND",  faculty: "SOM", steps:   500_000),
        RankRow(rank: 6, name: "CHINAVORN",     faculty: "SOM", steps:   100_000),
        RankRow(rank: 7, name: "THANANYA",      faculty: "SOM", steps:    90_000),
        RankRow(rank: 8, name: "PHATTARANAREE", faculty: "CSC", steps:         3),
    ]

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}
```

- [ ] **Step 2: Create `WBW/SURunRankingView.swift`**

```swift
import SwiftUI

/// SU RUN RANKING — leaderboard (Figma 179:59) · light mode
struct SURunRankingView: View {
    private let rows = SURunMock.leaderboard
    private var maxSteps: Int { rows.map(\.steps).max() ?? 1 }

    var body: some View {
        ZStack {
            Color.wbwCream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Text("RANKING")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Color.wbwInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        Text("1st")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.wbwGold, in: Capsule())
                        Text("You on the podium")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.wbwInk)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassSurface(Capsule())
                    .padding(.bottom, 6)

                    ForEach(rows) { row in rankRow(row) }
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rankRow(_ row: RankRow) -> some View {
        let frac = max(0.12, Double(row.steps) / Double(maxSteps))
        return HStack(spacing: 10) {
            Text(SURunMock.ordinal(row.rank))
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.wbwInk)
                .frame(width: 34, alignment: .leading)
            Text(row.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.wbwInk)
            Text(row.faculty).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.5))
            Spacer(minLength: 6)
            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    Capsule().fill(Color.wbwGreen.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.wbwGreen, Color.wbwGreen.opacity(0.6)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * frac)
                    Text("\(row.steps.formatted()) STEPS")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.trailing, 10)
                }
            }
            .frame(width: 170, height: 44)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { SURunRankingView() }
}
```

- [ ] **Step 3: Build green**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`. (No unit test — this is a visual screen; verify layout via the Xcode `#Preview` canvas.)

- [ ] **Step 4: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/SURunMock.swift WBW/SURunRankingView.swift
git commit -m "feat: SU RUN Ranking screen (light, mock leaderboard)"
```

---

### Task 3: SU RUN dashboard + tab swap + Notifications re-route

Add the SU RUN dashboard (pushes Ranking), put it in Tab 2 in place of Notifications, and keep Notifications reachable via a Home bell and a push-tap sheet.

**Files:**
- Create: `WBW/SURunView.swift`
- Modify: `WBW/MainTabView.swift`, `WBW/HomeView.swift`

**Interfaces:**
- Consumes: `SURunMock`, `SURunRankingView` (Task 2); `glassSurface(_:)` (Task 1); `NotiStore`, `NotificationsView`, `Session` (existing); `Notification.Name.openNotificationsTab` (existing).
- Produces: `struct SURunView: View`.

- [ ] **Step 1: Create `WBW/SURunView.swift`**

```swift
import SwiftUI

/// SU RUN — แดชบอร์ดกิจกรรม (Figma 163:36) · light mode · UI-only (mock)
struct SURunView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.wbwCream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        Text("SUSU RUN")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(Color.wbwInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)

                        selfRankPill
                        statGrid
                        mapBlock
                        startButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var selfRankPill: some View {
        HStack(spacing: 10) {
            Text("1st")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4).background(Color.wbwGold, in: Capsule())
            Text(SURunMock.selfName).font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.wbwInk)
            Text(SURunMock.selfFaculty).font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
            Spacer()
            NavigationLink {
                SURunRankingView()
            } label: {
                HStack(spacing: 4) { Text("RANKING"); Image(systemName: "chevron.right") }
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wbwGreen)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassSurface(RoundedRectangle(cornerRadius: 16))
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile("figure.walk", "Total steps", SURunMock.totalSteps)
            statTile("map", "Total distance", SURunMock.totalDistance)
            statTile("clock", "Activity Time", SURunMock.activityTime)
            statTile("flame", "Cal burn", SURunMock.calBurn)
        }
    }

    private func statTile(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.wbwGreen)
            Text(value).font(.system(size: 26, weight: .heavy)).foregroundStyle(Color.wbwInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    // placeholder: บล็อก MAP — no-op จนกว่าฟีเจอร์วิ่งจริงจะมา
    private var mapBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18).fill(Color.wbwGreen.opacity(0.12)).frame(height: 150)
            Text("MAP").font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color.wbwGreen.opacity(0.5)).padding(16)
        }
    }

    // placeholder: ยังไม่มี run session
    private var startButton: some View {
        Button { } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right")
                Text("Start now!").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Color.wbwGreen, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview { SURunView() }
```

- [ ] **Step 2: Swap Tab 2 and re-route Notifications in `WBW/MainTabView.swift`**

Add a state property near the other `@State` declarations:

```swift
    @State private var showNotifications = false
```

Change the Home tab to pass the noti store:

```swift
                Tab(value: 0) { HomeView(noti: noti) } label: { Image(systemName: "house.fill") }
```

Replace the Notifications tab (`Tab(value: 2) { NotificationsView(...) } ... .badge(noti.unreadCount)`) with the SU RUN tab:

```swift
                Tab(value: 2) { SURunView() } label: { Image(systemName: "figure.run") }
```

Change the push-tap handler from switching tabs to presenting the sheet:

```swift
            .onReceive(NotificationCenter.default.publisher(for: .openNotificationsTab)) { _ in
                showNotifications = true   // noti ไม่มี tab แล้ว → เปิดเป็น sheet
            }
```

Add the presentation modifier on the same `ZStack`/`TabView` chain (next to `.animation(...)`):

```swift
            .sheet(isPresented: $showNotifications) {
                NotificationsView(store: noti, token: session.token ?? "")
            }
```

Leave the `@StateObject private var noti = NotiStore()` and its `.task` load intact (still needed for the badge count).

- [ ] **Step 3: Add the Notifications bell to `WBW/HomeView.swift`**

Add a stored property so Home can read the unread count:

```swift
    @ObservedObject var noti: NotiStore
```

In the header `HStack` (the greeting row), after the trailing `Spacer()`, add the bell button:

```swift
                Button {
                    NotificationCenter.default.post(name: .openNotificationsTab, object: nil)
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.wbwInk)
                        .frame(width: 44, height: 44)
                        .modifier(GlassRing())
                        .overlay(alignment: .topTrailing) {
                            if noti.unreadCount > 0 {
                                Text("\(noti.unreadCount)")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(5).background(Color.red, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
```

(`GlassRing` is the `private struct` already defined at the bottom of `HomeView.swift` — reuse it. `noti.unreadCount` is the same `Int` the tab badge used.)

- [ ] **Step 4: Build green**

Run: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`. If the compiler reports `HomeView(noti:)` used elsewhere without the argument, fix that call site (only `MainTabView` constructs `HomeView`).

- [ ] **Step 5: Manual smoke (simulator)**

Build/install/launch on the iPhone 17 simulator and confirm: Tab 2 shows SU RUN with the `figure.run` icon; `RANKING ›` pushes the leaderboard; the QR tab shows the QR; the Home bell shows the unread badge and opens Notifications as a sheet. (Interactive login uses the test account `6939990001` / `SmokeTest123!`.)
Expected: all four behaviors work; glass surfaces render as Liquid Glass on iOS 26.

- [ ] **Step 6: Commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/SURunView.swift WBW/MainTabView.swift WBW/HomeView.swift
git commit -m "feat: SU RUN tab (pushes Ranking); move Notifications to Home bell"
```

---

## Self-Review Notes

- **Spec coverage:** My QR Code §1 → Task 1; SU RUN §2 → Task 3; Ranking §3 → Task 2; mock §4 → Task 2; nav changes §5 → Task 3; glass helper §6 → Task 1; files §7 → all; testing §8 → Task 1 unit test + build/preview/manual across tasks.
- **Type consistency:** `QRCode.image(from:)`, `glassSurface(_:interactive:)`, `RankRow`, `SURunMock`, `SURunRankingView`, `SURunView`, `HomeView(noti:)` are defined once and consumed with matching signatures. `noti.unreadCount` (Int) reused from the old tab badge.
- **Deferred detail:** exact Figma spacing/detail (nodes 16:229 / 163:36 / 179:59) may be refined via `get_design_context`; the code above compiles and captures the layout + light palette + native glass.
