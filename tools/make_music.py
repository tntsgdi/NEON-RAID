"""NEON RAID 配乐（numpy 合成，暗潮合成器 darksynth 风格）。

D 小调，128 BPM，64 小节一个循环（2 分钟），四段：
  A 铺垫（1–16）  B 律动（17–32）  C 高潮（33–48）  D 回落（49–64）
三层同长、同步播放，游戏里按战斗强度交叉淡变（scripts/core/music.gd）：
  explore  铺底 + 次低音 + 主旋律动机（拨弦）+ 踩镲
  combat   底鼓 / 军鼓 / 踩镲 + 闷音锯齿贝斯（两小节一变）+ 琶音
  peak     主旋律 lead + 锯齿和弦切音 + 嗵鼓加花（敌人多、第三波、残血时叠上去）
锯齿 / 方波用 PolyBLEP 带限合成，高音区不混叠。每段响度相差 2–3 dB，有起伏。
每个文件都是无缝循环：越过结尾的尾音会绕回开头。

用法：G:/audio_library/venv/Scripts/python.exe tools/make_music.py
输出：assets/music/explore.ogg、combat.ogg、peak.ogg
"""
import os
import subprocess
import wave

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
BPM = 128.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 64
LENGTH = BAR * BARS
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "music")
rng = np.random.default_rng(7)

# 四段和弦（每段 4 小节一句，重复 4 次；MIDI 根音 + 小/大三和弦）
PHRASES = {
    "A": [(50, "m"), (46, "M"), (53, "M"), (48, "M")],
    "B": [(50, "m"), (46, "M"), (53, "M"), (48, "M")],
    "C": [(46, "M"), (48, "M"), (50, "m"), (45, "M")],
    "D": [(43, "m"), (50, "m"), (46, "M"), (45, "M")],
}
SECTIONS = ["A", "B", "C", "D"]
# 各段响度（线性增益），A 最轻、C 最响
LEVEL = {"A": 0.72, "B": 0.9, "C": 1.0, "D": 0.68}


def chord_at(bar):
    """每段 16 小节 = 4 句；第 2、4 句的末小节换成属和弦（A 大三）制造张力，句与句不完全相同。"""
    sec = SECTIONS[bar // 16]
    phrase = (bar // 4) % 4
    if bar % 4 == 3 and phrase in (1, 3) and sec in "AB":
        return sec, (45, "M")
    return sec, PHRASES[sec][bar % 4]


def variant(bar):
    """这一句在段里是第几句（0–3），用来做变奏。"""
    return (bar // 4) % 4


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def triad(root, kind):
    return [root, root + (3 if kind == "m" else 4), root + 7]


class Track:
    """立体声缓冲；超出结尾的部分绕回开头，保证无缝循环。"""

    def __init__(self):
        self.n = int(round(LENGTH * SR))
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)

    def place(self, sig, at, gain=1.0, pan=0.0):
        gl = gain * np.cos((pan + 1) * np.pi / 4)
        gr = gain * np.sin((pan + 1) * np.pi / 4)
        i = int(round(at * SR)) % self.n
        k = 0
        while k < len(sig):
            m = min(len(sig) - k, self.n - i)
            self.L[i:i + m] += sig[k:k + m] * gl
            self.R[i:i + m] += sig[k:k + m] * gr
            k += m
            i = 0


def lp(x, cut, order=2):
    return sosfilt(butter(order, min(cut, SR * 0.45), "low", fs=SR, output="sos"), x)


def hp(x, cut, order=2):
    return sosfilt(butter(order, cut, "high", fs=SR, output="sos"), x)


def env(n, a, r):
    t = np.arange(n) / SR
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / max(r, 1e-4))


def fade_tail(x, sec=0.03):
    k = min(len(x), int(sec * SR))
    x[-k:] *= np.linspace(1, 0, k)
    return x


# ------------------------------------------------------------------ 带限振荡器
def _blep(t, dt):
    out = np.zeros_like(t)
    a = t < dt
    x = t[a] / dt[a] if np.ndim(dt) else t[a] / dt
    out[a] = 2 * x - x * x - 1
    b = t > 1 - dt
    y = (t[b] - 1) / (dt[b] if np.ndim(dt) else dt)
    out[b] = y * y + 2 * y + 1
    return out


def saw(f, n, detune=0.0):
    dt = f * (1 + detune) / SR
    t = (rng.random() + dt * np.arange(n)) % 1.0
    return 2 * t - 1 - _blep(t, dt)


def square(f, n):
    dt = f / SR
    t = (rng.random() + dt * np.arange(n)) % 1.0
    t2 = (t + 0.5) % 1.0
    return (2 * t - 1 - _blep(t, dt)) - (2 * t2 - 1 - _blep(t2, dt))


def supersaw(f, n, voices=5, spread=0.012):
    return sum(saw(f, n, (v - (voices - 1) / 2) * spread / voices) for v in range(voices)) / voices


# ------------------------------------------------------------------ 乐器
def kick():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 45 + 120 * np.exp(-t * 32)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    click = hp(rng.standard_normal(n), 2500) * np.exp(-t * 350) * 0.35
    return np.tanh((body + click) * 2.2) * 0.9


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.5
    noise = hp(lp(rng.standard_normal(n), 9000), 1200) * np.exp(-t * 15)
    return np.tanh((tone + noise) * 1.6) * 0.7


def crash():
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 5000, 2) * np.exp(-t * 2.6) * 0.5


def clap():
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    burst = np.zeros(n)
    for d in (0.0, 0.011, 0.022):
        i = int(d * SR)
        burst[i:] += np.exp(-(t[: n - i]) * 60)
    return hp(lp(rng.standard_normal(n), 7000), 1000) * (burst * 0.4 + np.exp(-t * 12) * 0.4)


def tom(m):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = hz(m) * (1 + 0.6 * np.exp(-t * 20))
    return np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 1.8) * 0.7


def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7000, 4) * np.exp(-t * (14 if open_ else 70)) * 0.4


def pad(chord, seconds, cut=1500):
    n = int(seconds * SR)
    x = lp(sum(supersaw(hz(m + 12), n) for m in chord) / 3.0, cut)
    return fade_tail(x * env(n, 0.35, 6.0), 0.3)


def sub(root, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    return fade_tail(np.sin(2 * np.pi * hz(root - 12) * t) * np.minimum(t / 0.02, 1.0), 0.05)


def pluck_bass(m, seconds, cutoff):
    n = int(seconds * SR)
    x = supersaw(hz(m), n, 3, 0.008) * 0.7 + saw(hz(m - 12), n) * 0.5
    t = np.arange(n) / SR
    head = int(n * 0.35)
    x = np.concatenate([lp(x[:head], cutoff), lp(x[head:], cutoff * 0.35)])
    return np.tanh(x * 2.0 * np.exp(-t * 9)) * 0.8


def pluck(m, seconds, bright=3500):
    n = int(seconds * SR)
    x = square(hz(m), n) * 0.35 + saw(hz(m), n) * 0.65
    return fade_tail(lp(x, bright) * env(n, 0.003, 0.16))


def lead_note(m, seconds):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(t / 0.3, 1)
    f = hz(m) * vib
    dt = f / SR
    ph = (np.cumsum(dt)) % 1.0
    x = (2 * ph - 1 - _blep(ph, dt)) * 0.7 + supersaw(hz(m + 12), n, 3, 0.01) * 0.25
    a = env(n, 0.02, 1.4)
    return fade_tail(lp(x, 3800) * a, 0.05)


def stab(chord, seconds):
    n = int(seconds * SR)
    x = sum(supersaw(hz(m + 12), n, 5, 0.02) for m in chord) / 3.0
    return fade_tail(lp(x, 4200) * env(n, 0.004, 0.12))


def delay(L, R, beats, fb, mix):
    d = int(BEAT * beats * SR)
    outL, outR = L.copy(), R.copy()
    bl, br = L * mix, R * mix
    for _ in range(4):
        bl, br = np.roll(br, d) * fb, np.roll(bl, d) * fb
        outL += bl
        outR += br
    return outL, outR


# 主旋律动机：4 小节一句（拍位, 相对和弦根音的音程, 拍长）；explore 用拨弦弹，peak 用 lead 拉长
MOTIF = [(0.0, 12, 1.0), (1.0, 15, 0.5), (1.5, 19, 1.5), (3.0, 17, 1.0),
         (4.0, 15, 1.5), (5.5, 12, 0.5), (6.0, 14, 2.0),
         (8.0, 12, 1.0), (9.0, 15, 0.5), (9.5, 19, 1.0), (10.5, 22, 1.5),
         (12.0, 24, 2.0), (14.0, 22, 1.0), (15.0, 19, 1.0)]


MOTIF_B = [(0.0, 12, 1.0), (1.0, 15, 0.5), (1.5, 19, 1.5), (3.0, 22, 1.0),
           (4.0, 24, 1.5), (5.5, 22, 0.5), (6.0, 19, 2.0),
           (8.0, 17, 1.0), (9.0, 15, 1.0), (10.0, 14, 2.0),
           (12.0, 12, 3.0), (15.0, 7, 1.0)]


def motif_notes(phrase_start_bar):
    """把动机映射到这一句（4 小节）的和弦上：每个音取所在小节和弦根音 + 音程，取 D 小调内的音。"""
    scale = {0, 2, 3, 5, 7, 9, 10}  # D 小调（相对 D）
    out = []
    motif = MOTIF if (phrase_start_bar // 4) % 2 == 0 else MOTIF_B
    for beat, iv, length in motif:
        bar = phrase_start_bar + int(beat // 4)
        _, (root, kind) = chord_at(bar % BARS)
        m = 50 + iv  # 以 D 为基准，保证旋律在调内
        while (m - 50) % 12 not in scale:
            m -= 1
        out.append((phrase_start_bar * BAR + beat * BEAT, m + 12, length))
    return out


# ------------------------------------------------------------------ 编曲
def explore():
    tr = Track()
    for b in range(BARS):
        sec, (root, kind) = chord_at(b)
        g = LEVEL[sec]
        t0 = b * BAR
        v = variant(b)
        cut = 1300 if sec in "AD" else 1900
        if v == 3:
            cut = 900 + 600 * (b % 4)  # 第 4 句：滤波逐小节扫开，引向下一句
        tr.place(pad(triad(root, kind), BAR + 0.4, cut), t0, 0.3 * g, -0.2)
        tr.place(pad(triad(root + 12, kind), BAR + 0.4), t0, 0.1 * g, 0.3)
        tr.place(sub(root, BAR), t0, 0.42 * g)
        for s in range(8):
            if sec == "A" and s % 2 == 0:
                continue
            tr.place(hat(), t0 + s * BEAT / 2 + BEAT / 4, (0.32 if s % 2 else 0.2) * g, 0.4)
        tr.place(kick(), t0, 0.3 * g)
        if sec == "C":
            tr.place(kick(), t0 + 2 * BEAT, 0.22)
    # 主旋律动机：B、C 段每句都弹，A、D 段隔句弹
    for phrase in range(BARS // 4):
        sec = SECTIONS[phrase // 4]
        if sec in "AD" and phrase % 2 == 0:
            continue
        for at, m, length in motif_notes(phrase * 4):
            tr.place(pluck(m, min(length * BEAT, 0.6)), at, 0.16 * LEVEL[sec], 0.25)
            if sec == "C":
                tr.place(pluck(m + 12, min(length * BEAT, 0.4), 4500), at, 0.06, -0.4)
    L, R = delay(tr.L, tr.R, 0.75, 0.3, 0.25)
    tr.L, tr.R = L, R
    return tr


def combat():
    tr = Track()
    duck = np.ones(tr.n)
    for b in range(BARS):
        sec, (root, kind) = chord_at(b)
        g = LEVEL[sec]
        t0 = b * BAR
        half = sec == "D"  # 回落段：半拍子
        kicks = [0, 2] if half else ([0, 1, 2, 3] if sec != "A" or b % 16 >= 8 else [0, 2])
        for q in kicks:
            tr.place(kick(), t0 + q * BEAT, 0.9 * g)
            i = int((t0 + q * BEAT) * SR) % tr.n
            k = int(0.22 * SR)
            seg = 1.0 - 0.7 * np.exp(-np.arange(k) / (0.06 * SR))
            j = min(tr.n, i + k)
            duck[i:j] = np.minimum(duck[i:j], seg[:j - i])
        if sec != "A" or b % 16 >= 8:
            for q in ([2] if half else [1, 3]):
                tr.place(snare(), t0 + q * BEAT, 0.6 * g, 0.05)
        v = variant(b)
        if b % 4 == 3 and sec in "BC":
            fills = 8 if v == 3 else 4
            for s in range(fills):
                at = t0 + (4 - fills / 4) * BEAT + s * BEAT / 4
                tr.place(snare(), at, (0.2 + 0.4 * s / fills) * g, 0.05)
        if b % 4 == 0 and v == 0 and sec in "BC":
            tr.place(crash(), t0, 0.35 * g, -0.3)
        for s in range(16):
            if half and s % 2:
                continue
            tr.place(hat(open_=(s % 4 == 2 or (v == 1 and s % 2 == 1))), t0 + s * BEAT / 4, (0.42 if s % 2 else 0.26) * g, 0.35)
        # 贝斯：两小节一变的节奏型（第二小节加切分和八度跳）
        pattern = [1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1] if b % 2 else [1, 1, 1, 1] * 4
        if v == 2:
            pattern = [1, 0, 1, 0] * 4  # 第 3 句：贝斯改成八度泵音
        for s in range(16):
            if not pattern[s] or (half and s % 2):
                continue
            m = root - 12 + (12 if s % 4 == 2 or (v == 2 and s % 4 == 2) else 0) + (7 if b % 2 and s == 14 else 0)
            tr.place(pluck_bass(m, BEAT / 4 * 0.95, 2000 if s % 4 == 0 else 1200), t0 + s * BEAT / 4, 0.42 * g)
        # 琶音：0-7-12-15 的上下跑动，C 段加快亮度
        ch = triad(root + 24, kind)
        arp = [ch[0], ch[1], ch[2], ch[0] + 12, ch[2], ch[1], ch[0] + 12, ch[2]]
        if sec != "A":
            for s in range(16):
                tr.place(pluck(arp[s % 8], BEAT / 4, 5000 if sec == "C" else 3800), t0 + s * BEAT / 4, 0.12 * g, 0.6 if s % 2 else -0.6)
    tr.L *= duck
    tr.R *= duck
    return tr


def peak():
    tr = Track()
    lead = Track()
    for b in range(BARS):
        sec, (root, kind) = chord_at(b)
        t0 = b * BAR
        if sec == "D":
            continue
        g = LEVEL[sec]
        # 锯齿和弦切音（反拍）
        for q in [0.5, 1.5, 2.5, 3.5]:
            tr.place(stab(triad(root, kind), BEAT * 0.4), t0 + q * BEAT, 0.13 * g, 0.2)
        tr.place(clap(), t0 + BEAT, 0.35 * g, -0.1)
        tr.place(clap(), t0 + 3 * BEAT, 0.35 * g, -0.1)
        if b % 4 == 3:
            for s, m in enumerate([50, 47, 45, 43]):
                tr.place(tom(m), t0 + 3 * BEAT + s * BEAT / 4, 0.45, -0.5 + s * 0.3)
    for phrase in range(BARS // 4):
        sec = SECTIONS[phrase // 4]
        if sec == "A":
            continue
        # 回落段 D：主旋律低一个八度、音量减半地回来，终段不会突然变空
        shift = -12 if sec == "D" else 0
        gain = 0.12 if sec == "D" else 0.24 * LEVEL[sec]
        for at, m, length in motif_notes(phrase * 4):
            lead.place(lead_note(m + shift, length * BEAT), at, gain)
    lL, lR = delay(lead.L, lead.R, 0.75, 0.35, 0.5)
    tr.L += lL
    tr.R += lR
    return tr


class Sting(Track):
    """不循环的短句。"""

    def __init__(self, seconds):
        self.n = int(round(seconds * SR))
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)

    def place(self, sig, at, gain=1.0, pan=0.0):
        i = int(round(at * SR))
        j = min(self.n, i + len(sig))
        if i >= self.n:
            return
        gl = gain * np.cos((pan + 1) * np.pi / 4)
        gr = gain * np.sin((pan + 1) * np.pi / 4)
        self.L[i:j] += sig[: j - i] * gl
        self.R[i:j] += sig[: j - i] * gr


def sting_wave():
    """波次开始：1.5 秒上扬（噪声扫频 + 上行锯齿和弦）→ 一记重拍。"""
    tr = Sting(2.6)
    n = int(1.5 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    sweep = np.zeros(n)
    for k in range(12):
        a, b = k * n // 12, (k + 1) * n // 12
        sweep[a:b] = hp(noise[a:b], 400 + 600 * k)
    tr.place(sweep * (t / 1.5) ** 2 * 0.4, 0.0)
    riser = sum(saw(hz(m) * 1.0, n) for m in (62, 65, 69)) / 3.0
    tr.place(lp(riser, 3000) * (t / 1.5) ** 1.5 * 0.35, 0.0)
    tr.place(kick(), 1.5, 1.0)
    tr.place(crash(), 1.5, 0.5)
    tr.place(stab(triad(50, "m"), 0.6), 1.5, 0.35)
    return tr


def sting_clear():
    """清场：小调九和弦的琶音上行，落在 D 上，带延迟。"""
    tr = Sting(3.5)
    for i, m in enumerate([62, 65, 69, 72, 74, 77, 81]):
        tr.place(pluck(m, 0.5, 5000), i * BEAT / 4, 0.3, -0.5 + i * 0.16)
    tr.place(pad([62, 65, 69, 76], 2.6, 2400), 7 * BEAT / 4, 0.4)
    L, R = delay(tr.L, tr.R, 0.75, 0.3, 0.35)
    tr.L, tr.R = L, R
    return tr


def mid_boost(x, gain=0.6):
    """800 Hz–3 kHz 提升约 4 dB：小喇叭上也听得清旋律和琶音。"""
    return x + sosfilt(butter(2, [800, 3000], "band", fs=SR, output="sos"), x) * gain


def write(name, tr, peak_level=0.89, boost=False):
    L, R = tr.L, tr.R
    if boost:
        L, R = mid_boost(L), mid_boost(R)
    m = max(np.abs(L).max(), np.abs(R).max(), 1e-6)
    L, R = np.tanh(L / m * 1.1) * peak_level, np.tanh(R / m * 1.1) * peak_level
    data = (np.stack([L, R], axis=1) * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)
    os.remove(wav)
    print("%-8s %.1fs -> %s" % (name, tr.n / SR, ogg))


if __name__ == "__main__":
    write("explore", explore(), 0.8, True)
    write("combat", combat(), 0.89, True)
    write("peak", peak(), 0.75)
    write("sting_wave", sting_wave(), 0.85)
    write("sting_clear", sting_clear(), 0.8)
