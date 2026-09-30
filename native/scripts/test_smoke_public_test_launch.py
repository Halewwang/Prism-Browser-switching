"""Synthetic startup tests; never launch Prism or inspect user data."""

import contextlib
import io
import importlib.util
import pathlib
import runpy
import subprocess
import tempfile
import types
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("smoke-public-test-launch.py")
SPEC = importlib.util.spec_from_file_location("smoke_public_test_launch", SCRIPT)
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)


class FakeProcess:
    def __init__(self, status=None):
        self.returncode = status
        self.stderr = io.BytesIO(b"synthetic startup failure")
        self.pid = 1234

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def poll(self):
        return self.returncode

    def terminate(self):
        self.returncode = 0

    def wait(self, timeout=None):
        return self.returncode

    def kill(self):
        self.returncode = -9


class SmokeLaunchTests(unittest.TestCase):
    def test_launch_is_wrapped_in_sandbox(self):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / "Prism.app"
            executable = app / "Contents/MacOS/Prism"
            executable.parent.mkdir(parents=True)
            executable.touch()
            with mock.patch("sys.argv", [str(SCRIPT), str(app)]), mock.patch(
                "subprocess.Popen", return_value=FakeProcess()
            ) as popen, mock.patch("time.sleep"), mock.patch(
                "pwd.getpwuid", return_value=types.SimpleNamespace(pw_dir=directory)
            ), contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(SCRIPT), run_name="__main__")
            command = popen.call_args.args[0]
            self.assertEqual(command[0], "/usr/bin/sandbox-exec")
            self.assertEqual(command[1], "-p")
            self.assertIn("(deny file-read* file-write*", command[2])
            self.assertIn(str(pathlib.Path(directory) / "Library/Application Support/Prism"), command[2])
            self.assertEqual(command[3], str(executable))

    def test_account_home_is_used_even_with_different_home_environment(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(
            "os.environ", {"HOME": "/synthetic/temporary-home"}
        ), mock.patch("pwd.getpwuid", return_value=types.SimpleNamespace(pw_dir=directory)):
            command = SMOKE.launch_command(pathlib.Path("/synthetic/Prism"))
            self.assertIn(str(pathlib.Path(directory) / "Library/Application Support/Prism"), command[2])
            self.assertNotIn("/synthetic/temporary-home", command[2])

    def test_sandbox_quotes_paths_without_accepting_profile_syntax(self):
        self.assertEqual(SMOKE.sandbox_string('/synthetic/home "work"\\name'),
                         '"/synthetic/home \\"work\\"\\\\name"')
        for character in ["\n", "\r", "\x00", "\x7f"]:
            with self.subTest(character=repr(character)), self.assertRaises(SystemExit):
                SMOKE.sandbox_string("/synthetic/" + character + "path")

    def test_missing_sandbox_refuses_before_creating_child(self):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / "Prism.app"
            executable = app / "Contents/MacOS/Prism"
            executable.parent.mkdir(parents=True)
            executable.touch()
            with mock.patch.object(SMOKE, "SANDBOX_EXEC", pathlib.Path(directory) / "missing"), mock.patch(
                "subprocess.Popen"
            ) as popen, self.assertRaisesRegex(SystemExit, "refusing an unsandboxed"):
                SMOKE.main([str(app)])
            popen.assert_not_called()

    def test_child_exit_including_zero_is_a_smoke_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / "Prism.app"
            executable = app / "Contents/MacOS/Prism"
            executable.parent.mkdir(parents=True)
            executable.touch()
            for status in [0, 23]:
                with self.subTest(status=status), mock.patch.object(
                    SMOKE, "launch_command", return_value=["synthetic-sandbox", str(executable)]
                ), mock.patch("subprocess.Popen", return_value=FakeProcess(status)), mock.patch(
                    "time.sleep"
                ), self.assertRaisesRegex(SystemExit, "status " + str(status)):
                    SMOKE.main([str(app)])

    def test_relative_protected_path_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, "must be absolute"):
            SMOKE.sandbox_profile(pathlib.Path("synthetic/Prism"))

    @unittest.skipUnless(pathlib.Path("/usr/bin/sandbox-exec").is_file(), "requires macOS sandbox-exec")
    def test_sandbox_denies_whole_synthetic_directory_and_alias(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            protected = base / 'Prism "quoted"\\directory'
            nested = protected / "Recovery/nested"
            nested.mkdir(parents=True)
            sentinel = nested / "pending-requests-v1.json"
            sentinel.write_text("synthetic-private-marker")
            alias = base / "PrismAlias"
            alias.symlink_to(protected, target_is_directory=True)
            allowed = base / "neighbor.txt"
            allowed.write_text("allowed-marker")
            nested_alias = protected / "PrismNative.store"
            nested_alias.symlink_to(allowed)
            profile = SMOKE.sandbox_profile(alias)

            def run(*arguments):
                return subprocess.run(["/usr/bin/sandbox-exec", "-p", profile, *arguments],
                                      capture_output=True, text=True, timeout=5)

            control = run("/bin/cat", str(allowed))
            self.assertEqual(control.returncode, 0, control.stderr)
            self.assertEqual(control.stdout, "allowed-marker")
            for path in [sentinel, alias / "Recovery/nested/pending-requests-v1.json"]:
                with self.subTest(path=path):
                    result = run("/bin/cat", str(path))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("synthetic-private-marker", result.stdout)
            result = run("/usr/bin/touch", str(nested / "new-file"))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((nested / "new-file").exists())
            result = run("/bin/cp", str(allowed), str(sentinel))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), "synthetic-private-marker")
            result = run("/bin/ls", str(protected))
            self.assertNotEqual(result.returncode, 0)
            result = run("/bin/cat", str(nested_alias))
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("allowed-marker", result.stdout)


if __name__ == "__main__":
    unittest.main()
