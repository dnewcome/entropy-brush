#!/usr/bin/env python3
"""Stream a 3Dconnexion SpaceMouse to entropy-brush over UDP.

The app integrates the 6 axes into the view: translate to pan, push/pull to
zoom, tilt/twist to orbit. Use it with your non-dominant hand while you paint.

Setup:
    pip install pyspacemouse
    # Linux also needs hidapi + permission to read the device:
    #   sudo apt install libhidapi-hidraw0
    #   add a udev rule for 3Dconnexion (vendor 256f/046d) or run with sudo.

Run (then toggle "Start SpaceMouse" in the app):
    python3 tools/spacemouse.py
"""
import json
import socket
import sys
import time

try:
    import pyspacemouse
except ImportError:
    sys.exit("Missing dep. Run: pip install pyspacemouse")

UDP = ("127.0.0.1", 5006)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

if not pyspacemouse.open():
    sys.exit("No SpaceMouse found (check it's plugged in and you have "
             "permission to read the HID device).")

print("Streaming SpaceMouse to 127.0.0.1:5006. Ctrl-C to quit.")
try:
    while True:
        st = pyspacemouse.read()
        pkt = {
            "tx": st.x, "ty": st.y, "tz": st.z,
            "rx": st.roll, "ry": st.pitch, "rz": st.yaw,
            "buttons": list(st.buttons),
        }
        sock.sendto(json.dumps(pkt).encode(), UDP)
        time.sleep(0.005)  # ~200 Hz
except KeyboardInterrupt:
    pass
finally:
    pyspacemouse.close()
