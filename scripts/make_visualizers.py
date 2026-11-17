"""Generate the closed-notch music animations (Lottie JSON, 64x64, 60 fps, seamless 2 s loop).

Usage: python3 scripts/make_visualizers.py <out_dir>
Every property is sampled from a function of t and baked as linear keyframes: easy to tune,
and loops are seamless because every function completes a whole number of cycles in OP frames.
"""
import json, math, os, sys

FR, OP, W, H = 60, 120, 64, 64
C = W / 2
TAU = 2 * math.pi
STEP = 2
SILVER = [0.93, 0.94, 0.96, 1]
LIN = {"o": {"x": [0], "y": [0]}, "i": {"x": [1], "y": [1]}}


def prop(v):
    """Static value, or a function of t baked to keyframes."""
    if not callable(v):
        return {"a": 0, "k": v}
    as_list = lambda x: [round(c, 3) for c in x] if isinstance(x, (list, tuple)) else [round(x, 3)]
    vals = [as_list(v(t)) for t in range(0, OP + 1, STEP)]
    if all(x == vals[0] for x in vals):
        return {"a": 0, "k": vals[0] if len(vals[0]) > 1 else vals[0][0]}
    kfs = [dict(t=t, s=s, **LIN) for t, s in zip(range(0, OP, STEP), vals)]
    kfs.append({"t": OP, "s": vals[-1]})
    return {"a": 1, "k": kfs}


def tr(p=(0, 0), s=(100, 100), r=0, o=100):
    return {"ty": "tr", "p": prop(p), "a": prop([0, 0]), "s": prop(s), "r": prop(r), "o": prop(o)}


def group(*items, **t):
    return {"ty": "gr", "it": list(items) + [tr(**t)]}


def ellipse(size, p=(0, 0)):
    return {"ty": "el", "p": prop(list(p)), "s": prop(size)}


def rect(size, p=(0, 0), r=0):
    return {"ty": "rc", "p": prop(list(p)), "s": prop(list(size)), "r": prop(r)}


def path(v, i=None, o=None, closed=False):
    z = [[0, 0]] * len(v)
    return {"ty": "sh", "ks": {"a": 0, "k": {"c": closed, "v": v, "i": i or z, "o": o or z}}}


def fill(color=SILVER, o=100):
    return {"ty": "fl", "c": prop(color), "o": prop(o), "r": 1}


def stroke(w, color=SILVER, o=100):
    return {"ty": "st", "c": prop(color), "o": prop(o), "w": prop(w), "lc": 2, "lj": 2}


def silver_linear(y0, y1):
    """Vertical silver gradient fill, bright on top."""
    return {"ty": "gf", "t": 1, "o": prop(100), "r": 1, "s": prop([0, y0]), "e": prop([0, y1]),
            "g": {"p": 3, "k": {"a": 0, "k": [0, 1, 1, 1, .5, .87, .88, .91, 1, .6, .62, .67]}}}


def radial(radius, stops, alphas):
    return {"ty": "gf", "t": 2, "o": prop(100), "r": 1, "s": prop([0, 0]), "e": prop([radius, 0]),
            "h": prop(0), "a": prop(0), "g": {"p": len(stops) // 4, "k": {"a": 0, "k": stops + alphas}}}


def trim(s, e, offset=0):
    return {"ty": "tm", "s": prop(s), "e": prop(e), "o": prop(offset), "m": 1}


def layer(name, *shapes, p=(C, C), s=(100, 100), r=0, o=100):
    sp = (lambda t: list(p(t)) + [0]) if callable(p) else list(p) + [0]
    ss = (lambda t: list(s(t)) + [100]) if callable(s) else list(s) + [100]
    return {"ty": 4, "nm": name, "ip": 0, "op": OP, "st": 0, "sr": 1, "ao": 0, "bm": 0,
            "ks": {"o": prop(o), "r": prop(r), "p": prop(sp), "a": prop([0, 0, 0]), "s": prop(ss)},
            "shapes": list(shapes)}


def comp(name, layers):
    for i, l in enumerate(layers):
        l["ind"] = i + 1
    return {"v": "5.7.0", "fr": FR, "ip": 0, "op": OP, "w": W, "h": H, "nm": name, "ddd": 0,
            "assets": [], "layers": layers}


def smooth(x):  # 0..1 -> 0..1 ease-in-out
    x = min(max(x, 0), 1)
    return x * x * (3 - 2 * x)


# 1 ─ Pulse Rings: rings born at the centre, widening and fading like sound from above.
def pulse_rings():
    def ring(i):
        ph = lambda t: (t / OP + i / 3) % 1
        size = lambda t: [8 + 50 * (1 - (1 - ph(t)) ** 2)] * 2          # fast out, slow end
        op = lambda t: 100 * smooth(ph(t) / 0.12) * (1 - smooth((ph(t) - 0.35) / 0.65))
        width = lambda t: 4 - 2.4 * ph(t)
        return layer(f"ring {i}", group(ellipse(size), stroke(width)), o=op)
    core = layer("core", group(ellipse([9, 9]), silver_linear(-4.5, 4.5)),
                 s=lambda t: [100 + 14 * math.sin(TAU * 3 * t / OP)] * 2)
    return comp("Pulse Rings", [core] + [ring(i) for i in range(3)])


# 2 ─ Vinyl: a record spinning at ~30 rpm under a fixed reflection.
def vinyl():
    glint = layer("glint", group(ellipse([40, 40]), trim(0, 9, 30), stroke(2.2, o=lambda t: 32 + 10 * math.sin(TAU * t / OP))),
                  group(ellipse([40, 40]), trim(0, 9, 210), stroke(2.2, o=lambda t: 32 - 10 * math.sin(TAU * t / OP))))
    disc = layer("disc",
                 group(rect([5.5, 1.6], (5.8, 0), 0.8), fill([0.32, 0.33, 0.36, 1])),          # label mark: shows the spin
                 group(ellipse([2.6, 2.6]), fill([0, 0, 0, 1])),                              # spindle hole
                 group(ellipse([20, 20]), silver_linear(-10, 10)),                            # label
                 group(ellipse([31, 31]), stroke(0.9, o=22)),                                 # grooves
                 group(ellipse([42, 42]), stroke(0.9, o=16)),
                 group(ellipse([54, 54]), fill([0.13, 0.13, 0.15, 1]), stroke(1.4, [0.42, 0.43, 0.47, 1])),
                 r=lambda t: 360 * t / OP)
    return comp("Vinyl", [glint, disc])


# 3 ─ Orbit: three dots on one orbit, drifting closer and apart, each with a short trail.
def orbit():
    R = 18

    def angle(i, t):
        return TAU * t / OP + TAU * i / 3 + 0.45 * math.sin(TAU * 2 * t / OP + i * 2.1)

    def dot(i, lag, size, o):
        pos = lambda t: [C + R * math.cos(angle(i, t) - lag), C + R * math.sin(angle(i, t) - lag)]
        return layer(f"dot {i}/{lag}", group(ellipse([size, size]), fill(o=o)), p=pos)

    layers = []
    for i in range(3):
        layers += [dot(i, 0, 8, 100), dot(i, 0.22, 6, 45), dot(i, 0.42, 4.5, 22), dot(i, 0.6, 3, 10)]
    ring = layer("orbit", group(ellipse([2 * R, 2 * R]), stroke(1, o=12)))
    return comp("Orbit", layers + [ring])


# 4 ─ Dot Matrix: 4x4 LED dots; each column lights up to its own level, like an old stereo.
def dot_matrix():
    cols, rows, gap, d = 4, 4, 13, 7.5
    x0 = C - gap * (cols - 1) / 2
    y0 = C + gap * (rows - 1) / 2

    def level(c, t):  # 0..rows, two integer harmonics per column
        u = TAU * t / OP
        return 2.1 + 1.3 * math.sin((c + 1) * u + c * 1.7) + 0.8 * math.sin((5 - c) * u + c)

    layers = []
    for c in range(cols):
        for r in range(rows):
            lit = lambda t, c=c, r=r: 14 + 86 * smooth(level(c, t) - r)
            layers.append(layer(f"led {c}{r}", group(ellipse([d, d]), fill()), p=(x0 + c * gap, y0 - r * gap), o=lit))
    return comp("Dot Matrix", layers)


# 5 ─ Breathing Orb: a soft radial orb inhaling and exhaling once per loop.
def breathing_orb():
    breath = lambda t: 0.5 - 0.5 * math.cos(TAU * t / OP)               # 0 -> 1 -> 0
    halo = layer("halo", group(ellipse([60, 60]), radial(30, [0, .85, .87, .92, 1, .85, .87, .92], [0, .35, .55, .12, 1, 0])),
                 s=lambda t: [78 + 22 * breath(t)] * 2, o=lambda t: 45 + 55 * breath(t))
    orb = layer("orb", group(ellipse([34, 34]), radial(17, [0, 1, 1, 1, .55, .86, .87, .9, 1, .55, .57, .62], [0, 1, 1, 1])),
                s=lambda t: [80 + 20 * breath(t)] * 2)
    return comp("Breathing Orb", [orb, halo])


# 6 ─ 3D Orbit: three dots on a tilted ring seen edge-on; nearer dots are bigger and brighter.
# Recreated from the "3D Orbit Dots Loader" Lottie: same motion, silver instead of copper.
def orbit_3d():
    RX, RY, D = 21, 6, 10

    def dot(i, front):
        a = lambda t: TAU * t / OP + TAU * i / 3
        z = lambda t: math.sin(a(t))                                     # +1 nearest the viewer
        pos = lambda t: [C + RX * math.cos(a(t)), C + RY * z(t)]
        size = lambda t: [D * (1 + 0.32 * z(t))] * 2
        grey = lambda t: [0.5 + 0.46 * (z(t) + 1) / 2] * 3 + [1]
        # each dot exists twice, below and above the others; only the copy on the right side shows
        vis = lambda t: 100 if (z(t) > -1e-9) == front else 0
        return layer(f"dot {i} {'front' if front else 'back'}", group(ellipse(size), fill(grey)), p=pos, o=vis)

    return comp("3D Orbit", [dot(i, True) for i in range(3)] + [dot(i, False) for i in range(3)])


ALL = {"pulse-rings": pulse_rings, "vinyl": vinyl, "orbit": orbit,
       "dot-matrix": dot_matrix, "breathing-orb": breathing_orb, "orbit-3d": orbit_3d}

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, make in ALL.items():
        data = make()
        js = json.dumps(data, separators=(",", ":"))
        # loop seam: every animated property must end where it starts
        for l in data["layers"]:
            for k, v in l["ks"].items():
                if v["a"] and k != "r":  # rotation may end a full turn later
                    assert all(abs(a - b) < 0.6 for a, b in zip(v["k"][0]["s"], v["k"][-1]["s"])), (name, l["nm"], k)
        open(os.path.join(out, f"{name}.json"), "w").write(js)
        print(f"{name}: {len(js) / 1024:.1f} KB")
