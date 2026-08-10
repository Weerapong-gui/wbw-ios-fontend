# โควตาออกจากกลุ่ม — ฝั่ง Dashboard (su-wbw-website) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** admin เห็นสิทธิ์ออกจากกลุ่มคงเหลือของทุกคน กรองหาคนที่สิทธิ์หมด ปรับสิทธิ์รายคน
และอ่านประวัติเข้า/ออก/ปรับสิทธิ์ของคนนั้นได้

**Architecture:** ไม่มี endpoint ใหม่เลย — ทุกอย่างเดินบน `getParticipants` / `patchParticipant` /
`getParticipantDetail` ที่หน้านี้เรียกอยู่แล้ว งานคือเพิ่ม field ใน type แล้วแสดง/แก้ในจอเดิม

**Tech Stack:** Next.js (app router), TypeScript, Tailwind, ระบบ i18n ของ repo (`useT()` + `lib/i18n/dictionaries.ts`)

**Repo:** `~/Projects/su-wbw-website` (ไม่ใช่ repo ที่ไฟล์แผนนี้อยู่)

**ต้องทำก่อน:** แผน backend (`2026-08-09-group-leave-quota-backend.md`) Task 5–7 ต้องขึ้นเซิร์ฟเวอร์
ที่หน้านี้ชี้อยู่ ไม่งั้น `leave_quota` เป็น `undefined` ทุกแถวและช่องแก้ไขจะบันทึกไม่ติด

## Global Constraints

- ข้อความบนจอทุกอันต้องผ่าน `useT()` และมีทั้งภาษาไทยและอังกฤษใน `lib/i18n/dictionaries.ts`
  (ไทยประมาณบรรทัด 480, อังกฤษประมาณ 1106 — โครงสร้าง key ต้องเหมือนกันเป๊ะทั้งสองฝั่ง)
- ใช้คลาส Tailwind ที่ไฟล์นั้นใช้อยู่แล้วเท่านั้น (`text-muted`, `border-line`, `bg-card`,
  `text-forest`, `bg-danger/12`, `rounded-[20px]`) ห้ามใส่ค่าสีดิบ
- ช่วงค่าโควตาที่ยอมรับคือ 0–10 ตรงกับ validation ฝั่ง backend
- `npm run lint` **ห้ามเพิ่มปัญหาใหม่** — repo นี้ lint ไม่ผ่านอยู่ก่อนแล้ว (17 problems: 13 error /
  4 warning ณ 2026-08-10 วัดที่ `main` = `79cdadb`) การไล่แก้ของเดิมไม่ใช่งานของแผนนี้ ·
  วิธีตรวจ: รัน lint แล้วเทียบจำนวนกับ baseline ไฟล์ที่ตัวเองแตะต้องไม่มี error โผล่ใหม่
- `npx tsc --noEmit` ต้องผ่านสะอาด — เป็นตาข่ายเดียวที่จับ key i18n ขาดฝั่งใดฝั่งหนึ่งได้
- commit ภาษาไทย ขึ้นต้น `feat:` / `fix:` / `docs:` · **ห้าม `git add -A`**

## File Structure

| ไฟล์ | สถานะ | รับผิดชอบ |
|---|---|---|
| `lib/adminApi.ts` | แก้ | type ของ `leave_quota` และ `membership_log` |
| `lib/i18n/dictionaries.ts` | แก้ | ข้อความใหม่ทั้งไทยและอังกฤษ |
| `components/dashboard/Participants.tsx` | แก้ | คอลัมน์ + ตัวกรอง + ช่องแก้ไข + ไทม์ไลน์ในโมดัล |
| `components/dashboard/Logs.tsx` | แก้ | สีป้ายของ action `ปรับสิทธิ์ออกกลุ่ม` |

---

### Task 1: type + ข้อความ

**Files:**
- Modify: `lib/adminApi.ts:105-121` (`Participant`), `type ParticipantPatch`, `type ParticipantDetail`
- Modify: `lib/i18n/dictionaries.ts` (บล็อก `dash.participants` ทั้งไทยและอังกฤษ, บล็อก `dash.logs`)

**Interfaces:**
- Produces: `Participant.leave_quota: number` · `ParticipantPatch.leave_quota?: number` ·
  `ParticipantDetail.membership_log: MembershipLogEntry[]` · `type MembershipLogEntry = {action, group_id, group_number, quota_after, actor_name, created_at}`
- Produces (i18n): `t.dash.participants.colQuota`, `.quotaLabel`, `.quotaZeroOnly`, `.quotaRange`,
  `.historyHeading`, `.historyEmpty`, `.historyBy`, `.historySelf`, `.actionJoin`, `.actionLeave`, `.actionAdjust`

- [ ] **Step 1: เพิ่ม type ใน `lib/adminApi.ts`**

ใน `export type Participant` ต่อท้าย `blood_type`:
```ts
  leave_quota: number;
```

ใน `export type ParticipantPatch` เพิ่ม:
```ts
  leave_quota?: number;
```

เพิ่ม type ใหม่ก่อน `ParticipantDetail`:
```ts
/** หนึ่งบรรทัดของประวัติเข้า/ออก/ปรับสิทธิ์ · actor_name เป็น null แปลว่าผู้ใช้ทำเอง ไม่ใช่ admin */
export type MembershipLogEntry = {
  action: "join" | "leave" | "quota_adjust";
  group_id: number | null;
  group_number: number | null;
  quota_after: number;
  actor_name: string | null;
  created_at: string;
};
```

ใน `export type ParticipantDetail` เพิ่ม:
```ts
  leave_quota: number;
  membership_log: MembershipLogEntry[];
```

- [ ] **Step 2: เพิ่มข้อความไทย**

ใน `lib/i18n/dictionaries.ts` บล็อก `participants` ของภาษาไทย (ต่อจาก `colCheckin`):
```ts
      colQuota: "สิทธิ์ออกจากกลุ่ม",
      quotaLabel: "สิทธิ์ออกจากกลุ่ม (0–10)",
      quotaZeroOnly: "เฉพาะคนที่สิทธิ์หมด",
      quotaRange: "สิทธิ์ต้องอยู่ระหว่าง 0 ถึง 10",
      historyHeading: "ประวัติกลุ่ม",
      historyEmpty: "ยังไม่มีประวัติ",
      historyBy: (name: string) => `โดย ${name}`,
      historySelf: "ผู้เข้าร่วมทำเอง",
      actionJoin: "เข้ากลุ่ม",
      actionLeave: "ออกจากกลุ่ม",
      actionAdjust: "ปรับสิทธิ์",
```

- [ ] **Step 3: เพิ่มข้อความอังกฤษ**

บล็อกเดียวกันของภาษาอังกฤษ (ต่อจาก `colCheckin: "Check-in"`):
```ts
      colQuota: "Leave quota",
      quotaLabel: "Group-leave quota (0–10)",
      quotaZeroOnly: "Out of quota only",
      quotaRange: "Quota must be between 0 and 10",
      historyHeading: "Group history",
      historyEmpty: "No history yet",
      historyBy: (name: string) => `by ${name}`,
      historySelf: "By participant",
      actionJoin: "Joined",
      actionLeave: "Left",
      actionAdjust: "Quota changed",
```

- [ ] **Step 4: ตรวจว่า type ของ dictionary ยังตรงกันสองภาษา**

Run: `npx tsc --noEmit`
Expected: ไม่มี error · ถ้าขึ้น error ว่า key ขาดในฝั่งใดฝั่งหนึ่ง แปลว่าเติมไม่ครบ — เติมให้ครบ
(นี่คือกลไกที่กันข้อความหายไปภาษาเดียว)

- [ ] **Step 5: Commit**

```bash
git add lib/adminApi.ts lib/i18n/dictionaries.ts
git commit -m "feat(dashboard): type และข้อความของสิทธิ์ออกจากกลุ่ม"
```

---

### Task 2: คอลัมน์ + ตัวกรองในตาราง

**Files:**
- Modify: `components/dashboard/Participants.tsx:44-48` (state), `:59-66` (`filtered`), `:78-108` (แถบตัวกรอง), `:115-127` (`<thead>`), แถวใน `<tbody>`

**Interfaces:**
- Consumes: `Participant.leave_quota`, `t.dash.participants.colQuota`, `.quotaZeroOnly`
- Produces: ตารางมีคอลัมน์สิทธิ์ · `colSpan` ของแถวว่างเปลี่ยนจาก `10` เป็น `11`

- [ ] **Step 1: เพิ่ม state ตัวกรอง**

```tsx
  const [quotaZeroOnly, setQuotaZeroOnly] = useState(false); // คำถามจริงของ admin คือ "ใครติดล็อกบ้าง"
```

- [ ] **Step 2: ใส่เงื่อนไขใน `filtered`**

```tsx
      if (quotaZeroOnly && r.leave_quota !== 0) return false;
```
และเพิ่ม `quotaZeroOnly` เข้า dependency array ของ `useMemo`

- [ ] **Step 3: ปุ่มกรองข้าง ๆ ตัวเลือกสำนักวิชา**

```tsx
          <button
            type="button"
            onClick={() => setQuotaZeroOnly((v) => !v)}
            className={`rounded-full border px-4 py-2.5 text-sm transition-colors ${
              quotaZeroOnly
                ? "border-danger bg-danger/12 text-danger"
                : "border-line bg-card text-muted hover:text-ink"
            }`}
          >
            {t.dash.participants.quotaZeroOnly}
          </button>
```

- [ ] **Step 4: หัวคอลัมน์ + ช่องในแถว**

ใน `<thead>` ต่อจาก `colCheckin`:
```tsx
                <th className="px-4 py-3 font-medium">{t.dash.participants.colQuota}</th>
```

ในแถวข้อมูล ต่อจากช่องเช็คอิน:
```tsx
                  <td className="px-4 py-3">
                    <span
                      className={`rounded-full px-2.5 py-1 text-xs ${
                        r.leave_quota === 0 ? "bg-danger/12 text-danger" : "bg-forest/10 text-forest"
                      }`}
                    >
                      {r.leave_quota}
                    </span>
                  </td>
```

แก้ `colSpan={10}` ทั้งสองแห่ง (แถว loading และแถวว่าง) เป็น `colSpan={11}`

- [ ] **Step 5: ดูของจริง**

Run: `npm run dev` แล้วเปิด `http://localhost:3000/dashboard` ล็อกอินเป็น admin
Expected: คอลัมน์ "สิทธิ์ออกจากกลุ่ม" มีตัวเลขทุกแถว · กดปุ่มกรองแล้วเหลือเฉพาะแถวที่เป็น 0
· สลับภาษาเป็นอังกฤษแล้วหัวคอลัมน์เปลี่ยนตาม

- [ ] **Step 6: lint แล้ว commit**

```bash
npm run lint
git add components/dashboard/Participants.tsx
git commit -m "feat(dashboard): คอลัมน์สิทธิ์ออกกลุ่ม + ตัวกรองคนที่สิทธิ์หมด"
```

---

### Task 3: ปรับสิทธิ์ในโมดัลแก้ไข

**Files:**
- Modify: `components/dashboard/Participants.tsx:227-245` (`form` ใน `EditModal`), `:255-272` (`useEffect` โหลด detail), `:279-305` (`save`), ส่วนฟอร์มในโมดัล

**Interfaces:**
- Consumes: `ParticipantDetail.leave_quota`, `patchParticipant`
- Produces: บันทึกแล้ว `onSaved(updated)` พาค่าใหม่กลับไปอัปเดตแถวในตารางเอง (ทางเดิม ไม่ต้องแก้)

- [ ] **Step 1: เพิ่มค่าในฟอร์ม**

ใน `useState({...})` ของ `form` เพิ่ม:
```tsx
    leave_quota: String(participant.leave_quota ?? 0),
```

- [ ] **Step 2: ให้ detail ทับค่าเมื่อโหลดเสร็จ**

ใน `.then((d) => { setForm((f) => ({ ...f, ... }))})` เพิ่ม:
```tsx
          leave_quota: String(d.leave_quota),
```

- [ ] **Step 3: ช่องกรอกในฟอร์ม**

วางถัดจากช่องกลุ่ม (ให้สองเรื่องที่เกี่ยวกันอยู่ติดกัน):
```tsx
        <TextField
          label={t.dash.participants.quotaLabel}
          value={form.leave_quota}
          onChange={set("leave_quota")}
          type="number"
        />
```
(ถ้า `TextField` ใน `components/register/ui` ไม่รับ prop `type` ให้เพิ่ม prop นั้นแบบ optional
ส่งต่อลง `<input>` — เป็นการเพิ่มที่ไม่กระทบผู้ใช้เดิมเพราะค่า default คือ `"text"`)

- [ ] **Step 4: ตรวจช่วงค่าก่อนส่ง แล้วส่งไปกับ patch**

ใน `save()` ก่อน `setBusy(true)`:
```tsx
    const quota = Number(form.leave_quota);
    // เช็คฝั่งนี้ด้วยแม้ backend จะเช็คอยู่แล้ว — ผู้ใช้ควรเห็นข้อความทันทีที่พิมพ์ผิด
    // ไม่ต้องรอ round trip แล้วได้ error กลับมาแบบไม่ผูกกับช่องไหน
    if (!Number.isInteger(quota) || quota < 0 || quota > 10) {
      setError(t.dash.participants.quotaRange);
      return;
    }
```
แล้วใน object ที่ส่งเข้า `patchParticipant` เพิ่ม **แบบมีเงื่อนไข** (แก้ 2026-08-10 หลัง final review):

```tsx
        ...(quota !== loadedQuota ? { leave_quota: quota } : {}),
```

โดย `loadedQuota` คือค่าที่โหลดมาตอนเปิดโมดัล (เก็บไว้ใน state คู่กับ `form.leave_quota`)

**ห้ามส่งทุกครั้ง** — backend ถือว่า "มี key `leave_quota` ใน body = แอดมินสั่งปรับโควตา" แล้วเขียน
audit สองตาราง (`group_membership_log` action `quota_adjust` + `admin_log`) · ถ้าส่งไปด้วยทุกครั้ง
การแก้เบอร์โทรเฉย ๆ จะสร้างแถวประวัติปลอม และที่แย่กว่านั้นคือ `COALESCE($13, leave_quota)` จะเขียน
ค่าที่ค้างอยู่ในฟอร์มทับของจริง — โมดัลเปิดค้างตอนสิทธิ์ยังเป็น 1 แล้วผู้ใช้กดออกจากกลุ่มจนเหลือ 0
พอแอดมินกดบันทึก สิทธิ์จะกลับไปเป็น 1 โดยไม่มีใครตั้งใจ · แถม `membership_log` มี `LIMIT 10`
แถวประวัติจริงจะถูกแถวปลอมเบียดหายไป

- [ ] **Step 5: ทดสอบของจริงทั้งทางถูกและทางผิด**

เปิดโมดัลแก้ไขของบัญชีทดสอบ:
1. ใส่ `99` → กดบันทึก → ต้องขึ้น "สิทธิ์ต้องอยู่ระหว่าง 0 ถึง 10" และ**ไม่**ยิง request
   (ดูใน Network tab ว่าไม่มี PATCH)
2. ใส่ `2` → บันทึก → โมดัลปิด และตัวเลขในตารางเปลี่ยนเป็น 2 ทันทีโดยไม่ต้องรีเฟรช
3. รีเฟรชหน้า → ยังเป็น 2 (ยืนยันว่าเขียนลงฐานจริง ไม่ใช่แค่ state)

- [ ] **Step 6: lint แล้ว commit**

```bash
npm run lint
git add components/dashboard/Participants.tsx components/register/ui.tsx
git commit -m "feat(dashboard): admin ปรับสิทธิ์ออกกลุ่มรายคนได้"
```

---

### Task 4: ไทม์ไลน์ประวัติกลุ่มในโมดัล

**Files:**
- Modify: `components/dashboard/Participants.tsx` (ส่วน `{detail && (...)}` ที่แสดง consent tags)

**Interfaces:**
- Consumes: `ParticipantDetail.membership_log`, `t.dash.participants.history*`, `.action*`, `formatTs` จาก `lib/datetime`

- [ ] **Step 1: เพิ่มตัวช่วยแปลชื่อ action**

ใกล้ ๆ ตัวช่วยอื่นบนสุดของไฟล์:
```tsx
// ป้ายชื่อของแต่ละ action · ค่าที่ backend ส่งมาเป็นภาษาอังกฤษคงที่ (join/leave/quota_adjust)
// ตั้งใจ — ถ้าส่งเป็นข้อความไทยมา หน้าเว็บจะแปลเป็นภาษาอังกฤษไม่ได้เลย
const ACTION_LABEL = (t: Dict) => ({
  join: t.dash.participants.actionJoin,
  leave: t.dash.participants.actionLeave,
  quota_adjust: t.dash.participants.actionAdjust,
});
```

- [ ] **Step 2: เพิ่มบล็อกไทม์ไลน์**

ในบล็อก `{detail && (` ต่อจากแถว consent:
```tsx
              <div className="mt-6">
                <h4 className="text-sm font-semibold text-forestdeep">
                  {t.dash.participants.historyHeading}
                </h4>
                {detail.membership_log.length === 0 ? (
                  <p className="mt-2 text-sm text-muted">{t.dash.participants.historyEmpty}</p>
                ) : (
                  <ul className="mt-2 space-y-2">
                    {detail.membership_log.map((l, i) => (
                      <li key={i} className="flex items-start gap-3 text-sm">
                        <span
                          className={`mt-0.5 flex-none rounded-full px-2.5 py-1 text-xs ${
                            l.action === "leave" ? "bg-danger/12 text-danger" : "bg-forest/10 text-forest"
                          }`}
                        >
                          {ACTION_LABEL(t)[l.action]}
                        </span>
                        <div className="min-w-0 flex-1">
                          <p className="text-ink">
                            {l.group_number != null ? `${t.dash.participants.colGroup} ${l.group_number}` : "—"}
                            {" · "}
                            {t.dash.participants.colQuota} {l.quota_after}
                          </p>
                          <p className="mt-0.5 text-xs text-muted">
                            {l.actor_name
                              ? t.dash.participants.historyBy(l.actor_name)
                              : t.dash.participants.historySelf}
                          </p>
                        </div>
                        <span className="flex-none text-xs text-muted">
                          {formatTs(l.created_at, t.dash.locale)}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
```
เพิ่ม `import { formatTs } from "@/lib/datetime";` ถ้าไฟล์นี้ยังไม่มี

`key={i}` ใช้ index ได้เพราะรายการนี้อ่านอย่างเดียว ไม่มีการแทรก/ลบ/เรียงใหม่ในหน้า

- [ ] **Step 3: ทดสอบของจริง**

เปิดโมดัลของบัญชีที่เพิ่งถูกปรับสิทธิ์ใน Task 3 → ต้องเห็นบรรทัด "ปรับสิทธิ์" บนสุด พร้อมชื่อ admin
· ให้บัญชีทดสอบเข้า/ออกกลุ่มจากแอป แล้วเปิดโมดัลใหม่ → ต้องมีบรรทัด "เข้ากลุ่ม"/"ออกจากกลุ่ม"
ที่ระบุว่า "ผู้เข้าร่วมทำเอง"

- [ ] **Step 4: lint แล้ว commit**

```bash
npm run lint
git add components/dashboard/Participants.tsx
git commit -m "feat(dashboard): ไทม์ไลน์ประวัติเข้า/ออกกลุ่มในรายละเอียดผู้เข้าร่วม"
```

---

### Task 5: สีป้ายในหน้า Logs + ตรวจทั้งหน้า

**Files:**
- Modify: `components/dashboard/Logs.tsx:9-17` (`ACTION_TONE`)

- [ ] **Step 1: เพิ่ม tone**

```ts
  ปรับสิทธิ์ออกกลุ่ม: "bg-gold/12 text-gold",
```
(โทนเดียวกับ "แก้ไขผู้เข้าร่วม" — เป็นการแก้ข้อมูล ไม่ใช่การสร้างหรือลบ)

- [ ] **Step 2: ตรวจว่าโผล่จริง**

ปรับสิทธิ์ของใครสักคนอีกครั้ง แล้วเปิดหน้า Logs → บรรทัดบนสุดต้องเป็น action "ปรับสิทธิ์ออกกลุ่ม"
พร้อม detail รูปแบบ `693xxxxxxx → N ครั้ง` และมีสีทอง ไม่ใช่สีเทาของค่า default

- [ ] **Step 3: build จริง**

Run: `npm run build`
Expected: สำเร็จ ไม่มี type error (`npm run dev` ไม่จับ type error บางประเภทที่ build จับ)

- [ ] **Step 4: ตรวจสองภาษา**

สลับภาษาเป็นอังกฤษ แล้วเปิดหน้าผู้เข้าร่วม + โมดัลแก้ไข + หน้า Logs → ต้องไม่มีข้อความไทยโผล่ปนใน
ส่วนที่เพิ่มใหม่ (ยกเว้นค่า `action` ที่มาจาก `admin_log` ซึ่งเป็นข้อความไทยจาก backend อยู่แล้ว
— ของเดิมเป็นแบบนี้ทั้งหน้า ไม่ใช่ของใหม่ที่เพิ่มเข้ามา)

- [ ] **Step 5: Commit**

```bash
git add components/dashboard/Logs.tsx
git commit -m "feat(dashboard): สีป้ายของ action ปรับสิทธิ์ออกกลุ่ม"
```

---

## เช็คก่อนปิดแผนนี้

- [ ] `npm run lint` และ `npm run build` ผ่านทั้งคู่
- [ ] คอลัมน์สิทธิ์แสดงครบทุกแถว และปุ่มกรอง "เฉพาะคนที่สิทธิ์หมด" ทำงาน
- [ ] ปรับสิทธิ์แล้วค่าคงอยู่หลังรีเฟรช
- [ ] ค่านอกช่วง 0–10 ถูกปฏิเสธตั้งแต่ฝั่งหน้าเว็บ (ไม่มี request ออกไป)
- [ ] ไทม์ไลน์แสดงทั้ง 3 ชนิด action และแยก "admin ทำให้" กับ "ผู้เข้าร่วมทำเอง" ได้
- [ ] สลับภาษาแล้วไม่มีข้อความค้างภาษาเดียว
