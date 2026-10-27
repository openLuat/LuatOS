--[[
@module  conf
@summary 桌面时钟/日历 - 板级与业务参数
@author  王世豪
@version 1.0
@date    2026.10.26
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡

所有硬件参数与 project/factory/config/eng_8607_10i_v0.lua 对齐：
  LCD_DISP = GPIO15   LCD 供电 = GPIO17（低有效）   SD_EN = GPIO74
  SPI1_CS = GPIO8     TP_RST = GPIO14   TP_INT = GPIO51
  背光: PWM3(GPIO13)   功放 PA: GPIO73（本工程不出声，开局关断）

@note Air8607 无 4G / 无 WiFi：时间只能靠本地 RTC + 手动校时，无法自动授时。
改板子只需要改这一个文件。
]]
return {
    -- 屏幕逻辑分辨率
    W = 1024,
    H = 600,

    -- ===== TF / SD 卡（SPI1，只用来读壁纸）=====
    sd = {
        spi_id    = 1,
        pin_cs    = 8,
        pin_en    = 74,           -- SD_EN 高电平供电（Air8607 底板 = GPIO74）
        speed     = 40 * 1000 * 1000,
        mount     = "/sd",
        page_size = 100,
    },

    -- ===== 中文字库 =====
    font = {
        size       = 16,
        cache_size = 2048,
        antialias  = 1,
    },

    -- ===== 背光 =====
    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 100,            -- 默认亮度 %
        min     = 10,             -- 下限，防止调成全黑看不见
    },

    -- ===== RTC（无网络，纯本地）=====
    -- rtc.timezone(32) = 东八区。单位是 15 分钟，8 小时 = 32。
    -- 基准年 1900 必须显式设置，否则时间戳换算基准不对。
    rtc = {
        timezone  = 32,
        base_year = 1900,
    },

    -- ===== 时钟 =====
    clock = {
        tick_ms  = 1000,          -- 界面刷新间隔（1 秒）
        show_sec = true,          -- 是否显示秒
    },

    --[[壁纸（可选）
    真机解码全屏大图的内存开销很大，多图切换压力更大。所以这里：
      - 只支持 **JPEG**（jpeg 通道），不支持 PNG；
      - 只加载 **一张**，永不切换（内存紧张，不做轮换）。
    不想用壁纸就把 enabled 改成 false，程序会退化成纯色渐变背景。
    ]]
    wallpaper = {
        enabled = true,
        file    = "/sd/wallpaper/clock.jpg",
        -- 找不到文件时自动尝试这些候选（第一个存在的生效）
        fallback = {
            "/sd/wallpaper/clock.jpg",
            "/sd/wallpaper/wp1.jpg",
            "/sd/clock.jpg",
            "/sd/bg.jpg",
        },
    },

    -- ===== 倒计时 / 纪念日 =====
    -- 每年循环的日子写 month/day；一次性日期写 date = "2027-06-01"。
    events = {
        { name = "新年",   month = 1,  day = 1  },
        { name = "国庆",   month = 10, day = 1  },
        { name = "圣诞节", month = 12, day = 25 },
    },
}
