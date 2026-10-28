--[[
@module config
@summary 抓娃娃机 demo 布局常量与玩法调参
@ver 1.0.0
@author cqd
@note 板级档位沿用 cqd_LuckyWheel 约定：air8607_10i 为官方 10.1 寸核心板
      （RGB565 1024*600，exd_jd9165ba_rgb 初始化）；非 air8607 板子（含 PC）
      走内置屏路径。UI 布局固定按 1024*600 整数坐标设计。
@usage local config = require "config"
]]

return {
    -- ==================== 板级 ====================
    BOARD_PROFILE = "air8607_10i", -- 板级档位
    BACKLIGHT_DUTY = 90,           -- 屏幕背光 PWM 占空比 %
    width = 1024,
    height = 600,
    frame_ms = 40,                 -- 主循环帧间隔（25fps）
    performance_log_ms = 2000,     -- 性能日志间隔

    -- ==================== 机柜布局（claw_model 与 ui 共用） ====================
    rail_y = 132,                  -- 横轨中心线 Y
    claw_rest_y = 232,             -- 爪体静止高度（爪体中心 Y）
    claw_grab_y = 430,             -- 抓取高度（爪体中心 Y）
    claw_min_x = 96,               -- 横移范围（爪中心 X）
    claw_max_x = 638,
    toy_y = 505,                   -- 娃娃堆中心高度
    toy_r = 32,                    -- 娃娃半径
    floor_y = 540,                 -- 台面 Y
    chute_x = 638,                 -- 出货口中心 X
    chute_land_y = 556,            -- 娃娃落入出货口的落点 Y
    toy_fall_g = 2600,             -- 出货下落加速度 px/s^2

    -- ==================== 玩法调参 ====================
    claw_speed = 420,              -- 横移速度 px/s
    drop_speed = 520,              -- 下探速度 px/s
    lift_speed = 380,              -- 回升速度 px/s
    carry_speed = 460,             -- 搬运横移速度 px/s
    grab_ms = 480,                 -- 闭爪时长 ms
    release_ms = 620,              -- 张爪放娃时长 ms
    result_hold_ms = 1400,         -- 结果停留时长 ms
    grab_chance = 0.62,            -- 对准后的基础成功率（0~1）
    align_bonus = 0.33,            -- 完美对准的追加成功率
    capture_pad = 18,              -- 抓取判定容差 px

    -- ==================== 音效（exaudio） ====================
    sfx_vol = 30,                  -- 音量 0~100
    pa_ctrl = 73,                  -- 功放使能 GPIO（HT6873，与板级 AUDIOPA_EN 一致）
    pa_on_level = 1,
    dac_delay = 6,

    -- ==================== 娃娃阵容 ====================
    -- kind: bear / bunny / frog / duck；color: 填充基色
    toys = {
        { x = 128, kind = "bear",  color = 0xE8A33D },
        { x = 212, kind = "bunny", color = 0xF2A9C4 },
        { x = 296, kind = "frog",  color = 0x7BC96F },
        { x = 380, kind = "duck",  color = 0xF5D14E },
        { x = 464, kind = "bear",  color = 0x9B7BE8 },
        { x = 548, kind = "bunny", color = 0x79C7E8 },
    },
}
