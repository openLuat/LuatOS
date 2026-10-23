-- Air8601 / 7 inch 1024x600 / official LuatOS + AirUI.
-- All IO is simulated. No relay, motor, or mains GPIO is driven.
return {
    width = 1024,
    height = 600,
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
