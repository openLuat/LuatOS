-- Air8601 / 7 inch 1024x600 / official LuatOS + AirUI.
-- All IO is simulated. No relay, motor, or mains GPIO is driven.
return {
    width = 1024,
    height = 600,
    -- air8607_10i：Air8607(Air1603)+AirLCD_1100 10.1寸 JD9165BA(1024x600 RGB)
    -- air8601_7i ：Air8601(Air1601)+7寸 HX8282(1024x600 RGB)
    BOARD_PROFILE = "air8607_10i",
    BACKLIGHT_DUTY = 90, -- 仅 air8607_10i 的 PWM3 背光使用，0~100
    tick_ms = 100,
    -- Wall-clock durations; only the opaque drawer parent moves at 20 ms ticks.
    drawer_animation_ms = 220,
    drawer_close_animation_ms = 180,
    network = {transition_ms = 400},
    device_names = {
        {"上料单元","装配机械臂","视觉检测","自动包装"},
        {"上料单元","装配机械臂","视觉检测","自动包装"},
    },
    fault_interval_ms = 60000,
    check_period_ms = 500,
    stable_samples = 2,
    verification_timeout_ms = 12000,
    event_limit = 24,
    background_a = "/luadb/line_a.jpg",
    background_b = "/luadb/line_b.jpg",
    -- Empty URL: local event bus + JSON log only. Do not claim cloud delivery.
    -- Set a real HTTP(S) ingestion endpoint AND enable networking separately.
    report_url = "",
    report_timeout_ms = 8000,
    report_queue_limit = 12,
    -- Optional endpoint header. Keep production credentials out of shared code.
    report_headers = { ["Content-Type"] = "application/json" },
}
