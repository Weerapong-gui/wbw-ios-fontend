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
check_count "ไฟล์ .swift ที่รากของ WBW/" 46 "$(find WBW -maxdepth 1 -name '*.swift' | wc -l | tr -d ' ')"
check_count "WBW/SOS"      11 "$(find WBW/SOS      -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Map3D"    10 "$(find WBW/Map3D    -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Chat"     5 "$(find WBW/Chat     -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Feedback" 4 "$(find WBW/Feedback -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Scene3D"  7 "$(find WBW/Scene3D  -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/SURun"      3 "$(find WBW/SURun      -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Conditions" 4 "$(find WBW/Conditions -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Bloom"      3 "$(find WBW/Bloom      -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "WBW/Demo"       3 "$(find WBW/Demo       -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
check_count "ไฟล์เทสใน WBWTests/" 63 "$(find WBWTests -name '*.swift' | wc -l | tr -d ' ')"
# workflow.md กำชับว่ายังไม่เอา Swift Testing เข้ามา ต้องคุยก่อน — ตัวเลขนี้ต้องเป็น 0 จนกว่าจะคุยกันแล้ว
check_count "ไฟล์ที่ import Testing" 0 "$(grep -rl 'import Testing' WBWTests 2>/dev/null | wc -l | tr -d ' ')"
check_count "ไฟล์ skill ใน $SKILL_DIR" 5 "$(find "$SKILL_DIR" -name '*.md' | wc -l | tr -d ' ')"

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

echo
if [ "$fail" -eq 0 ]; then
  ok "skill ยังตรงกับ repo"
else
  red "skill เน่าแล้ว — แก้ไฟล์ skill ในคอมมิตเดียวกับงานที่ทำให้มันเปลี่ยน (ดู workflow.md หัวข้อ 'skill เน่าเมื่อไหร่')"
fi
exit "$fail"
