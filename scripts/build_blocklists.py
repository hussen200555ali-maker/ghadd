#!/usr/bin/env python3
"""بناء قوائم حجب المواقع المدمجة لغَضّ (0.3.6).

المدخلات (مصادر عامة، نزّلها مسبقًا إلى /tmp/bl):
  blp_porn.txt      — Block List Project: Porn   (0.0.0.0 host)
  blp_fraud.txt     — Block List Project: Fraud  (0.0.0.0 host)
  blp_scam.txt      — Block List Project: Scam   (0.0.0.0 host)
  phishing.txt      — Phishing Army extended      (domains/تعليقات)

المخرجات:
  android/app/src/main/assets/blocklists/adult.txt.gz
  android/app/src/main/assets/blocklists/harm.txt.gz
كل ملف: سطر لكل نطاق، مرتّب بترتيب البايتات (LC_ALL=C)
بحيث يكفي البحث الثنائي على الملف المفكوك دون أي فهرس في الذاكرة.
"""
import gzip
import re
import sys
from pathlib import Path

SRC = Path("/tmp/bl")
OUT = Path("/home/z/my-project/download/ghadd-android/android/app/src/main/assets/blocklists")

DOMAIN_RE = re.compile(r"^(?=.{4,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)"
                       r"(\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$")
INVALID = {"localhost", "localhost.localdomain", "local", "ip6-localhost", "broadcasthost"}

# حماية من الأضرار الجانبية: نطاقات مشهورة لا يجوز أن تسقط في أي قائمة بغلط المصدر
KEEP_SAFE = {
    "google.com", "youtube.com", "facebook.com", "instagram.com", "twitter.com",
    "x.com", "whatsapp.com", "amazon.com", "wikipedia.org", "reddit.com",
    "netflix.com", "apple.com", "microsoft.com", "samsung.com", "cnn.com",
    "bbc.com", "bbc.co.uk", "github.com", "linkedin.com", "tiktok.com",
    "telegram.org", "gmail.com", "stackoverflow.com", "yahoo.com", "bing.com",
    "m.youtube.com", "mail.google.com", "duckduckgo.com", "opera.com",
    "mozilla.org", "android.com", "play.google.com", "translate.google.com",
}


def domains_from_hosts_style(path: Path):
    """أسطر بصيغة 0.0.0.0 domain أو domain مجرد؛ تتجاهل التعليقات والأسطر الفارغة."""
    out = set()
    bad = 0
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            s = line.strip().lower()
            if not s or s.startswith("#"):
                continue
            parts = s.split()
            cand = parts[-1] if len(parts) >= 2 else (parts[0] if parts else "")
            if not cand or any(ch in cand for ch in ("/:*?[]@ \t")):
                bad += 1
                continue
            if cand in INVALID:
                bad += 1
                continue
            while cand.startswith("www."):
                cand = cand[4:]
            if DOMAIN_RE.match(cand):
                out.add(cand)
            else:
                bad += 1
    return out, bad


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    adult, a_bad = domains_from_hosts_style(SRC / "blp_porn.txt")

    harm, h_bad = domains_from_hosts_style(SRC / "blp_fraud.txt")
    h2, b2 = domains_from_hosts_style(SRC / "blp_scam.txt")
    harm |= h2
    h3, b3 = domains_from_hosts_style(SRC / "phishing.txt")
    harm |= h3

    before_a, before_h = len(adult), len(harm)
    adult -= KEEP_SAFE
    harm -= KEEP_SAFE

    for name, items in (("adult", adult), ("harm", harm)):
        data = "\n".join(sorted(items)) + "\n"
        raw = data.encode("utf-8")
        target = OUT / f"{name}.txt.gz"
        with gzip.GzipFile(str(target), "wb", compresslevel=9, mtime=0) as g:
            g.write(raw)
        print(f"{name}: {len(items):,} نطاق — raw {len(raw)/1e6:.1f}MB — gz {target.stat().st_size/1e6:.2f}MB")

    print(f"مرفوضات adult: {a_bad:,} | مرفوضات harm: {h_bad + b2 + b3:,}")
    print(f"أُزيلت من adult {before_a - len(adult)} ومن harm {before_h - len(harm)} (قائمة الأمان)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
