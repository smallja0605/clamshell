#!/usr/bin/env python3
"""Synthesises Clamshell's completion chime (two soft bell notes) into Resources/Sounds/chime.wav. Standard library only."""
import math, os, struct, wave

RATE = 44100
NOTES = [(0.00, 659.25), (0.13, 987.77)]   # E5 then B5
LENGTH = 0.95

def sample(t):
    v = 0.0
    for start, freq in NOTES:
        if t < start:
            continue
        dt = t - start
        env = math.exp(-dt * 5.5) * min(1.0, dt / 0.004)       # fast attack, bell-like decay
        v += env * (math.sin(2 * math.pi * freq * dt)
                    + 0.28 * math.sin(2 * math.pi * freq * 2.0 * dt) * math.exp(-dt * 4)
                    + 0.12 * math.sin(2 * math.pi * freq * 3.01 * dt) * math.exp(-dt * 7))
    return v

def main():
    out = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'Sounds')
    os.makedirs(out, exist_ok=True)
    n = int(RATE * LENGTH)
    data = [sample(i / RATE) for i in range(n)]
    peak = max(abs(x) for x in data) or 1
    frames = b''.join(struct.pack('<h', int(x / peak * 0.6 * 32767)) for x in data)
    with wave.open(os.path.join(out, 'chime.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(frames)
    print('wrote chime.wav')

if __name__ == '__main__':
    main()
