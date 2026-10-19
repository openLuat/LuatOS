--[[
@module  watchdog_app
@summary 出厂固件外置硬件看门狗模块（Air153C/Air153D，按版本启用）
@version 1.0
@date    2026.09.20
@author  李源龙
@usage
本模块为出厂固件的外置硬件看门狗管理模块，核心业务逻辑为：
1、按 factory_config.DEVICE_VER 读取看门狗配置（启用开关/喂狗引脚/喂狗周期）
2、调用 exair153x_wdt.init() 初始化并启动自动喂狗任务
3、所有5个版本板子均带 Air153 外置看门狗，默认全部启用

硬件接线：GPIO → NPN 三极管 → WTDOG
  GPIO 高电平 → NPN 导通 → WTDOG 低电平（空闲态）
  GPIO 低电平 → NPN 截止 → WTDOG 高电平（喂狗有效）

注意：
- 喂狗周期必须 >=150s（Air153C 超时240s；Air153D 超时由硬件STRAP决定，默认240s）
- 软狗 wdt（LuatOS 内核，9s超时3s喂狗）在 main.lua 已启用，两者互不影响可共存
]]

local watchdog_app = {}

local factory_config = require "factory_config"
local exair153x_wdt = require "exair153x_wdt"

--[[
初始化外置硬件看门狗（按版本配置）

@local
@function init_watchdog
@return boolean 是否启用成功
]]
local function init_watchdog()
    local wdt_cfg = factory_config.get_wdt()
    if not wdt_cfg or not wdt_cfg.enable then
        log.info("watchdog_app", "当前版本未启用外置看门狗:", factory_config.get_ver())
        return false
    end
    local ok = exair153x_wdt.init({
        wdt_pin = wdt_cfg.pin,
        auto_feed_period_s = wdt_cfg.period,
    })
    if ok then
        log.info("watchdog_app", "外置看门狗已启用，引脚:", wdt_cfg.pin, "周期:", wdt_cfg.period, "秒")
        return true
    else
        log.error("watchdog_app", "外置看门狗初始化失败")
        return false
    end
end

-- 启动看门狗
init_watchdog()

return watchdog_app
