#!/usr/bin/env bash
# ตรวจว่าไฟล์ skill ใน .claude/skills/wbw-ios/ ยังตรงกับ repo จริงไหม
#
# ทำไมต้องมี: workflow.md เขียนไว้เองว่าเลขบรรทัดที่ skill อ้างไว้ตรง ๆ จะเพี้ยนแบบเงียบ ๆ ตอนมีคน
# แทรกโค้ดเหนือบรรทัดนั้น และไม่มี build/test ตัวไหนจับได้ — session ถัดไปอ่าน SKILL.md แล้วเชื่อทันที
# โดยไม่ตรวจซ้ำ สคริปต์นี้คือตัวจับ ให้รันก่อน commit งานที่ย้าย/เพิ่ม/ลบไฟล์ใน WBW/ หรือ WBWTests/
#
# ใช้: ./scripts/check-skill-refs.sh   (exit 1 ถ้ามีอะไรไม่ตรง)

set -uo pipefail
cd "$(dirname "$0")/.."

SKILL_DIR=".claude/skills/wbw-ios"
fail=0

red()  { printf '\033[31m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m%s\033[0m\n' "$1"; }

# ---------- 1. ตัวเลขที่ SKILL.md การันตีไว้ ----------
# แก้เลขพวกนี้พร้อมกับแก้ SKILL.md เสมอ ไม่ใช่แก้ที่นี่อย่างเดียวให้ผ่าน ๆ ไป
check_count() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    red "FAIL  $label: skill บอก $expected แต่ของจริง $actual"
    fail=1
  else
    printf '  ok   %s = %s\n' "$label" "$actual"
  fi
}

echo "== จำนวนไฟล์ที่ skill อ้างไว้ =="
check_count "ไฟล์ .swift ที่รากของ WBW/" 51 "$(find WBW -maxdepth 1 -name '*.swift' | wc -l | tr -d ' ')"
check_count "WBW/SOS"      13 "$(find WBW/SOS      -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Map3D"    14 "$(find WBW/Map3D    -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Walk"     5 "$(find WBW/Walk     -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Chat"     8 "$(find WBW/Chat     -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Feedback" 7 "$(find WBW/Feedback -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Scene3D"  7 "$(find WBW/Scene3D  -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Conditions" 4 "$(find WBW/Conditions -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Bloom"      3 "$(find WBW/Bloom      -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Demo"       3 "$(find WBW/Demo       -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "ไฟล์เทสใน WBWTests/" 112 "$(find WBWTests -name '*.swift' | wc -l | tr -d ' ')"
# workflow.md กำชับว่ายังไม่เอา Swift Testing เข้ามา ต้องคุยก่อน — ตัวเลขนี้ต้องเป็น 0 จนกว่าจะคุยกันแล้ว
check_count "ไฟล์ที่ import Testing" 0 "$(grep -rl 'import Testing' WBWTests 2>/dev/null | wc -l | tr -d ' ')"
check_count "ไฟล์ skill ใน $SKILL_DIR" 6 "$(find "$SKILL_DIR" -name '*.md' | wc -l | tr -d ' ')"

# ---------- 2. path ที่ skill อ้าง ยังมีอยู่จริงไหม ----------
echo
echo "== path ที่ skill อ้างถึง =="
missing_paths=0
grep -rhoE '(WBW|WBWTests|docs|scripts|\.claude)/[A-Za-z0-9_./+-]+' "$SKILL_DIR" \
  | sed 's/[.,)]*$//' \
  | grep -vE '<|YYYY|\*' \
  | sort -u \
  | while read -r p; do
      [ -e "$p" ] || { red "FAIL  path หายไป: $p"; echo x >> /tmp/.skillrefs.$$; }
    done
[ -f /tmp/.skillrefs.$$ ] && { missing_paths=$(wc -l < /tmp/.skillrefs.$$); rm -f /tmp/.skillrefs.$$; }
if [ "$missing_paths" -eq 0 ]; then
  ok "  ok   path ที่อ้างไว้มีครบทุกอัน"
else
  fail=1
fi

# ---------- 3. เลขบรรทัดที่อ้างแบบ path:NN ----------
# ไม่ได้เทียบเนื้อหาว่าต้องเป็นข้อความอะไร (จะกลายเป็นของที่ต้องดูแลสองที่) แค่การันตีว่าเลขไม่เกินท้ายไฟล์
# แล้วพิมพ์บรรทัดปัจจุบันออกมาให้คนอ่านตรวจด้วยตาว่ายังชี้ของถูกอยู่
echo
echo "== เลขบรรทัดที่อ้างไว้ตรง ๆ (อ่านบรรทัดที่พิมพ์ออกมาว่ายังตรงกับที่ skill เล่าไหม) =="
while IFS= read -r ref; do
  path="${ref%%:*}"
  line="${ref##*:}"
  if [ ! -f "$path" ]; then
    red "FAIL  $ref — ไม่มีไฟล์นี้แล้ว"
    fail=1
    continue
  fi
  total=$(wc -l < "$path" | tr -d ' ')
  if [ "$line" -gt "$total" ]; then
    red "FAIL  $ref — ไฟล์มีแค่ $total บรรทัด"
    fail=1
    continue
  fi
  printf '  %-45s %s\n' "$ref" "$(sed -n "${line}p" "$path" | sed 's/^[[:space:]]*//')"
done < <(grep -rhoE '(WBW|WBWTests)/[A-Za-z0-9_./+-]+\.swift:[0-9]+' "$SKILL_DIR" | sort -u)

# ---------- 4. ผลกระทบต่อ App Store ----------
# ทำไมต้องมี: ของนอกโค้ด (เอกสารรอบส่ง เลข build สูตรถ่ายสกรีนช็อต) ไม่มี build/test ตัวไหนจับให้เลย
# และคือเหตุที่รอบ 1.0 (7) โดนตีกลับจริง — ตารางเต็มอยู่ที่ .claude/skills/wbw-ios/appstore.md
echo
echo "== ผลกระทบต่อ App Store =="

yml_setting() { grep -m1 "$1:" project.yml | sed 's/.*: *//; s/"//g' | tr -d ' \r'; }
build_no=$(yml_setting CURRENT_PROJECT_VERSION)
marketing=$(yml_setting MARKETING_VERSION)
checklist="docs/appstore/connect-checklist.md"

# 4.1 เอกสารรอบส่งต้องพูดถึงเลข build ปัจจุบัน — บั๊มเลขแล้วลืมอัปเอกสารคือของที่หลุดง่ายที่สุด
#     (เช็กลิสต์ที่ยังเล่าเรื่อง build เก่าจะพา session ถัดไปกดตามลำดับของรอบที่ผ่านไปแล้ว)
if grep -qF "$marketing ($build_no)" "$checklist"; then
  printf '  ok   %s พูดถึง build %s (%s)\n' "$checklist" "$marketing" "$build_no"
else
  red "FAIL  $checklist ไม่พูดถึง build $marketing ($build_no) — บั๊มเลขแล้วลืมอัปเอกสารรอบส่ง"
  fail=1
fi

# 4.2 แฟลกที่สูตรถ่ายสกรีนช็อตสั่งไว้ ต้องยังมีอยู่ในโค้ด — ลบแฟลกทิ้งแล้วถ่ายใหม่จะได้จอผิดแบบเงียบ ๆ
#     ไม่มี error ให้เห็น แล้วรูปที่ไม่ตรงกับแอปคือเหตุตีกลับ 2.3.3
missing_flags=""
for flag in $(grep -ohE '\-uitest[A-Za-z]+' docs/appstore/README.md | sed 's/^-//' | sort -u); do
  grep -rqF "$flag" WBW || missing_flags="$missing_flags $flag"
done
if [ -z "$missing_flags" ]; then
  ok "  ok   แฟลก -uitest* ที่ใช้ถ่ายสกรีนช็อตยังมีครบในโค้ด"
else
  red "FAIL  docs/appstore/README.md สั่งใช้แฟลกที่ไม่มีในโค้ดแล้ว:$missing_flags"
  fail=1
fi

# 4.3 เตือนเฉย ๆ ไม่ทำให้ exit 1 — ระหว่างพัฒนาสภาพนี้เป็นเรื่องปกติ ที่ไม่ปกติคือ archive ทั้งอย่างนี้
bump_commit=$(git log -1 --format=%H -S"CURRENT_PROJECT_VERSION: \"$build_no\"" -- project.yml 2>/dev/null)
if [ -n "$bump_commit" ]; then
  since=$(git log --oneline "$bump_commit"..HEAD -- WBW 2>/dev/null | wc -l | tr -d ' ')
  if [ "$since" -gt 0 ]; then
    printf '  เตือน แตะโค้ดใน WBW/ ไปแล้ว %s คอมมิตหลังบั๊ม build %s — archive รอบหน้าต้องบั๊มก่อน\n' "$since" "$build_no"
  else
    printf '  ok   ยังไม่มีคอมมิตแตะ WBW/ หลังบั๊ม build %s\n' "$build_no"
  fi
fi

# 4.4 สกรีนช็อตอยู่ใน .gitignore (35 MB) จึงมีเฉพาะบนเครื่องที่ถ่าย — ไม่มีไม่ใช่ความผิด
shots="docs/appstore/screenshots"
if [ -d "$shots" ]; then
  for size in 6.5 6.9; do
    n=$(find "$shots/$size" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" = "10" ]; then
      printf '  ok   สกรีนช็อต %s ครบ 10 ใบ\n' "$size"
    else
      printf '  เตือน สกรีนช็อต %s มี %s ใบ — ASC รับ 10 ใบต่อขนาด (เพดานเต็มพอดี)\n' "$size" "$n"
    fi
  done
else
  printf '  ข้าม  ไม่มีสกรีนช็อตบนเครื่องนี้ (gitignore) ถ่ายใหม่ตาม docs/appstore/README.md\n'
fi


echo
if [ "$fail" -eq 0 ]; then
  ok "skill ยังตรงกับ repo"
else
  red "skill เน่าแล้ว — แก้ไฟล์ skill ในคอมมิตเดียวกับงานที่ทำให้มันเปลี่ยน (ดู workflow.md หัวข้อ 'skill เน่าเมื่อไหร่')"
fi
exit "$fail"
