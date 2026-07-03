#!/usr/bin/env python3
"""Summarize privacy-safe KnowType AI debug logs."""

from __future__ import annotations

import argparse
import math
import re
import sys
from collections import Counter
from pathlib import Path


KEY_VALUE_PATTERN = re.compile(r"([A-Za-z][A-Za-z0-9_]*)=([^ \n]+)")
AI_MARKER = "KnowType debug: category=ai"
LATENCY_MARKER = "KnowType debug: category=input_latency"
SAMPLE_STAGES = {
    "transport_started",
    "transport_left_stale",
    "transport_cancellation_requested",
    "transport_cancelled_by_new_input",
    "cancelled",
    "provider_error",
    "timeout",
    "stale_result_dropped",
}
SAMPLE_KEYS = (
    "stage",
    "requestID",
    "compositionID",
    "rawLength",
    "rawRevision",
    "elapsedMs",
    "provider",
    "reason",
)
UNAVAILABLE_STAGES = {"cooldown_active"}
UNAVAILABLE_REASON_MARKERS = ("unavailable", "暂不可用")


def parse_fields(line: str) -> dict[str, str]:
    return {key: value for key, value in KEY_VALUE_PATTERN.findall(line)}


def percentile(values: list[float], quantile: float) -> float:
    if not values:
        return 0.0
    index = max(0, math.ceil(len(values) * quantile) - 1)
    return values[min(index, len(values) - 1)]


def is_unavailable_event(stage: str, reason: str | None) -> bool:
    if stage in UNAVAILABLE_STAGES:
        return True
    if not reason:
        return False
    folded = reason.casefold()
    return any(marker in folded for marker in UNAVAILABLE_REASON_MARKERS)


def summarize(path: Path, sample_limit: int) -> tuple[int, str]:
    if not path.exists():
        return 2, f"error: log file does not exist: {path}\n"
    if not path.is_file():
        return 2, f"error: log path is not a file: {path}\n"

    stage_counts: Counter[str] = Counter()
    reason_counts: Counter[str] = Counter()
    cancellation_samples: list[dict[str, str]] = []
    handle_key_totals: list[float] = []
    ai_event_count = 0
    unavailable_count = 0

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if AI_MARKER in line:
            fields = parse_fields(line)
            stage = fields.get("stage")
            if not stage:
                continue
            ai_event_count += 1
            stage_counts[stage] += 1
            reason = fields.get("reason")
            if reason:
                reason_counts[reason] += 1
            if is_unavailable_event(stage, reason):
                unavailable_count += 1
            if stage in SAMPLE_STAGES:
                cancellation_samples.append(
                    {key: fields[key] for key in SAMPLE_KEYS if key in fields}
                )
        elif LATENCY_MARKER in line and "stage=handle_key_total" in line:
            fields = parse_fields(line)
            try:
                handle_key_totals.append(float(fields["elapsedMs"]))
            except (KeyError, ValueError):
                continue

    lines: list[str] = []
    lines.append(f"logFile={path}")
    lines.append(f"aiEvents={ai_event_count}")
    lines.append("aiStageCounts:")
    for stage, count in sorted(stage_counts.items()):
        lines.append(f"  {stage}={count}")
    lines.append("aiReasonCounts:")
    for reason, count in sorted(reason_counts.items()):
        lines.append(f"  {reason}={count}")
    lines.append(
        "providerHealthSignals: "
        f"provider_error={stage_counts.get('provider_error', 0)} "
        f"timeout={stage_counts.get('timeout', 0)} "
        f"unavailable={unavailable_count}"
    )

    values = sorted(handle_key_totals)
    lines.append(
        "handleKeyTotalMs: "
        f"count={len(values)} "
        f"min={values[0]:.2f} " if values else "handleKeyTotalMs: count=0 "
    )
    if values:
        lines[-1] += (
            f"p50={percentile(values, 0.50):.2f} "
            f"p90={percentile(values, 0.90):.2f} "
            f"p95={percentile(values, 0.95):.2f} "
            f"max={values[-1]:.2f}"
        )

    lines.append("transportSamples:")
    for sample in cancellation_samples[-sample_limit:]:
        lines.append("  " + " ".join(f"{key}={value}" for key, value in sample.items()))
    if not cancellation_samples:
        lines.append("  none")

    return 0, "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Summarize privacy-safe KnowType AI debug log metadata."
    )
    parser.add_argument("logfile", help="Path to a KnowType unified-log text export.")
    parser.add_argument(
        "--sample-limit",
        type=int,
        default=12,
        help="Number of transport/cancellation samples to include. Defaults to 12.",
    )
    args = parser.parse_args(argv)

    code, output = summarize(Path(args.logfile), max(0, args.sample_limit))
    stream = sys.stderr if code else sys.stdout
    stream.write(output)
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
