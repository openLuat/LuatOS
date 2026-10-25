return {
    width = 1024,
    height = 600,

    -- air8607_10i：Air8607(Air1603)+AirLCD_1100 10.1寸 JD9165BA(1024x600 RGB)
    -- air8601_7i ：Air8601(Air1601)+7寸 HX8282(1024x600 RGB)
    BOARD_PROFILE = "air8607_10i",
    BACKLIGHT_DUTY = 90, -- 仅 air8607_10i 的 PWM3 背光使用，0~100

    -- 模拟刷新周期（运行总览与站场图共用）
    frame_ms = 120,

    -- 模拟时钟起点 10:42:00
    start_seconds = 10 * 3600 + 42 * 60,
    simulated_date = "2026-10-20"
}
