#!/usr/bin/env python3
"""Summarize manually captured source-probe rows; never change the manifest."""

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import sys
import uuid


FIELDS = {"timestamp", "appName", "bundleIdentifier", "senderPIDPresent", "confidence", "expectedSource", "runState", "passed"}
REQUIRED_FIELDS = FIELDS - {"bundleIdentifier"}
TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z\Z")
CAPTURE_ID = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\Z")
BUNDLE_ID = re.compile(r"[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+\Z")
EXPECTED_SOURCES = {"DingTalk", "Lark", "WeChat", "Slack", "Finder", "Terminal", "Safari", "Chrome", "Arc"}


def expected_bundle(value):
    name, separator, bundle = value.partition("=")
    if not separator or name not in EXPECTED_SOURCES or not BUNDLE_ID.fullmatch(bundle):
        raise argparse.ArgumentTypeError("Expected Source=exact.bundle.identifier for a supported probe source")
    return name, bundle


def macos_version(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise argparse.ArgumentTypeError("Use an observed macOS version in major.minor.patch format")
    return value


def validated_row(value, expected):
    if not isinstance(value, dict) or not REQUIRED_FIELDS <= set(value) or not set(value) <= FIELDS | {"captureID"}:
        return None
    value = dict(value)
    value.setdefault("bundleIdentifier", None)
    if "captureID" in value:
        capture_id = value["captureID"]
        if not isinstance(capture_id, str) or not CAPTURE_ID.fullmatch(capture_id):
            return None
        value["captureID"] = str(uuid.UUID(capture_id))
    if not all(isinstance(value[key], str) for key in ("timestamp", "appName", "confidence", "expectedSource", "runState")):
        return None
    if type(value["passed"]) is not bool or type(value["senderPIDPresent"]) is not bool:
        return None
    bundle = value["bundleIdentifier"]
    if bundle is not None and (not isinstance(bundle, str) or not BUNDLE_ID.fullmatch(bundle)):
        return None
    if value["confidence"] not in ("confirmed", "low", "unknown") or value["runState"] not in ("cold", "warm"):
        return None
    if value["expectedSource"] not in expected or not value["appName"]:
        return None
    if not TIMESTAMP.fullmatch(value["timestamp"]):
        return None
    try:
        timestamp = datetime.fromisoformat(value["timestamp"].replace("Z", "+00:00"))
        if timestamp.tzinfo is None:
            return None
    except ValueError:
        return None
    return value, timestamp


def summarize(paths, macos, expected):
    sources = {name: {"expectedSource": name, "bundleIdentifier": bundle, "coldSamples": 0, "warmSamples": 0, "confirmedCorrectCount": 0, "falseAttributionCount": 0} for name, bundle in sorted(expected.items())}
    invalid = duplicates = 0
    seen = {}
    legacy_seconds = set()
    identified_seconds = set()
    for path in paths:
        with path.open(encoding="utf-8") as stream:
            for line in stream:
                if not line.strip():
                    continue
                try:
                    validated = validated_row(json.loads(line), expected)
                except (ValueError, TypeError):
                    validated = None
                if validated is None:
                    invalid += 1
                    continue
                row, timestamp = validated
                capture_id = row.get("captureID")
                key = ("captureID", capture_id) if capture_id else ("legacyTimestamp", timestamp)
                second = timestamp.replace(microsecond=0)
                # A legacy second cannot distinguish a new capture from an old copy.
                if (capture_id and second in legacy_seconds) or (not capture_id and second in identified_seconds):
                    invalid += 1
                    continue
                if capture_id:
                    identified_seconds.add(second)
                else:
                    legacy_seconds.add(second)
                # Repeated saves retain the ID. Legacy rows conservatively use time.
                if key in seen:
                    duplicates += 1
                    if row != seen[key]:
                        invalid += 1
                    continue
                seen[key] = row
                source = sources[row["expectedSource"]]
                source[row["runState"] + "Samples"] += 1
                exact_bundle = row["bundleIdentifier"] == source["bundleIdentifier"]
                is_confirmed = row["confidence"] == "confirmed"
                if is_confirmed and not exact_bundle:
                    source["falseAttributionCount"] += 1
                if is_confirmed and exact_bundle and row["passed"] and row["senderPIDPresent"]:
                    source["confirmedCorrectCount"] += 1
    for source in sources.values():
        total = source["coldSamples"] + source["warmSamples"]
        source["accepted"] = (source["coldSamples"] >= 20 and source["warmSamples"] >= 20 and source["confirmedCorrectCount"] == total and source["falseAttributionCount"] == 0)
    return {"macOS": macos, "invalidRows": invalid, "duplicateRows": duplicates, "accepted": invalid == 0 and bool(sources) and all(source["accepted"] for source in sources.values()), "sources": list(sources.values()), "manifestUpdated": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jsonl", type=Path, nargs="+")
    parser.add_argument("--macos", required=True, type=macos_version, help="Observed OS for this homogeneous capture session; not inferred from the file")
    parser.add_argument("--expected-bundle", action="append", required=True, type=expected_bundle, help="Independent expected source identity, e.g. Slack=com.tinyspeck.slackmacgap")
    args = parser.parse_args()
    expected = dict(args.expected_bundle)
    if len(expected) != len(args.expected_bundle):
        parser.error("Each expected source must be specified once")
    try:
        report = summarize(args.jsonl, args.macos, expected)
    except (OSError, UnicodeError):
        # Do not echo paths or file contents into an error report.
        print("Could not read source evidence files", file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
