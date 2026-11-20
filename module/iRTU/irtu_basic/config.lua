local config = {}

-- 看门狗配置（Air153C 硬件看门狗）
-- 硬件接线：AGPIO24 → NPN → WTDOG（见 exair153x_wdt 库注释）
-- 默认开启：喂狗 GPIO24，周期 180 秒（Air153C 超时固定 240s，喂狗周期需 >150s）
config.WDT_CONFIG = {
    ENABLE = true,                 -- 是否启用看门狗（默认开启）
    FEED_PIN = 24,                 -- 喂狗引脚（AGPIO24 → NPN → WTDOG）
    FEED_INTERVAL = 180,           -- 喂狗间隔(秒)，需大于150
}

return config