--[[
@module  ns2009_1024_600
@summary NS2009 电阻触摸测试 · 1024x600 配置（配置驱动架构）
@version 1.0
@date    2026.11.13

本文件是「配置驱动」架构下的一份纯数据配置文件，由 core/platform_loader.lua
根据 main.lua 里的 PROJECT 值 require 加载，存入 _G.project_config。
换分辨率不删代码：在 main.lua 把 PROJECT 改成对应值即可（映射见 platform_loader）。

  PROJECT = "NS2009_RESISTIVE_TOUCH_1024_600" → 本配置
  PROJECT = "NS2009_RESISTIVE_TOUCH_800_480"  → config/ns2009_800_480.lua
  PROJECT = "NS2009_RESISTIVE_TOUCH_480_272"  → config/ns2009_480_272.lua

★ 改硬件只改本配置文件：上电时序 / RGB 时序 / 背光 / 触摸参数 / 字号全在这里，
  其它模块只读 _G.project_config，不写死任何引脚号或分辨率。
]]

return {
    name       = "NS2009_RESISTIVE_TOUCH_1024_600",
    chip       = "Air1603",
    baseboard  = "Air8603M1",

    -- ===== 底板上电时序（★ 真机必须，否则屏/触摸都没电）=====
    -- 5V_EN=GPIO12、9V_EN=GPIO56、12V_EN=GPIO44、5VOUT_EN=GPIO52
    power_on = {
        { pin = 12, dir = 0, level = 1 },              -- 5V_EN
        { pin = 56, dir = 0, level = 1, delay = 100 }, -- 9V_EN，等 100ms 稳定
        { pin = 44, dir = 0, level = 1 },              -- 12V_EN（屏背光升压）
        { pin = 52, dir = 0, level = 1 },              -- 5VOUT_EN（对外 5V）
    },

    -- ===== LCD：7 寸 1024x600 RGB-24BIT =====
    -- ★ 换屏后 hbp/hspw/hfp/vbp/vspw/vfp 必须按新屏规格书核对，下面是一组通用参考值；
    --   直接沿用原 800x480 屏（HX8264）的时序会花屏/黑屏。
    lcd = {
        w   = 1024,
        h   = 600,
        hbp = 140,                 -- 水平后廊（参考值，以规格书为准）
        hspw= 20,                  -- 水平同步脉宽（参考值）
        hfp = 160,                 -- 水平前廊（参考值）
        vbp = 20,                  -- 垂直后廊（参考值）
        vspw= 3,                   -- 垂直同步脉宽（参考值）
        vfp = 12,                  -- 垂直前廊（参考值）
        -- 像素时钟：(1024+140+20+160) x (600+20+3+12) x 60Hz ≈ 51.2MHz；
        -- 51MHz≈59.8Hz（稳）。画面不稳可下调，屏支持高刷再上调。
        bus_speed = 51 * 1000 * 1000,
        pin_rst   = 15,            -- DISP/LCD_DISP = GPIO15，填 0xFF 表示不驱动
        direction = 0,             -- 0/90/180/270，同时作为 airui.set_rotation
    },

    -- ===== 背光：PWM3 调光（与 Air8603M1 出厂配置一致）=====
    backlight = {
        pwm_ch   = 3,
        pwm_freq = 1000,
        level    = 90,             -- 0~100，开机亮度
    },

    -- ===== 触摸：NS2009（核心库 tp，新版 API）=====
    touch = {
        i2c_id  = 1,               -- I2C1：PIN42=SCL / PIN41=SDA
        pin_int = 51,              -- PENIRQ 引脚（★ 按实际接线修改；nil 则启动时报错）
        w       = 1024,            -- 触摸映射目标宽度（与屏一致）
        h       = 600,             -- 触摸映射目标高度
        refresh_rate = 20,         -- tp 库触摸读取刷新率（拖动时 MOVE 上报密度）
        -- 触摸坐标方向：默认都不设，方向问题靠首次上电强制四点标定解决
        direction = nil,           -- 触摸坐标旋转 0/1/2/3；nil=跟随 LCD 方向
        swap_xy  = nil,            -- 坐标镜像翻转；nil=不翻转（用固件默认基准）
        -- 标定持久化：★ 换分辨率/换屏后必须重新四点标定。用独立 cal_kv 键名
        -- 让其它分辨率的旧存档自动失效、上电强制重标（每个分辨率独立存档）。
        save_cal = true,           -- 标定完成后自动存 fskv，上电自动恢复
        cal_kv  = "ns2009_cal_1024x600",  -- fskv 键名（每个分辨率独立）
        auto_cal = true,           -- 无有效存档时上电自动四点标定（约 20 秒）
        -- I2C1 引脚显式复用（PIN42=SCL / PIN41=SDA）；固件无 pins 库会自动跳过
        pins = {
            { 42, "I2C1_SCL" },
            { 41, "I2C1_SDA" },
        },
    },

    -- ===== AirUI 界面主题（配色 + 字号 + 标定十字尺寸）=====
    -- 字号按固件内置 hzfont 字库对齐（12~255 号可用）。
    ui = {
        font_size     = 16,        -- 中文/标签字号
        val_font_size = 20,        -- 坐标读数大字号
        cross_r       = 30,        -- 标定十字外圈半径
        cross_arm     = 46,        -- 标定十字臂长（从圆心到端点）
        color = {
            bg        = 0x0E1620,  -- 全屏背景
            header    = 0x16324A,  -- 顶栏
            panel     = 0x122029,  -- 右侧数值面板
            pad_bg    = 0x0A1218,  -- 触摸区背景
            grid      = 0x1E3A4A,  -- 网格线
            border    = 0x2E6E8E,  -- 边框
            text      = 0xDCE9F2,  -- 主文字
            dim       = 0x7F97A8,  -- 次要文字
            accent    = 0xFFD54F,  -- 强调（准星/高亮）
            ok        = 0x66BB6A,  -- 成功/按下
            warn      = 0xFFA726,  -- 已标定
            err       = 0xEF5350,  -- 失败/超时
            btn_bg    = 0x1F3A4D,  -- 按钮底
            btn_press = 0x2E6E8E,  -- 按钮按下
            trace     = 0x00E5FF,  -- 轨迹线
        },
    },
}
