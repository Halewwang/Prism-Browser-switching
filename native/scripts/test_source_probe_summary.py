import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid


SCRIPT = Path(__file__).with_name("summarize-source-probe.py")


class SourceProbeSummaryTests(unittest.TestCase):
    def sample(self, index, **changes):
        row = {
            "timestamp": f"2026-09-30T00:{index // 60:02}:{index % 60:02}Z",
            "appName": "Slack", "bundleIdentifier": "com.tinyspeck.slackmacgap",
            "senderPIDPresent": True, "confidence": "confirmed",
            "expectedSource": "Slack", "runState": "cold" if index < 20 else "warm",
            "passed": True,
        }
        row.update(changes)
        return row

    def summarize(self, rows):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.jsonl"
            path.write_text("\n".join(json.dumps(row) for row in rows))
            result = subprocess.run([
                sys.executable, str(SCRIPT), str(path), "--macos", "26.0.1",
                "--expected-bundle", "Slack=com.tinyspeck.slackmacgap",
            ], capture_output=True, text=True)
            self.assertIn(result.returncode, (0, 1), result.stderr)
            return result, json.loads(result.stdout)

    def test_script_exists(self):
        self.assertTrue(SCRIPT.is_file(), "A source evidence summary command is required")

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_forty_correct_unique_samples_meet_acceptance(self):
        result, report = self.summarize([self.sample(index) for index in range(40)])
        self.assertEqual(result.returncode, 0)
        self.assertTrue(report["accepted"])
        source = report["sources"][0]
        self.assertEqual((source["coldSamples"], source["warmSamples"], source["confirmedCorrectCount"]), (20, 20, 40))
        self.assertEqual(report["macOS"], "26.0.1")

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_repeated_capture_cannot_inflate_counts(self):
        rows = [self.sample(index) for index in range(39)]
        _, report = self.summarize(rows + [rows[-1]] * 20)
        self.assertFalse(report["accepted"])
        self.assertEqual(report["duplicateRows"], 20)
        self.assertEqual(report["sources"][0]["warmSamples"], 19)

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_conflicting_duplicate_cannot_hide_a_failed_capture(self):
        rows = [self.sample(index) for index in range(40)]
        _, report = self.summarize(rows + [self.sample(0, bundleIdentifier="com.other.app")])
        self.assertFalse(report["accepted"])
        self.assertEqual(report["invalidRows"], 1)

    def test_distinct_capture_ids_allow_two_real_captures_in_the_same_second(self):
        rows = [self.sample(index, captureID=str(uuid.uuid4())) for index in range(40)]
        rows[1]["timestamp"] = rows[0]["timestamp"]
        _, report = self.summarize(rows)
        self.assertTrue(report["accepted"])
        self.assertEqual(report["sources"][0]["confirmedCorrectCount"], 40)

    def test_saving_the_same_capture_id_again_counts_once(self):
        rows = [self.sample(index, captureID=str(uuid.uuid4())) for index in range(40)]
        _, report = self.summarize(rows + [rows[0]])
        self.assertTrue(report["accepted"])
        self.assertEqual(report["duplicateRows"], 1)
        self.assertEqual(report["sources"][0]["coldSamples"], 20)

    def test_conflicting_capture_id_fails_even_with_different_timestamps(self):
        rows = [self.sample(index, captureID=str(uuid.uuid4())) for index in range(40)]
        conflicting = dict(rows[0], timestamp="2026-09-30T00:02:00Z", passed=False)
        _, report = self.summarize(rows + [conflicting])
        self.assertFalse(report["accepted"])
        self.assertEqual(report["invalidRows"], 1)

    def test_fractional_timestamps_and_chinese_app_name_are_accepted_with_exact_bundle(self):
        rows = [self.sample(index, captureID=str(uuid.uuid4()), appName="飞书") for index in range(40)]
        rows[0]["timestamp"] = "2026-09-30T00:00:00.123Z"
        _, report = self.summarize(rows)
        self.assertTrue(report["accepted"])

    def test_capture_id_must_be_a_uuid_and_timestamp_must_be_strict_iso8601(self):
        for changes in ({"captureID": "private text"}, {"timestamp": "2026-09-30 00:00:00+00:00"}, {"timestamp": "2026-09-30T00:00:00+08:00"}):
            _, report = self.summarize([self.sample(0, **changes)])
            self.assertEqual(report["invalidRows"], 1)

    def test_mixed_legacy_and_new_timestamp_collision_cannot_double_count(self):
        rows = [self.sample(index) for index in range(40)]
        _, report = self.summarize(rows + [self.sample(0, captureID=str(uuid.uuid4()))])
        self.assertFalse(report["accepted"])
        self.assertEqual(report["invalidRows"], 1)

    def test_missing_optional_bundle_from_swift_encoder_counts_as_unknown_failure(self):
        row = self.sample(0, confidence="unknown", passed=False)
        del row["bundleIdentifier"]
        _, report = self.summarize([row])
        self.assertEqual(report["invalidRows"], 0)
        self.assertEqual(report["sources"][0]["coldSamples"], 1)
        self.assertFalse(report["accepted"])

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_pass_flag_cannot_hide_false_bundle_attribution(self):
        rows = [self.sample(index) for index in range(40)]
        rows[0]["bundleIdentifier"] = "com.other.app"
        _, report = self.summarize(rows)
        self.assertFalse(report["accepted"])
        self.assertEqual(report["sources"][0]["falseAttributionCount"], 1)

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_low_unknown_and_operator_failure_are_not_confirmed_correct(self):
        for changes in ({"confidence": "low"}, {"confidence": "unknown"}, {"passed": False}, {"senderPIDPresent": False}):
            with self.subTest(changes=changes):
                rows = [self.sample(index) for index in range(40)]
                rows[0].update(changes)
                _, report = self.summarize(rows)
                self.assertFalse(report["accepted"])
                self.assertEqual(report["sources"][0]["confirmedCorrectCount"], 39)

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_private_extra_fields_are_rejected_and_never_echoed(self):
        row = self.sample(0, url="https://private.invalid/sensitive")
        result, report = self.summarize([row])
        self.assertEqual(report["invalidRows"], 1)
        self.assertFalse(report["accepted"])
        self.assertNotIn("sensitive", result.stdout + result.stderr)
        self.assertNotIn("private.invalid", result.stdout + result.stderr)

    @unittest.skipUnless(SCRIPT.is_file(), "script not implemented yet")
    def test_invalid_rows_missing_fields_and_unknown_sources_fail_closed(self):
        for row in (self.sample(0, passed="true"), self.sample(0, timestamp="bad"), self.sample(0, expectedSource="Unmeasured")):
            _, report = self.summarize([row])
            self.assertEqual(report["invalidRows"], 1)
            self.assertFalse(report["accepted"])


if __name__ == "__main__":
    unittest.main()
