#!/usr/bin/env python3
"""Stream a 3Dconnexion SpaceMouse to entropy-brush over UDP.

On Linux the device is usually owned by the **spacenavd** daemon, which exposes
a world-readable UNIX socket. This reads from that socket (stdlib only — no
pyspacemouse, no HID permissions, no udev rules, no sudo). The app integrates
the 6 axes into the view: translate→pan, push/pull→zoom, tilt/twist→orbit.

Requires spacenavd running (it already is if `pgrep spacenavd` shows it):
    sudo apt install spacenavd && sudo systemctl enable --now spacenavd

Run (then toggle "Start SpaceMouse" in the app):
    python3 tools/spacemouse.py        # add --debug to watch raw axes
"""
import json
import os
import socket
import struct
import sys

UDP = ("127.0.0.1", 5006)
SOCK_PATHS = ["/run/spnav.sock", "/var/run/spnav.sock"]
SCALE = 350.0  # spacenavd raw axis range is roughly -350..350
DEBUG = "--debug" in sys.argv

# spacenavd legacy (v0) unix protocol: 8 little-endian int32 per event.
#   data[0] = 0 motion (data[1..6] = x,y,z,rx,ry,rz, data[7] = period)
#           = 1 button press (data[1] = button #)
#           = 2 button release
EVENT = struct.Struct("<8i")


def main():
    sock_path = next((p for p in SOCK_PATHS if os.path.exists(p)), None)
    if not sock_path:
        sys.exit("spacenavd socket not found — is spacenavd running? "
                 "(sudo systemctl enable --now spacenavd)")

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(sock_path)
    except OSError as e:
        sys.exit(f"Could not connect to spacenavd at {sock_path}: {e}")

    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    axes = [0.0] * 6
    buttons = [0] * 4
    print(f"Reading SpaceMouse via spacenavd ({sock_path}); "
          f"streaming to {UDP[0]}:{UDP[1]}. Ctrl-C to quit.")

    buf = b""
    while True:
        chunk = s.recv(256)
        if not chunk:
            break
        buf += chunk
        while len(buf) >= EVENT.size:
            data = EVENT.unpack(buf[:EVENT.size])
            buf = buf[EVENT.size:]
            if data[0] == 0:  # motion
                axes = [max(-1.0, min(1.0, v / SCALE)) for v in data[1:7]]
                if DEBUG:
                    print("  ".join(f"{a:+.2f}" for a in axes), end="\r")
            elif data[0] in (1, 2):  # button press / release
                b = data[1]
                if 0 <= b < len(buttons):
                    buttons[b] = 1 if data[0] == 1 else 0
            out.sendto(json.dumps({
                "tx": axes[0], "ty": axes[1], "tz": axes[2],
                "rx": axes[3], "ry": axes[4], "rz": axes[5],
                "buttons": buttons,
            }).encode(), UDP)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
