local air153c_wdt = {}

local config = require "config"

function air153c_wdt.init()
    local cfg = config.WDT_CONFIG or {}
    if cfg.ENABLE ~= true then
        log.info("air153c_wdt", "看门狗未开启，跳过初始化")
        return
    end
    if not cfg.FEED_PIN then
        log.warn("air153c_wdt", "未配置喂狗 GPIO 引脚，跳过看门狗初始化")
        return
    end

    local ok, exair153x_wdt = pcall(require, "exair153x_wdt")
    if not ok or not exair153x_wdt then
        log.error("air153c_wdt", "加载 exair153x_wdt 库失败")
        return
    end

    local feed_interval = cfg.FEED_INTERVAL or 180
    if feed_interval < 150 then
        log.warn("air153c_wdt", "喂狗时间过小，强制为150秒")
        feed_interval = 150
    end

    local init_ok = exair153x_wdt.init({
        wdt_pin            = cfg.FEED_PIN,
        auto_feed_period_s = feed_interval,
    })
    if init_ok then
        log.info("air153c_wdt", "Air153C 看门狗初始化成功，喂狗引脚:", cfg.FEED_PIN, "周期:", feed_interval, "秒")
    else
        log.error("air153c_wdt", "Air153C 看门狗初始化失败")
    end
end

return air153c_wdt
