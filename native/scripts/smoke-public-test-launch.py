#!/usr/bin/env python3
"""Fail if a public-test app cannot stay alive past dynamic loading/startup."""

import pathlib
import subprocess
import sys
import time

if len(sys.argv) != 2:
    raise SystemExit("usage: smoke-public-test-launch.py <Prism.app>")

executable = pathlib.Path(sys.argv[1]) / "Contents/MacOS/Prism"
if not executable.is_file():
    raise SystemExit("Prism executable missing: " + str(executable))

with subprocess.Popen(
    [str(executable)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
) as process:
    try:
        time.sleep(5)
        if process.poll() is not None:
            stderr = process.stderr.read().decode("utf-8", "replace")
            raise SystemExit(
                "Prism exited during launch with status "
                + str(process.returncode)
                + ": "
                + stderr[-3000:]
            )
        print("Prism remained running for 5 seconds after launch (PID", process.pid, ")")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
