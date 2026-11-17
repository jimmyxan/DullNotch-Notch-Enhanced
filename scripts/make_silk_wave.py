"""'Silk Wave': two tapered sine strokes drifting in counter-phase. Seamless 2 s loop, transparent, 64x64."""
import json, math, sys

FR, OP, W, H = 60, 120, 64, 64
X0, X1 = 6.0, 58.0           # wave span
N = 13                       # vertices per path (same count every key -> safe morph)
STEP = 3                     # bake a key every 3 frames, linear between (continuous loop motion)
TAU = 2 * math.pi

# (stroke px, opacity %, max amplitude px, spatial cycles, temporal cycles per loop, phase, breath phase)
WAVES = [
    (3.5, 38, 17.0, 1.5, -1, 1.9, 2.4),   # back wave, opposite drift
    (4.5, 100, 20.0, 1.25, 1, 0.0, 0.0),  # hero wave
]

def y(x, t, amp, cyc, tc, ph, bph):
    u = (x - X0) / (X1 - X0)
    env = math.sin(math.pi * u) ** 2                      # tapers to 0 at both ends
    breath = 0.72 + 0.28 * math.sin(TAU * t / OP + bph)   # 1 cycle per loop -> seamless
    return H / 2 + amp * breath * env * math.sin(TAU * (cyc * u - tc * t / OP) + ph)

def path(t, *wp):
    xs = [X0 + (X1 - X0) * i / (N - 1) for i in range(N)]
    dx, e = (X1 - X0) / (N - 1), 1e-3
    v, ins, outs = [], [], []
    for x in xs:
        slope = (y(x + e, t, *wp) - y(x - e, t, *wp)) / (2 * e)
        tx, ty = dx / 3, slope * dx / 3                    # Hermite -> Bezier tangents
        v.append([round(x, 3), round(y(x, t, *wp), 3)])
        ins.append([round(-tx, 3), round(-ty, 3)])
        outs.append([round(tx, 3), round(ty, 3)])
    return {"c": False, "v": v, "i": ins, "o": outs}

LIN = {"o": {"x": 0, "y": 0}, "i": {"x": 1, "y": 1}}

def layer(idx, sw, op, *wp):
    kfs = [dict(t=t, s=[path(t, *wp)], **LIN) for t in range(0, OP, STEP)]
    kfs.append({"t": OP, "s": [path(OP, *wp)]})            # == frame 0 (integer cycles)
    return {
        "ty": 4, "nm": f"wave {idx}", "ind": idx, "ip": 0, "op": OP, "st": 0, "sr": 1, "ao": 0, "bm": 0,
        "ks": {"o": {"a": 0, "k": op}, "r": {"a": 0, "k": 0}, "p": {"a": 0, "k": [0, 0, 0]},
               "a": {"a": 0, "k": [0, 0, 0]}, "s": {"a": 0, "k": [100, 100, 100]}},
        "shapes": [{"ty": "gr", "nm": "wave", "it": [
            {"ty": "sh", "nm": "path", "ks": {"a": 1, "k": kfs}},
            # Horizontal silver gradient: bright core, cooler tails -> reinforces the taper.
            {"ty": "gs", "nm": "silver", "o": {"a": 0, "k": 100}, "w": {"a": 0, "k": sw}, "lc": 2, "lj": 2, "t": 1,
             "s": {"a": 0, "k": [X0, 0]}, "e": {"a": 0, "k": [X1, 0]},
             "g": {"p": 3, "k": {"a": 0, "k": [0, .62, .64, .70,  .5, 1, 1, 1,  1, .62, .64, .70]}}},
            {"ty": "tr", "p": {"a": 0, "k": [0, 0]}, "a": {"a": 0, "k": [0, 0]}, "s": {"a": 0, "k": [100, 100]},
             "r": {"a": 0, "k": 0}, "o": {"a": 0, "k": 100}},
        ]}],
    }

if __name__ == "__main__":
    wp0 = WAVES[1][2:]
    assert path(0, *wp0) == path(OP, *wp0), "loop seam"
    layers = [layer(len(WAVES) - i, w[0], w[1], *w[2:]) for i, w in enumerate(reversed(WAVES))]  # hero on top
    anim = {"v": "5.7.0", "fr": FR, "ip": 0, "op": OP, "w": W, "h": H, "nm": "Silk Wave", "ddd": 0,
            "assets": [], "layers": layers}
    json.dump(anim, open(sys.argv[1], "w"), separators=(",", ":"))
    print("ok", sys.argv[1])
