# hzfont 矢量字库

## 一、概述
hzfont 是 LuatOS 专为嵌入式 UI 开发设计的矢量字库，能够高效、清晰地支持界面中的各类字符显示。它不仅内置便捷，还可灵活加载外部字体，显著降低开发成本与复杂度，并可搭配 lcd、AirUI、exeasyui等核心库，大幅拓展 UI 表现力。

**核心优势：**

1. 全字号无级缩放：完整支持 12-255 字号，可随意指定任意大小，满足精细化的界面排版需求。
2. 智能抗锯齿优化：支持可调节的抗锯齿等级，有效平滑字体边缘，提升显示细腻度与视觉效果。
3. 字体使用高度自由：既可使用固件内置字库快速上手，也能轻松加载外部 .ttf 字体文件，便于对定制字体与多国语言的支持。

**注意事项:**

1. 当前Air8000/Air780EXX系列仅 V2020 及以上版本的 14 号和 114 号 LuatOS 固件版本支持 hzfont;
   - Air8000 系列的模组可以参考：https://docs.openluat.com/air8000/luatos/firmware/
   - Air7XX 系列模组可以参考：https://docs.openluat.com/air780epm/luatos/firmware/version/
2. Air8101仅 V2004 及以上版本的 102号和104 号 LuatOS 固件版本支持 hzfont，固件内没有内置.ttf字体文件，需要在下载固件时手动将.ttf文件字体文件在烧录固件和脚本时一并烧录到模组的文件系统中
   - Air8101 可以参考：https://docs.openluat.com/air8101/luatos/firmware/

## 二、演示效果

![](https://docs.openluat.com/osapi/core/image/hzfont效果演示.png)


## 三、使用说明

1. Air8101 支持 hzfont 的固件中未内置.ttf 文件，可以选择从 SD 卡或者模组文件系统中加载。如果选择从模组文件系统中加载，那么在烧录固件时需要手动将.ttf 文件字体文件一并烧录到模组的文件系统中，且初始化 hzfont 时选择所烧录的字体文件。
2. 本文件内 MiSans_gb2312.ttf 可选择作为hzfont从外部加载.ttf方式所使用的字体文件，Air8101 上可以使用，实际效果与Air780EXX系列/Air8000系列支持hzfont固件所内置的效果一样。
3. 字体文件大小不能超过固件所支持的文件系统空间。
4. 烧录步骤如下：

   - 将本文件内 MiSans_gb2312.ttf 下载后单独放入一个空文件夹中
   - 烧录固件时选择对应的文件夹，然后选择下载底层和脚本
     ![](https://docs.openluat.com/cdn/image/hzfont烧录字体文件到文件系统.PNG)
5. 使用方式：搭配 lcd 核心库、AirUI 核心库、exeasyui 扩展库使用方式
   
**示例 1： 使用 LCD 核心库加载 hzfont**

```lua
-- 使用固件内置字库
hzfont.init()

-- 从文件加载，使用默认缓存 256
hzfont.init("/sd/font.ttf")

-- 从文件加载，指定缓1024
hzfont.init("/sd/font.ttf", hzfont.HZFONT_CACHE_1024)

-- 从luadb文件系统加载
hzfont.init("/luadb/font.ttf")

-- lcd库显示utf-8字符方式
lcd.drawHzfontUtf8(10, 10, "合宙LuatOS字体演示", 10, 0xF800, 1)
lcd.drawHzfontUtf8(10, 30, "合宙LuatOS字体演示", 20, 0x07E0, 1)
lcd.drawHzfontUtf8(10, 70, "合宙LuatOS字体演示", 40, 0x001F, 1)
lcd.drawHzfontUtf8(10, 130, "合宙LuatOS字体演示", 60, 0xFD20, 1)
lcd.drawHzfontUtf8(10, 210, "合宙LuatOS字体演示", 80, 0x9E66, 1)
lcd.drawHzfontUtf8(10, 310, "合宙LuatOS字体演示", 100, 0xFFFF, 1)
```

**示例 2： 使用 AirUI 核心库加载 hzfont**

```lua
-- PC端/Air8000/780EHM 从14号固件/114号固件中加载hzfont字库，从而支持12-255号中文显示
airui.font_load({
    type = "hzfont", -- 字体类型，可选 "hzfont" 或 "bin"
    path = nil,    -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
    size = 20,     -- 字体大小，默认 16
    cache_size = 1048, -- 缓存字数大小，默认 2048
    antialias = 1, -- 抗锯齿等级，默认 4
})

-- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
airui.font_load({
    type = "hzfont",             -- 字体类型，可选 "hzfont" 或 "bin"
    path = "/MiSans_gb2312.ttf", -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
    size = 20,                   -- 字体大小，默认 16
    cache_size = 1048,           -- 缓存字数大小，默认 2048
    antialias = 2,               -- 抗锯齿等级，默认 4
})
```

**示例 3： 使用 exeasyui 扩展库加载 hzfont**

```lua
-- 必须加载才能启用exeasyui的功能
local ui = require("exeasyui")

-- 启用14号固件内置HzFont矢量字体方式驱动
hw_font_drv.init({
    type = "hzfont",
    size = 32,
    antialias = -1  -- 自动抗锯齿
})
```

---

## 四、扩展使用

更详细的参数说明可以参考 [hzfont核心库](https://docs.openluat.com/osapi/core/hzfont/)