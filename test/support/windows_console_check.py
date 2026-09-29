"""Run TermUI through a real Windows ConPTY console and check its output."""

import argparse
import ctypes
import json
import os
from pathlib import Path
import queue
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time


def console_modes():
    from ctypes import wintypes

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetStdHandle.argtypes = [wintypes.DWORD]
    kernel.GetStdHandle.restype = wintypes.HANDLE
    kernel.GetConsoleMode.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel.GetConsoleMode.restype = wintypes.BOOL
    modes = []
    for identifier in (-10, -11):
        mode = wintypes.DWORD()
        handle = kernel.GetStdHandle(identifier)
        if not kernel.GetConsoleMode(handle, ctypes.byref(mode)):
            raise ctypes.WinError(ctypes.get_last_error())
        modes.append(mode.value)
    return modes


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def restore_console_modes(modes):
    from ctypes import wintypes

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetStdHandle.argtypes = [wintypes.DWORD]
    kernel.GetStdHandle.restype = wintypes.HANDLE
    kernel.SetConsoleMode.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.SetConsoleMode.restype = wintypes.BOOL
    for identifier, mode in zip((-10, -11), modes):
        if not kernel.SetConsoleMode(kernel.GetStdHandle(identifier), mode):
            raise ctypes.WinError(ctypes.get_last_error())


def run_child(shell, probe):
    before = console_modes()
    mix = shutil.which("mix")
    assert mix, "mix executable was not found"
    def command(arguments):
        args = [mix, "run", "--no-compile", *arguments]
        if shell == "cmd":
            return [os.environ["COMSPEC"], "/d", "/s", "/c", subprocess.list2cmdline(args)]
        bash = Path(os.environ["ProgramFiles"]) / "Git/bin/bash.exe"
        unix_mix = Path(mix).with_suffix("")
        assert bash.is_file() and unix_mix.is_file(), "Git Bash or the Mix shell script is absent"
        args[0] = unix_mix.as_posix()
        return [str(bash), "--noprofile", "--norc", "-c", "exec " + shlex.join(args)]

    # Compare with the same VM and shell without a TermUI runtime. OTP can
    # change a console flag during VM startup even when no application opens it.
    baseline = subprocess.run(command(["-e", ":ok"]), timeout=90, check=False)
    baseline_after = console_modes()
    assert baseline.returncode == 0, baseline.returncode
    restore_console_modes(before)
    assert console_modes() == before

    result = subprocess.run(command([f"test/support/{probe}.exs"]), timeout=90, check=False)
    after = console_modes()
    record = {"exit_code": result.returncode, "before": before, "vm_baseline": baseline_after, "after": after}
    Path(os.environ["TERM_UI_CONSOLE_PROGRESS"] + ".console").write_text(json.dumps(record), encoding="utf-8")
    assert result.returncode == 0, record
    assert after == baseline_after, f"Console modes differ from the plain VM: {record}"


class Console:
    def __init__(self, shell, backend, directory, probe="windows_console_probe"):
        import pyte
        from winpty import PtyProcess
        from winpty.enums import Backend

        self.progress = Path(directory) / f"{shell}-{backend}-{probe}.json"
        self.output = []
        self.pending = queue.Queue()
        self.screen = pyte.Screen(40, 10)
        self.stream = pyte.Stream(self.screen)
        environment = dict(
            os.environ,
            TERM="xterm-256color",
            COLORTERM="truecolor",
            MIX_ENV="dev",
            TERM_UI_CONSOLE_PROGRESS=str(self.progress),
            TERM_UI_CONSOLE_BACKEND=backend,
            TERM_UI_CONSOLE_FORCE_NATIVE="1",
        )
        # pywinpty 3.0.5 treats numeric zero as absent before it reads this
        # setting. Set it on the controller too, so ConPTY is explicit.
        os.environ["PYWINPTY_BACKEND"] = str(Backend.ConPTY)
        self.process = PtyProcess.spawn(
            [sys.executable, str(Path(__file__).resolve()), "--child", shell, probe],
            cwd=str(Path(__file__).resolve().parents[2]),
            env=environment,
            dimensions=(10, 40),
            backend=Backend.ConPTY,
        )
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        try:
            while True:
                self.pending.put(self.process.read(65536))
        except EOFError:
            self.pending.put(None)
        except Exception as error:
            self.pending.put(error)

    def wait(self, condition, message, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            try:
                data = self.pending.get(timeout=0.02)
            except queue.Empty:
                continue
            if isinstance(data, Exception):
                raise data
            if data is None:
                assert condition(), f"Console closed before {message}: {''.join(self.output)[-3000:]}"
                return
            self.output.append(data)
            self.stream.feed(data)
            if "\x1b[6n" in data:
                self.process.write(f"\x1b[{self.screen.cursor.y + 1};{self.screen.cursor.x + 1}R")
        state = json.dumps(self.state(), ensure_ascii=True)
        raise AssertionError(f"Timed out on {message}; state={state}; output={''.join(self.output)[-3000:]}")

    def state(self):
        return read_json(self.progress) or {}

    def send(self, text):
        self.process.write(text)

    def check_screen(self, count, width=40, height=10):
        def matches():
            first = self.screen.buffer[0][0]
            last = self.screen.buffer[height - 1][width - 1]
            return (
                self.screen.display[0].startswith(f"READY {count}")
                and self.screen.display[1].startswith("é界")
                and (first.fg, first.bg) == ("f0c814", "0a14b4")
                and last.data == "!"
            )

        self.wait(matches, f"rendered {width}x{height} frame {count}")

    def finish(self):
        result_path = Path(str(self.progress) + ".result")
        console_path = Path(str(self.progress) + ".console")
        self.wait(lambda: read_json(result_path) and read_json(console_path), "normal cleanup")
        result = read_json(result_path)
        modes = read_json(console_path)
        assert result["reason"] == ":normal", result
        assert result["manager_stopped"] and result["reader_stopped"], result
        assert modes["exit_code"] == 0 and modes["vm_baseline"] == modes["after"], modes

    def close(self):
        log = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / self.progress.with_suffix(".log").name
        log.write_text("".join(self.output), encoding="utf-8")
        self.process.close(force=True)


def check_application(shell, backend, directory):
    console = Console(shell, backend, directory)
    try:
        console.check_screen(0)
        expected_backend = "TermUI.Backend.Raw" if backend == "raw" else "TermUI.Backend.TTY"
        assert console.state()["backend"] == expected_backend, console.state()
        suffix = "\r" if backend == "tty" else ""
        console.send("é " + suffix)
        console.wait(
            lambda: {"text": "é"} in console.state().get("events", [])
            and {"text": " "} in console.state().get("events", []),
            "Unicode and space input",
        )

        if backend == "raw":
            console.send("\x1b[A\x0f\x03\x13\x11")
            expected = [
                {"key": "up", "modifiers": []},
                *[{"key": key, "modifiers": ["ctrl"]} for key in "ocsq"],
            ]
            console.wait(
                lambda: all(event in console.state().get("events", []) for event in expected),
                "arrow and control input",
            )

        console.screen.resize(lines=12, columns=52)
        console.process.setwinsize(12, 52)
        console.wait(lambda: console.state().get("dimensions") == [52, 12], "console resize")
        console.check_screen(len(console.state()["events"]), 52, 12)
        console.send("q" + suffix)
        console.finish()
        print(f"PASS {shell}/{backend}: cells, colors, Unicode, input, resize, shutdown, and console modes")
    finally:
        console.close()


def check_native_controls(directory):
    console = Console("cmd", "raw", directory, "raw_mode_pty_probe")
    try:
        console.wait(lambda: "__TERM_UI_READY__" in "".join(console.output), "native raw mode")
        console.send("\x0f\x03\x13\x11")
        console.wait(
            lambda: "__TERM_UI_RESULT__:0F031311::ok" in "".join(console.output),
            "native control bytes",
        )
        path = Path(str(console.progress) + ".console")
        console.wait(lambda: read_json(path), "native console cleanup")
        modes = read_json(path)
        assert modes["exit_code"] == 0 and modes["vm_baseline"] == modes["after"], modes
        print("PASS source NIF: Ctrl+O/C/S/Q and saved console modes")
    finally:
        console.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--child", nargs=2, metavar=("SHELL", "PROBE"))
    options = parser.parse_args()
    assert sys.platform == "win32", "This check requires a real Windows console"
    if options.child:
        run_child(*options.child)
        return
    with tempfile.TemporaryDirectory(prefix="term-ui-conpty-") as directory:
        for shell in ("cmd", "git-bash"):
            check_application(shell, "tty", directory)
            if os.environ.get("TERM_UI_TTY_NIF") != "disabled":
                check_application(shell, "raw", directory)
        if os.environ.get("TERM_UI_TTY_NIF") != "disabled":
            check_native_controls(directory)


if __name__ == "__main__":
    main()
