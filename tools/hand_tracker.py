#!/usr/bin/env python3
"""entropybrush webcam hand tracker.

Tracks one hand with MediaPipe and streams brush input to the Flutter app over
UDP. Pinch thumb + index together to "press the brush down"; the pinch midpoint
is the brush position and how hard you pinch is the pressure.

Setup:
    python3 -m venv .venv && source .venv/bin/activate
    pip install mediapipe opencv-python

Run (with the app open and "Start webcam" toggled on):
    python3 tools/hand_tracker.py

Keys: q to quit. A preview window shows the tracked hand; the dot turns green
when the brush is "down".
"""
import json
import math
import socket
import sys

try:
    import cv2
    import mediapipe as mp
except ImportError:
    sys.exit("Missing deps. Run: pip install mediapipe opencv-python")

UDP_IP = "127.0.0.1"
UDP_PORT = 5005
PINCH_DOWN = 0.06   # normalized thumb-index distance below which the brush is down

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
mp_hands = mp.solutions.hands
mp_draw = mp.solutions.drawing_utils

cap = cv2.VideoCapture(0)
if not cap.isOpened():
    sys.exit("Could not open webcam (device 0).")

last_x, last_y = 0.5, 0.5

print(f"Streaming hand input to {UDP_IP}:{UDP_PORT}. Pinch to paint, 'q' to quit.")

with mp_hands.Hands(
    max_num_hands=1,
    min_detection_confidence=0.6,
    min_tracking_confidence=0.5,
) as hands:
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        # Mirror so moving your hand right moves the brush right (selfie view).
        frame = cv2.flip(frame, 1)
        result = hands.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))

        down = False
        pressure = 0.0
        if result.multi_hand_landmarks:
            lm = result.multi_hand_landmarks[0].landmark
            ix, iy = lm[8].x, lm[8].y    # index fingertip
            tx, ty = lm[4].x, lm[4].y    # thumb tip
            dist = math.hypot(ix - tx, iy - ty)
            down = dist < PINCH_DOWN
            # Brush point = midpoint of the pinch (stable between the two tips).
            last_x, last_y = (ix + tx) / 2.0, (iy + ty) / 2.0
            if down:
                pressure = max(0.05, min(1.0, (PINCH_DOWN - dist) / PINCH_DOWN + 0.3))

            mp_draw.draw_landmarks(
                frame, result.multi_hand_landmarks[0], mp_hands.HAND_CONNECTIONS
            )
            color = (0, 220, 0) if down else (0, 0, 230)
            h, w = frame.shape[:2]
            cv2.circle(frame, (int(last_x * w), int(last_y * h)), 12, color, -1)

        packet = {"x": last_x, "y": last_y, "down": bool(down), "pressure": float(pressure)}
        sock.sendto(json.dumps(packet).encode(), (UDP_IP, UDP_PORT))

        cv2.putText(
            frame,
            "PINCH to paint" if not down else "painting",
            (10, 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (255, 255, 255),
            2,
        )
        cv2.imshow("entropybrush hand tracker", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

cap.release()
cv2.destroyAllWindows()
