# Group Join Screen — Liquid Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** เปลี่ยนหน้าจับกลุ่มจากพื้นครีมทึบ + การ์ดขาวทึบ ให้เป็นการ์ด Liquid Glass ลอยบนฉากป่า 3D ตัวเดียวกับที่ Home / Login / QR ใช้ พร้อมหัวข้อใหญ่สองบรรทัดและปุ่มเข้ากลุ่มขาวทึบตัวหนังสือเขียว

**Architecture:** แตะไฟล์เดียว `WBW/GroupJoinView.swift` ไม่สร้างไฟล์ใหม่ ใช้ของที่มีอยู่แล้วสองชิ้น — `.glassSurface(_:interactive:)` จาก `WBW/GlassSurface.swift` (Liquid Glass เนทีฟ iOS 26 · fallback `.ultraThinMaterial` สำหรับ 18-25) และ `.forestBackground(day:)` จาก `WBW/Scene3D/ForestSceneHost.swift` ตรรกะ join / ค้นหา / จัดการ error เดิมคงไว้ครบ เปลี่ยนเฉพาะชั้นการแสดงผล

**Tech Stack:** SwiftUI, iOS 18.0 deployment target, XcodeGen, XCTest

**Spec:** `docs/superpowers/specs/2026-08-06-group-join-glass-design.md`

## Global Constraints

- **iOS deployment target คือ 18.0** — เรียก `glassEffect` ตรง ๆ ไม่ได้ ต้องผ่าน `.glassSurface(_:interactive:)` ซึ่ง gate ด้วย `#available(iOS 26.0, *)` ไว้แล้ว **ห้ามปลอม glass ด้วย blur เอง**
- สีมาจาก `WBW/Config.swift` เท่านั้น: `wbwCream`, `wbwInk`, `wbwGold`, `wbwGreen` บวก `.white` กับ `.white.opacity(...)` **ห้ามคิดสีใหม่ตั้งชื่อเอง**
- คอมเมนต์ Swift ในโปรเจกต์นี้เป็นภาษาไทย เขียนตาม
- ข้อความบนหน้าจอเป็นภาษาไทยทั้งหมด (mockup เป็นอังกฤษ แต่ทั้งแอปเป็นไทย)
- **ห้ามแตะ** `GroupStore`, `APIClient`, `GroupHomeView`, `GroupMembersView`, `GroupChatView` หรือ endpoint ใด ๆ
- ไม่มีไฟล์ใหม่ในแผนนี้ จึงไม่ต้องรัน `xcodegen generate` เพราะไฟล์ใหม่ — แต่ยังต้องรันก่อน build อยู่ดีตามขั้นตอนปกติของโปรเจกต์
- iOS build: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild -scheme WBW -destination 'generic/platform=iOS Simulator' build`
- iOS test: `cd /Users/park/wbw-ios-fontend && xcodegen generate && xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17'`
- Xcode build ใช้เวลาเป็นนาที ตั้ง Bash timeout ได้ถึง `600000` ms

## เรื่อง TDD — อ่านก่อนเริ่ม

**แผนนี้ไม่มี test cycle แบบ red-green** เพราะงานทั้งหมดเป็นการเปลี่ยนภาพ ไม่มีตรรกะใหม่ให้เทส เทสในโปรเจกต์เป็น unit test ล้วน 133 ตัว ไม่มี UI test ไม่มี snapshot test

**ห้ามแต่งเทสขึ้นมาให้ดูมี TDD** — เทสที่ assert ว่า `Color.white == Color.white` ไม่ได้พิสูจน์อะไรและเป็นหนี้ที่ต้องมาดูแลต่อ

วงจรของทุก task ในแผนนี้จึงเป็น:

1. แก้โค้ด
2. `xcodebuild test` — ต้องได้ **133/133 เท่าเดิม** (กันพัง ไม่ใช่พิสูจน์ว่าสวย)
3. รันบนซิม เก็บภาพ **ดูด้วยตาจริง**
4. commit

ข้อ 3 ไม่ใช่พิธีกรรม — ความเสี่ยงหลักของงานนี้ (Task 1) มองไม่เห็นจาก build log เลย build ผ่านแต่จอขาวโพลนได้

---

## Environment setup (ทำครั้งเดียว ก่อน Task 1)

- [ ] **Step A: ยืนยันว่าซิมบูตอยู่**

```bash
xcrun simctl list devices booted
```

Expected: เห็น `iPhone 17 (...) (Booted)` ถ้าไม่มี บูตด้วย `xcrun simctl boot "iPhone 17"` แล้ว `open -a Simulator`

- [ ] **Step B: ขอ JWT จาก production**

แอปตอนนี้ตั้ง `Config.backend = .susProd` (`WBW/Config.swift:44`) → `https://api.studentunion.social/wbw`

```bash
curl -s -X POST https://api.studentunion.social/wbw/auth/login \
  -H 'content-type: application/json' \
  -d '{"username":"<username>","password":"<password>"}'
```

Expected: JSON ที่มี field `token` เก็บค่านั้นไว้เป็น `<jwt>`

**ถามผู้ใช้เพื่อขอบัญชี** — บัญชีบน production ที่รู้จักคือ `6939999999` (participant) แต่รหัสผ่านไม่ได้อยู่ใน repo และ **ยังไม่รู้ว่าบัญชีนี้อยู่ในกลุ่มแล้วหรือยัง** อย่าเดา อย่าลองสุ่มรหัส

- [ ] **Step C: ยืนยันว่าบัญชีนั้นยังไม่อยู่ในกลุ่ม**

```bash
curl -s https://api.studentunion.social/wbw/me -H "Authorization: Bearer <jwt>"
```

Expected: field `group_id` เป็น `null`

**นี่เป็นเงื่อนไขบังคับ** — `GroupTabView.swift:12` แสดง `GroupJoinView` เฉพาะตอน `profile.me?.groupId == nil` ถ้าบัญชีอยู่ในกลุ่มแล้วจะได้ `GroupHomeView` แทน แล้วจะถ่ายภาพหน้าที่กำลังแก้ไม่ได้เลย ถ้า `group_id` ไม่ใช่ null ให้หยุดแล้วถามผู้ใช้ว่าจะออกจากกลุ่มหรือใช้บัญชีอื่น

- [ ] **Step D: build + install + launch เข้าแท็บกลุ่มตรง ๆ**

```bash
cd /Users/park/wbw-ios-fontend
xcodegen generate
xcodebuild -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-build build
xcrun simctl install booted /tmp/wbw-build/Build/Products/Debug-iphonesimulator/WBW.app
xcrun simctl launch booted th.ac.mfu.wbwSwift \
  -uitestToken <jwt> -uitestUser <username> -uitestRole participant -uitestTab 3
```

`-uitestTab 3` = แท็บกลุ่ม (0 Home · 1 Map · 2 SU RUN · 3 Group · 4 QR) hook อยู่ที่ `MainTabView.swift:41` และ `Session.swift:36` ไม่มี `idb` หรือเครื่องมือแตะจอในเครื่องนี้ การ launch ด้วย argument จึงเป็นทางเดียวที่เข้าจอชั้นในแบบไม่ต้องกดเองได้

- [ ] **Step E: เก็บภาพ "ก่อนแก้" ไว้เทียบ**

```bash
xcrun simctl io booted screenshot /tmp/group-join-before.png
```

เปิดดูด้วย Read tool ต้องเห็นหน้าจับกลุ่มพื้นครีม การ์ดขาว ปุ่มทอง ถ้าเห็นอย่างอื่นแปลว่า Step C ผิด กลับไปแก้ก่อน

---

## File structure

| ไฟล์ | สถานะ | หน้าที่ |
|---|---|---|
| `WBW/GroupJoinView.swift` | **แก้** | หน้าจับกลุ่มทั้งหน้า — ไฟล์เดียวที่งานนี้แตะ |
| `WBW/GlassSurface.swift` | อ่านอย่างเดียว | ให้ `.glassSurface(_:interactive:)` |
| `WBW/Scene3D/ForestSceneHost.swift` | อ่านอย่างเดียว | ให้ `.forestBackground(day:)` และ `ForestSceneHost.tabBarClearance` (= 89) |
| `WBW/Config.swift` | อ่านอย่างเดียว | ให้ `Color.wbwGreen` (`#40916C`), `Color.wbwInk`, `Color.wbwGold` |

---

## Task 1: พื้นหลังฉากป่า 3D

นี่คือ task ที่มีความเสี่ยงจริงข้อเดียวของแผน ทำก่อนและทำลำพัง — ถ้าไม่ผ่าน แผนที่เหลือเปลี่ยนรูปหมด (ต้องถอด `NavigationStack`) จึงต้องรู้ผลก่อนจะไปแตะสีอะไร

**Files:**
- Modify: `WBW/GroupJoinView.swift:3` (ลบ `private let bg`)
- Modify: `WBW/GroupJoinView.swift:14-47` (`body`)

**Interfaces:**
- Consumes: `.forestBackground(day:plantStep:plantTotal:bottomClearance:)` จาก `WBW/Scene3D/ForestSceneHost.swift:196` · `ForestMath.dayStill`
- Produces: ไม่มี — task ถัดไปไม่พึ่งอะไรจาก task นี้นอกจากพื้นหลังที่ตั้งแล้ว

**ทำไมใช้ค่าพวกนี้:**
- `day: ForestMath.dayStill` — เหมือน `LoginView.swift:85` และ `MyQRCodeView.swift:36` (จอที่ไม่ผูกกับความคืบหน้าเช็คอิน) ตรึงความสว่างไว้คงที่
- ไม่ส่ง `plantStep` → `nil` → ไม่มีต้นไม้ มีแค่ `HomeView` ที่ส่งต้นไม้
- ไม่ส่ง `bottomClearance` → ค่าเริ่มต้น `ForestSceneHost.tabBarClearance` (89) ถูกแล้วเพราะหน้านี้อยู่ใต้แท็บบาร์ลอย

- [ ] **Step 1: ลบค่าสีครีมที่ไม่ใช้แล้ว**

ลบบรรทัด 3 ทั้งบรรทัด:

```swift
private let bg = Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255)
```

- [ ] **Step 2: เปลี่ยน body ให้ใช้ฉากป่า**

แทน `body` ทั้งตัว (บรรทัด 14-47) ด้วย:

```swift
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if !groups.matchedPeople.isEmpty { peopleSection }
                            ForEach(groups.filteredGroups) { g in
                                GroupCard(
                                    group: g,
                                    previews: groups.indexMembers(groupId: g.groupId),
                                    joining: joining == g.groupId,
                                    onJoin: { Task { await join(g) } }
                                )
                            }
                            if groups.loaded && groups.filteredGroups.isEmpty && groups.matchedPeople.isEmpty {
                                Text("ไม่พบกลุ่ม").foregroundStyle(.secondary).padding(.top, 40)
                            }
                        }
                        .padding(16)
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.white)
                        .padding(12).background(.red.opacity(0.9), in: Capsule())
                        .padding(.bottom, 30).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .forestBackground(day: ForestMath.dayStill)
            .navigationBarHidden(true)
            .task { if !groups.loaded { await groups.load(token: session.token ?? "") } }
        }
    }
```

สิ่งที่เปลี่ยนมีสามอย่างเท่านั้น: `bg.ignoresSafeArea()` หายไปจากบรรทัดแรกของ `ZStack`, เพิ่ม `.frame(maxWidth: .infinity, maxHeight: .infinity)` (ให้ฉากยึดเต็มจอเหมือน `HomeView.swift:78`), เพิ่ม `.forestBackground(day: ForestMath.dayStill)` ที่เหลือคัดลอกมาเหมือนเดิมทุกตัวอักษร

- [ ] **Step 3: build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-build build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: รันเทสกันพัง**

```bash
cd /Users/park/wbw-ios-fontend && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -6
```

Expected: `Executed 133 tests, with 0 failures` และ `** TEST SUCCEEDED **`

ถ้าจำนวนไม่ใช่ 133 ให้หยุด — แปลว่าไปแตะอย่างอื่นโดยไม่ตั้งใจ

- [ ] **Step 5: ดูด้วยตา — นี่คือขั้นที่ตัดสิน task นี้**

```bash
xcrun simctl install booted /tmp/wbw-build/Build/Products/Debug-iphonesimulator/WBW.app
xcrun simctl launch booted th.ac.mfu.wbwSwift \
  -uitestToken <jwt> -uitestUser <username> -uitestRole participant -uitestTab 3
xcrun simctl io booted screenshot /tmp/group-join-01-bg.png
```

เปิด `/tmp/group-join-01-bg.png` ด้วย Read tool

Expected: **เห็นฉากป่า 3D เป็นพื้นหลัง** การ์ดยังขาวทึบอยู่ (ยังไม่แก้ใน task นี้) แต่พื้นหลังรอบ ๆ การ์ดต้องเป็นป่า ไม่ใช่ขาวโพลนหรือครีม

- [ ] **Step 6: ถ้าเห็นป่า → ข้ามไป Step 7 · ถ้าเห็นขาวทึบ → ไล่แผนถอย**

`NavigationStack` ไม่เคยถูกใช้ร่วมกับ `forestBackground` ที่ไหนในแอปนี้มาก่อน (`HomeView`, `LoginView`, `MyQRCodeView`, `ForestBlank` ไม่มีจอไหนมี `NavigationStack`) ถ้าโดนบัง ลองตามลำดับ หยุดที่ข้อแรกที่ได้ผล แล้วถ่ายภาพยืนยันใหม่ทุกครั้ง:

**ถอยขั้น 1** — เติมสองบรรทัดนี้ต่อจาก `.navigationBarHidden(true)`:

```swift
            .toolbarBackground(.hidden, for: .navigationBar)
            .scrollContentBackground(.hidden)
```

**ถอยขั้น 2** — ถอด `NavigationStack` ออก เปลี่ยนการกดดูสมาชิกจาก `NavigationLink` เป็น `.sheet` `GroupMembersView` เป็นจอปลายทางที่ไม่ push ต่อ จึงไม่เสียความสามารถอะไร ต้องแก้สามจุด:

ก) ถอด `NavigationStack { ... }` ออกจาก `body` (เหลือ `ZStack` เป็นตัวนอกสุด) และลบ `.navigationBarHidden(true)`

ข) เพิ่ม state ที่ `GroupJoinView`:

```swift
    /// กลุ่มที่กำลังเปิดดูสมาชิกอยู่ — nil = ไม่ได้เปิด
    @State private var memberSheet: GroupSummary?
```

ค) ที่ `GroupCard` เปลี่ยน `NavigationLink { ... } label: { ... }` เป็น `Button { onOpenMembers() } label: { ... }` แล้วเพิ่ม `let onOpenMembers: () -> Void` เป็น property ตัวที่ห้าของ struct ฝั่งเรียกส่ง `onOpenMembers: { memberSheet = g }` และแขวน sheet ไว้ที่ `ZStack`:

```swift
            .sheet(item: $memberSheet) { g in
                GroupMembersView(groupId: g.groupId, groupNumber: g.groupNumber)
            }
```

`.sheet(item:)` ต้องการ `GroupSummary` conform `Identifiable` — ยืนยันแล้วว่าใช่: `WBW/Models.swift:160` ประกาศ `struct GroupSummary: Codable, Identifiable` ใช้ได้เลยไม่ต้องเติม conformance

**ถ้าถอยถึงขั้น 2 ให้บันทึกไว้ในแผนนี้ใต้ task ว่าใช้ทางไหนและเพราะอะไร** แล้วบอกผู้ใช้ก่อนไป Task 2 เพราะโครงหน้าเปลี่ยนจากสเปก

- [ ] **Step 7: commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/GroupJoinView.swift
git commit -m "feat(group): หน้าจับกลุ่มใช้ฉากป่า 3D เป็นพื้นหลังแทนพื้นครีมทึบ"
```

---

## Task 2: หัวจอ — หัวข้อใหญ่ + ปุ่มกลับกระจก + ช่องค้นหากระจก

**Files:**
- Modify: `WBW/GroupJoinView.swift:50-68` (`header`)

**Interfaces:**
- Consumes: `.glassSurface(_:interactive:)` จาก `WBW/GlassSurface.swift:7` · `groups.search` (`@Published var search: String` ใน `GroupStore`)
- Produces: ไม่มี

- [ ] **Step 1: แทน header ทั้งตัว**

แทนบรรทัด 49-68 (คอมเมนต์ `// แถวบน: ย้อนกลับ + ค้นหา` รวมด้วย) ด้วย:

```swift
    // หัวจอสามชั้น: ปุ่มกลับ · หัวข้อใหญ่ · ช่องค้นหา
    // เดิมปุ่มกลับกับค้นหาอยู่แถวเดียวกัน แยกออกเพราะหัวข้อใหญ่ต้องการความกว้างเต็ม
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassSurface(Circle(), interactive: true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("เลือก")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
                Text("กลุ่มของคุณ")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.7))
                // placeholder เริ่มต้นของ TextField ใช้สีระบบที่จางเกินไปบนพื้นเข้ม จนอ่านแทบไม่ออก
                // วาง Text ของตัวเองทับตอนช่องว่างแทน แล้วส่ง "" เป็น placeholder จริงให้ TextField
                ZStack(alignment: .leading) {
                    if groups.search.isEmpty {
                        Text("ค้นหากลุ่ม หรือ ชื่อเพื่อน")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    TextField("", text: $groups.search)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14).frame(height: 40)
            .glassSurface(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }
```

- [ ] **Step 2: build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-build build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: รันเทสกันพัง**

```bash
cd /Users/park/wbw-ios-fontend && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -6
```

Expected: `Executed 133 tests, with 0 failures`

- [ ] **Step 4: ดูด้วยตา รวมทั้งตอนพิมพ์ค้นหา**

```bash
xcrun simctl install booted /tmp/wbw-build/Build/Products/Debug-iphonesimulator/WBW.app
xcrun simctl launch booted th.ac.mfu.wbwSwift \
  -uitestToken <jwt> -uitestUser <username> -uitestRole participant -uitestTab 3
xcrun simctl io booted screenshot /tmp/group-join-02-header.png
```

เปิดภาพด้วย Read tool ตรวจสี่ข้อ:
1. หัวข้อ "เลือก / กลุ่มของคุณ" อ่านออกชัด ไม่จมไปกับป่า
2. ปุ่มย้อนกลับเป็นวงกระจก ไม่ใช่วงขาวทึบ
3. ช่องค้นหาเป็นแคปซูลกระจก และเห็นข้อความ "ค้นหากลุ่ม หรือ ชื่อเพื่อน" อ่านออก
4. การ์ดกลุ่มยังขาวทึบอยู่ (ถูกแล้ว — Task 3 ค่อยแก้)

**ถ้าหัวข้อจมไปกับส่วนสว่างของฉาก** (สเปก §3.4) ใส่ scrim ใต้ข้อความ — เติมต่อจาก `.padding(.bottom, 12)` ของ `header`:

```swift
        .background(
            LinearGradient(colors: [.black.opacity(0.35), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
```

แล้วถ่ายภาพยืนยันใหม่

- [ ] **Step 5: commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/GroupJoinView.swift
git commit -m "feat(group): หัวจอจับกลุ่ม — หัวข้อใหญ่สองบรรทัด ปุ่มกลับและช่องค้นหาเป็นกระจก"
```

---

## Task 3: การ์ดกลุ่ม — กระจก + สีที่อ่านออกบนพื้นเข้ม

**Files:**
- Modify: `WBW/GroupJoinView.swift:102-155` (`private struct GroupCard`)

**Interfaces:**
- Consumes: `.glassSurface(_:interactive:)` · `Color.wbwGreen` (`WBW/Config.swift:55`, `#40916C`) · `GroupSummary` (`.groupNumber`, `.memberCount`, `.capacity`, `.isFull`, `.groupId`) · `GroupMemberIndex` (`.firstName`) · `ProfileAvatar(name:photoUrl:size:)`
- Produces: ไม่มี

**สิ่งที่ต้องไม่เปลี่ยน:** เนื้อในการ์ดทุกชิ้นอยู่ครบ — วงกลมเลขกลุ่ม, ชื่อกลุ่ม, avatar สมาชิกซ้อน 4 คน, `45/50`, ปุ่มเข้ากลุ่ม, แตะที่ตัวการ์ดไปหน้าสมาชิก เปลี่ยนเฉพาะสีและพื้น

- [ ] **Step 1: แทน GroupCard ทั้ง struct**

แทนบรรทัด 102 ถึงท้ายไฟล์ด้วย:

```swift
/// การ์ดกลุ่ม 1 กลุ่ม — กระจกลอยบนฉากป่า ตัวหนังสือขาวทั้งใบ
private struct GroupCard: View {
    let group: GroupSummary
    let previews: [GroupMemberIndex]
    let joining: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // แตะดูสมาชิก
            NavigationLink { GroupMembersView(groupId: group.groupId, groupNumber: group.groupNumber) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        // เดิมเป็น wbwGold ที่ opacity 0.15 — บนกระจกใสทับป่าเขียวแทบมองไม่เห็น
                        // เปลี่ยนเป็นขาวจาง ๆ เรื่องอ่านออก ไม่ใช่เรื่องรสนิยม
                        Circle().fill(.white.opacity(0.20)).frame(width: 46, height: 46)
                        Text("\(group.groupNumber)").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("กลุ่ม \(group.groupNumber)").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        HStack(spacing: 6) {
                            avatarPreview
                            Text("\(group.memberCount)/\(group.capacity)")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // ปุ่มเข้ากลุ่ม — ขาวทึบตัดจากกระจก ตัวหนังสือเขียวป่า
            Button(action: onJoin) {
                Group {
                    if joining { ProgressView().tint(Color.wbwGreen) }
                    else { Text(group.isFull ? "เต็ม" : "เข้ากลุ่ม").font(.system(size: 13, weight: .semibold)) }
                }
                .foregroundStyle(group.isFull ? Color.white.opacity(0.6) : Color.wbwGreen)
                .frame(width: 74, height: 34)
                .background(group.isFull ? Color.white.opacity(0.25) : Color.white, in: Capsule())
            }
            .disabled(group.isFull || joining)
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 16))
    }

    private var avatarPreview: some View {
        HStack(spacing: -8) {
            ForEach(previews.prefix(4)) { m in
                ProfileAvatar(name: m.firstName ?? "", photoUrl: nil, size: 22)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
            }
        }
    }
}
```

- [ ] **Step 2: build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-build build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: รันเทสกันพัง**

```bash
cd /Users/park/wbw-ios-fontend && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -6
```

Expected: `Executed 133 tests, with 0 failures`

- [ ] **Step 4: ดูด้วยตา**

```bash
xcrun simctl install booted /tmp/wbw-build/Build/Products/Debug-iphonesimulator/WBW.app
xcrun simctl launch booted th.ac.mfu.wbwSwift \
  -uitestToken <jwt> -uitestUser <username> -uitestRole participant -uitestTab 3
xcrun simctl io booted screenshot /tmp/group-join-03-cards.png
```

เปิดภาพด้วย Read tool ตรวจ:
1. การ์ดโปร่ง เห็นป่าทะลุหลัง ไม่ใช่แผ่นขาวทึบและไม่ใช่แผ่นเทาตัน
2. ชื่อกลุ่มกับ `45/50` อ่านออกทั้งบนส่วนสว่างและส่วนมืดของฉาก
3. เลขในวงกลมอ่านออก
4. ปุ่ม "เข้ากลุ่ม" ขาวทึบ ตัวหนังสือเขียว ตัดจากการ์ดชัด
5. ถ้ามีกลุ่มที่เต็มในลิสต์ ปุ่ม "เต็ม" ต้องดูปิดใช้งานชัดเจนแต่ยังอ่านออก

**ถ้าในลิสต์ไม่มีกลุ่มเต็มเลย** ให้บันทึกไว้ว่ายังไม่ได้ยืนยันสถานะเต็มด้วยตา แล้วยกไปยืนยันใน Task 5 อย่ารายงานว่าตรวจครบทั้งที่ไม่เห็น

- [ ] **Step 5: commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/GroupJoinView.swift
git commit -m "feat(group): การ์ดกลุ่มเป็นกระจก ตัวหนังสือขาว ปุ่มเข้ากลุ่มขาวทึบตัวเขียว"
```

---

## Task 4: ส่วนที่เหลือบนหน้า — ผลค้นหาคน ข้อความว่าง ระยะล่างลิสต์

ถ้าไม่ทำ task นี้ จะเหลือของขาวทึบโดดอยู่กลางจอกระจกตอนค้นหาเจอคน และการ์ดใบสุดท้ายจะโดนแท็บบาร์ทับ

**Files:**
- Modify: `WBW/GroupJoinView.swift` — `peopleSection`, บรรทัด `"ไม่พบกลุ่ม"`, `.padding(16)` ของ `LazyVStack`

**Interfaces:**
- Consumes: `.glassSurface(_:)` · `ForestSceneHost.tabBarClearance` (`static let = 89`, `WBW/Scene3D/ForestSceneHost.swift:137`) · `groups.matchedPeople` (`.fullName`, `.firstName`, `.groupNumber`)
- Produces: ไม่มี

- [ ] **Step 1: แทน peopleSection ทั้งตัว**

```swift
    // ผลค้นหาคน
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("คนที่พบ").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            ForEach(groups.matchedPeople) { p in
                HStack(spacing: 10) {
                    ProfileAvatar(name: p.firstName ?? "", photoUrl: nil, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.fullName).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                        Text("กลุ่ม \(p.groupNumber)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                }
                .padding(12)
                .glassSurface(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
```

- [ ] **Step 2: แก้ข้อความ "ไม่พบกลุ่ม" ให้อ่านออกบนพื้นเข้ม**

ใน `body` เปลี่ยน:

```swift
                                Text("ไม่พบกลุ่ม").foregroundStyle(.secondary).padding(.top, 40)
```

เป็น:

```swift
                                Text("ไม่พบกลุ่ม").foregroundStyle(.white.opacity(0.75)).padding(.top, 40)
```

- [ ] **Step 3: เพิ่มระยะล่างให้การ์ดใบสุดท้ายพ้นแท็บบาร์**

ใน `body` เปลี่ยน `.padding(16)` ของ `LazyVStack` เป็นสองบรรทัด:

```swift
                        .padding(16)
                        // ใช้ค่าเดียวกับที่ฉากป่าใช้กันเครดิตโมเดล จะได้ไม่มีเลขวิเศษสองตัวที่หมายถึงระยะเดียวกัน
                        .padding(.bottom, ForestSceneHost.tabBarClearance)
```

- [ ] **Step 4: build**

```bash
cd /Users/park/wbw-ios-fontend && xcodegen generate && \
xcodebuild -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/wbw-build build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: รันเทสกันพัง**

```bash
cd /Users/park/wbw-ios-fontend && \
xcodebuild test -scheme WBW -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -6
```

Expected: `Executed 133 tests, with 0 failures`

- [ ] **Step 6: ดูด้วยตา — ต้องเห็น peopleSection จริง**

`peopleSection` โผล่เฉพาะตอน `groups.matchedPeople` ไม่ว่าง ซึ่งต้องมีคำค้นที่ตรงชื่อคน ถ่ายภาพหน้าปกติก่อน:

```bash
xcrun simctl install booted /tmp/wbw-build/Build/Products/Debug-iphonesimulator/WBW.app
xcrun simctl launch booted th.ac.mfu.wbwSwift \
  -uitestToken <jwt> -uitestUser <username> -uitestRole participant -uitestTab 3
xcrun simctl io booted screenshot /tmp/group-join-04-list.png
```

ตรวจว่าการ์ดใบสุดท้ายเลื่อนลงไปสุดแล้วไม่โดนแท็บบาร์ทับ

จากนั้นต้องเห็น `peopleSection` ด้วยตา — ไม่มีเครื่องมือแตะจอในเครื่องนี้ พิมพ์ในช่องค้นหาแบบ headless ไม่ได้ **ให้ขอผู้ใช้พิมพ์ชื่อคนในช่องค้นหาบนซิมแล้วบอกให้ถ่ายภาพ** หรือถ้าผู้ใช้ไม่สะดวก ให้บันทึกไว้ตรง ๆ ว่ายังไม่ได้ยืนยัน `peopleSection` ด้วยตา **ห้ามรายงานว่าตรวจแล้ว**

- [ ] **Step 7: commit**

```bash
cd /Users/park/wbw-ios-fontend
git add WBW/GroupJoinView.swift
git commit -m "feat(group): ผลค้นหาคนและข้อความว่างเข้าชุดกระจก + ระยะล่างพ้นแท็บบาร์"
```

---

## Task 5: ยืนยันข้อที่เหลือ — fallback iOS 18 และ claim ฉากตอน push

task นี้ไม่มีโค้ดใหม่เป็นค่าตั้งต้น มีไว้ปิดสองความเสี่ยงที่สเปกสั่งให้ยืนยัน (§3.2, §3.3) ถ้าพบปัญหาถึงจะมีโค้ดแก้

**Files:**
- Modify (เฉพาะถ้าพบปัญหา): `WBW/GroupJoinView.swift` หรือ `WBW/GlassSurface.swift`

- [ ] **Step 1: ยืนยันว่าฉากป่าไม่หายตอนเข้าหน้าสมาชิก (สเปก §3.2)**

ฉากป่าใช้ระบบ claim เจ้าของทีละจอ (`claimScene()` / `releaseScene()`) ถ้า SwiftUI ยิง `onDisappear` ของ `GroupJoinView` ตอน push ป่าจะถูกปล่อยคืนแล้วหายระหว่างดูสมาชิก

ต้องแตะการ์ดเพื่อ push ซึ่ง headless ทำไม่ได้ **ขอให้ผู้ใช้แตะการ์ดกลุ่มบนซิม** แล้ว:

```bash
xcrun simctl io booted screenshot /tmp/group-join-05-members.png
```

Expected: หน้าสมาชิกโผล่ **โดยฉากป่ายังอยู่** (หรืออย่างน้อยไม่มีจอดำ/ขาววาบ)

ถ้าป่าหาย ทางแก้คือให้ `GroupMembersView` claim ต่อ — เติม `.forestBackground(day: ForestMath.dayStill)` ที่ตัวนอกสุดของ `GroupMembersView` คอมเมนต์ที่ `ForestSceneHost` ระบุว่า `onAppear` ของจอใหม่มาก่อน `onDisappear` ของจอเก่าเสมอ จึงส่งไม้ต่อได้โดยไม่มีช่องว่าง **แต่การแก้นี้แตะไฟล์นอกขอบเขตสเปก (§5 ระบุว่าไม่แตะ `GroupMembersView`) ต้องถามผู้ใช้ก่อน**

- [ ] **Step 2: ยืนยัน fallback `.ultraThinMaterial` (สเปก §3.3) — อ่านข้อจำกัดก่อน**

```bash
xcrun simctl list runtimes | grep iOS
```

**เครื่องนี้มีแค่ runtime iOS 26.5 ตัวเดียว ไม่มี iOS 18** สเปก §4 เขียนไว้ว่าให้ "รันซ้ำบนซิมที่ตั้ง iOS 18" — ทำตามตัวอักษรไม่ได้ถ้าไม่โหลด runtime เพิ่ม (หลาย GB ผ่าน Xcode → Settings → Components)

มีสองทาง เลือกโดยถามผู้ใช้:

**ทาง ก — โหลด runtime iOS 18 มาจริง** ยืนยันได้ตรงที่สุด แต่ใช้เวลาและพื้นที่ดิสก์มาก

**ทาง ข — บังคับให้เดินสาย fallback บน iOS 26** แก้ `WBW/GlassSurface.swift` ชั่วคราวให้ข้ามสาขาเนทีฟ:

```swift
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        // ชั่วคราวเพื่อดู fallback — ต้อง revert ก่อน commit
        if false, #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(0.6), lineWidth: 1))
        }
    }
```

build + ถ่ายภาพ แล้ว **revert ไฟล์ทันที** ด้วย `git checkout WBW/GlassSurface.swift`

ทาง ข พิสูจน์ได้ว่า `.ultraThinMaterial` สุ่มสีฉากป่าติดหรือกลายเป็นแผ่นเทาเปล่า ซึ่งเป็นความเสี่ยงตัวจริงใน §3.3 แต่ **ไม่ได้พิสูจน์ว่าหน้าตาบน iOS 18 เหมือนกันเป๊ะ** เพราะ `.ultraThinMaterial` ของ iOS 26 กับ iOS 18 ไม่ใช่ของตัวเดียวกัน ต้องเขียนข้อจำกัดนี้ลงรายงานตรง ๆ ไม่ใช่บอกว่า "ยืนยัน iOS 18 แล้ว"

- [ ] **Step 3: ปิดข้อที่ค้างจาก Task 3 Step 4**

ถ้าตอน Task 3 ไม่เห็นกลุ่มที่เต็มในลิสต์ ให้หาให้เจอตอนนี้ — เลื่อนลิสต์ลงหรือค้นหาเลขกลุ่มที่รู้ว่าเต็ม ถ่ายภาพปุ่มสถานะ "เต็ม" ถ้าบน production ไม่มีกลุ่มเต็มเลยจริง ๆ ให้บันทึกว่ายังไม่ได้ยืนยันสถานะนี้ด้วยตา

- [ ] **Step 4: รวมภาพทั้งหมดรายงานผู้ใช้**

แนบภาพทุกใบที่เก็บมา พร้อมระบุชัดว่าอะไรยืนยันด้วยตาแล้วและอะไรยังไม่ได้:

- ลิสต์กลุ่มปกติ
- ผลค้นหาคน (`peopleSection`)
- กลุ่มที่เต็ม
- กำลังกดเข้ากลุ่ม (spinner)
- fallback material
- หน้าสมาชิกหลัง push

**ห้ามเขียนว่าเสร็จถ้ายังมีข้อไหนไม่ได้ยืนยัน** ให้บอกตรง ๆ ว่าข้อไหนค้างและเพราะอะไร

- [ ] **Step 5: commit ถ้ามีการแก้จาก Step 1-3**

```bash
cd /Users/park/wbw-ios-fontend
git status --short
# ถ้ามีไฟล์เปลี่ยน — ระบุไฟล์ตรง ๆ:
git add WBW/GroupJoinView.swift
git commit -m "fix(group): <สิ่งที่แก้จริงหลังยืนยันด้วยตา>"
```

**ห้ามใช้ `git add -A` หรือ `git add .`** ใน repo นี้มีงานที่ยังไม่ commit ของคนอื่นวางอยู่
(`docs/superpowers/plans/2026-08-06-sos.md` — แผน Emergency SOS 151k ที่ไม่เกี่ยวกับงานนี้)
`git add -A` จะกวาดมันเข้า commit ของเราไปด้วย ระบุไฟล์ทีละตัวเสมอ

ถ้าไม่มีอะไรต้องแก้ ข้าม step นี้ อย่า commit เปล่า

---

## Coverage against the spec

| หัวข้อในสเปก | Task |
|---|---|
| §1 ใช้ `glassSurface` / `forestBackground` ที่มีอยู่ | 1, 2, 3, 4 |
| §2.1 พื้นหลังฉากป่า | 1 |
| §2.2 หัวจอสามชั้น + placeholder อ่านออก | 2 |
| §2.3 การ์ดกระจก + ตารางสี + ปุ่มขาวตัวเขียว | 3 |
| §2.4 `peopleSection`, "ไม่พบกลุ่ม" | 4 |
| §2.5 ระยะล่างพ้นแท็บบาร์ | 4 |
| §3.1 `NavigationStack` ทับฉาก + แผนถอย 3 ขั้น | 1 Step 6 |
| §3.2 claim ฉากตอน push | 5 Step 1 |
| §3.3 fallback `.ultraThinMaterial` | 5 Step 2 |
| §3.4 scrim ใต้หัวข้อถ้าจม | 2 Step 4 |
| §3.5 รอยต่อ `GroupHomeView` — ไม่แก้โดยตั้งใจ | ไม่มี task (ตั้งใจ) |
| §4 เทส 133/133 ทุก task | 1-4 ทุก task |
| §4 ภาพ 4 สถานะ | 3, 4, 5 |
| §5 สิ่งที่ไม่ทำ | Global Constraints |
