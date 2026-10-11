#!/usr/bin/env python3
"""Draws Clamshell's mascot: a small red crab typing on a laptop.

Writes Resources/Sprites/{intro,loop,outro}_NN.png (full colour) and *_t_NN.png (monochrome "template"
versions for the menu-bar's black/white mode) plus preview.png for eyeballing the animation.

Pure standard library (PNG is written by hand), so it runs anywhere python3 does:  python3 tools/make_sprites.py
Each frame is drawn from parameters (lid angle, claw pose, blink...) rather than hand-pixelled, so changing
the motion means editing a few numbers.
"""
import os, struct, sys, zlib

W, H, SCALE = 22, 12, 3          # art grid and integer upscale -> 66x36 px, i.e. 18pt tall on a 2x display

# colour key -> (rgba, template alpha). Template alpha 0 means "hole" (shows the menu bar through).
PALETTE = {
    'R': ((0xE5, 0x4B, 0x4B, 255), 1.0),   # shell
    'r': ((0xA8, 0x2E, 0x3A, 255), 0.65),  # shell shade
    'h': ((0xFF, 0x8A, 0x7A, 255), 1.0),   # shell highlight
    'W': ((0xFF, 0xFF, 0xFF, 255), 0.0),   # eye white
    'K': ((0x14, 0x14, 0x1C, 255), 1.0),   # pupil
    'L': ((0xD3, 0xD9, 0xE2, 255), 1.0),   # laptop body
    'l': ((0x8B, 0x94, 0xA5, 255), 0.65),  # laptop shade
    'S': ((0x22, 0x2B, 0x3C, 255), 1.0),   # screen
    'C': ((0x7B, 0xEA, 0xF4, 255), 0.0),   # screen glow (code lines)
    'c': ((0x35, 0x86, 0x96, 255), 0.4),   # dim glow
    'G': ((0x6B, 0x74, 0x86, 255), 0.8),   # key gaps
}


class Grid:
    def __init__(self):
        self.p = [[None] * W for _ in range(H)]

    def put(self, x, y, k):
        if 0 <= x < W and 0 <= y < H:
            self.p[y][x] = k

    def rect(self, x0, y0, x1, y1, k):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, k)

    def hline(self, x0, x1, y, k):
        self.rect(x0, y, x1, y, k)


def crab_body(g, dy=0, blink=False, look=0):
    """Shell, eye stalks, legs. `dy` shifts it down (used when it sinks behind / rises from the laptop)."""
    # legs peek out below
    for lx in (3, 5, 16, 18):
        g.rect(lx, 9 + dy, lx, 10 + dy, 'r')
    # shell
    g.rect(6, 4 + dy, 15, 8 + dy, 'R')
    g.hline(7, 14, 3 + dy, 'R')
    g.hline(7, 12, 3 + dy, 'h'); g.put(13, 3 + dy, 'R')
    g.hline(6, 15, 8 + dy, 'r')
    g.put(6, 4 + dy, 'r'); g.put(15, 4 + dy, 'r')
    # eye stalks + eyes
    for ex in (8, 13):
        g.rect(ex, 1 + dy, ex, 3 + dy, 'R')
    for ex in (8, 13):
        if blink:
            g.hline(ex - 1, ex + 1, 1 + dy, 'K')
        else:
            g.put(ex - 1, 0 + dy, 'W'); g.put(ex, 0 + dy, 'W'); g.put(ex + 1, 0 + dy, 'W')
            g.put(ex - 1, 1 + dy, 'W'); g.put(ex, 1 + dy, 'W'); g.put(ex + 1, 1 + dy, 'W')
            g.put(ex + look, 1 + dy, 'K')


def claw(g, side, pose, dy=0):
    """pose: 'up' (raised), 'rest' (hanging by the shell), 'typeA'/'typeB' (tapping the keyboard)."""
    sgn = -1 if side == 'L' else 1
    x0 = 5 if side == 'L' else 16      # shoulder x, touching the shell
    # arm goes outwards then a pincer
    if pose == 'up':
        pts = [(x0 + sgn * 1, 6), (x0 + sgn * 2, 5), (x0 + sgn * 3, 4)]
        pinch = [(x0 + sgn * 3, 3), (x0 + sgn * 4, 3), (x0 + sgn * 4, 4), (x0 + sgn * 3, 2)]
    elif pose == 'rest':
        pts = [(x0 + sgn * 1, 7), (x0 + sgn * 2, 7)]
        pinch = [(x0 + sgn * 3, 7), (x0 + sgn * 3, 8), (x0 + sgn * 2, 8)]
    elif pose == 'typeA':   # claw lifted a little above the keys
        pts = [(x0 + sgn * 1, 7), (x0 + sgn * 2, 7), (x0 + sgn * 2, 8)]
        pinch = [(x0 + sgn * 2, 9), (x0 + sgn * 3, 9), (x0 + sgn * 3, 8)]
    else:                   # typeB: pressed down on the keys
        pts = [(x0 + sgn * 1, 7), (x0 + sgn * 2, 8), (x0 + sgn * 3, 8)]
        pinch = [(x0 + sgn * 3, 9), (x0 + sgn * 4, 9), (x0 + sgn * 4, 10)]
    for x, y in pts:
        g.put(x, y + dy, 'R')
    for x, y in pinch:
        g.put(x, y + dy, 'R')
    g.put(*[(pts[0][0], pts[0][1] + dy)][0], 'r')


def laptop(g, lid, glow, dy=0, keys=0, scroll=0):
    """lid: 0 = closed ... 5 = fully open. `dy` slides the whole laptop down (offscreen when >= 4)."""
    by = 9 + dy                              # base top row
    g.rect(3, by, 18, by + 1, 'L')
    g.hline(3, 18, by + 1, 'l')
    g.put(3, by, 'l'); g.put(18, by, 'l')
    # keyboard hint: key gaps
    if lid > 0:
        for x in range(5, 17, 2):
            g.put(x, by, 'G')
    if keys:
        g.put(5 + (keys * 2) % 12, by, 'h')  # a key flashing under a claw
    if lid <= 0:
        return
    # lid: grows upwards from the base's back edge
    top = by - lid
    g.rect(4, top, 17, by - 1, 'l')          # bezel
    if lid >= 2:
        g.rect(5, top + 1, 16, by - 2, 'S')  # screen
        if glow:
            rows = list(range(top + 1, by - 1))
            for i, y in enumerate(rows):
                n = ((i * 5 + scroll * 3) % 7) + 3
                col = 'C' if (i + scroll) % 3 else 'c'
                g.hline(6, min(15, 5 + n), y, col)


def render(frame):
    g = Grid()
    kind = frame['kind']
    if kind == 'crab_only':
        crab_body(g, blink=frame.get('blink', False), look=frame.get('look', 0))
        claw(g, 'L', frame.get('cl', 'rest')); claw(g, 'R', frame.get('cr', 'rest'))
        return g
    crab_body(g, blink=frame.get('blink', False), look=frame.get('look', 0))
    claw(g, 'L', frame.get('cl', 'rest')); claw(g, 'R', frame.get('cr', 'rest'))
    laptop(g, frame['lid'], frame.get('glow', False), frame.get('dy', 0), frame.get('keys', 0), frame.get('scroll', 0))
    return g


# --- the three sequences -------------------------------------------------------------------------------
INTRO = [
    dict(kind='crab_only', cl='up', cr='rest', look=1),
    dict(kind='crab_only', cl='rest', cr='up', look=-1),
    dict(kind='laptop', lid=0, dy=3),
    dict(kind='laptop', lid=0, dy=1, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=1, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=3, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=5, glow=False, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=5, glow=True, cl='typeA', cr='typeA', scroll=0),
]
LOOP = [
    dict(kind='laptop', lid=5, glow=True, cl='typeB', cr='typeA', scroll=0, keys=1),
    dict(kind='laptop', lid=5, glow=True, cl='typeA', cr='typeB', scroll=1, keys=3),
    dict(kind='laptop', lid=5, glow=True, cl='typeB', cr='typeA', scroll=2, keys=2),
    dict(kind='laptop', lid=5, glow=True, cl='typeA', cr='typeB', scroll=3, keys=5, blink=True),
    dict(kind='laptop', lid=5, glow=True, cl='typeB', cr='typeB', scroll=4, keys=4),
    dict(kind='laptop', lid=5, glow=True, cl='typeA', cr='typeA', scroll=5, keys=0),
    dict(kind='laptop', lid=5, glow=True, cl='typeB', cr='typeA', scroll=6, keys=1),
    dict(kind='laptop', lid=5, glow=True, cl='typeA', cr='typeB', scroll=7, keys=3),
]
OUTRO = [
    dict(kind='laptop', lid=5, glow=False, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=3, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=1, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=0, cl='typeA', cr='typeA'),
    dict(kind='laptop', lid=0, dy=2),
    dict(kind='laptop', lid=0, dy=4),
    dict(kind='crab_only', cl='up', cr='up', look=0),
    dict(kind='crab_only', cl='rest', cr='rest', blink=True),
]

# --- PNG output -----------------------------------------------------------------------------------------

def png_bytes(w, h, rgba_rows):
    raw = b''.join(b'\x00' + bytes(row) for row in rgba_rows)
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def to_rows(g, template):
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            k = g.p[y][x]
            if k is None:
                px = (0, 0, 0, 0)
            elif template:
                a = PALETTE[k][1]
                px = (0, 0, 0, int(round(255 * a)))
            else:
                px = PALETTE[k][0]
            row.append(px)
        for _ in range(SCALE):
            rows.append([c for px in row for _ in range(SCALE) for c in px])
    return W * SCALE, H * SCALE, rows


def export_large(path, frame=None, scale=12):
    """One typing frame as a big crisp PNG (used by the icon and the installer artwork)."""
    global SCALE
    old, SCALE = SCALE, scale
    w, h, rows = to_rows(render(frame or LOOP[2]), False)
    SCALE = old
    with open(path, 'wb') as fh:
        fh.write(png_bytes(w, h, rows))


def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--export-large':
        export_large(sys.argv[2], scale=int(sys.argv[3]) if len(sys.argv) > 3 else 12)
        return
    out = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'Sprites')
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith('.png'):
            os.remove(os.path.join(out, f))
    sheet = []
    for name, seq in (('intro', INTRO), ('loop', LOOP), ('outro', OUTRO)):
        for i, fr in enumerate(seq):
            g = render(fr)
            for template, suffix in ((False, ''), (True, 't_')):
                w, h, rows = to_rows(g, template)
                with open(os.path.join(out, f'{name}_{suffix}{i:02d}.png'), 'wb') as fh:
                    fh.write(png_bytes(w, h, rows))
            w, h, rows = to_rows(g, False)
            sheet.append(rows)
    # preview: all frames side by side on a dark bar, 1 row per sequence
    pad = 6
    seqs = [len(INTRO), len(LOOP), len(OUTRO)]
    maxn = max(seqs)
    pw, ph = maxn * (W * SCALE + pad) + pad, 3 * (H * SCALE + pad) + pad
    bg = (0x2A, 0x2F, 0x6B, 255)
    canvas = [[bg for _ in range(pw)] for _ in range(ph)]
    idx = 0
    for r, n in enumerate(seqs):
        for i in range(n):
            rows = sheet[idx]; idx += 1
            ox, oy = pad + i * (W * SCALE + pad), pad + r * (H * SCALE + pad)
            for y in range(H * SCALE):
                row = rows[y]
                for x in range(W * SCALE):
                    a = row[x * 4 + 3]
                    if a:
                        canvas[oy + y][ox + x] = (row[x*4], row[x*4+1], row[x*4+2], 255)
    flat = [[c for px in row for c in px] for row in canvas]
    with open(os.path.join(out, 'preview.png'), 'wb') as fh:
        fh.write(png_bytes(pw, ph, flat))
    print('wrote', sum(seqs), 'frames x2 to', os.path.normpath(out))


if __name__ == '__main__':
    main()
