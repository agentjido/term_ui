"""A real PTY child for input, query, resize, and process cleanup checks."""
import fcntl
import json
import os
import select
import signal
import struct
import sys
import termios
import tty

record = sys.argv[1]
state = {"pid": os.getpid(), "input": "", "size": []}


def save():
    rows, columns, _, _ = struct.unpack("HHHH", fcntl.ioctl(0, termios.TIOCGWINSZ, bytes(8)))
    state["size"] = [rows, columns]
    with open(record + ".tmp", "w", encoding="utf-8") as file:
        json.dump(state, file)
    os.replace(record + ".tmp", record)


tty.setraw(0)
size_changed = False


def resized(*_):
    global size_changed
    size_changed = True


signal.signal(signal.SIGWINCH, resized)
save()
os.write(1, b"\x1b[2J\x1b[H\x1b[?2004h\x1b[?1004h\x1b[?1000h\x1b[?1006h")
os.write(1, "\x1b[38;2;12;34;56mé界\x1b[0m\x1b[6n\r\nREADY".encode())
while True:
    if size_changed:
        size_changed = False
        save()
    if not select.select([0], [], [], 0.05)[0]:
        continue
    data = os.read(0, 4096)
    state["input"] += data.hex()
    save()
    if b"\x04" in data:
        break
