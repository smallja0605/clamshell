#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns: the mascot (a typing frame) on a rounded gradient tile.
Needs ImageMagick (`magick`) and macOS `iconutil` — run once and commit the result."""
import math, os, shutil, struct, subprocess, sys, tempfile, zlib
sys.path.insert(0, os.path.dirname(__file__))

SIZE = 1024
TILE, RADIUS = 824, 186          # macOS icon template: 824pt tile centred in 1024, ~22.5% corner radius

def png(w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')

def tile_coverage(x, y):
    """Anti-aliased coverage of the rounded square (centre-based signed distance)."""
    cx = cy = SIZE / 2
    qx = abs(x - cx) - (TILE / 2 - RADIUS)
    qy = abs(y - cy) - (TILE / 2 - RADIUS)
    d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - RADIUS
    return min(1.0, max(0.0, 0.5 - d))

def main():
    # usage: make_icon.py [--gif animation.gif --frame N] [--out path.icns]
    args = sys.argv[1:]
    def opt(name, default=None):
        return args[args.index(name) + 1] if name in args else default
    gif, frame, out_path = opt('--gif'), opt('--frame', '20'), opt('--out')
    rows = []
    for y in range(SIZE):
        row = []
        t = y / SIZE
        # deep indigo -> teal gradient, top to bottom
        bg = (int(38 + 10 * t), int(40 + 70 * t), int(110 + 40 * t))
        for x in range(SIZE):
            cov = tile_coverage(x, y)
            if cov <= 0:
                row += [0, 0, 0, 0]; continue
            px = bg
            row += [px[0], px[1], px[2], int(255 * cov)]
        rows.append(row)
    tmp = tempfile.mkdtemp()
    base = os.path.join(tmp, 'icon_1024.png')
    open(base, 'wb').write(png(SIZE, SIZE, rows))
    # the mascot, drawn big with hard pixel edges and centred on the tile
    if gif:
        crab = os.path.join(tempfile.gettempdir(), 'clamshell_icon_crab.png')
        subprocess.run(['magick', gif + '[' + frame + ']', '-trim', '+repage', '-filter', 'point', '-resize', '420%', crab], check=True)
    else:
        crab = os.path.join(tempfile.gettempdir(), 'clamshell_icon_crab.png')
        subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'make_sprites.py'), '--export-large', crab, '26'], check=True)
    subprocess.run(['magick', base, crab, '-gravity', 'center', '-geometry', '+0+10', '-composite', base], check=True)
    iconset = os.path.join(tmp, 'AppIcon.iconset')
    os.makedirs(iconset)
    for s in (16, 32, 128, 256, 512):
        for scale_ in (1, 2):
            px = s * scale_
            name = f'icon_{s}x{s}' + ('@2x' if scale_ == 2 else '') + '.png'
            subprocess.run(['magick', base, '-filter', 'Lanczos', '-resize', f'{px}x{px}', os.path.join(iconset, name)], check=True)
    out = out_path or os.path.join(os.path.dirname(__file__), '..', 'Resources', 'AppIcon.icns')
    subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', out], check=True)
    shutil.rmtree(tmp)
    print('wrote', os.path.normpath(out))

if __name__ == '__main__':
    main()
