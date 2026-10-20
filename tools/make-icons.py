#!/usr/bin/env python3
"""Generate the app icons with Pillow: a side-view plank figure, elbow joint in brass."""
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("NEED PIL — run: /opt/homebrew/bin/python3 -m pip install pillow")

INK = (14, 26, 24)
PALE = (220, 230, 226)
FLOOR = (38, 60, 57)
BRASS = (201, 146, 47)
TRACK = (79, 163, 165)


def figure(size, inset=0.0):
    s = size
    img = Image.new("RGB", (s, s), INK)
    d = ImageDraw.Draw(img)
    pad = s * (0.10 + inset)
    w = s * 0.055

    floor_y = s * 0.80
    d.line([pad * 0.6, floor_y, s - pad * 0.6, floor_y], fill=FLOOR, width=int(s * 0.018))

    def P(xf, yf):
        x = pad + (s - 2 * pad) * xf
        y = pad + (s - 2 * pad) * yf
        return (x, y)

    shoulder = P(0.27, 0.44)
    hip = P(0.56, 0.50)
    knee = P(0.73, 0.53)
    ankle = P(0.90, 0.56)
    elbow = P(0.245, 0.63)
    wrist = P(0.34, 0.745)
    head = P(0.155, 0.385)

    d.line([hip, knee, ankle], fill=PALE, width=int(w), joint="curve")
    d.line([shoulder, hip], fill=PALE, width=int(w * 1.08), joint="curve")
    d.line([shoulder, elbow, wrist], fill=TRACK, width=int(w * 0.8), joint="curve")
    r = s * 0.085
    d.ellipse([head[0] - r, head[1] - r, head[0] + r, head[1] + r], fill=PALE)
    for pt, rad, col in ((elbow, 0.048, BRASS), (ankle, 0.030, PALE), (wrist, 0.030, TRACK)):
        rr = s * rad
        d.ellipse([pt[0] - rr, pt[1] - rr, pt[0] + rr, pt[1] + rr], fill=col)
    return img


def save(size, name, maskable=False):
    img = figure(size, inset=0.16 if maskable else 0.0)
    img.save("icons/" + name)
    print("wrote icons/%s (%dpx)" % (name, size))


save(512, "icon-512.png")
save(192, "icon-192.png")
save(512, "maskable-512.png", maskable=True)
save(192, "maskable-192.png", maskable=True)
save(180, "apple-touch-icon.png")
save(32, "favicon-32.png")
