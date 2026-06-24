#!/usr/bin/env python3
"""Stream a 3Dconnexion SpaceMouse to entropy-brush over UDP.

Two backends:

  (default) spacenavd socket — reads /run/spnav.sock. Convenient if the
            spacenavd daemon is running, but spacenavd applies its OWN default
            axis convention (sensitivity, dead-zone, axis identity) before you
            see it. No custom config is needed for this to differ from raw.

  --js      RAW joystick — reads /dev/input/js0 directly (Linux joystick API,
            stdlib only, world-readable, NO spacenavd in the loop). Use this to
            see the device's true axis numbers, or to avoid the daemon entirely.

Add --debug to print the live axes so you can identify which axis each gesture
moves, then tell me and I'll map it exactly.

    python3 tools/spacemouse.py            # via spacenavd
    python3 tools/spacemouse.py --js --debug
"""
import json
import os
import socket
import struct
import sys

UDP = ("127.0.0.1", 5006)
DEBUG = "--debug" in sys.argv
USE_JS = "--js" in sys.argv


def send(out, axes, buttons):
    out.sendto(json.dumps({
        "tx": axes[0], "ty": axes[1], "tz": axes[2],
        "rx": axes[3], "ry": axes[4], "rz": axes[5],
        "buttons": buttons[:4],
    }).encode(), UDP)
    if DEBUG:
        print("  ".join(f"a{i}:{a:+.2f}" for i, a in enumerate(axes)), end="\r")


def run_js(out):
    """Raw /dev/input/js0 — bypasses spacenavd. js_event = u32,s16,u8,u8 (8B)."""
    path = "/dev/input/js0"
    if not os.path.exists(path):
        sys.exit(f"{path} not found.")
    ev = struct.Struct("IhBB")
    axes = [0.0] * 6
    buttons = [0] * 16
    print(f"RAW joystick {path} → {UDP[0]}:{UDP[1]}  (no spacenavd). Ctrl-C to quit.")
    if os.path.exists("/run/spnav.sock"):
        print("NOTE: spacenavd is running and grabs the device — js0 will show "
              "NO motion until you stop it:\n      sudo systemctl stop spacenavd\n"
              "      (or just drop --js to read via spacenavd instead).",
              file=sys.stderr)
    with open(path, "rb") as f:
        while True:
            data = f.read(8)
            if not data:
                break
            _, value, etype, number = ev.unpack(data)
            etype &= ~0x80  # strip JS_EVENT_INIT
            if etype == 0x02 and number < len(axes):  # axis
                axes[number] = max(-1.0, min(1.0, value / 32767.0))
            elif etype == 0x01 and number < len(buttons):  # button
                buttons[number] = value
            send(out, axes, buttons)


def run_spacenavd(out):
    """spacenavd legacy v0 socket: 8×int32LE per event."""
    sp = next((p for p in ("/run/spnav.sock", "/var/run/spnav.sock")
               if os.path.exists(p)), None)
    if not sp:
        sys.exit("spacenavd socket not found (try --js for the raw device).")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sp)
    EVENT = struct.Struct("<8i")
    axes = [0.0] * 6
    buttons = [0] * 4
    print(f"spacenavd {sp} → {UDP[0]}:{UDP[1]}. Ctrl-C to quit.")
    buf = b""
    while True:
        chunk = s.recv(256)
        if not chunk:
            break
        buf += chunk
        while len(buf) >= 32:
            data = EVENT.unpack(buf[:32])
            buf = buf[32:]
            if data[0] == 0:
                axes = [max(-1.0, min(1.0, v / 350.0)) for v in data[1:7]]
            elif data[0] in (1, 2) and data[1] < len(buttons):
                buttons[data[1]] = 1 if data[0] == 1 else 0
            send(out, axes, buttons)


def main():
    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    (run_js if USE_JS else run_spacenavd)(out)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
