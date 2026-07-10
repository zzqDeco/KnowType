#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


INVALID_ENDPOINT = "<invalid endpoint>"


def privacy_safe_endpoint_summary(value):
    if not isinstance(value, str):
        return INVALID_ENDPOINT
    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        if parsed.scheme.lower() not in {"http", "https"} or not hostname:
            return INVALID_ENDPOINT

        rendered_host = f"[{hostname}]" if ":" in hostname else hostname
        netloc = rendered_host
        if parsed.port is not None:
            netloc = f"{netloc}:{parsed.port}"
        summary = urlunsplit((parsed.scheme.lower(), netloc, parsed.path, "", ""))
        return f"{summary} [query redacted]" if parsed.query else summary
    except (TypeError, ValueError):
        return INVALID_ENDPOINT


def verify_fixtures(path):
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    failures = []
    for fixture in payload.get("cases", []):
        actual = privacy_safe_endpoint_summary(fixture.get("input"))
        if actual != fixture.get("summary"):
            failures.append({"input": fixture.get("input"), "expected": fixture.get("summary"), "actual": actual})
    if failures:
        raise SystemExit(json.dumps(failures, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("url", nargs="?")
    parser.add_argument("--verify-fixtures")
    args = parser.parse_args()
    if args.verify_fixtures:
        verify_fixtures(args.verify_fixtures)
        return
    print(privacy_safe_endpoint_summary(args.url))


if __name__ == "__main__":
    main()
