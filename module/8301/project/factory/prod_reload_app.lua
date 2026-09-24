--[[
@module  prod_reload_app
@summary RELOAD 按键驱动模块（产测模式，WAKEUP2 唯一持有者）
@version 2.0
@date    2026.08.04
@version_note 产测专属：仅保留按键检测上报，去掉长按 5 秒恢复出厂逻辑
@usage
WAKEUP2 按键检测，require 即注册：
- 按下时发布 KEY_EVENT("reload_down")
- 抬起时发布 KEY_EVENT("reload_up")

说明：board_init.lua 不再注册该引脚，避免中断重复注册覆盖。
产测由 prod_test 订阅 KEY_EVENT 上报 RELOAD_PRESS# / RELOAD_RELEASE#。
]]

local RELOAD_PIN = gpio.WAKEUP2

--[[
WAKEUP2 按键中断回调（BOTH 边沿触发）：
注意：PULLUP 模式下，按下=低电平(val=0)，抬起=高电平(val=1)
- 按下(val=0)：发布 KEY_EVENT("reload_down")
- 抬起(val=1)：发布 KEY_EVENT("reload_up")

@local
@function handle_reload_key
@param val number 0=按下(低电平), 1=释放(高电平)
]]
local function handle_reload_key(val)
    if val == 0 then
        log.info("prod_reload_app", "RELOAD按键按下")
        sys.publish("KEY_EVENT", "reload_down")
    else
        log.info("prod_reload_app", "RELOAD按键抬起")
        sys.publish("KEY_EVENT", "reload_up")
    end
end

-- 注册 WAKEUP2 中断（BOTH 边沿触发）
gpio.setup(RELOAD_PIN, handle_reload_key, gpio.PULLUP, gpio.BOTH)
gpio.debounce(RELOAD_PIN, 50, 0) -- 50ms防抖

log.info("prod_reload_app", "RELOAD按键初始化完成")
