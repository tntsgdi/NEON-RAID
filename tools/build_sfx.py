"""从本地 Sonniss GDC 音效库切出游戏音效，写到 assets/sfx/。

Sonniss GDC Game Audio Bundle：免版税、可商用、无需署名。
用法：G:/audio_library/venv/Scripts/python.exe tools/build_sfx.py
每个音效由若干层组成：(文件名片段, 起点秒, 时长秒或 None, 增益 dB)。
各层对齐起音后混合，裁掉开头静音，加淡出，峰值归一化到 -1 dBFS。
"""
import glob
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

LIB = "G:/audio_library/sonniss/files"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
RATE = 44100

# 每个音效：layers = [(文件名片段或 @合成, 起点秒, 时长秒, 增益 dB)]，cat 决定统一的响度，lp 可选低通
# 响度按类别统一 RMS（打击 -16、破空 -20、界面/环境 -24 dBFS），而不是只看峰值
CAT_RMS = {"hit": -16.0, "whoosh": -20.0, "ui": -24.0}
SFX = {
    # 挥刀：三段用三种不同的破空声，压掉 4 kHz 以上的嘶嘶声，叠一层短促的剑鸣
    "swing_1": {"cat": "whoosh", "lp": 4000, "layers": [("Fast Action Swish_HW 05", 0.60, 0.29, 0), ("@ring", 0.0, 0.22, -10)]},
    "swing_2": {"cat": "whoosh", "lp": 4000, "layers": [("Action Swish_HW 02", 2.54, 0.29, 0), ("@ring", 0.0, 0.22, -11)]},
    "swing_3": {"cat": "whoosh", "lp": 4000, "layers": [("Seq 2.1 whoosh #1 96 HK1", 0.01, 0.22, 0), ("@ring", 0.0, 0.25, -9)]},
    "swing_heavy": {"cat": "whoosh", "lp": 4500, "layers": [("Action Swish_HW 02", 1.07, 0.29, 0), ("Fast Action Swish_HW 05", 0.11, 0.35, -4), ("@ring", 0.0, 0.35, -7)]},
    # 命中机器人（分层）：起音 click + 功夫片式打击 + 金属撞击 + 电火花噼啪 + 次低音闷响
    "hit_1": {"cat": "hit", "layers": [("@click", 0.0, 0.01, -2), ("Seq 2.27 Hit #1 96 HK1", 0.10, 0.23, 0), ("BC0258_cinematic_metal_impact_052", 0.0, 0.25, -7),
                                       ("sizzling_crackling_006", 0.3, 0.12, -14), ("@thump", 0.0, 0.14, -5)]},
    "hit_2": {"cat": "hit", "layers": [("@click", 0.0, 0.01, -2), ("Seq 2.1 Hit #1 96 HK1", 0.07, 0.26, 0), ("BC0258_cinematic_metal_impact_069", 0.0, 0.25, -7),
                                       ("sizzling_crackling_006", 0.8, 0.12, -14), ("@thump", 0.0, 0.14, -5)]},
    "hit_3": {"cat": "hit", "layers": [("@click", 0.0, 0.01, -2), ("Seq 2.27 Hit #1 96 HK1", 0.10, 0.23, -1), ("BC0258_cinematic_metal_impact_050", 0.0, 0.25, -6),
                                       ("sizzling_crackling_006", 1.4, 0.12, -13), ("@thump", 0.0, 0.14, -5)]},
    "hit_heavy": {"cat": "hit", "rms": -15.0, "layers": [("@click", 0.0, 0.01, 0), ("Hit Impact Hard Metal Scrap Debris_UC 01", 0.21, 0.47, 0), ("steel bulkhead hit, low 01", 0.0, 0.5, -4),
                                           ("sizzling_crackling_006", 2.0, 0.2, -12), ("@thump", 0.0, 0.25, -2)]},
    # 终结一击：电影感重击 + 下坠次低音 + 剑鸣 + 电火花
    "finisher": {"cat": "hit", "rms": -11.0, "layers": [("@click", 0.0, 0.01, 0), ("@crack", 0.0, 0.08, -4), ("DSGNBoom_Cinematic Hit 2", 0.0, 0.9, 0), ("BC0294_modern_cinematic_impact_022", 0.0, 0.7, -3),
                                          ("Sub Drop 2", 0.0, 0.9, -6), ("@ring", 0.0, 0.4, -8), ("sizzling_crackling_006", 2.6, 0.3, -12)]},
    "break": {"cat": "hit", "layers": [("demolisher_metal_impact_002", 0.0, 1.0, 0), ("glass_impact_break_small_014", 0.0, 0.5, -10), ("Impact_Boom_Distorted_02", 0.0, 0.6, -8), ("@thump", 0.0, 0.3, -4)]},
    # 击毁：金属碎裂 + 零件四散的叮当 + 电火花
    "kill": {"cat": "hit", "rms": -14.0, "layers": [("@crack", 0.0, 0.06, -8), ("@click", 0.0, 0.01, -2), ("BC0258_cinematic_metal_anvil_impact_005", 0.0, 0.5, 0), ("glass_impact_break_small_014", 0.0, 0.4, -9),
                                      ("sizzling_crackling_006", 1.9, 0.35, -10), ("@thump", 0.0, 0.25, -3)]},
    # 撞墙反弹：沉闷的钢板撞击
    "wall_bounce": {"cat": "hit", "rms": -14.0, "layers": [("@crack", 0.0, 0.06, -3), ("BC0258_cinematic_metal_impact_069", 0.0, 0.2, -6), ("steel bulkhead hit, low 01", 0.0, 0.4, 0), ("@thump", 0.0, 0.2, -3)]},
    # 异体专属命中
    "slam": {"cat": "hit", "rms": -13.0, "layers": [("@crack", 0.0, 0.08, -3), ("BC0258_cinematic_metal_impact_050", 0.0, 0.3, -5), ("@click", 0.0, 0.01, 0), ("Low Boom 3", 0.0, 1.0, 0), ("Impact_Boom_Distorted_02", 0.0, 0.7, -3), ("steel bulkhead hit, low 01", 0.0, 0.5, -5)]},
    "ram_hit": {"cat": "hit", "rms": -13.0, "layers": [("@crack", 0.0, 0.06, -3), ("BC0258_cinematic_metal_impact_052", 0.0, 0.25, -5), ("@click", 0.0, 0.01, 0), ("PUNCH_PERCUSSIVE_HEAVY_06", 0.0, 0.35, 0), ("steel bulkhead hit, low 01", 0.0, 0.4, -4), ("@thump", 0.0, 0.2, -3)]},
    "rail_hit": {"cat": "hit", "layers": [("@click", 0.0, 0.01, 0), ("@zap", 0.0, 0.25, -2), ("sizzling_crackling_006", 0.5, 0.3, -6), ("BC0258_cinematic_metal_impact_050", 0.0, 0.3, -5)]},
    "disc_hit": {"cat": "hit", "layers": [("@click", 0.0, 0.01, 0), ("Swell_Metallic Ring_02", 0.0, 0.5, -4), ("BC0258_cinematic_metal_impact_069", 0.0, 0.3, 0)]},
    # 长矛蓄满 / 过载倒计时 / 过载爆炸
    "rail_full": {"cat": "ui", "rms": -17.0, "layers": [("@blip_hi", 0.0, 0.09, 0), ("Swell_Metallic Ring_02", 0.0, 0.4, -6)]},
    "overload_alarm": {"cat": "ui", "rms": -14.0, "layers": [("@alarm", 0.0, 0.16, 0)]},
    "overload": {"cat": "hit", "rms": -12.0, "layers": [("@crack", 0.0, 0.08, -4), ("@click", 0.0, 0.01, 0), ("BC0294_modern_cinematic_impact_boom_003", 0.0, 1.2, 0), ("sizzling_crackling_006", 0.0, 0.6, -6), ("Sub Drop 2", 0.0, 0.9, -5)]},
    # 移动：只留短促、低调的声音
    "dash": {"cat": "whoosh", "layers": [("WHSH_InsJ_Whooshing_Low_Double_01-01", 0.04, 0.19, 0)]},
    # 界面音：短促、偏高频、比战斗音低（ui 类别 -24 dB）
    "ui_tick": {"cat": "ui", "layers": [("@click", 0.0, 0.01, -8), ("@blip", 0.0, 0.06, 0)]},
    "ui_open": {"cat": "ui", "layers": [("@sweep", 0.0, 0.16, 0), ("@click", 0.0, 0.01, -8)]},
    "ui_card": {"cat": "ui", "layers": [("@click", 0.0, 0.01, -2), ("IMPACT_LOW_THUD_10", 0.0, 0.30, 0), ("@ring", 0.0, 0.35, -5)]},
    "ui_ready": {"cat": "ui", "layers": [("@blip_hi", 0.0, 0.09, 0), ("@blip", 0.0, 0.05, -6)]},
    # 附身异体
    "mut_grow": {"cat": "whoosh", "layers": [("@crystal", 0.0, 0.35, 0), ("@sweep", 0.0, 0.2, -6)]},
    "rail_charge": {"cat": "ui", "layers": [("@hum", 0.0, 0.6, 0)]},
    "rail_fire": {"cat": "hit", "layers": [("@click", 0.0, 0.01, 0), ("@zap", 0.0, 0.35, 0), ("SCIWeap_Shot Pulse YR 05", 0.0, 0.3, -6)]},
    "swarm": {"cat": "whoosh", "layers": [("@zap", 0.0, 0.12, -4), ("@zap", 0.06, 0.12, -6), ("@zap", 0.12, 0.12, -8), ("SCIWeap_Shot Pulse YR 05", 0.0, 0.2, -10)]},
    "grapple": {"cat": "whoosh", "layers": [("@zap", 0.0, 0.18, -2), ("Whoosh_Cloth_Leather_Fight_174", 0.0, 0.2, -4)]},
    "walljump": {"cat": "whoosh", "layers": [("Whoosh_Cloth_Leather_Fight_174", 0.0, 0.30, 0)]},
    "land": {"cat": "ui", "layers": [("IMPACT_LOW_THUD_10", 0.0, 0.20, 0)]},
    "slide": {"cat": "ui", "lp": 5000, "layers": [("EFX SD Sliding Whoosh By 06", 0.0, 0.45, 0)]},
    # 战斗
    "shot": {"cat": "whoosh", "layers": [("@click", 0.0, 0.01, -4), ("SCIWeap_Shot Pulse YR 05", 0.0, 0.45, 0)]},
    "enemy_shot": {"cat": "whoosh", "layers": [("Blast Laser 4", 0.0, 0.5, 0)]},
    "deflect": {"cat": "hit", "lp": 4000, "layers": [("@click", 0.0, 0.01, 0), ("Machete_Hit_Ring_Fienup_001", 0.0, 0.7, 0), ("@ring", 0.0, 0.3, -6)]},
    # 神经超频：重音就在开头（重击），然后低音往下坠，像时间被拖慢
    "overclock": {"cat": "hit", "layers": [("PUNCH_DESIGNED_LIGHT_78", 0.0, 0.4, 0), ("Bass Drop & Downer Fast 16", 0.0, 0.9, -14), ("@ring", 0.0, 0.5, -3)]},
    "hurt": {"cat": "hit", "layers": [("PUNCH_PERCUSSIVE_HEAVY_06", 0.0, 0.4, 0), ("Broken_Robot_Morphing_Short_Static_Pitch_Confused_Glitch_02", 0.0, 0.4, -6)]},
    "charge": {"cat": "ui", "layers": [("electricity_surge_discharge_electrical_arc_crackling_002_01", 0.0, 0.5, -2)]},
    "shield_block": {"cat": "hit", "layers": [("cinematic_metal_impact_050", 0.0, 0.4, 0)]},
    # 夺壳：一声上扬的剑鸣 + 短促的破空（意识射出去）
    "possess": {"cat": "hit", "layers": [("@click", 0.0, 0.01, -4), ("@ring", 0.0, 0.35, 0), ("WHSH_InsJ_Whooshing_Low_Double_01-01", 0.04, 0.19, -5)]},
    # 疾驰：进档时的一声风啸；wind 是循环用的风声（下面单独做无缝循环）
    "sprint": {"cat": "whoosh", "lp": 6000, "layers": [("WINDDsgn_Wind, Rush, Whoosh, Long x5 01", 0.02, 0.6, 0), ("@ring", 0.0, 0.3, -12)]},
}

# 循环音：[文件名片段, 起点, 时长]，首尾交叉淡化成无缝循环
LOOPS = {
    "wind": ("@wind", 0.0, 3.0),
}


def synth(kind, dur):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    if kind == "@click":
        return (np.random.default_rng(3).standard_normal(n) * np.exp(-t * 900)).astype(np.float32)
    if kind == "@ring":
        # 剑鸣：1.1→2.6 kHz 的短扫频，带两个泛音，迅速衰减
        f = 1100 + 1500 * (t / max(dur, 1e-3))
        ph = 2 * np.pi * np.cumsum(f) / RATE
        x = np.sin(ph) + 0.4 * np.sin(2.01 * ph) + 0.2 * np.sin(3.03 * ph)
        return (x * np.exp(-t * 18) * np.minimum(t / 0.004, 1)).astype(np.float32)
    if kind in ("@blip", "@blip_hi"):
        # 电子提示音：纯正弦 + 一点三次泛音，2 ms 起音、快速衰减
        f = 2200 if kind == "@blip" else 3300
        x = np.sin(2 * np.pi * f * t) + 0.15 * np.sin(2 * np.pi * 3 * f * t)
        return (x * np.exp(-t * 45) * np.minimum(t / 0.002, 1)).astype(np.float32)
    if kind == "@crystal":
        # 晶体生长：一串快速的高频碎裂声（随机短促的高音粒子）
        x = np.zeros(n)
        rng = np.random.default_rng(21)
        for k in range(14):
            at = int(rng.uniform(0, dur * 0.8) * RATE)
            f = rng.uniform(2400, 5200)
            m = min(n - at, int(0.03 * RATE))
            tt = np.arange(m) / RATE
            x[at:at + m] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * 140)
        return x.astype(np.float32)
    if kind == "@hum":
        # 蓄力嗡鸣：180 → 520 Hz 上扫的锯齿波，越来越响
        f = 180 + 340 * (t / max(dur, 1e-3)) ** 1.5
        ph = np.cumsum(f) / RATE
        x = 2 * (ph % 1.0) - 1
        return (x * np.minimum(t / dur, 1.0) * 0.8).astype(np.float32)
    if kind == "@zap":
        # 电磁放电：下扫的方波 + 噪声
        f = 2200 * np.exp(-t * 9) + 120
        ph = 2 * np.pi * np.cumsum(f) / RATE
        x = np.sign(np.sin(ph)) * 0.6 + np.random.default_rng(4).standard_normal(n) * 0.25
        return (x * np.exp(-t * 10)).astype(np.float32)
    if kind == "@thump":
        # 次低音闷响：90 → 45 Hz 下滑的正弦，给每一下打击"肉感"
        f = 45 + 45 * np.exp(-t * 30)
        x = np.sin(2 * np.pi * np.cumsum(f) / RATE)
        return (np.tanh(x * 1.6) * np.exp(-t * 14) * np.minimum(t / 0.002, 1)).astype(np.float32)
    if kind == "@crack":
        # 金属"咔"：1.5–3 kHz 带通噪声 + 2.4 kHz 衰减正弦，给低频重击一个小喇叭也放得出来的头
        from scipy.signal import butter, sosfilt
        noise = np.random.default_rng(11).standard_normal(n)
        x = sosfilt(butter(2, [1500, 3200], "band", fs=RATE, output="sos"), noise) * 2.0
        x += np.sin(2 * np.pi * 2400 * t) * 0.6
        return (x * np.exp(-t * 60) * np.minimum(t / 0.001, 1)).astype(np.float32)
    if kind == "@alarm":
        # 过载警报：两声短促的方波哔（1.3 / 1.0 kHz）
        x = np.zeros(n)
        for k, (f, at) in enumerate([(1300, 0.0), (1000, 0.08)]):
            i = int(at * RATE)
            m = min(n - i, int(0.065 * RATE))
            tt = np.arange(m) / RATE
            tone = np.sign(np.sin(2 * np.pi * f * tt)) * 0.5 + np.sin(2 * np.pi * 2 * f * tt) * 0.25 + np.sin(2 * np.pi * 3 * f * tt) * 0.15
            x[i:i + m] += tone * np.minimum(tt / 0.002, 1) * np.minimum((0.065 - tt) / 0.005, 1)
        return x.astype(np.float32)
    if kind == "@sweep":
        # 面板展开：500→1800 Hz 上扫，带轻微噪声质感
        f = 500 + 1300 * (t / max(dur, 1e-3)) ** 0.7
        ph = 2 * np.pi * np.cumsum(f) / RATE
        x = np.sin(ph) + 0.08 * np.random.default_rng(5).standard_normal(n)
        return (x * np.sin(np.pi * np.minimum(t / dur, 1.0)) ** 0.5).astype(np.float32)
    sys.exit("未知合成层：" + kind)


def find(part):
    hits = [p for p in glob.glob(LIB + "/**/*.wav", recursive=True) if part in os.path.basename(p)]
    if not hits:
        sys.exit("找不到音源：" + part)
    return sorted(hits, key=len)[0]


def load(part, start, dur):
    path = find(part)
    info = sf.info(path)
    a = int(start * info.samplerate)
    b = info.frames if dur is None else min(info.frames, a + int(dur * info.samplerate))
    x, sr = sf.read(path, start=a, stop=b, always_2d=True, dtype="float32")
    x = x.mean(axis=1)
    if sr != RATE:
        g = np.gcd(sr, RATE)
        x = resample_poly(x, RATE // g, sr // g).astype(np.float32)
    # 从起音开始（-40 dB 以上的第一个采样往前 2 ms）
    thr = np.abs(x).max() * 0.01
    on = int(np.argmax(np.abs(x) > thr))
    return x[max(0, on - int(0.002 * RATE)):]


def build(recipe):
    parts = []
    for f, s, d, g in recipe["layers"]:
        x = synth(f, d) if f.startswith("@") else load(f, s, d)
        parts.append(x / max(1e-6, np.abs(x).max()) * 10 ** (g / 20))
    n = max(len(p) for p in parts)
    mix = np.zeros(n, dtype=np.float32)
    for p in parts:
        mix[: len(p)] += p
    if recipe.get("lp"):
        mix = lowpass(mix, recipe["lp"])
    target = recipe.get("rms", CAT_RMS[recipe["cat"]])
    fade = min(len(mix), int(0.04 * RATE))
    mix[-fade:] *= np.linspace(1.0, 0.0, fade)
    # 按类别统一响度：取开头 250 ms 和整段 RMS 中较大的（长尾巴的低频也算进去）；峰值不超过 -1 dBFS
    head = mix[: int(0.25 * RATE)]
    rms = max(np.sqrt(np.mean(head ** 2)), np.sqrt(np.mean(mix ** 2))) + 1e-9
    mix = mix * (10 ** (target / 20) / rms)
    # 峰值不超过 -1 dBFS：用 tanh 软限幅压瞬态尖峰（整体缩小会把终结、冲撞的响度档位吃掉）
    lim = 10 ** (-1 / 20)
    if np.abs(mix).max() > lim:
        mix = np.tanh(mix / lim) * lim
    return mix.astype(np.float32)


def lowpass(x, cut):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(4, cut, "low", fs=RATE, output="sos"), x).astype(np.float32)


def make_loop(part, start, dur):
    if part == "@wind":
        # 风声：低通噪声，强弱缓慢起伏（两条不同速度的正弦调制），首尾交叉淡化
        n = int((dur + 0.4) * RATE)
        t = np.arange(n) / RATE
        noise = np.random.default_rng(9).standard_normal(n)
        from scipy.signal import butter, sosfilt
        x = sosfilt(butter(2, [250, 1800], "band", fs=RATE, output="sos"), noise)
        x *= 0.7 + 0.2 * np.sin(2 * np.pi * 0.5 * t) + 0.1 * np.sin(2 * np.pi * 1.3 * t + 1.0)
        x = x.astype(np.float32)
    else:
        x = load(part, start, dur + 0.4)
    x = lowpass(x, 5000)
    fade = int(0.4 * RATE)
    body = x[: len(x) - fade].copy()
    tail = x[len(x) - fade:]
    body[:fade] = body[:fade] * np.linspace(0, 1, fade) + tail * np.linspace(1, 0, fade)
    rms = np.sqrt(np.mean(body ** 2)) + 1e-9
    return (body * (10 ** (-22 / 20) / rms)).astype(np.float32)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (part, start, dur) in LOOPS.items():
        y = make_loop(part, start, dur)
        sf.write(os.path.join(OUT, name + ".wav"), y, RATE, subtype="PCM_16")
        print("%-12s %.2fs  (loop) <- %s" % (name, len(y) / RATE, part))
    for name, recipe in SFX.items():
        y = build(recipe)
        sf.write(os.path.join(OUT, name + ".wav"), y, RATE, subtype="PCM_16")
        print("%-12s %.2fs  <- %s" % (name, len(y) / RATE, " + ".join(l[0] for l in recipe["layers"])))


if __name__ == "__main__":
    main()
