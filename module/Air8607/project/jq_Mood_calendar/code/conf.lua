--[[
@module  conf
@summary 情绪日历 —— 板级与业务参数
@author  蒋骞
@version 1.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡

所有硬件参数与 project/factory/config/eng_8607_10i_v0.lua 对齐：
  LCD_DISP = GPIO15   LCD 供电 = GPIO17（低有效）   SD_EN = GPIO74
  SPI1_CS = GPIO8     TP_RST = GPIO14   TP_INT = GPIO51
  背光: PWM3(GPIO13)   功放 PA: GPIO73（本工程不出声，开局关断）

@note Air8607 无 4G / 无 WiFi：时间只能靠本地 RTC，无法自动授时。
改板子只需要改这一个文件。
]]
return {
    -- 屏幕逻辑分辨率
    W = 1024,
    H = 600,

    -- ===== TF / SD 卡（SPI1，只在 fskv 不可用时用来存心情数据）=====
    sd = {
        spi_id    = 1,
        pin_cs    = 8,
        pin_en    = 74,           -- SD_EN 高电平供电（Air8607 底板 = GPIO74）
        speed     = 40 * 1000 * 1000,
        mount     = "/sd",
    },

    -- ===== 中文字库 =====
    -- hzfont 是按需生成字形的矢量字库，任意字号都可用；
    -- cache_size 是字形缓存条数，1024x600 满屏中文建议 >= 2048。
    font = {
        size       = 16,
        cache_size = 2048,
        antialias  = 1,
    },

    -- ===== 背光 =====
    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 100,            -- 亮度 %（本工程不提供调节入口）
    },

    -- ===== RTC（无网络，纯本地）=====
    -- rtc.timezone(32) = 东八区。单位是 15 分钟，8 小时 = 32。
    -- 基准年 1900 必须显式设置，否则时间戳换算基准不对。
    --
    -- 时间「从哪来」：RTC 断电后是无效值，所以启动时会把 RTC 拉正，基准按优先级取：
    --   1、app/build_stamp.lua 的烧录戳（tools/更新烧录时间.bat 写入，最准）
    --   2、rtos.buildDate() 固件编译日期（合宙官方固件可能很旧，只作兜底）
    rtc = {
        timezone  = 32,
        base_year = 1900,

        -- RTC 年份小于这个值，视为「没初始化」，直接按基准校准
        valid_year = 2020,
        -- 基准只有日期时（固件编译日期），校准到当天的这个钟点
        -- 取上午，避开 0 点跨时区把日期算到前一天
        build_hour = 8,
        -- true = 每次上电都强制把时间重置为基准
        -- false = 只在 RTC 无效或落后于基准时才校准（默认，更安全）
        force_calibrate = false,--true,
    },

    -- 界面刷新间隔（毫秒）：只在“跨天”时真正重画，平时几乎没有开销
    tick_ms = 1000,

    -- 心情数据的存储键前缀：fskv key = "mood_202610"
    mood_key_prefix = "mood_",

    --[[心情五档（分数 1~5，固定从高到低排列，UI 直接按顺序画）

    颜色是治愈系低饱和色：
      5 蜜桃橙  4 暖黄  3 薄荷  2 雾蓝  1 淡紫
    格子背景用的是它再调淡（tint）后的颜色，文字用调深（shade）后的颜色，
    保证浅色底上文字依旧看得清。
    ]]
    moods = {
        { score = 5, name = "超棒", color = 0xFF9E7A },
        { score = 4, name = "不错", color = 0xF7C46B },
        { score = 3, name = "一般", color = 0x9FD3C7 },
        { score = 2, name = "不好", color = 0x9BB8D9 },
        { score = 1, name = "糟糕", color = 0xBCA9CF },
    },
}
