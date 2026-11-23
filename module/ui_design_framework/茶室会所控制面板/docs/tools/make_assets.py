"""把设计稿 / 生成图加工成真机可用的 luadb 资源。

两套主题各用各的素材，互不染色：

  暖夜（docs/img/）            宣纸（docs/img/paper/）
  bg_night.jpg                 bg_paper.jpg        背景
  dev_<key>.jpg                p_<key>.jpg         设备卡图

输出到 code/ 根目录（与 Lua 同目录，打包后位于 /luadb/ 下）：
  bg_night.jpg / bg_paper.jpg  704x412 背景（运行时 stretch 到 1024x600，放大 1.45 倍）
  dev_*.jpg                    420x376 夜大卡/详情左图（cover 后压暗、底部渐隐）
  dev_*_s.jpg                  216x180 夜小卡
  p_*.jpg                      418x374 宣纸大卡/详情左图（不压暗，提亮 + 降饱和）
  p_*_s.jpg                    214x178 宣纸小卡

为什么按显示尺寸出四套，而不是一张 400x358 让组件缩：
  1) 真机实测切主题一次 685ms（trace 12:54:26.941→27.624），几乎全是 6 张 JPG
     的硬解（30~110ms/张）。图片池按最久未用淘汰，400x358 解码后一张 280KB，
     两套主题 12 张就 3.4MB，把默认 1MB 的池子顶穿 → 每次切主题必然全部重解。
     按显示尺寸劈开后，夜 927KB + 纸 918KB ≈ 1.8MB，两套能同时留在池里，
     切主题走缓存命中，不再解码。
  2) 小卡原本把 400x358 缩到 214x178（0.53x），全屏重绘时每帧逐像素采样，
     是最贵的一档。1:1 出图后走直接拷贝。
  3) 官方建议也是「图片按屏分辨率预先裁好，不要把大图丢给组件缩放」。
  代价只是文件数从 12 个变 22 个，体积反而从 896KB 降到 500KB 级。

为什么是 JPG 不是 PNG（真机日志实测，不是偏好）：
  1) Air1603 硬件 PNG 解码不支持多 IDAT 块。PIL 存稍大的图必然切成多块，
     固件直接打 "W/image png hw probe failed: ..., multiple IDAT blocks are
     not supported by hardware"，控件整块空白；退回软解在 400x358 上会
     "E/image image decoder error, ret = 9"，一样出不来。
  2) PNG 要先解出整张位图才能上屏：400x358 RGB565 一张 280KB，12 张叠起来
     逼近 airui 默认 1MB 图片缓存；JPG 边解码边输出，内存占用低一个量级。
  必须 baseline 编码（progressive=False），渐进式 JPG 会被固件拒绝。

为什么宣纸图不能拿暖夜图提亮：
  暖夜图本身是暗调照片，提亮只会把噪点和灰雾一起抬上来（上一版 bg_paper 就是
  这么废掉的）。宣纸这套是单独生成的浅调素材，保持它自己的高明度，
  卡片上的深墨字才压得住。

为什么还要量化 + 轻微模糊：
  去高频噪点后 JPG 可以压得更狠（q82 就能到 30KB 级），屏幕是 RGB565，
  肉眼几乎看不出差别。背景额外降到 512x300：整屏最底层、放大 2 倍无损观感。

水印：生成图右下角有"AI生成"字样，源图先裁掉底部 8% 再 cover。

用法：python tools/make_assets.py
"""
import os
from PIL import Image, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "img")
SRC_PAPER = os.path.join(SRC, "paper")
DST = os.path.join(ROOT, "code")

W, H = 1024, 600
# 背景尺寸的取舍（改过一次，这里是第二版）：
#
#   512x300 —— 上一版。跑得动，但运行时被 stretch 到 1024x600，整整放大 2 倍，
#              加上出图时还做了一次 0.8 高斯模糊，真机上就是"一层糊"。
#   1024x600 —— 清晰，但解码后 1024*600*2 = 1.2MB，直接大于 airui 默认的 1MB
#              图片池：装不下自己，每帧都可能重解，比糊更糟。
#   704x412 —— 现在这版。解码 567KB，留给 5 张墙页小卡（76KB x 5 = 380KB）
#              后仍有约 77KB 余量，能同时留在池里；运行时只放大 1.45 倍。
#
# 放大倍数从 2.0 降到 1.45，细节密度提升近一倍，这是 1MB 池子下能拿到的上限。
# 要彻底不放大，只能把图片池开到 4MB —— 那是固件编译期参数，Lua 侧改不了。
# 同时把出图模糊从 0.8 降到 0.3，并补一档轻度锐化，专门抵消这 1.45 倍。
BG_W, BG_H = 704, 412
# 卡片按真机显示尺寸 1:1 出图（见顶部说明），四套各自对应一个控件
NIGHT_BIG = (420, 376)         # ui_wall 大卡 = card 420x376（无内缩）
NIGHT_SM = (216, 180)          # ui_wall 小卡 = card 216x180（无内缩）
PAPER_BIG = (418, 374)         # 纸面大卡 = 内缩 1px 的卡面
PAPER_SM = (214, 178)          # 纸面小卡 = 内缩 1px 的卡面
CARDS = ("light", "incense", "music", "humid", "ambient")

EXT = ".jpg"
JPEG_Q = 84
# 4:4:4（subsampling=0）：卡片是满铺照片，4:2:0 会在暖光/木纹的色渐变上出灰边；
# 这点体积换画质是值的，改完总包仍不到原来 PNG 的六成。
JPEG_SUB = 0

BG_BLUR = 0.3        # 不再按"放大 2 倍"去糊，只做极轻去噪
BG_SHARP = 55        # 背景锐化强度，抵消 1.45 倍放大带来的软化
CARD_BLUR = 0.3

WATERMARK_CUT = 0.08           # 源图底部裁掉的比例（去生成水印）


def cover(im, w, h):
    """等比缩放后居中裁切到目标比例"""
    sw, sh = im.size
    s = max(w / sw, h / sh)
    nw, nh = max(1, round(sw * s)), max(1, round(sh * s))
    im = im.resize((nw, nh), Image.LANCZOS)
    left = (nw - w) // 2
    top = (nh - h) // 2
    return im.crop((left, top, left + w, top + h))


def load(path):
    """读源图并裁掉底部水印"""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    return im.crop((0, 0, w, int(h * (1 - WATERMARK_CUT))))


def veil(im, stops):
    """按 CSS linear-gradient 的 stops 逐行叠色。
    stops = [(位置 0..1, (r,g,b), alpha 0..1), ...]，位置递增"""
    base = im.convert("RGBA")
    lay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    px = lay.load()
    w, h = base.size
    for y in range(h):
        p = y / max(1, h - 1)
        # 找所在区间
        for i in range(len(stops) - 1):
            p0, c0, a0 = stops[i]
            p1, c1, a1 = stops[i + 1]
            if p0 <= p <= p1:
                t = 0 if p1 == p0 else (p - p0) / (p1 - p0)
                c = tuple(round(c0[k] * (1 - t) + c1[k] * t) for k in range(3))
                a = round(255 * (a0 * (1 - t) + a1 * t))
                for x in range(w):
                    px[x, y] = (c[0], c[1], c[2], a)
                break
    return Image.alpha_composite(base, lay)


def save_jpg(im, path, blur, sharp=0):
    """去噪 → baseline JPG（硬解前提：非渐进式，单 SOS 扫描）

    sharp > 0 时补一档 UnsharpMask：背景会被放大到 1024x600，
    出图前先锐化比让硬件做双线性放大更能保住边缘。
    """
    im = im.convert("RGB").filter(ImageFilter.GaussianBlur(blur))
    if sharp:
        im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=sharp, threshold=2))
    im.save(path, "JPEG", quality=JPEG_Q, optimize=True,
            progressive=False, subsampling=JPEG_SUB)


def make_bg():
    # ---- 暖夜：整体压暗 + 顶/底压暗（与 CSS veil 一致）----
    im = cover(load(os.path.join(SRC, "bg_night.png")), BG_W, BG_H)
    night = veil(im, [
        (0.00, (8, 6, 4), 0.52),
        (0.34, (8, 6, 4), 0.18),
        (1.00, (8, 6, 4), 0.72),
    ])
    save_jpg(night, os.path.join(DST, "bg_night" + EXT), BG_BLUR, BG_SHARP)

    # ---- 宣纸：保留晨光原貌，只做轻微提亮与去饱和 ----
    # 不叠任何纱：卡面、面板都是浅色不透明块，背景只负责四周留白处的"纸感"
    im = cover(load(os.path.join(SRC_PAPER, "bg_paper.png")), BG_W, BG_H)
    paper = ImageEnhance.Brightness(im).enhance(1.04)
    paper = ImageEnhance.Color(paper).enhance(0.92)
    save_jpg(paper, os.path.join(DST, "bg_paper" + EXT), BG_BLUR, BG_SHARP)


def make_cards_night():
    """暖夜卡图：一张源图裁两个尺寸（大卡 420×376、小卡 216×180）"""
    for name in CARDS:
        src = load(os.path.join(SRC, "dev_%s.png" % name))
        save_jpg(cover(src, *NIGHT_BIG),
                 os.path.join(DST, "dev_%s%s" % (name, EXT)), CARD_BLUR)
        save_jpg(cover(src, *NIGHT_SM),
                 os.path.join(DST, "dev_%s_s%s" % (name, EXT)), CARD_BLUR)


def make_cards_paper():
    """宣纸卡图：底色本来就是浅的，不能压暗。
    把整体明度再抬一档、饱和降下来，保证下半部压深墨字时对比度有余量。
    先在源图上做增强再 cover：两个尺寸的观感才完全一致（顺序反过来会因为
    先缩放后增强产生细微差别）。"""
    for name in CARDS:
        im = load(os.path.join(SRC_PAPER, "dev_%s.png" % name))
        im = ImageEnhance.Brightness(im).enhance(1.06)
        im = ImageEnhance.Color(im).enhance(0.90)
        im = ImageEnhance.Contrast(im).enhance(0.96)
        save_jpg(cover(im, *PAPER_BIG),
                 os.path.join(DST, "p_%s%s" % (name, EXT)), CARD_BLUR)
        save_jpg(cover(im, *PAPER_SM),
                 os.path.join(DST, "p_%s_s%s" % (name, EXT)), CARD_BLUR)


def drop_stale():
    """删掉 code/ 下旧的 PNG 资源：它们会被一起打进 luadb 白占空间，
    而且留在目录里容易让人误以为还在用。"""
    for f in os.listdir(DST):
        if f.endswith(".png"):
            os.remove(os.path.join(DST, f))
            print("rm  %s" % f)


def report():
    """打印体积。

    文字对比度不在这里验：两套主题的文字都落在实心底上
    （暖夜压在自建压暗层、宣纸压在实心纸签），与图片内容无关，
    所以不会出现"某张图偏暗导致某张卡读不清"的情况。
    """
    total = 0
    for f in sorted(os.listdir(DST)):
        if f.endswith(EXT):
            p = os.path.join(DST, f)
            n = os.path.getsize(p)
            total += n
            im = Image.open(p)
            print("%-16s %4d KB  %s" % (f, n // 1024, "progressive" if im.info.get("progressive") else "baseline"))

    print("total %d KB" % (total // 1024))


if __name__ == "__main__":
    os.makedirs(DST, exist_ok=True)
    make_bg()
    make_cards_night()
    make_cards_paper()
    drop_stale()
    report()
