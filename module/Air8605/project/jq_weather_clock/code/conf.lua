--[[
@module  conf
@summary 桌面天气时钟 —— 全局配置（硬件 / 业务 / 视觉参数唯一入口）
@version 1.0
@date    2026.11.08
@board   Air8605 系列（Air1602 主控）+ 10.1 寸 RGB 1024x600 + GT911 触摸

=== 改这里就够了 ===
换硬件：改 M.lcd / M.touch / M.power_on
换城市：改 M.weather.fallback.city（联网后仍会被 IP 定位结果覆盖）
调速度：M.time.demo_day_seconds（0 = 跟随真实时钟；>0 = 把一天压缩成这么多秒，用于演示日夜循环）
换房间温湿度来源：M.sensor.model（"none" = 演示值，"aht20" = I2C 读真实传感器）
]]

local M = {}

-- ==================== 屏幕 ====================
M.W, M.H      = 1024, 600
M.rotation    = 0            -- 0 / 90 / 180 / 270
M.screen_size = 10.0         -- 屏尺寸（英寸），只用于 density_scale 打印
M.need_buffer = true         -- RGB 屏必须开帧缓冲，否则撕裂

-- RGB 时序（1024x600 生态实测组，与 factory/config/eng_8605m_10i_v0.lua 一致）
M.lcd = {
    interface = "rgb",
    pin_rst   = 15,          -- LCD_DISP = GPIO15（显示使能）
    w         = 1024,
    h         = 600,
    hbp       = 140,
    hspw      = 20,
    hfp       = 160,
    vbp       = 20,
    vspw      = 3,
    vfp       = 12,
    bus_speed = 50 * 1000 * 1000,
}

-- 触摸 GT911（I2C1 轮询模式）
M.touch = {
    port     = 1,
    pin_rst  = 72,           -- TP_RST = GPIO72
    pin_int  = 51,           -- TP_INT = GPIO51
    poll     = true,         -- true = 轮询模式（中断模式会丢点）
}

-- 背光 PWM3
M.backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 }

-- ==================== 上电时序 ====================
-- 顺序即依赖：电源轨 → SD → 4G 复位 → 485
-- 与 factory/config/eng_8605m_10i_v0.lua 一致，但**故意少开两路**：
--   GPIO73 = AUDIOPA_EN（Air1103 语音芯片供电）：本工程不用语音，不给它上电
--   GPIO58 = UVC_EN（摄像头供电）：本工程不用摄像头，少一路功耗与 I2C/USB 干扰
-- 4G_RESET = GPIO64：拉高 50ms 再拉低 120ms 才是完整复位（见该配置文件的文件头第 4 条），
-- 只拉低不复位，模组有时会卡在开机瞬间的状态里注不上网。
M.power_on = {
    { pin = 44, level = 1 },              -- 12V_EN
    { pin = 12, level = 1 },              -- 5V_EN
    { pin = 56, level = 1 },              -- 9V_EN
    { pin = 74, level = 1 },              -- SD_EN
    { pin = 64, level = 1, delay = 50 },  -- 4G_RESET 拉高 50ms
    { pin = 64, level = 0, delay = 120 }, -- 再拉低 120ms 完成复位
    { pin = 14, level = 1 },              -- 485 总电源（不通信，保持常供）
}

-- ==================== 字体 ====================
-- hzfont 每出现一个新字号就会建一份字体实例（含点阵缓存），
-- 所以全工程只允许下面这几个字号，别在循环里动态算字号。
M.font = { size = 20, cache_size = 512, antialias = 1 }
M.F = {
    clock = 84,   -- 顶部大时钟
    big   = 40,   -- 预报页大温度
    mid   = 30,   -- 日期 / 城市 / 室内温湿度
    small = 22,   -- 预报页正文
    tiny  = 16,   -- 提示 / 脚注
}

-- ==================== 时间 ====================
M.time = {
    base_year  = 1900,   -- rtc.setBaseYear
    timezone   = 32,     -- 合宙时区单位是 15 分钟，东八区 = 32
    -- 0 = 跟随真实时钟（真机默认）
    -- >0 = 把 24 小时压缩成这么多秒循环播放，只为演示「天亮→天黑→天亮」
    demo_day_seconds = 0,
    -- 夜间判定（小动物回窝）
    night_start = 18.5,
    night_end   = 6.5,
}

-- ==================== 天气 ====================
M.weather = {
    refresh_ms    = 30 * 60 * 1000,   -- 成功后的刷新间隔
    retry_min_ms  = 60 * 1000,
    retry_max_ms  = 10 * 60 * 1000,
    forecast_days = 8,                -- 今天 + 未来 7 天
    --[[固定城市（最可靠的做法，建议部署时填上）

    留 "" / nil = 按出口 IP 自动定位。但 4G 和大部分公司网络的出口 IP 落在
    运营商的大区机房（人在西安、出口在北京），IP 库只能给出那个机房所在的城市，
    屏上就会显示成别的城市 —— 这不是 bug，是 IP 定位的物理上限。

    填了城市名就完全跳过 IP 定位，直接按这个名字查天气。例：city = "西安"
    （名字要能被 open-meteo 的城市库检索到，写"西安"而不是"西安市"。）]]
    city          = "",
    -- 离线兜底数据：开机先上屏，联网成功后整体替换。
    -- 数值抄的是参考图里的西安场景，方便对版。
    fallback = {
        city = "西安",
        condition = "晴",
        temp = 6,
        temp_min = 1,
        temp_max = 10,
        daily = {
            { wd = "周一", date = "11/09", cond = "晴",   high = 10, low = 1 },
            { wd = "周二", date = "11/10", cond = "多云", high = 12, low = 3 },
            { wd = "周三", date = "11/11", cond = "阴",   high = 9,  low = 2 },
            { wd = "周四", date = "11/12", cond = "雨",   high = 7,  low = 4 },
            { wd = "周五", date = "11/13", cond = "雨",   high = 8,  low = 5 },
            { wd = "周六", date = "11/14", cond = "多云", high = 11, low = 3 },
            { wd = "周日", date = "11/15", cond = "晴",   high = 13, low = 2 },
        },
    },
}

-- ==================== 房间温湿度 ====================
-- "none"  ：没有传感器，用「室外温度 + 室内外温差模型」算一个稳定的演示值
-- "aht20" ：AHT20（I2C，0x38），需要另外一路 I2C 总线（I2C1 被触摸占用）
-- 想接自己的传感器：在 drv/room_sensor.lua 里给 M.reader 赋一个函数即可
M.sensor = {
    model  = "none",
    i2c_id = 0,
    addr   = 0x38,
}

-- ==================== 角色 ====================
M.actor = {
    order   = { "cyclist", "cat", "dog", "rabbit" },  -- 点击小人/小动物循环切换
    default = "cyclist",
    x       = 512,     -- 初始横坐标
    house_x = 806,     -- 小窝门中心横坐标
    pet_min_x = 360,   -- 小动物散步范围
    pet_max_x = 700,
}

return M
