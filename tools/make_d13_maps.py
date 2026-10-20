"""生成第 1 关「第十三街地下城」001–005 的字符地图 → scripts/level/d13_maps.gd

用法：python tools/make_d13_maps.py
地图用"积木"拼出来：光标从左往右走，每块积木（平地、台阶、沟、低矮通道、高墙、塔、平台、敌人小组……）
接着上一块铺。节奏：每 25–30 格（400–480 像素）至少一个遭遇或一个地形动作。
图例见 scripts/level/region.gd 开头。改关卡就改这里再重新生成，然后跑 tests/bot_run.gd 量用时。
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "scripts", "level", "d13_maps.gd")


class B:
    """关卡积木。gr = 当前地面顶面所在的行；x = 光标列。"""

    def __init__(self, cols, rows, ground_row):
        self.g = [[" "] * cols for _ in range(rows)]
        self.cols, self.rows = 600, rows   # 先开一张很宽的图，end() 时按实际用到的宽度裁掉
        self.g = [[" "] * self.cols for _ in range(rows)]
        self.maxc = 0
        self.gr = ground_row
        self.x = 2
        self.fill(0, 0, 1, rows - 1)

    # ---- 底层
    def fill(self, c0, r0, c1, r1, ch="#"):
        for r in range(max(r0, 0), min(r1, self.rows - 1) + 1):
            for c in range(max(c0, 0), min(c1, self.cols - 1) + 1):
                self.g[r][c] = ch
        if ch != " " and c1 < self.cols:
            self.maxc = max(self.maxc, c1)

    def put(self, c, r, ch):
        self.g[r][c] = ch
        self.maxc = max(self.maxc, c)

    # ---- 积木（都从光标 x 开始，铺完光标右移）
    def floor(self, n):
        self.fill(self.x, self.gr, self.x + n - 1, self.rows - 1)
        self.x += n
        return self

    def up(self, h, n):
        self.gr -= h
        return self.floor(n)

    def down(self, h, n):
        self.gr += h
        return self.floor(n)

    def gap(self, n):
        self.x += n
        return self

    def low(self, n):
        """低矮通道：头顶净高 2 格（32 像素），只能滑铲；天花板一直连到顶，不能从上面绕"""
        self.fill(self.x, 0, self.x + n - 1, self.gr - 3)
        return self.floor(n)

    def wall(self, h, w=3):
        """一堵 h 格高的墙：走上去、翻过去"""
        self.fill(self.x, self.gr - h, self.x + w - 1, self.gr - 1)
        return self.floor(w)

    def ceiling(self, c0, c1, row):
        """从顶上一直盖到 row 行（走廊）"""
        self.fill(c0, 0, c1, row)

    def plat(self, dx, h, w):
        """离地 h 格的平台（1 格厚），相对光标"""
        r = self.gr - h
        self.fill(self.x + dx, r, self.x + dx + w - 1, r)

    # ---- 放东西（dx 相对光标；h = 离当前地面几格，0 = 站在地上）
    def at(self, dx, ch, h=0):
        self.put(self.x + dx, self.gr - 1 - h, ch)

    def on_plat(self, dx, plat_h, ch):
        self.put(self.x + dx, self.gr - 1 - plat_h, ch)

    def end(self):
        w = max(self.x, self.maxc + 1) + 2
        # 右边界墙；地面一直铺到墙
        for row in self.g:
            del row[w:]
        self.fill(w - 2, 0, w - 1, self.rows - 1)
        return ["".join(row) for row in self.g]


# ---------------------------------------------------------------- 001：移动（不打架）

def r001():
    b = B(300, 30, 22)
    b.at(2, "@"); b.at(4, "?"); b.at(8, "T", 4)
    b.floor(14)
    # 台阶：上 1、上 1、下 2
    b.floor(6); b.up(1, 5); b.up(1, 5); b.down(2, 6)
    # 窄沟
    b.at(0, "?"); b.floor(4); b.gap(5); b.floor(8)
    # 低矮通道 → 出口直接一道沟（滑铲接跳）
    b.low(12); b.floor(3); b.gap(4); b.floor(6)
    b.at(2, "C"); b.floor(8)
    # 高墙：走上去
    b.at(0, "?"); b.floor(4); b.wall(12, 4)
    # 高台路线：上 6 走一段，中间一道墙，再下来
    b.up(6, 10); b.wall(5, 3); b.floor(10); b.down(6, 8)
    b.at(2, "C"); b.at(6, "T", 4); b.floor(12)
    # 双塔：走上第一座塔，塔顶之间跳过去，再从第二座塔下来
    b.wall(1, 1); b.up(13, 6); b.gap(6); b.floor(6); b.down(13, 8)
    b.at(2, "C"); b.floor(8)
    # 冲刺直道：低矮通道 × 3、台阶
    b.floor(10); b.low(6); b.floor(10); b.low(6); b.floor(8); b.up(2, 6); b.down(2, 4); b.low(8); b.floor(10)
    b.at(2, "C"); b.floor(6)
    # 竖井：掉进 8 格深的坑，再沿另一侧墙走上来
    b.gap(0); b.down(8, 10); b.up(8, 6)
    # 连续窄沟
    b.floor(6); b.gap(4); b.floor(4); b.gap(5); b.floor(4); b.gap(4); b.floor(12)
    b.at(4, "E"); b.floor(10)
    return {"name": "D13_R1", "map": b.end(), "tips": ["T_R1_MOVE", "T_R1_JUMP", "T_R1_WALL"], "texts": ["D13_T1", "D13_T9", "D13_T2"]}


# ---------------------------------------------------------------- 002：战斗 + 中继过沟

def r002():
    b = B(330, 30, 22)
    b.at(2, "@"); b.at(4, "?"); b.floor(12)
    # 单个射手：学锁定框
    b.at(4, "?"); b.at(16, "g"); b.floor(22)
    # 平台射手 + 冲锋机
    b.plat(6, 4, 8); b.on_plat(9, 4, "g"); b.at(20, "r"); b.floor(26)
    # 上 2：盾兵 + 三连发
    b.up(2, 4); b.at(10, "s"); b.at(18, "b"); b.at(14, "T", 5); b.floor(24)
    b.at(2, "C"); b.at(0, "B"); b.at(3, "G"); b.floor(6)
    # 下 3：侦察机 + 射手 + 冲锋机
    b.down(3, 4); b.plat(12, 4, 6); b.at(8, "d", 6); b.on_plat(14, 4, "g"); b.at(22, "r"); b.floor(30)
    b.at(2, "C"); b.floor(6)
    # 中继 + 36 格深沟 + 两台失控侦察机
    b.at(2, "?"); b.at(7, "R"); b.floor(11)
    b.at(20, "w", 7); b.at(30, "w", 4); b.gap(36)
    # 对岸
    b.at(2, "C"); b.at(10, "g"); b.at(18, "b"); b.at(24, "d", 6); b.floor(30)
    b.up(3, 4); b.at(8, "s"); b.at(14, "r"); b.at(10, "T", 5); b.floor(22)
    b.plat(4, 4, 10); b.on_plat(7, 4, "g"); b.at(16, "g"); b.floor(24)
    b.at(4, "E"); b.floor(12)
    return {"name": "D13_R2", "map": b.end(), "tips": ["T_R2_FIGHT", "T_R2_LOCK", "T_R2_RELAY"], "texts": ["D13_T2", "D13_T7"], "require_clear": True}


# ---------------------------------------------------------------- 003：重装机

def r003():
    b = B(280, 36, 20)
    # 上层走廊（天花板到第 13 行）：重装机 → 警示墙 → 射手 → 警示墙 + 盾兵 → 警示地板
    b.ceiling(2, 64, 13)
    b.at(2, "@"); b.at(4, "?"); b.at(10, "h"); b.floor(18)
    b.fill(b.x, 14, b.x + 1, 19, "W"); b.floor(2)
    b.at(2, "C"); b.at(12, "g"); b.floor(18)
    b.fill(b.x, 14, b.x + 1, 19, "W"); b.floor(2)
    b.at(6, "s"); b.at(14, "?"); b.floor(20)
    # 上层走廊尽头封死
    b.fill(b.x - 1, 0, b.x + 1, 21)
    # 警示地板（1 格厚），下面是下层隧道
    fx = b.x - 7
    tunnel_end = fx + 70
    b.fill(b.x + 2, 0, tunnel_end, 21)
    # 下层：隧道（第 21–27 行，从地板下面开始）挖空，地面从第 28 行起
    b.fill(fx, 21, tunnel_end, 27, " ")
    b.fill(2, 28, tunnel_end + 80, 35)
    b.fill(fx, 20, fx + 3, 20, "F")
    # 隧道里：两台冲锋机 + 射手
    b.put(fx + 14, 27, "C"); b.put(fx + 26, 27, "r"); b.put(fx + 40, 27, "g"); b.put(fx + 52, 27, "r")
    # 机库大厅：精英重装机 + 射手 + 平台上的三连发
    hall = tunnel_end + 1
    b.put(hall + 4, 27, "C"); b.put(hall + 5, 27, "?"); b.put(hall + 14, 23, "T")
    b.put(hall + 30, 27, "H"); b.put(hall + 44, 27, "g")
    b.fill(hall + 20, 23, hall + 28, 23); b.put(hall + 24, 22, "b")
    # 出口前再一道警示墙（要么留着自己的重装机，要么夺精英重装机）
    b.fill(hall + 60, 0, hall + 62, 21)
    b.fill(hall + 60, 22, hall + 61, 27, "W")
    b.put(hall + 70, 27, "E")
    return {"name": "D13_R3", "map": b.end(), "tips": ["T_R3_WALL", "T_R3_SLAM", "T_R3_ELITE"], "texts": ["D13_T6"], "require_clear": True}


# ---------------------------------------------------------------- 004：三壳换壳路线

def r004():
    b = B(330, 36, 20)
    b.ceiling(2, 52, 13)
    b.at(2, "@"); b.at(4, "?"); b.at(10, "h"); b.floor(18)
    b.fill(b.x, 14, b.x + 1, 19, "W"); b.floor(2)
    b.at(2, "C"); b.at(14, "g"); b.at(8, "T", 3); b.floor(26)
    b.fill(b.x - 1, 0, b.x + 1, 21)
    fx = b.x - 7
    tunnel_end = fx + 64
    b.fill(b.x + 2, 0, tunnel_end, 21)
    b.fill(fx, 21, tunnel_end, 27, " ")
    b.fill(2, 28, tunnel_end + 30, 35)
    b.fill(fx, 20, fx + 3, 20, "F")
    # 隧道：钥匙安保机 + 敌对射手 → 安保门 → 冲锋机
    b.put(fx + 8, 27, "?"); b.put(fx + 16, 27, "k"); b.put(fx + 24, 27, "g")
    door = fx + 34
    b.fill(door, 22, door, 27, "D")
    b.put(door + 4, 27, "C"); b.put(door + 18, 27, "r")
    # 爬出隧道：2 格一级的台阶
    s = tunnel_end + 1
    b.fill(s, 26, s + 2, 27); b.fill(s + 3, 24, s + 5, 27); b.fill(s + 6, 22, s + 8, 27); b.fill(s + 9, 20, s + 26, 35)
    b.put(s + 12, 19, "C"); b.put(s + 18, 19, "b")
    b.put(s + 20, 19, "?"); b.put(s + 24, 19, "R")
    # 36 格深沟 + 失控侦察机
    chasm = s + 27
    b.put(chasm + 26, 12, "w")
    far = chasm + 36
    b.fill(far, 20, far + 90, 35)
    b.put(far + 3, 19, "C"); b.put(far + 12, 19, "s"); b.put(far + 20, 19, "k")
    # 第二道安保门：落地后再夺一台钥匙安保机
    b.fill(far + 30, 0, far + 32, 13)
    b.fill(far + 31, 14, far + 31, 19, "D")
    b.put(far + 36, 19, "C"); b.put(far + 44, 19, "g"); b.put(far + 52, 15, "T")
    b.put(far + 70, 19, "E")
    return {"name": "D13_R4", "map": b.end(), "tips": ["T_R4_ROUTE", "T_R4_DOOR", "T_R4_RELAY"], "texts": ["D13_T5", "D13_T4"]}


# ---------------------------------------------------------------- 005：封锁线（清场）

def r005():
    b = B(290, 30, 22)
    b.at(2, "@"); b.at(4, "?"); b.at(10, "T", 4); b.floor(16)
    # A 区：射手、冲锋机、盾兵、平台射手
    b.plat(8, 4, 10); b.on_plat(12, 4, "g"); b.at(20, "r"); b.at(26, "s"); b.floor(34)
    b.at(2, "C"); b.floor(6)
    # B 区：两台侦察机、三连发、精英重装机，高低平台
    b.plat(4, 4, 8); b.plat(16, 7, 8); b.at(8, "d", 6); b.on_plat(19, 7, "b"); b.at(28, "H"); b.at(36, "d", 7); b.floor(44)
    b.at(2, "C"); b.floor(6)
    # C 区：台阶上的射手、两台冲锋机、盾兵三连发；一台停放的重装机可以借用
    b.at(4, "h"); b.floor(10); b.up(2, 4); b.at(6, "g"); b.floor(12); b.down(2, 4)
    b.at(8, "r"); b.at(16, "r"); b.at(24, "s"); b.at(30, "b"); b.plat(18, 4, 8); b.on_plat(21, 4, "g"); b.floor(38)
    b.at(4, "E"); b.at(6, "T", 6); b.floor(8)
    # 封锁者的大门
    b.fill(b.x, 0, b.x + 3, b.gr - 1); b.floor(4); b.floor(10)
    return {"name": "D13_R5", "map": b.end(), "tips": ["T_R5_FINAL"], "texts": ["D13_T3", "D13_T8"], "require_clear": True, "clear_span": 99999.0}


def gd_value(v, indent):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        inner = ",\n".join(pad + "\t" + gd_value(x, indent + 1) for x in v)
        return "[\n" + inner + ",\n" + pad + "]"
    if isinstance(v, dict):
        inner = ",\n".join(pad + "\t" + '"%s": %s' % (k, gd_value(x, indent + 1)) for k, x in v.items())
        return "{\n" + inner + ",\n" + pad + "}"
    raise TypeError(v)


def main():
    regions = [r001(), r002(), r003(), r004(), r005()]
    out = ["class_name D13Maps",
           "## 第 1 关「第十三街地下城」001–005 的字符地图。由 tools/make_d13_maps.py 生成，别手改。",
           "",
           "const REGIONS := " + gd_value(regions, 0),
           ""]
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    for r in regions:
        print(r["name"], "cols", len(r["map"][0]), "rows", len(r["map"]))


if __name__ == "__main__":
    main()
