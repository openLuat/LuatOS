--[[
@module  config
@summary 硬件配置（唯一配置源，按实际接线/屏型号修改）
@version 1.0
@date    2026.11.11
@usage
硬件（参考 module/Air8603/demo/ns2009_resistive_touch）：
  底板 Air8603M1（模组 Air1603）+ 40PIN 电阻触摸显示屏
  屏   宏显伟业 0700A001-H1E0191：7 寸 800x480 RGB-24BIT，驱动 IC HX8264
  触摸 深圳纳芯微 NS2009：I2C1（PIN42=SCL / PIN41=SDA），地址 0x49（A0 拉高）

本目录是 NS2009 电阻触摸整机测试 Demo：
  · 界面用 AirUI 控件（container/label/button/shape）绘制，不手写 display 像素/点阵字模；
  · 触摸 / 标定 / fskv 存档走核心库 tp；
  · AirUI 通过 airui.device_bind_touch(dev) 复用 tp.init 的设备，拿到的就是标定后的屏幕坐标。

改硬件只动本文件：上电时序 / RGB 时序 / 背光 / 触摸参数全在这里；
其它模块只 require 本文件，不写死任何引脚号。
]]

local CFG = {}

-- ===== 底板上电时序（★ 真机必须，否则屏/触摸都没电）=====
-- 取自 factory 的 power_on：5V_EN=GPIO12、9V_EN=GPIO56、12V_EN=GPIO44、5VOUT_EN=GPIO52
CFG.power_on = {
    { pin = 12, dir = 0, level = 1 },              -- 5V_EN
    { pin = 56, dir = 0, level = 1, delay = 100 }, -- 9V_EN，等 100ms 稳定
    { pin = 44, dir = 0, level = 1 },              -- 12V_EN（屏背光升压）
    { pin = 52, dir = 0, level = 1 },              -- 5VOUT_EN（对外 5V）
}

-- ===== LCD：7 寸 800x480 RGB-24BIT（HX8264）=====
-- AirUI 真机(LUATOS)走 display 后端：先 display.init 分配 FB，再 airui.init 使用。
CFG.lcd = {
    w   = 800,
    h   = 480,
    hbp = 140,                 -- 水平后廊
    hspw= 20,                  -- 水平同步脉宽
    hfp = 160,                 -- 水平前廊
    vbp = 20,                  -- 垂直后廊
    vspw= 3,                   -- 垂直同步脉宽
    vfp = 12,                  -- 垂直前廊
    -- 像素时钟：800x480 + 上面这组时序，33MHz≈57Hz（稳）；
    -- 若确认屏能跑 87Hz 可上 50MHz（画面更"实"）。
    bus_speed = 33 * 1000 * 1000,
    pin_rst   = 15,            -- DISP/LCD_DISP = GPIO15，填 0xFF 表示不驱动
    direction = 0,             -- 0/90/180/270，同时作为 airui.set_rotation
}

-- ===== 背光：PWM3 调光（与 Air8603M1 出厂配置一致）=====
CFG.backlight = {
    pwm_ch   = 3,
    pwm_freq = 1000,
    level    = 90,             -- 0~100，开机亮度
}

-- ===== 触摸：NS2009（核心库 tp，新版 API）=====
CFG.touch = {
    i2c_id  = 1,               -- I2C1：PIN42=SCL / PIN41=SDA
    pin_int = 51,              -- PENIRQ 引脚（★ 按实际接线修改；nil 则启动时报错）
    w       = 800,             -- 触摸映射目标宽度（与屏一致）
    h       = 480,             -- 触摸映射目标高度
    refresh_rate = 20,         -- tp 库触摸读取刷新率（拖动时 MOVE 上报密度）
    -- 触摸坐标方向（tp.init 的 param.direction / param.swap_xy）：
    --   默认都不设：NS2009 未标定映射原点在左下角（Y 向上），上下颠倒问题
    --   不靠镜像参数解决，而是靠首次上电强制四点标定（不限时，直到成功）；
    --   ★ 改了方向参数后，旧的 fskv 标定存档不再匹配，需删除存档重标一次
    direction = nil,           -- 触摸坐标旋转 0/1/2/3；nil=跟随 LCD 方向
    swap_xy  = nil,            -- 坐标镜像翻转；nil=不翻转（用固件默认基准）
    -- 标定持久化（新版 tp API 支持系数读回/回灌后启用）：
    save_cal = true,           -- true=标定完成后自动存 fskv，上电自动恢复，免重复标定
    cal_kv  = "ns2009_cal",    -- fskv 键名
    auto_cal = true,           -- 无有效存档时上电自动四点标定（约 20 秒）
    -- I2C1 引脚显式复用（PIN42=SCL / PIN41=SDA）；固件无 pins 库会自动跳过
    pins = {
        { 42, "I2C1_SCL" },
        { 41, "I2C1_SDA" },
    },
}

-- ===== AirUI 界面主题（原生重设计：配色 + 字号）=====
-- 颜色一律 0xRRGGBB；字号按固件内置字库对齐（真机默认 hzfont 中文字库）。
CFG.ui = {
    font_size = 16,            -- 默认字号
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
}

return CFG
