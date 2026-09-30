#!/usr/bin/env python3
"""Check startup with production Prism persistence inaccessible to the child."""

import os
import pathlib
import pwd
import subprocess
import sys
import time

SANDBOX_EXEC = pathlib.Path("/usr/bin/sandbox-exec")


def sandbox_string(value):
    """Quote an SBPL string; reject controls rather than accepting profile syntax."""
    value = str(value)
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise SystemExit("Unsupported control character in protected data path")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sandbox_profile(data_directory):
    if not data_directory.is_absolute():
        raise SystemExit("Protected Prism data path must be absolute")
    # Resolve directory aliases using filesystem metadata only, never store contents.
    directories = dict.fromkeys([data_directory, data_directory.resolve()])
    filters = []
    for directory in directories:
        quoted = sandbox_string(directory)
        filters.extend(["(literal " + quoted + ")", "(subpath " + quoted + ")"])
    return "(version 1)\n(allow default)\n(deny file-read* file-write*\n  " + "\n  ".join(filters) + ")\n"


def launch_command(executable):
    if not SANDBOX_EXEC.is_file() or not os.access(SANDBOX_EXEC, os.X_OK):
        raise SystemExit("sandbox-exec unavailable; refusing an unsandboxed Prism launch")
    # Use the account home, not a temporary or caller-supplied HOME environment.
    home = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)
    data_directory = home / "Library/Application Support/Prism"
    # ModelContainerFactory and AtomicPendingRequestStore share this parent.
    return [str(SANDBOX_EXEC), "-p", sandbox_profile(data_directory), str(executable)]


def main(arguments):
    if len(arguments) != 1:
        raise SystemExit("usage: smoke-public-test-launch.py <Prism.app>")
    executable = pathlib.Path(arguments[0]) / "Contents/MacOS/Prism"
    if not executable.is_file():
        raise SystemExit("Prism executable missing: " + str(executable))

    with subprocess.Popen(
        launch_command(executable), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    ) as process:
        try:
            time.sleep(5)
            if process.poll() is not None:
                stderr = process.stderr.read().decode("utf-8", "replace")
                raise SystemExit(
                    "Sandboxed Prism exited during launch with status "
                    + str(process.returncode)
                    + ": "
                    + stderr[-3000:]
                )
            print("Sandboxed Prism remained running for 5 seconds after launch (PID", process.pid, ")")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main(sys.argv[1:])
