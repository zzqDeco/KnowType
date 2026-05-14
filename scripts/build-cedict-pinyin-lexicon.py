#!/usr/bin/env python3
"""Build KnowType's CC-CEDICT derived pinyin lexicon.

Usage:
  scripts/build-cedict-pinyin-lexicon.py cedict_1_0_ts_utf-8_mdbg.txt.gz \
    Sources/KnowTypeCore/Resources/pinyin_lexicon.tsv
"""

from __future__ import annotations

import gzip
import re
import sys
from pathlib import Path


LINE_PATTERN = re.compile(r"^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/")

MANUAL_BOOST = {
    "你": 0.84,
    "是": 0.84,
    "谁": 0.82,
    "我": 0.84,
    "的": 0.86,
    "了": 0.82,
    "不": 0.82,
    "在": 0.82,
    "有": 0.82,
    "中国": 0.88,
    "中文": 0.88,
    "可以": 0.88,
    "没有": 0.88,
    "问题": 0.88,
    "接口": 0.88,
    "功能": 0.88,
}


def normalize_pinyin(raw: str) -> list[str] | None:
    tokens: list[str] = []
    for token in raw.lower().replace("u:", "v").split():
        normalized = re.sub(r"[1-5]", "", token).replace("'", "")
        if not re.fullmatch(r"[a-zv]+", normalized) or not is_standard_pinyin_token(normalized):
            return None
        tokens.append(normalized)
    return tokens


def is_standard_pinyin_token(token: str) -> bool:
    if token == "er":
        return True
    if not any(vowel in token for vowel in "aeiouv"):
        return False
    if token.endswith("g"):
        return token.endswith("ng")
    if token.endswith("r"):
        return token == "er"
    return token[-1] in "aeiouvn"


def confidence(simplified: str, traditional: str, token_count: int) -> float:
    if simplified in MANUAL_BOOST:
        return MANUAL_BOOST[simplified]

    if token_count == 1:
        score = 0.58
    elif token_count == 2:
        score = 0.64
    elif token_count == 3:
        score = 0.66
    else:
        score = 0.63

    han_count = sum(1 for char in simplified if "\u4e00" <= char <= "\u9fff")
    if han_count == len(simplified):
        score += 0.04
    if simplified == traditional:
        score += 0.01
    return min(score, 0.89)


def build(input_path: Path) -> list[tuple[str, str, float]]:
    seen: set[tuple[str, str]] = set()
    entries: list[tuple[str, str, float]] = []

    with gzip.open(input_path, "rt", encoding="utf-8") as source:
        for line in source:
            if not line or line.startswith("#"):
                continue
            match = LINE_PATTERN.match(line)
            if not match:
                continue

            traditional, simplified, raw_pinyin = match.groups()
            pinyin = normalize_pinyin(raw_pinyin)
            if not pinyin or len(pinyin) > 6 or len(simplified) > 8:
                continue

            han_count = sum(1 for char in simplified if "\u4e00" <= char <= "\u9fff")
            if han_count == 0:
                continue

            pinyin_key = " ".join(pinyin)
            dedupe_key = (pinyin_key, simplified)
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            entries.append((pinyin_key, simplified, confidence(simplified, traditional, len(pinyin))))

    return sorted(entries, key=lambda row: (row[0], -row[2], len(row[1]), row[1]))


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    output_path.parent.mkdir(parents=True, exist_ok=True)

    entries = build(input_path)
    with output_path.open("w", encoding="utf-8") as output:
        for pinyin, word, score in entries:
            output.write(f"{pinyin}\t{word}\t{score:.3f}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
