"""Synthetic command adapters verify the check runner, not Swift or app correctness."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class CheckRunnerTests(unittest.TestCase):
    def test_isolated_logs_scratch_selection_and_failure_survive_next_run(self):
        with tempfile.TemporaryDirectory(prefix="dama-check-runner-") as temporary:
            base = Path(temporary)
            binaries = base / "bin"
            binaries.mkdir()
            adapter = f"#!{sys.executable}\n" + '''
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
print("SYNTHETIC ADAPTER", name, repr(sys.argv[1:]))
if name == "swiftc":
    path = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
    path.write_text("#!/bin/sh\\nexit 0\\n")
    path.chmod(0o700)
if name == "swift" and sys.argv[1:2] == ["test"] and os.environ.get("DAMA_CHECK_TEST_FAILURE") == "1":
    print("SYNTHETIC FAILURE — retained evidence")
    sys.exit(11)
'''
            for name in ["python3", "swift", "swiftc", "xcodebuild"]:
                binary = binaries / name
                binary.write_text(adapter)
                binary.chmod(0o700)
            env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"])
            logs = base / "logs with spaces"
            scratch = base / "selected scratch"
            command = ["bash", "scripts/check.sh", "--log-root", str(logs), "--scratch-path", str(scratch)]
            first = subprocess.run(command, cwd=ROOT, env=dict(env, DAMA_CHECK_TEST_FAILURE="1"), capture_output=True, text=True)
            self.assertEqual(first.returncode, 1, first.stdout + first.stderr)
            old = next(logs.iterdir())
            evidence = {p.relative_to(old): p.read_bytes() for p in old.rglob("*") if p.is_file()}
            self.assertIn(b"SYNTHETIC FAILURE", evidence[Path("swift-test.log")])
            self.assertIn(str(scratch).encode(), evidence[Path("swift-test.log")])
            self.assertIn(b"exit_status=1", evidence[Path("result.txt")])
            self.assertIn(b"SYNTHETIC ADAPTER xcodebuild", evidence[Path("xcodebuild.log")])
            second = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
            self.assertEqual(len(list(logs.iterdir())), 2)
            self.assertEqual({p.relative_to(old): p.read_bytes() for p in old.rglob("*") if p.is_file()}, evidence)
            # The default scratch must be distinct from both explicit and previous default runs.
            defaults = []
            for _ in range(2):
                result = subprocess.run(command[:4], cwd=ROOT, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                defaults.append(next(line for line in result.stdout.splitlines() if line.startswith("Scratch: ")))
            self.assertNotEqual(defaults[0], defaults[1])
            self.assertTrue(all(str(scratch) not in value for value in defaults))

    def test_invalid_options_fail_before_running_checks(self):
        for args in [["--scratch-path"], ["--log-root", ""], ["--unknown"]]:
            result = subprocess.run(["bash", "scripts/check.sh", *args], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Logs:", result.stdout)


if __name__ == "__main__":
    unittest.main()
