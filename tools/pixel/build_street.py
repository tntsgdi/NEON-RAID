"""第十三街雨巷检查站的场景像素资源 → assets/tiles/street、assets/bg、assets/props

- 地图块（16×16）：混凝土地面（湿的顶面）、钢格栅薄平台、钢板墙；顶 / 侧 / 内部 / 深处 / 底面若干变体
- 视差背景（横向可无缝平铺）：L1 远景天际线、L2 中景楼体（窗格、防火梯、灯牌）、L3 近景墙（管道、钢梁、电缆、通风口）
- 道具：路灯、检查站岗亭、闸门（栏杆）、灯牌 ×3、空调外机、通风扇（4 帧）、积水
原则：背景越远越暗、越低对比，绝不比角色抢眼；高饱和颜色只用在很小的灯点上。
运行：G:/audio_library/venv/Scripts/python.exe tools/pixel/build_street.py
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import pix  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "assets")
C = {k: np.array(v + (255,), np.uint8) for k, v in pix.PALETTE.items()}
rng = np.random.default_rng(13)


def canvas(w, h):
    return np.zeros((h, w, 4), np.uint8)


def rect(img, x, y, w, h, col):
    img[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)] = C[col]


def px(img, x, y, col):
    if 0 <= y < img.shape[0] and 0 <= x < img.shape[1]:
        img[y, x] = C[col]


def hline(img, x0, x1, y, col):
    rect(img, x0, y, x1 - x0 + 1, 1, col)


def vline(img, x, y0, y1, col):
    rect(img, x, y0, 1, y1 - y0 + 1, col)


def noise(img, x, y, w, h, cols, density):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if rng.random() < density:
                px(img, xx, yy, cols[rng.integers(len(cols))])


def save(img, *path):
    p = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    pix.write_png(p, img)


# ---------------------------------------------------------------- 地图块

TILE = 16
TILES = {}   # 名字 → (列, 行)


def tiles():
    cols, rows = 12, 6
    img = canvas(cols * TILE, rows * TILE)
    slot = [0]

    def add(name, fn):
        i = slot[0]
        slot[0] += 1
        cx, cy = i % cols, i // cols
        t = canvas(TILE, TILE)
        fn(t)
        img[cy * TILE:(cy + 1) * TILE, cx * TILE:(cx + 1) * TILE] = t
        TILES[name] = [cx, cy]

    # 混凝土：内部（3 个变体，带一点颗粒和偶尔的裂缝）
    def concrete(t, base="k2", dark="k1", seed_crack=False):
        rect(t, 0, 0, 16, 16, base)
        noise(t, 0, 0, 16, 16, [dark, "k3"], 0.06)
        if seed_crack:
            for i, (x, y) in enumerate([(3, 4), (4, 5), (4, 6), (5, 7), (5, 8), (6, 9)]):
                px(t, x, y, "k1")
    for v in range(3):
        add("con_in%d" % v, lambda t, v=v: concrete(t, seed_crack=(v == 2)))
    add("con_deep", lambda t: concrete(t, "k1", "k0"))

    # 混凝土顶面：湿的——最上 1px 冷光反光，下面一道路缘，再往下是混凝土
    def con_top(t, v):
        concrete(t)
        hline(t, 0, 15, 0, "g1")
        hline(t, 0, 15, 1, "k6")
        hline(t, 0, 15, 2, "k4")
        hline(t, 0, 15, 3, "k3")
        hline(t, 0, 15, 4, "k3")
        hline(t, 0, 15, 5, "k1")
        # 路缘的接缝 / 排水孔
        if v == 1:
            vline(t, 8, 2, 4, "k1")
        if v == 2:
            rect(t, 5, 2, 5, 2, "k1")
            hline(t, 6, 8, 2, "k2")
        # 湿面上偶尔的高光点
        for x in rng.integers(0, 16, 2):
            px(t, int(x), 1, "k7")
    for v in range(3):
        add("con_top%d" % v, lambda t, v=v: con_top(t, v))

    # 侧面（左 / 右）：1px 暗边 + 1px 亮边，模拟板材厚度
    def side(t, left, top):
        concrete(t)
        if top:
            con_top(t, 0)
        x = 0 if left else 15
        vline(t, x, 0 if not top else 1, 15, "k4" if left else "k1")
        vline(t, 1 if left else 14, 0 if not top else 2, 15, "k3")
        if top:
            px(t, x, 0, "k6")
    add("con_l", lambda t: side(t, True, False))
    add("con_r", lambda t: side(t, False, False))
    add("con_tl", lambda t: side(t, True, True))
    add("con_tr", lambda t: side(t, False, True))

    # 底面：暗、带一道阴影
    def bottom(t):
        concrete(t, "k1", "k0")
        hline(t, 0, 15, 15, "k0")
        hline(t, 0, 15, 14, "k0")
    add("con_bot", bottom)

    # 钢格栅薄平台（1 格高）：上面一条亮边、网格孔、下面的横梁和阴影
    def grate(t, v):
        rect(t, 0, 0, 16, 7, "k3")
        hline(t, 0, 15, 0, "k7")
        hline(t, 0, 15, 1, "k5")
        for x in range(1, 16, 3):
            rect(t, x, 2, 2, 3, "k1")
        hline(t, 0, 15, 5, "k4")
        hline(t, 0, 15, 6, "k2")
        # 横梁
        rect(t, 0, 7, 16, 3, "k2")
        hline(t, 0, 15, 7, "k4")
        if v == 1:
            rect(t, 6, 7, 4, 6, "k2")
            vline(t, 6, 7, 12, "k4")
        px(t, 2, 8, "k5")
        px(t, 13, 8, "k5")
    add("grate0", lambda t: grate(t, 0))
    add("grate1", lambda t: grate(t, 1))

    # 钢板墙（窄高的墙体）：竖向面板、铆钉、面板缝
    def steel(t, v, top=False):
        rect(t, 0, 0, 16, 16, "k3")
        vline(t, 0, 0, 15, "k5")
        vline(t, 1, 0, 15, "k4")
        vline(t, 15, 0, 15, "k1")
        vline(t, 8, 0, 15, "k2")
        hline(t, 0, 15, 15 if v else 7, "k2")
        for (x, y) in [(3, 3), (12, 3), (3, 12), (12, 12)]:
            px(t, x, y, "k5")
        if top:
            hline(t, 0, 15, 0, "k7")
            hline(t, 0, 15, 1, "k5")
    add("steel0", lambda t: steel(t, 0))
    add("steel1", lambda t: steel(t, 1))
    add("steel_top", lambda t: steel(t, 0, True))

    save(img, "tiles", "street", "tiles.png")
    with open(os.path.join(ROOT, "tiles", "street", "tiles.json"), "w") as f:
        json.dump({"tile": TILE, "map": TILES}, f)


# ---------------------------------------------------------------- 视差背景

def far():
    """L1 远景天际线：640×220，两层楼群剪影，极少的窗点和天线红灯"""
    w, h = 640, 220
    img = canvas(w, h)
    for layer, (col, top_min, top_max, win) in enumerate([("b0", 40, 110, "k3"), ("k1", 80, 150, "k3")]):
        x = 0
        while x < w:
            bw = int(rng.integers(18, 54))
            top = int(rng.integers(top_min, top_max))
            rect(img, x, top, bw, h - top, col)
            # 屋顶细节：水箱 / 天线
            if rng.random() < 0.4:
                ax = x + int(rng.integers(3, max(4, bw - 3)))
                vline(img, ax, top - int(rng.integers(6, 18)), top, col)
            if rng.random() < 0.3:
                rect(img, x + 3, top - 4, 6, 4, col)
            # 窗：稀疏的暗点（远处不亮）
            for yy in range(top + 6, h - 10, 6):
                for xx in range(x + 3, x + bw - 3, 4):
                    if rng.random() < 0.08:
                        px(img, xx, yy, win)
                    elif rng.random() < 0.012:
                        px(img, xx, yy, "y0")
            x += bw + int(rng.integers(0, 6))
    # 雾：底部往上压一层夜空蓝
    for y in range(h - 70, h):
        k = (y - (h - 70)) / 70.0
        mask = img[y, :, 3] > 0
        if k > 0.5:
            img[y, mask] = C["b0"]
    save(img, "bg", "street_far.png")


def sign(img, x, y, w, h, col, glyph_col):
    """霓虹灯牌：暗底 + 亮边框 + 抽象字形（块状笔画），边框断一截（接触不良）"""
    rect(img, x, y, w, h, "k1")
    for i in range(w):
        if not (w // 3 < i < w // 3 + 2):
            px(img, x + i, y, col)
            px(img, x + i, y + h - 1, col)
    vline(img, x, y, y + h - 1, col)
    vline(img, x + w - 1, y, y + h - 1, col)
    gx = x + 3
    while gx < x + w - 5:
        gw = int(rng.integers(3, 5))
        for yy in range(y + 3, y + h - 3):
            if rng.random() < 0.55:
                hline(img, gx, gx + gw - 1, yy, glyph_col) if rng.random() < 0.4 else px(img, gx + int(rng.integers(gw)), yy, glyph_col)
        gx += gw + 2


def mid():
    """L2 中景楼体：640×200，楼面、窗格（少量亮窗）、防火梯、空调、两块低饱和灯牌；楼之间留缝，透出远景和天空"""
    w, h = 640, 200
    img = canvas(w, h)
    x = 0
    i = 0
    while x < w:
        bw = int(rng.integers(60, 120))
        top = int(rng.integers(30, 110))
        base = "k2" if i % 2 == 0 else "k1"
        if i % 3 == 2:
            # 楼缝：空出一段，远景从这里透出来
            x += int(rng.integers(30, 70))
            i += 1
            continue
        rect(img, x, top, bw, h - top, base)
        hline(img, x, x + bw - 1, top, "k4")
        vline(img, x, top, h - 1, "k3")
        # 楼层分隔
        for yy in range(top + 14, h, 18):
            hline(img, x, x + bw - 1, yy, "k1" if base == "k2" else "k0")
        # 窗格
        for yy in range(top + 6, h - 8, 18):
            for xx in range(x + 6, x + bw - 10, 12):
                rect(img, xx, yy, 7, 8, "k0")
                r = rng.random()
                if r < 0.05:
                    rect(img, xx + 1, yy + 1, 5, 6, "y0")
                    hline(img, xx + 1, xx + 5, yy + 1, "y1")
                elif r < 0.08:
                    rect(img, xx + 1, yy + 1, 5, 6, "c0")
                elif r < 0.4:
                    px(img, xx + 1, yy + 1, "k2")
        # 防火梯（之字形钢架）
        if i % 2 == 1:
            fx = x + bw - 26
            for yy in range(top + 20, h - 10, 18):
                hline(img, fx, fx + 20, yy, "k4")
                for xx in range(fx, fx + 21, 3):
                    px(img, xx, yy - 1, "k3")
                vline(img, fx, yy - 8, yy, "k3")
                vline(img, fx + 20, yy - 8, yy, "k3")
                for k in range(9):
                    px(img, fx + 2 + k * 2, yy + 9 - k, "k3")
        # 空调外机
        for _ in range(int(rng.integers(1, 4))):
            ax = x + int(rng.integers(6, bw - 16))
            ay = top + 10 + int(rng.integers(0, 6)) * 18
            rect(img, ax, ay, 10, 7, "k3")
            hline(img, ax, ax + 9, ay, "k5")
            rect(img, ax + 2, ay + 2, 4, 4, "k1")
        x += bw
        i += 1
    # 两块灯牌（低饱和：洋红暗阶 / 青暗阶为主，亮阶只给边框）
    sign(img, 120, 80, 34, 16, "m1", "m0")
    sign(img, 430, 70, 16, 40, "c1", "c0")
    save(img, "bg", "street_mid.png")


def near():
    """L3 近景结构：640×200，透明底——上方是钢梁、横管、下垂电缆（中远景从缝里透出来），
    下方 70px 是贴着游戏层的矮墙（砖缝、通风口、褪色海报）"""
    w, h = 640, 200
    img = canvas(w, h)
    wall_top = h - 70
    rect(img, 0, wall_top, w, 70, "k1")
    hline(img, 0, w - 1, wall_top, "k3")
    hline(img, 0, w - 1, wall_top + 1, "k2")
    for yy in range(wall_top + 6, h, 6):
        off = 0 if (yy // 6) % 2 == 0 else 6
        for xx in range(off, w, 12):
            px(img, xx, yy, "k2")
    noise(img, 0, wall_top + 2, w, 68, ["k2"], 0.02)
    # 钢梁（竖）每 160px 一根，从顶一直到矮墙
    for bx in range(40, w, 160):
        rect(img, bx, 0, 7, h, "k2")
        vline(img, bx, 0, h - 1, "k3")
        vline(img, bx + 6, 0, h - 1, "k1")
        for yy in range(6, h, 14):
            px(img, bx + 2, yy, "k4")
            px(img, bx + 4, yy, "k4")
        # 斜撑
        for k in range(22):
            px(img, bx + 7 + k, 40 + k, "k2")
            px(img, bx - 1 - k, 40 + k, "k2")
    # 横管 ×2（带法兰），挂在钢梁之间
    for py, r in [(64, 3), (80, 2)]:
        rect(img, 0, py, w, r * 2, "k2")
        hline(img, 0, w - 1, py, "k4")
        hline(img, 0, w - 1, py + r * 2 - 1, "k1")
        for fx in range(20, w, 48):
            rect(img, fx, py - 1, 3, r * 2 + 2, "k3")
            px(img, fx + 1, py - 1, "k5")
    # 竖管：从横管下到矮墙
    for vx in [100, 300, 520]:
        rect(img, vx, 68, 4, h - 68, "k2")
        vline(img, vx, 68, h - 1, "k4")
        vline(img, vx + 3, 68, h - 1, "k1")
        rect(img, vx - 1, wall_top - 4, 6, 3, "k3")
    # 下垂的电缆
    for x0, x1, y0, sag in [(0, 180, 30, 16), (180, 380, 34, 22), (380, 640, 28, 18), (60, 260, 96, 12)]:
        for xx in range(x0, x1):
            t = (xx - x0) / max(x1 - x0, 1)
            yy = int(round(y0 + sag * 4 * t * (1 - t)))
            px(img, xx, yy, "k0")
    # 矮墙上：卷帘门（暗）、一扇亮着的小门、墙脚一道暗青色的灯带
    for sx in [20, 340]:
        rect(img, sx, wall_top + 16, 46, 54, "k2")
        for yy in range(wall_top + 18, h, 3):
            hline(img, sx + 1, sx + 44, yy, "k3")
        hline(img, sx, sx + 45, wall_top + 16, "k4")
    rect(img, 130, wall_top + 24, 14, 46, "k0")
    rect(img, 131, wall_top + 25, 12, 45, "y0")
    vline(img, 131, wall_top + 25, h - 1, "y1")
    rect(img, 128, wall_top + 20, 18, 3, "k3")
    px(img, 137, wall_top + 21, "y2")
    hline(img, 0, w - 1, h - 3, "c0")
    for xx in range(0, w, 9):
        px(img, xx, h - 3, "c1")
    # 矮墙上的通风口和海报
    for vx in [200, 440]:
        rect(img, vx, wall_top + 18, 22, 14, "k2")
        for yy in range(wall_top + 20, wall_top + 31, 3):
            hline(img, vx + 2, vx + 19, yy, "k3")
        hline(img, vx, vx + 21, wall_top + 18, "k4")
    for (ox, col) in [(250, "m0"), (580, "b1")]:
        oy = wall_top + 14
        rect(img, ox, oy, 16, 22, col)
        rect(img, ox + 2, oy + 3, 12, 5, "k1")
        for yy in range(oy + 11, oy + 20, 2):
            hline(img, ox + 3, ox + 3 + int(rng.integers(5, 10)), yy, "k2")
    save(img, "bg", "street_near.png")


# ---------------------------------------------------------------- 道具

def props():
    d = ("props",)
    # 路灯：灯杆 + 弯臂 + 暖黄灯头（灯光锥由运行时叠加）
    lamp = canvas(24, 72)
    rect(lamp, 10, 8, 3, 64, "k3")
    vline(lamp, 10, 8, 71, "k5")
    for xx in range(12, 21):
        px(lamp, xx, 8 - (1 if xx > 16 else 0), "k4")
    rect(lamp, 16, 6, 7, 3, "k4")
    hline(lamp, 16, 22, 9, "y2")
    hline(lamp, 17, 21, 10, "y1")
    rect(lamp, 8, 66, 7, 6, "k4")
    save(pix.outline(lamp)[1:-1, 1:-1], *d, "lamp.png")
    # 检查站岗亭：钢板亭、亮着的窗、顶灯、警示条
    booth = canvas(44, 56)
    rect(booth, 2, 10, 40, 46, "k3")
    rect(booth, 0, 6, 44, 6, "k4")
    hline(booth, 0, 43, 6, "k6")
    rect(booth, 6, 18, 32, 14, "k0")
    rect(booth, 7, 19, 30, 12, "c0")
    hline(booth, 7, 36, 19, "c1")
    for xx in range(9, 36, 7):
        vline(booth, xx, 19, 30, "k2")
    # 窗里的人影（安保员剪影）
    rect(booth, 24, 22, 5, 9, "k1")
    rect(booth, 25, 20, 3, 3, "k1")
    for xx in range(2, 42, 4):
        rect(booth, xx, 50, 2, 4, "y1")
        rect(booth, xx + 2, 50, 2, 4, "k1")
    rect(booth, 18, 0, 8, 6, "k4")
    rect(booth, 20, 1, 4, 3, "r2")
    px(booth, 21, 1, "r3")
    vline(booth, 2, 10, 55, "k5")
    vline(booth, 41, 10, 55, "k1")
    rect(booth, 14, 36, 16, 12, "k2")
    rect(booth, 16, 38, 12, 3, "k4")
    save(pix.outline(booth)[1:-1, 1:-1], *d, "booth.png")
    # 闸门栏杆：立柱 + 红白相间的横杆
    gate = canvas(70, 40)
    rect(gate, 2, 10, 8, 30, "k4")
    vline(gate, 2, 10, 39, "k6")
    rect(gate, 3, 12, 6, 4, "r1")
    px(gate, 5, 13, "r3")
    for xx in range(10, 70):
        col = "r2" if (xx // 6) % 2 == 0 else "k7"
        rect(gate, xx, 18, 1, 3, col)
    hline(gate, 10, 69, 21, "k1")
    save(pix.outline(gate)[1:-1, 1:-1], *d, "gate.png")
    # 灯牌 ×3（游戏层旁的小灯牌，比背景亮一点，但只占很小的面积）
    for i, (wd, ht, col, gcol) in enumerate([(30, 14, "m1", "m0"), (14, 30, "c2", "c1"), (24, 12, "y1", "y0")]):
        s = canvas(wd, ht)
        sign(s, 0, 0, wd, ht, col, gcol)
        save(s, *d, "sign%d.png" % i)
    # 空调外机
    ac = canvas(18, 14)
    rect(ac, 0, 0, 18, 14, "k3")
    hline(ac, 0, 17, 0, "k6")
    rect(ac, 3, 3, 8, 8, "k1")
    for k in range(4):
        px(ac, 4 + k * 2, 4 + k * 2, "k4")
        px(ac, 10 - k * 2, 4 + k * 2, "k4")
    for yy in range(3, 11, 2):
        hline(ac, 13, 15, yy, "k2")
    save(pix.outline(ac)[1:-1, 1:-1], *d, "ac.png")
    # 通风扇 4 帧（16×16）
    for f in range(4):
        fan = canvas(16, 16)
        rect(fan, 0, 0, 16, 16, "k2")
        hline(fan, 0, 15, 0, "k5")
        vline(fan, 0, 0, 15, "k4")
        c = 7.5
        for k in range(4):
            a = (f / 4.0 + k / 4.0) * np.pi * 0.5 * 2
            for r in range(1, 7):
                xx = int(round(c + np.cos(a) * r))
                yy = int(round(c + np.sin(a) * r))
                px(fan, xx, yy, "k5" if r < 5 else "k4")
        px(fan, 7, 7, "k6")
        save(fan, *d, "fan%d.png" % f)


def main():
    tiles()
    far()
    mid()
    near()
    props()
    print("street assets ->", os.path.abspath(ROOT))


if __name__ == "__main__":
    main()
