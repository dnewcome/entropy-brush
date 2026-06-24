#!/usr/bin/env python3
"""Stream a 3Dconnexion SpaceMouse to entropy-brush over UDP.

Backends:
  (default)   spacenavd socket (/run/spnav.sock)
  --js        raw /dev/input/js0 (stop spacenavd first; it grabs the device)

Calibration (recommended — fixes per-device axis identity once and for all):
  --calibrate   walk through each gesture; detect which raw axis + direction it
                is; save a mapping so the app always gets correct semantic axes.

  --debug       print live axes.

    python3 tools/spacemouse.py --calibrate
    python3 tools/spacemouse.py            # then runs with your saved mapping
"""
import json
import os
import socket
import struct
import sys
import time

UDP = ("127.0.0.1", 5006)
DEBUG = "--debug" in sys.argv
USE_JS = "--js" in sys.argv
MAP_PATH = os.path.expanduser("~/.config/entropy-brush/spacemouse_map.json")
FIELDS = ["tx", "ty", "tz", "rx", "ry", "rz"]

# What each app field should do, and the gesture that drives it (positive dir).
CALIB = [
    ("tx", "SLIDE the cap to the RIGHT"),          # -> pan X
    ("ty", "PUSH the cap AWAY from you"),           # -> zoom in
    ("tz", "PRESS the cap straight DOWN"),          # -> pan Y
    ("rx", "TILT the top of the cap FORWARD (away)"),  # -> tilt fwd/back
    ("ry", "TWIST the cap CLOCKWISE"),              # -> spin canvas
    ("rz", "TILT the cap to the RIGHT"),            # -> tilt left/right
]


def load_map():
    try:
        with open(MAP_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


MAP = load_map()


def remap(axes):
    if not MAP:
        return axes
    out = [0.0] * 6
    for i, fld in enumerate(FIELDS):
        m = MAP.get(fld)
        if m:
            out[i] = m[1] * axes[m[0]]
    return out


def send(out, axes, buttons):
    a = remap(axes)
    out.sendto(json.dumps({
        "tx": a[0], "ty": a[1], "tz": a[2],
        "rx": a[3], "ry": a[4], "rz": a[5],
        "buttons": buttons[:4],
    }).encode(), UDP)
    if DEBUG:
        print("  ".join(f"a{i}:{v:+.2f}" for i, v in enumerate(axes)), end="\r")


# --- spacenavd backend -------------------------------------------------------

def _spnav_connect():
    sp = next((p for p in ("/run/spnav.sock", "/var/run/spnav.sock")
               if os.path.exists(p)), None)
    if not sp:
        sys.exit("spacenavd socket not found (try --js for the raw device).")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sp)
    return s, sp


def run_spacenavd(out):
    s, sp = _spnav_connect()
    EVENT = struct.Struct("<8i")
    axes = [0.0] * 6
    buttons = [0] * 4
    print(f"spacenavd {sp} → {UDP[0]}:{UDP[1]}"
          f"{'  [mapped]' if MAP else '  [raw — run --calibrate]'}. Ctrl-C to quit.")
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


# --- raw js0 backend ---------------------------------------------------------

def run_js(out):
    path = "/dev/input/js0"
    if not os.path.exists(path):
        sys.exit(f"{path} not found.")
    if os.path.exists("/run/spnav.sock"):
        print("NOTE: spacenavd grabs the device — js0 shows NO motion until you "
              "stop it (sudo systemctl stop spacenavd), or drop --js.",
              file=sys.stderr)
    ev = struct.Struct("IhBB")
    axes = [0.0] * 6
    buttons = [0] * 16
    print(f"RAW joystick {path} → {UDP[0]}:{UDP[1]}. Ctrl-C to quit.")
    with open(path, "rb") as f:
        while True:
            data = f.read(8)
            if not data:
                break
            _, value, etype, number = ev.unpack(data)
            etype &= ~0x80
            if etype == 0x02 and number < len(axes):
                axes[number] = max(-1.0, min(1.0, value / 32767.0))
            elif etype == 0x01 and number < len(buttons):
                buttons[number] = value
            send(out, axes, buttons)


# --- calibration (spacenavd) -------------------------------------------------

def calibrate():
    s, _ = _spnav_connect()
    s.settimeout(0.05)
    EVENT = struct.Struct("<8i")
    state = {"buf": b"", "axes": [0.0] * 6}

    def pump():
        try:
            state["buf"] += s.recv(256)
        except socket.timeout:
            return
        while len(state["buf"]) >= 32:
            data = EVENT.unpack(state["buf"][:32])
            state["buf"] = state["buf"][32:]
            if data[0] == 0:
                state["axes"] = [max(-1.0, min(1.0, v / 350.0)) for v in data[1:7]]

    def sample(dur):
        peak = [0.0] * 6
        end = time.time() + dur
        while time.time() < end:
            pump()
            for i in range(6):
                if abs(state["axes"][i]) > abs(peak[i]):
                    peak[i] = state["axes"][i]
        return peak

    print("Calibration — for each gesture: do it, KEEP HOLDING, then press Enter.\n")
    mapping = {}
    for field, instr in CALIB:
        while True:
            input(f"  {instr} and hold, then press Enter...")
            peak = sample(1.5)
            idx = max(range(6), key=lambda i: abs(peak[i]))
            if abs(peak[idx]) < 0.12:
                print("    (no clear motion — push firmer and keep holding)\n")
                continue
            sign = 1 if peak[idx] >= 0 else -1
            mapping[field] = [idx, sign]
            print(f"    detected raw axis {idx} (dir {sign:+d}, peak {peak[idx]:+.2f})\n")
            break

    os.makedirs(os.path.dirname(MAP_PATH), exist_ok=True)
    with open(MAP_PATH, "w") as f:
        json.dump(mapping, f, indent=2)
    print(f"Saved mapping → {MAP_PATH}")
    print("Run `python3 tools/spacemouse.py` and toggle Start SpaceMouse in the app.")
    print("If a direction feels inverted, re-run --calibrate moving the other way.")


def main():
    if "--calibrate" in sys.argv:
        calibrate()
        return
    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    (run_js if USE_JS else run_spacenavd)(out)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
