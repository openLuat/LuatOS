--[[
@module  conf
@summary 失物招领公示 - 板级与业务参数
@version 1.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10 寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡
@usage
改标题、示例数据、每页条数、身份证示例，都只改本文件。
]]

local M = {}

-- ==================== 屏幕 / 触摸 / 背光 ====================
M.W, M.H = 1024, 600

M.display = {
    pin_rst = 15,        -- LCD_DISP / 复位
    rotation = 0,
}

M.touch = {
    model = "gt911",
    port = 1,
    pin_rst = 14,
    pin_int = 51,
}

M.backlight = {
    pwm_ch = 3,          -- 背光 PWM3 (GPIO13)
    freq = 1000,
    duty = 90,           -- 0..100
}

M.font = {
    size = 16,
    cache_size = 2048,
    antialias = 1,
}

-- ==================== 业务 ====================
M.TITLE    = "失物招领公示"
M.SUBTITLE = "LOST & FOUND · 拾金不昧 文明有礼"
M.PAGE_SIZE = 5          -- 每页列表条数

-- 合成示例身份证（17 位数字 + 校验位，仅演示用，非真实证件）
M.SAMPLE_ID = "110101199001011237"

-- 示例数据（开机即带，便于演示）
M.SAMPLE_ITEMS = {
    { kind = "found", name = "黑色钱包",   time = "2026-10-28 08:30", place = "食堂二楼",    contact = "13800001111" },
    { kind = "lost",  name = "苹果手机",   time = "2026-10-29 12:05", place = "图书馆三楼",  contact = "13900002222" },
    { kind = "found", name = "学生卡",     time = "2026-10-30 09:15", place = "操场看台",    contact = "13700003333" },
    { kind = "lost",  name = "蓝色雨伞",   time = "2026-10-27 18:40", place = "校门口",      contact = "13600004444" },
    { kind = "found", name = "无线耳机",   time = "2026-10-26 15:20", place = "体育馆",      contact = "13500005555" },
    { kind = "lost",  name = "校园卡",     time = "2026-10-25 11:00", place = "教学楼A座",   contact = "13400006666" },
    { kind = "found", name = "黑色书包",   time = "2026-10-24 17:30", place = "办公楼大厅",  contact = "13300007777" },
    { kind = "lost",  name = "儿童手表",   time = "2026-10-23 10:10", place = "公园东门",    contact = "13200008888" },
}

return M
