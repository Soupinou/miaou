"""Render Tulip: an original red-orange tulip, drawn procedurally.

Like Pompon, every pixel comes out of the maths below -- nothing is traced or
sampled from existing art. The flower head is a union of three pointed petals
(one in front, two behind) whose spread is driven by a single `openness`
value, so the closed bud, the half-open awake cup and every in-between frame of
waking up are the same shape at different settings. Leaves are bent blades
anchored at the stem foot, with their angle driving "low" (asleep) versus
"tall" (awake).
"""

import math
import os
import struct
import zlib
from dataclasses import dataclass, replace

CANVAS = 512

PETAL = (238, 78, 42, 255)
PETAL_LIGHT = (255, 136, 70, 255)
PETAL_TIP = (255, 210, 150, 255)
PETAL_SHADE = (178, 36, 26, 255)
PETAL_BACK = (204, 52, 32, 255)
PETAL_OUT = (64, 16, 10, 255)
LEAF = (102, 182, 80, 255)
LEAF_LIGHT = (156, 218, 112, 255)
LEAF_SHADE = (60, 130, 60, 255)
LEAF_OUT = (20, 52, 28, 255)
SOIL = (124, 84, 58, 255)
SOIL_LIGHT = (160, 114, 80, 255)
SOIL_OUT = (48, 28, 18, 255)
ROOT = (206, 160, 108, 255)
DARK = (34, 14, 24, 255)
WHITE = (255, 255, 255, 255)
BLUSH = (255, 170, 120, 255)
TONGUE = (255, 150, 120, 255)
SPARK = (255, 216, 64, 255)
SPARK_LIGHT = (255, 250, 214, 255)
CLEAR = (0, 0, 0, 0)

NEIGH4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
NEIGH8 = NEIGH4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def write_png(path, pixels, w, h):
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        for x in range(w):
            raw.extend(pixels[y][x])

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.cells = [[None] * w for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.cells[y][x] = c


def scan(g, pred):
    return {(x, y) for y in range(g.h) for x in range(g.w) if pred(x + 0.5, y + 0.5)}


def outline(g, inside, color):
    """Hard 1-cell outline drawn over whatever is already there, so each part
    stays separated from the one behind it."""
    for (x, y) in inside:
        for dx, dy in NEIGH8:
            if (x + dx, y + dy) not in inside:
                g.set(x + dx, y + dy, color)


def depth_map(inside):
    """Distance in cells from the silhouette edge."""
    depth = {}
    frontier = [c for c in inside
                if any((c[0] + dx, c[1] + dy) not in inside for dx, dy in NEIGH4)]
    for c in frontier:
        depth[c] = 1
    while frontier:
        nxt = []
        for (x, y) in frontier:
            for dx, dy in NEIGH4:
                c = (x + dx, y + dy)
                if c in inside and c not in depth:
                    depth[c] = depth[(x, y)] + 1
                    nxt.append(c)
        frontier = nxt
    return depth


# --- pose -------------------------------------------------------------------

@dataclass
class Pose:
    openness: float = 1.0      # 0 = closed bud, 1 = awake, a little open
    tilt: float = 0.0          # head rotation (radians, + leans right)
    stem: float = 9.5          # stem length
    lean: float = 0.0          # sideways offset of the head over the foot
    leaf_phi: float = 0.36     # leaf angle from vertical (0 = straight up)
    leaf_len: float = 12.5
    leaf_bend: float = 0.16
    leaf_droop: bool = False   # bend the tips down (asleep) instead of out
    leaf_wave: float = 0.0     # + raises the right leaf / lowers the left
    lift: float = 0.0          # whole plant off the ground
    roots: object = None       # phase of the dangling roots; None = hidden
    root_swing: float = 1.4    # how far the root tips sway
    mood: str = "awake"        # sleep | drowsy | awake | happy | lookup | tiny
    k: float = 1.0             # global geometry scale (status bar uses < 1)


GW, GH, SCALE = 37, 37, 13
BASELINE = 34.0


def petal_inside(lx, ly, cx, cy, a, b, theta):
    """Tulip petal: pointed tip on top, rounded base."""
    dx, dy = lx - cx, ly - cy
    c, s = math.cos(theta), math.sin(theta)
    u = dx * c + dy * s
    v = -dx * s + dy * c
    t = v / b
    if t < -1 or t > 1:
        return False
    w = a * ((1 - t * t) ** 0.85 if t < 0 else math.sqrt(1 - t * t))
    return abs(u) <= w


def head_parts(o):
    """(front petal, back petals) in head-local units, centre at the origin."""
    # Opening drops the front petal a little and fans the back ones out, so
    # their tips rise past it at the corners: the classic three-point cup.
    front = (0.0, 0.4 * o, 5.4 + 0.5 * o, 8.6 - 0.5 * o, 0.0)
    spread = 1.3 + 2.9 * o
    turn = 0.04 + 0.40 * o
    backs = [(-spread, 0.7 - 0.6 * o, 4.4, 8.2 + 0.2 * o, -turn),
             (spread, 0.7 - 0.6 * o, 4.4, 8.2 + 0.2 * o, turn)]
    return front, backs


HEAD_PIVOT = 7.4  # head-local y of where the stem joins
HEAD_K = 0.84     # head size relative to the rest of the plant


def draw_tulip(g, p, gw=GW, baseline=BASELINE):
    k = p.k
    foot_x = gw / 2.0
    foot_y = baseline - p.lift
    pivot = (foot_x + p.lean * k, foot_y - 1.0 * k - p.stem * k)

    hk = k * HEAD_K

    def to_local(px, py):
        rx, ry = px - pivot[0], py - pivot[1]
        c, s = math.cos(-p.tilt), math.sin(-p.tilt)
        lx = rx * c - ry * s
        ly = rx * s + ry * c
        return lx / hk, ly / hk + HEAD_PIVOT

    def to_world(lx, ly):
        lx, ly = lx * hk, (ly - HEAD_PIVOT) * hk
        c, s = math.cos(p.tilt), math.sin(p.tilt)
        return pivot[0] + lx * c - ly * s, pivot[1] + lx * s + ly * c

    # Leaves, behind everything. Each grows from the stem foot.
    for side in (-1, 1):
        phi = side * p.leaf_phi + p.leaf_wave
        bx, by = foot_x + side * 0.8 * k, foot_y - 1.2 * k
        d = (math.sin(phi), -math.cos(phi))
        n = (math.cos(phi), math.sin(phi))
        if p.leaf_droop:
            sign = 1 if n[1] > 0 else -1
        else:
            sign = 1 if n[0] * side > 0 else -1
        L, a = p.leaf_len * k, 2.7 * k

        def leaf_pred(px, py, bx=bx, by=by, d=d, n=n, sign=sign, L=L, a=a):
            rx, ry = px - bx, py - by
            t = (rx * d[0] + ry * d[1]) / L
            if t < 0 or t > 1:
                return False
            u = rx * n[0] + ry * n[1] - sign * p.leaf_bend * L * t * t
            return abs(u) <= a * math.sin(math.pi * t ** 0.8) + 0.15

        leaf = scan(g, leaf_pred)
        outline(g, leaf, LEAF_OUT)
        for (x, y) in leaf:
            rx, ry = x + 0.5 - bx, y + 0.5 - by
            t = (rx * d[0] + ry * d[1]) / L
            u = rx * n[0] + ry * n[1] - sign * p.leaf_bend * L * t * t
            if abs(u) < 0.55 and 0.12 < t < 0.8:
                col = LEAF_SHADE  # midrib
            elif u * side < 0:
                col = LEAF_LIGHT  # face towards the stem catches the light
            else:
                col = LEAF
            g.set(x, y, col)

    # Stem: a curve from the foot up to the head, two cells thick.
    stem = set()
    ctrl = (foot_x, (foot_y + pivot[1]) / 2)
    for i in range(80):
        t = i / 79
        sx = (1 - t) ** 2 * foot_x + 2 * (1 - t) * t * ctrl[0] + t * t * pivot[0]
        sy = (1 - t) ** 2 * (foot_y - 0.5) + 2 * (1 - t) * t * ctrl[1] + t * t * (pivot[1] + 1)
        stem.add((int(math.floor(sx - 0.5)), int(math.floor(sy))))
        stem.add((int(math.floor(sx + 0.5)), int(math.floor(sy))))
    outline(g, stem, LEAF_OUT)
    for (x, y) in stem:
        g.set(x, y, LEAF if (x + 1, y) in stem else LEAF_SHADE)

    srx, sry = 4.6 * k, 2.4 * k

    # Tiny roots wiggling out of the soil once it is off the ground.
    if p.roots is not None:
        roots = set()
        # Hair-thin strands: an outline would fuse them into a clump.
        # The sway grows towards the tip and travels down the strand, so the
        # roots wriggle rather than shift sideways as a block.
        for ox, length, drift, lag in ((-2.6, 5, -0.4, 0.0), (0.0, 6, 0.0, 2.1),
                                       (2.6, 5, 0.4, 4.2)):
            x0 = foot_x + ox * k
            prev = None
            for j in range(length):
                tip = j / (length - 1)
                x = x0 + drift * j + p.root_swing * tip * math.sin(p.roots + lag - 0.8 * j)
                cx, cy = int(math.floor(x)), int(math.floor(foot_y + 1.6 * k)) + j
                # Bridge sideways jumps so a strand never breaks into dots.
                if prev is not None:
                    step = 1 if cx > prev else -1
                    for bx in range(prev + step, cx, step):
                        roots.add((bx, cy - 1))
                roots.add((cx, cy))
                prev = cx
        for c in roots:
            g.set(*c, ROOT)

    # Little clump of soil the tulip stands in.
    soil = scan(g, lambda px, py: py <= foot_y + 0.6
                and ((px - foot_x) / srx) ** 2 + ((py - foot_y) / sry) ** 2 <= 1.0)
    outline(g, soil, SOIL_OUT)
    for (x, y) in soil:
        g.set(x, y, SOIL)
    for (x, y) in soil:
        if (x, y - 1) not in soil and (x + y) % 3 != 0:
            g.set(x, y, SOIL_LIGHT)

    # Flower head.
    front, backs = head_parts(p.openness)
    local = {}

    def head_pred(px, py):
        lx, ly = to_local(px, py)
        if petal_inside(lx, ly, *front):
            local[(int(px), int(py))] = (lx, ly, True)
            return True
        if any(petal_inside(lx, ly, *bp) for bp in backs):
            local[(int(px), int(py))] = (lx, ly, False)
            return True
        return False

    head = scan(g, head_pred)
    outline(g, head, PETAL_OUT)
    depth = depth_map(head)
    for c in head:
        lx, ly, is_front = local[c]
        if not is_front:
            col = PETAL_BACK
            if ly < -5.0:
                col = PETAL  # back petal tips peek out a touch lighter
        else:
            col = PETAL_LIGHT if ly < -5.2 else PETAL
            if ly > 3.0 and depth[c] <= 2:
                col = PETAL_SHADE
        g.set(*c, col)
    # Seam where the front petal overlaps the back ones.
    for c in head:
        if local[c][2] and any(
                (c[0] + dx, c[1] + dy) in head and not local[(c[0] + dx, c[1] + dy)][2]
                for dx, dy in NEIGH4):
            g.set(*c, PETAL_SHADE)
    # Sheen on the upper left of the front petal.
    for c in head:
        lx, ly, is_front = local[c]
        if is_front and ((lx + 2.6) / 1.2) ** 2 + ((ly + 2.6) / 2.2) ** 2 <= 1.0:
            g.set(*c, PETAL_TIP)

    draw_face(g, p.mood, to_world)
    hx, hy = to_world(0, 0)
    return hx, hy, k


def stamp(g, x, y, cells, color):
    for dx, dy in cells:
        g.set(x + dx, y + dy, color)


def draw_face(g, mood, to_world):
    """Stamped on in pixels at rotated positions -- never rotated itself."""
    if mood == "tiny":
        for side in (-1, 1):
            ex, ey = to_world(side * 2.6, 0.6)
            g.set(int(ex), int(ey), DARK)
        return

    for side in (-1, 1):
        ex, ey = (int(round(v)) for v in to_world(side * 2.9, 0.4))
        bx, by = (int(round(v)) for v in to_world(side * 4.2, 2.6))
        if mood in ("awake", "happy", "lookup", "drowsy"):
            stamp(g, bx, by, ((0, 0), (1, 0)) if side < 0 else ((-1, 0), (0, 0)), BLUSH)
        if mood in ("sleep", "drowsy"):
            # Closed: a little downward curve with the ends lifted.
            stamp(g, ex, ey, ((-1, 0), (0, 0), (1, 0)), DARK)
            stamp(g, ex, ey, ((-2, -1), (2, -1)), DARK)
        elif mood == "happy":
            # ^ ^ eyes.
            stamp(g, ex, ey, ((-2, 1), (-1, 0), (0, -1), (1, 0), (2, 1)), DARK)
        elif mood == "lookup":
            # Usual eyes, raised, with the pupils rolled up to the top.
            stamp(g, ex, ey - 1, ((0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)), DARK)
            g.set(ex + 1, ey - 1, WHITE)
        else:
            stamp(g, ex, ey, ((0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)), DARK)
            g.set(ex, ey, WHITE)  # glint

    mx, my = (int(round(v)) for v in to_world(0, 3.6))
    if mood == "awake":
        stamp(g, mx, my, ((-2, 0), (-1, 1), (0, 1), (1, 1), (2, 0)), DARK)
    elif mood == "drowsy":
        stamp(g, mx, my, ((-1, 0), (0, 1), (1, 0)), DARK)
    elif mood == "happy":
        stamp(g, mx, my, ((-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
                          (-2, 1), (2, 1), (-1, 2), (0, 2), (1, 2)), DARK)
        stamp(g, mx, my, ((-1, 1), (0, 1), (1, 1)), TONGUE)
    elif mood == "lookup":
        stamp(g, mx, my - 1, ((0, 0), (1, 0), (0, 1), (1, 1)), DARK)
    elif mood == "sleep":
        stamp(g, mx, my, ((0, 0), (1, 0)), DARK)


def draw_zs(g, x, y):
    for ox, oy, s in ((0, 0, 3), (4, -4, 4), (9, -8, 5)):
        bx, by = x + ox, y + oy
        for dx in range(s):
            g.set(bx + dx, by, DARK)
            g.set(bx + dx, by + s - 1, DARK)
        for d in range(s):
            g.set(bx + s - 1 - d, by + d, DARK)


def draw_sparkle(g, x, y, size=1):
    """Four-point yellow sparkle; size 0 is a single twinkle dot."""
    for d in range(1, size + 1):
        for ox, oy in NEIGH4:
            g.set(x + ox * d, y + oy * d, SPARK)
    g.set(x, y, SPARK_LIGHT)


def rasterize(g, scale, path):
    ox = (CANVAS - g.w * scale) // 2
    oy = (CANVAS - g.h * scale) // 2
    pixels = [[CLEAR] * CANVAS for _ in range(CANVAS)]
    for gy in range(g.h):
        for gx in range(g.w):
            c = g.cells[gy][gx]
            if c is None:
                continue
            for y in range(oy + gy * scale, oy + (gy + 1) * scale):
                for x in range(ox + gx * scale, ox + (gx + 1) * scale):
                    if 0 <= x < CANVAS and 0 <= y < CANVAS:
                        pixels[y][x] = c
    write_png(path, pixels, CANVAS, CANVAS)


# --- frames -----------------------------------------------------------------

AWAKE = Pose()
ASLEEP = Pose(openness=0.0, tilt=0.14, stem=4.5, lean=0.6, leaf_phi=1.38,
              leaf_len=10.0, leaf_bend=0.22, leaf_droop=True, mood="sleep")

TAU = 2 * math.pi


def walk_pose(i):
    ph = TAU * i / 6
    return replace(AWAKE,
                   lift=max(0.0, 2.0 * math.sin(ph)),
                   stem=AWAKE.stem + 0.6 * math.sin(ph),
                   tilt=0.06 * math.sin(ph + 1.0),
                   leaf_wave=0.12 * math.sin(ph))


def wake_pose(s):
    """s = 0 asleep -> 1 awake. Eyes stay shut until the petals start to part."""
    ease = s * s * (3 - 2 * s)
    mood = "sleep" if s < 0.45 else ("drowsy" if s < 0.75 else "awake")
    return Pose(openness=ease,
                tilt=ASLEEP.tilt * (1 - ease),
                stem=ASLEEP.stem + (AWAKE.stem - ASLEEP.stem) * ease
                + 0.8 * math.sin(math.pi * s),  # little stretch on the way up
                lean=ASLEEP.lean * (1 - ease),
                leaf_phi=ASLEEP.leaf_phi + (AWAKE.leaf_phi - ASLEEP.leaf_phi) * ease,
                leaf_len=ASLEEP.leaf_len + (AWAKE.leaf_len - ASLEEP.leaf_len) * ease,
                leaf_bend=ASLEEP.leaf_bend + (AWAKE.leaf_bend - ASLEEP.leaf_bend) * ease,
                leaf_droop=s < 0.5,
                mood=mood)


def dance_pose(i):
    sw = math.sin(TAU * i / 6)
    return replace(AWAKE, openness=1.15, mood="happy",
                   tilt=0.34 * sw, lean=2.6 * sw,
                   lift=1.2 * abs(math.cos(TAU * i / 6)),
                   leaf_phi=0.62, leaf_wave=0.45 * sw)


# Sparkles around the dancing head, shuffled per frame so they twinkle.
DANCE_SPARKLES = (
    ((-11, -9, 2), (10, -3, 1), (-8, 3, 0)),
    ((-10, -4, 1), (11, -10, 2), (9, 4, 0)),
    ((-12, -8, 0), (9, -7, 1), (-9, 1, 2)),
    ((-9, -11, 2), (11, -2, 0), (8, 3, 1)),
    ((-11, -3, 1), (10, -9, 2), (-7, 4, 0)),
    ((-10, -10, 0), (12, -5, 1), (9, 2, 2)),
)


def gen_pet(outdir, name):
    os.makedirs(outdir, exist_ok=True)

    def frame(pose, path, extra=None):
        g = Grid(GW, GH)
        hx, hy, _ = draw_tulip(g, pose)
        if extra:
            extra(g, hx, hy)
        rasterize(g, SCALE, f"{outdir}/{path}")

    for i in range(6):
        frame(walk_pose(i), f"{i:02d}_{name}_walk.png")

    def sparkles(i):
        def draw(g, hx, hy):
            for fx, fy, size in DANCE_SPARKLES[i]:
                draw_sparkle(g, int(hx) + fx, int(hy) + fy, size)
        return draw

    for i in range(6):
        frame(dance_pose(i), f"{i:02d}_{name}_notification.png", sparkles(i))

    for i in range(6):
        frame(wake_pose(i / 5), f"{i:02d}_{name}_sleep_to_walk.png")
        frame(wake_pose(1 - i / 5), f"{i:02d}_{name}_walk_to_sleep.png")

    # Lifted: plucked off the ground, looking up at whoever holds it, leaves
    # flailing and tiny roots wiggling under the soil.
    for i in range(6):
        sw = math.sin(TAU * i / 6)
        frame(replace(AWAKE, mood="lookup", lift=5.5, openness=0.8, roots=TAU * i / 6,
                      tilt=-0.18 * sw, lean=1.6 * sw,
                      leaf_phi=1.5, leaf_droop=True, leaf_wave=0.3 * sw),
              f"{i:02d}_{name}_lifted.png")

    # Lifted idle: dangling still, just breathing.
    for i in range(6):
        sw = math.sin(TAU * i / 6)
        frame(replace(AWAKE, mood="lookup", lift=5.5, roots=TAU * i / 6,
                      root_swing=0.9,
                      stem=AWAKE.stem + 0.4 * sw,
                      leaf_phi=1.45, leaf_droop=True, leaf_wave=0.08 * sw),
              f"{i:02d}_{name}_lifted_idle.png")

    def zs(g, hx, hy):
        draw_zs(g, int(hx) + 5, int(hy) - 7)

    frame(ASLEEP, f"00_{name}_sleep.png", zs)


def gen_statusbar(outdir):
    """Coarser grid: read at 22pt, so a scaled-down plant and a dot face."""
    os.makedirs(outdir, exist_ok=True)
    gw, gh, scale, baseline, k = 24, 22, 20, 20.0, 0.62

    g = Grid(gw, gh)
    draw_tulip(g, replace(ASLEEP, k=k, mood="tiny"), gw, baseline)
    rasterize(g, scale, f"{outdir}/icon_idle.png")

    for i in range(6):
        g = Grid(gw, gh)
        draw_tulip(g, replace(walk_pose(i), k=k, mood="tiny",
                              lift=walk_pose(i).lift * 0.5), gw, baseline)
        rasterize(g, scale, f"{outdir}/icon_{i + 1}.png")


if __name__ == "__main__":
    import sys
    root = sys.argv[1]
    gen_pet(f"{root}/tulip", "tulip")
    gen_statusbar(f"{root}/statusbar/tulip")
    print("done")
