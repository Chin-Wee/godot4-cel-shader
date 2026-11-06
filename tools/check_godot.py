#!/usr/bin/env python3
"""Run all headless first-party checks and copy checks; requires an imported demo and Godot 4.7."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    godot = shutil.which("godot")
    if godot is None:
        print("godot is not on PATH", file=sys.stderr)
        return 1
    output = Path(tempfile.mkdtemp(prefix="godot-checks-"))
    print(f"Logs and replay metrics: {output}", flush=True)
    failures = []
    for source in sorted((root / "src").rglob("*")):
        if source.suffix not in {".gd", ".gdshader", ".gdshaderinc", ".glsl", ".tres"}:
            continue
        relative = source.relative_to(root / "src")
        runtime = root / "demo" / ("src" if relative.parts[0] == "post" else "shaders") / relative
        canonical = source.read_text()
        copied = runtime.read_text() if runtime.is_file() else ""
        if relative.as_posix() == "cel-shader-base.gdshader":
            # Runtime painting is the deliberate wrapper difference; implementation is shared.
            copied = copied.replace("#define USE_COLOR_SATURATION 1", "#define USE_COLOR_SATURATION 0")
            copied = copied.replace("#define USE_PAINT_VARIATION 1", "#define USE_PAINT_VARIATION 0")
        if canonical != copied:
            failures.append(f"Distributable/demo copy differs: {relative}")
    tests = sorted((root / "demo").glob("aerial/tests/test_*.gd"))
    tests += sorted((root / "demo").glob("actors/mechs/tests/test_*.gd"))
    tests += sorted((root / "demo").glob("scripts/tests/test_*.gd"))
    for test in tests:
        for fps in ([30, 144, 240] if test.stem == "test_phantom_camera" else [60]):
            name = f"{test.stem}-{fps}"
            command = [godot, "--headless", "--fixed-fps", str(fps), "--path", str(root / "demo"),
                       "--script", "res://" + test.relative_to(root / "demo").as_posix(), "--"]
            command += [str(fps)] if test.stem == "test_phantom_camera" else [str(output / name), "--metrics-only"]
            log = output / f"{name}.log"
            with log.open("w") as stream:
                try:
                    result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
                except subprocess.TimeoutExpired:
                    failures.append(f"{name}: timed out; {log}")
                    print(f"FAIL {name}", flush=True)
                    continue
            # GDScript assertions can stop a coroutine while Godot exits zero.
            if result.returncode or "ERROR:" in log.read_text(errors="replace"):
                failures.append(f"{name}: {log}")
                print(f"FAIL {name}", flush=True)
            else:
                print(f"PASS {name}", flush=True)
    for failure in failures:
        print(failure, file=sys.stderr)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
