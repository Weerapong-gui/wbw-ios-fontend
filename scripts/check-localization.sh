#!/bin/bash
# ตรวจว่าคีย์ที่โค้ดเรียกใช้มีอยู่จริงในทั้ง en และ th
#
# มีเพราะ **คีย์ที่หายไม่ทำให้ build พัง** — iOS คืนชื่อคีย์เป็นข้อความแทน ผู้ใช้จึงเห็นคำว่า
# "group_leave" บนปุ่ม ซึ่งดูเหมือนแอปยังทำไม่เสร็จ ไม่ใช่ดูเหมือนบั๊ก และไม่มีอะไรจับได้เลย
set -u
cd "$(dirname "$0")/.."
python3 - "$@" <<'PY'
import re, os, sys
def catalogue(p):
    return set(re.findall(r'^"([^"]+)"\s*=', open(p).read(), re.M))
en = catalogue('WBW/en.lproj/Localizable.strings')
th = catalogue('WBW/th.lproj/Localizable.strings')
used = {}
pat = re.compile(r'(?:Loc\.t\(|String\(localized:\s*|Text\(|Label\(|TextField\(|Button\(|navigationTitle\(|accessibilityLabel\(|alert\()"([a-z][a-z0-9_]*)"')
for root, _, files in os.walk('WBW'):
    for f in sorted(files):
        if f.endswith('.swift'):
            p = os.path.join(root, f)
            for i, line in enumerate(open(p).read().split('\n'), 1):
                if line.strip().startswith('//'): continue
                for k in pat.findall(line):
                    used.setdefault(k, f"{p}:{i}")
# ตัวระบุรูปแบบต้องตรงกันทั้งสองภาษา — `%1$@` ที่แปลไปเป็น `%1$lld` จะไม่พังตอน build
# แต่ `String(format:)` จะอ่าน Int เป็นตัวชี้ object แล้ว **crash** ตอนผู้ใช้สลับภาษา
# (เจอมาแล้วจริงบนบัตรผู้เข้าร่วม: `%1$@` คู่กับหมายเลขกลุ่มที่เป็น Int → EXC_BAD_ACCESS)
spec = re.compile(r'%(?:(\d+)\$)?[-+ #0]*[\d.*]*(?:hh|h|ll|l|q|L|z|t|j)?([@dioufFeEgGxXscpaA])')
def specs(path):
    out = {}
    for k, v in re.findall(r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";', open(path).read(), re.M):
        out[k] = sorted(spec.findall(v))
    return out
en_s, th_s = specs('WBW/en.lproj/Localizable.strings'), specs('WBW/th.lproj/Localizable.strings')
mismatched = [k for k in sorted(set(en_s) & set(th_s)) if en_s[k] != th_s[k]]
for k in mismatched:
    print(f"FORMAT ต่างกันระหว่าง en/th: {k}  en={en_s[k]} th={th_s[k]}")

bad = len(mismatched)
for k, where in sorted(used.items()):
    miss = [n for n, c in (('en', en), ('th', th)) if k not in c]
    if miss:
        print(f"MISSING [{','.join(miss)}] {k}  ({where})"); bad += 1
print(f"— คีย์ที่โค้ดเรียก {len(used)} ตัว · ขาด {bad}")
print(f"— en {len(en)} คีย์ · th {len(th)} คีย์ · เฉพาะ en {len(en-th)} · เฉพาะ th {len(th-en)}")
for k in sorted(en ^ th):
    print(f"  ไม่ครบสองภาษา: {k}")
sys.exit(1 if bad or (en ^ th) else 0)
PY
