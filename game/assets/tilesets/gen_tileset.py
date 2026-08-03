#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IRONGLYPH (合金文字機甲) 地形 tileset 生成器
风格: 宣纸底 x 水墨彩墨, 严格遵守 game/data/palette.json 色板
所有纹理均使用数学上真正可无缝平铺 (periodic) 的噪声/Voronoi构造,
保证 TileMap 横向平铺时不会出现接缝。
"""
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
import math, os, json

rng_master = np.random.default_rng(20260803)

SIZE = 512
OUT_DIR = "/tmp/ironglyph_tileset_assets"

# ---- 色板 (来自 game/data/palette.json) ----
PAPER       = np.array([0.93, 0.90, 0.83])
PAPER_SHADE = np.array([0.84, 0.80, 0.71])
INK         = np.array([0.04, 0.04, 0.04])
ELEMENTS = {
    "water": np.array([0.02, 0.08, 0.70]),
    "fire":  np.array([0.80, 0.04, 0.139]),
    "wood":  np.array([0.04, 0.58, 0.10]),
    "earth": np.array([0.737, 0.58, 0.02]),
    "neutral": np.array([0.087, 0.03, 0.03]),
}

def to_u8(rgb_float):
    return tuple(int(round(max(0, min(1, c)) * 255)) for c in rgb_float)

# ---------------------------------------------------------------
# 真正可平铺的 Perlin 噪声 (periodic gradient noise)
# 参考经典 tileable-perlin 实现: 保证 shape 对 res 取整除时首尾梯度完全一致
# ---------------------------------------------------------------
def tileable_perlin(shape, res, rng):
    def f(t):
        return 6 * t**5 - 15 * t**4 + 10 * t**3
    delta = (res[0] / shape[0], res[1] / shape[1])
    d = (shape[0] // res[0], shape[1] // res[1])
    grid = np.mgrid[0:res[0]:delta[0], 0:res[1]:delta[1]].transpose(1, 2, 0) % 1
    angles = 2 * np.pi * rng.random((res[0] + 1, res[1] + 1))
    gradients = np.dstack((np.cos(angles), np.sin(angles)))
    # 周期化: 边界梯度与起点相同 -> 平铺无缝
    gradients[-1, :] = gradients[0, :]
    gradients[:, -1] = gradients[:, 0]
    gradients = gradients.repeat(d[0], 0).repeat(d[1], 1)
    g00 = gradients[:-d[0], :-d[1]]
    g10 = gradients[d[0]:, :-d[1]]
    g01 = gradients[:-d[0], d[1]:]
    g11 = gradients[d[0]:, d[1]:]
    n00 = np.sum(np.dstack((grid[:, :, 0], grid[:, :, 1])) * g00, 2)
    n10 = np.sum(np.dstack((grid[:, :, 0] - 1, grid[:, :, 1])) * g10, 2)
    n01 = np.sum(np.dstack((grid[:, :, 0], grid[:, :, 1] - 1)) * g01, 2)
    n11 = np.sum(np.dstack((grid[:, :, 0] - 1, grid[:, :, 1] - 1)) * g11, 2)
    t = f(grid)
    n0 = n00 * (1 - t[:, :, 0]) + t[:, :, 0] * n10
    n1 = n01 * (1 - t[:, :, 0]) + t[:, :, 0] * n11
    val = np.sqrt(2) * ((1 - t[:, :, 1]) * n0 + t[:, :, 1] * n1)
    return val  # roughly in [-1, 1]

def fbm(shape, base_res, octaves, rng, persistence=0.55, lacunarity=2):
    total = np.zeros(shape)
    amp = 1.0
    amp_sum = 0.0
    res = base_res
    for o in range(octaves):
        total += amp * tileable_perlin(shape, (res, res), rng)
        amp_sum += amp
        amp *= persistence
        res = int(res * lacunarity)
        # 保证整除512, 用容许的分辨率序列
        while shape[0] % res != 0:
            res += 1
    return total / amp_sum

def normalize01(a):
    a = a - a.min()
    m = a.max()
    return a / m if m > 0 else a

# ---------------------------------------------------------------
# 周期性 (环面) Voronoi —— 用于岩层/裂纹/供坛石块
# ---------------------------------------------------------------
def periodic_voronoi(shape, n_points, rng):
    H, W = shape
    pts = rng.random((n_points, 2)) * [W, H]
    yy, xx = np.mgrid[0:H, 0:W]
    dist = np.full((H, W), 1e9)
    cellid = np.zeros((H, W), dtype=np.int32)
    offsets = [-1, 0, 1]
    for i, (px, py) in enumerate(pts):
        for oy in offsets:
            for ox in offsets:
                d = np.sqrt((xx - (px + ox * W))**2 + (yy - (py + oy * H))**2)
                mask = d < dist
                dist[mask] = d[mask]
                cellid[mask] = i
    return dist, cellid

# ---------------------------------------------------------------
# 工具: 混合颜色场 (paper 基底 + 少量 ink 线 + 少量 element 淡染),
# 全程保证结果贴近纸色 (paper distance 控制)
# ---------------------------------------------------------------
def compose(base_field, ink_field, tint_color, tint_strength=0.10, ink_strength=0.35,
            paper_variation=0.05):
    """
    base_field: 0-1 noise, 用来在 paper / paper_shade 间做柔和过渡 (地形肌理)
    ink_field: 0-1, 值越大代表该处水墨线条/笔触越浓
    tint_color: 该关卡属性色 (已经是"离纸较远"的饱和色，这里我们只用极低强度掺入)
    """
    H, W = base_field.shape
    img = np.zeros((H, W, 3))
    # 纸底在 paper 和 paper_shade 之间波动 (地形起伏感)
    t = base_field[..., None]
    paper_mix = PAPER * (1 - t * paper_variation) + PAPER_SHADE * (t * paper_variation)
    img[:] = paper_mix
    # 淡淡属性色染 (极低强度, 保证色彩仍然"压得住"贴近纸色)
    tint_mix = tint_color * tint_strength + PAPER * (1 - tint_strength)
    tint_amt = (ink_field[..., None] * 0.6)  # 属性色跟随墨迹淡淡浮现
    img = img * (1 - tint_amt) + tint_mix * tint_amt
    # 水墨线条 (ink) 叠加在最上层，浓度由 ink_field 控制，但整体保持轻薄(飞白感)
    ink_amt = np.clip(ink_field, 0, 1)[..., None] * ink_strength
    img = img * (1 - ink_amt) + INK * ink_amt
    return np.clip(img, 0, 1)

def to_image(arr):
    return Image.fromarray((arr * 255).astype(np.uint8), mode="RGB")

def periodic_soften(edge01, max_r=3, blur_r=1.2):
    """对 0/1 边界图做 MaxFilter+GaussianBlur，但先做 wrap padding 保证结果严格可平铺。"""
    H, W = edge01.shape
    pad = max(max_r, int(math.ceil(blur_r * 3)))
    src = (edge01 * 255).astype(np.uint8)
    padded = np.pad(src, ((pad, pad), (pad, pad)), mode="wrap")
    img = Image.fromarray(padded)
    img = img.filter(ImageFilter.MaxFilter(max_r if max_r % 2 == 1 else max_r + 1))
    img = img.filter(ImageFilter.GaussianBlur(blur_r))
    out = np.asarray(img).astype(float) / 255.0
    return out[pad:pad + H, pad:pad + W]

def add_paper_grain(img_arr, rng, strength=0.02):
    """加入极细腻的纸纹颗粒感 (不破坏可平铺性, 逐像素独立噪声在统计上均匀)"""
    grain = rng.normal(0, strength, img_arr.shape[:2])[..., None]
    return np.clip(img_arr + grain, 0, 1)

def report(name, arr):
    mean = arr.reshape(-1, 3).mean(axis=0)
    sat = mean.max() - mean.min()
    print(f"[{name}] mean_rgb={mean.round(3)} sat_range={sat:.3f} "
          f"paper_dist={np.linalg.norm(mean-PAPER):.3f}")

# ================================================================
# 1. 水域关 water_ground.png — 淡鶱蓝水波纹 (毛笔波浪线)
# ================================================================
def gen_water(rng):
    base = normalize01(fbm((SIZE, SIZE), 8, 4, rng))
    # 波浪: 用整数周期 sin 波叠加 fbm 扰动相位, 保持水平方向严格周期 -> 无缝
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    warp = fbm((SIZE, SIZE), 8, 3, rng) * 14  # 相位扰动(仍来自可平铺noise, 可平铺)
    waves = np.zeros((SIZE, SIZE))
    for k, (freq, amp, weight) in enumerate([(3, 1.0, 0.5), (5, 0.6, 0.3), (8, 0.4, 0.2)]):
        phase = rng.random() * 2 * np.pi
        waves += weight * np.sin(2 * np.pi * freq * (yy + warp) / SIZE + phase)
    waves = normalize01(waves)
    # 水墨波纹线: 突出波峰附近的细线 (飞白感 —— 用高频细线, 非满涂)
    line = np.clip(np.abs(np.gradient(waves, axis=0)) * 18, 0, 1)
    line = line * (0.55 + 0.45 * base)  # 让笔触浓淡不均，模拟毛笔运墨
    ink_field = np.clip(line * 0.9 + (base > 0.82) * 0.15, 0, 1)
    img = compose(base, ink_field, ELEMENTS["water"], tint_strength=0.14,
                  ink_strength=0.20, paper_variation=0.55)
    img = add_paper_grain(img, rng, 0.015)
    return img

# ================================================================
# 2. 火山关 fire_ground.png — 淡朱砂纹, 熔岩裂纹感
# ================================================================
def gen_fire(rng):
    base = normalize01(fbm((SIZE, SIZE), 8, 4, rng))
    ridge_noise = fbm((SIZE, SIZE), 16, 4, rng)
    ridge = 1 - np.abs(ridge_noise)  # 山脊/裂纹特征
    ridge = normalize01(ridge)
    crack = np.clip((ridge - 0.72) * 6, 0, 1)  # 裂纹细线(阈值化, 保持稀疏飞白)
    ink_field = np.clip(crack * 0.65 + (base > 0.85) * 0.08, 0, 1)
    img = compose(base, ink_field, ELEMENTS["fire"], tint_strength=0.12,
                  ink_strength=0.18, paper_variation=0.55)
    img = add_paper_grain(img, rng, 0.015)
    return img

# ================================================================
# 3. 森林关 wood_ground.png — 淡石继(绿)纹, 树根/苔痕/木纹
# ================================================================
def gen_wood(rng):
    base = normalize01(fbm((SIZE, SIZE), 8, 4, rng))
    # 木纹: 水平方向的年轮状条纹 (整数周期, 受 fbm 扰动弯曲)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    warp = fbm((SIZE, SIZE), 8, 3, rng) * 20
    grain_freq = 6
    grain = np.sin(2 * np.pi * grain_freq * (yy + warp) / SIZE)
    grain_lines = np.clip(np.abs(np.gradient(grain, axis=0)) * 10, 0, 1)
    # 苔痕斑块: 用 periodic voronoi 生成不规则团块 (树根/苔藓)
    dist, cellid = periodic_voronoi((SIZE, SIZE), 26, rng)
    moss = normalize01(dist)
    moss_patch = np.clip((0.45 - moss) * 3.0, 0, 1)  # 团块状苔痕(半径内)
    root_lines = np.clip(np.abs(np.gradient(moss, axis=0)) + np.abs(np.gradient(moss, axis=1)), 0, 1)
    root_lines = normalize01(root_lines)
    root_lines = np.clip((root_lines - 0.55) * 4, 0, 1)  # 细根线(voronoi边缘)
    ink_field = np.clip(grain_lines * 0.28 + root_lines * 0.45 + moss_patch * 0.15, 0, 1)
    img = compose(base, ink_field, ELEMENTS["wood"], tint_strength=0.11,
                  ink_strength=0.16, paper_variation=0.55)
    img = add_paper_grain(img, rng, 0.015)
    return img

# ================================================================
# 4. 石窟关 earth_ground.png — 淡藤黄纹, 岩层/石块感
# ================================================================
def gen_earth(rng):
    base = normalize01(fbm((SIZE, SIZE), 8, 4, rng))
    dist, cellid = periodic_voronoi((SIZE, SIZE), 22, rng)
    # 石块边界 (Voronoi edge -> 岩块缝隙线)
    edge = np.zeros((SIZE, SIZE))
    cf = cellid.astype(float)
    gy = np.roll(cf, -1, axis=0) - cf
    gx = np.roll(cf, -1, axis=1) - cf
    edge = (np.abs(gy) + np.abs(gx) > 0).astype(float)
    edge_soft = periodic_soften(edge, max_r=3, blur_r=1.1)
    # 岩层水平层理 (整数周期)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    warp = fbm((SIZE, SIZE), 8, 3, rng) * 10
    strata = np.sin(2 * np.pi * 10 * (yy + warp) / SIZE)
    strata_lines = np.clip(np.abs(np.gradient(strata, axis=0)) * 6, 0, 0.5)
    ink_field = np.clip(edge_soft * 0.7 + strata_lines * 0.3, 0, 1)
    img = compose(base, ink_field, ELEMENTS["earth"], tint_strength=0.14,
                  ink_strength=0.22, paper_variation=0.55)
    img = add_paper_grain(img, rng, 0.015)
    return img

# ================================================================
# 5. 终章祭坛 altar_ground.png — 淡焦墨纹(中性), 裂纹+石块, 崩笔祭坛意境
# ================================================================
def gen_altar(rng):
    base = normalize01(fbm((SIZE, SIZE), 8, 4, rng))
    dist, cellid = periodic_voronoi((SIZE, SIZE), 14, rng)  # 更大块的石板
    cf2 = cellid.astype(float)
    gy = np.roll(cf2, -1, axis=0) - cf2
    gx = np.roll(cf2, -1, axis=1) - cf2
    edge = (np.abs(gy) + np.abs(gx) > 0).astype(float)
    edge_soft = periodic_soften(edge, max_r=3, blur_r=1.4)
    # 崩笔裂纹: 细碎、带方向感的裂纹(用高频ridge噪声, 阈值极窄制造飞白破碎感)
    ridge_noise = fbm((SIZE, SIZE), 16, 4, rng)
    ridge = normalize01(1 - np.abs(ridge_noise))
    crack = np.clip((ridge - 0.80) * 8, 0, 1)
    ink_field = np.clip(edge_soft * 0.6 + crack * 0.45, 0, 1)
    img = compose(base, ink_field, ELEMENTS["neutral"], tint_strength=0.08,
                  ink_strength=0.24, paper_variation=0.55)
    img = add_paper_grain(img, rng, 0.015)
    return img

# ---------------------------------------------------------------
GENERATORS = {
    "water_ground": gen_water,
    "fire_ground":  gen_fire,
    "wood_ground":  gen_wood,
    "earth_ground": gen_earth,
    "altar_ground": gen_altar,
}

def make_tiled_preview(img, path, reps=2):
    w, h = img.size
    canvas = Image.new("RGB", (w * reps, h * reps))
    for j in range(reps):
        for i in range(reps):
            canvas.paste(img, (i * w, j * h))
    canvas.save(path)

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in GENERATORS.items():
        rng = np.random.default_rng(abs(hash(name)) % (2**32))
        arr = fn(rng)
        report(name, arr)
        img = to_image(arr)
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        img.save(out_path)
        make_tiled_preview(img, os.path.join(OUT_DIR, f"{name}_tiled_preview.png"))
        print("saved:", out_path)
    print("DONE")
