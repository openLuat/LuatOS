--[[
@module  reload_app
@summary RELOAD按键驱动模块（WAKEUP2，唯一持有者）
@version 2.0
@date    2026.08.04
@author  江访
@usage
WAKEUP2 按键检测，require 即注册：
- 按下时发布 KEY_EVENT("reload_down")
- 抬起时发布 KEY_EVENT("reload_up")
- 持续按压5秒发布 FACTORY_RESET_REQUEST（恢复出厂设置，由 board_init 处理）

说明：board_init.lua 不再注册该引脚，避免中断重复注册覆盖。
]]

local RELOAD_PIN = gpio.WAKEUP2
local RESET_HOLD_MS = 5000 -- 5 秒

-- 按压计时器
local reset_press_timer = nil

--[[
长按5秒触发恢复出厂设置回调（发布 FACTORY_RESET_REQUEST，由 board_init 处理）

@local
@function factory_reset_cb
]]
local function factory_reset_cb()
    log.warn("reload_app", "RELOAD按住5秒，触发恢复出厂设置")
    sys.publish("FACTORY_RESET_REQUEST")
end

--[[
WAKEUP2 按键中断回调（BOTH 边沿触发）：
- 按下(val=1)：发布 KEY_EVENT("reload_down")，启动5秒长按计时器
- 抬起(val=0)：发布 KEY_EVENT("reload_up")，取消长按计时器

@local
@function handle_reload_key
@param val number 1=按下, 0=释放
]]
local function handle_reload_key(val)
    if val == 1 then
        log.info("reload_app", "RELOAD按键按下")
        sys.publish("KEY_EVENT", "reload_down")
        -- 启动5秒计时器：按住不松手则触发恢复出厂
        reset_press_timer = sys.timerStart(factory_reset_cb, RESET_HOLD_MS)
    else
        log.info("reload_app", "RELOAD按键抬起")
        sys.publish("KEY_EVENT", "reload_up")
        if reset_press_timer then
            sys.timerStop(reset_press_timer)
            reset_press_timer = nil
        end
    end
end

-- 注册 WAKEUP2 中断（BOTH 边沿触发）
gpio.setup(RELOAD_PIN, handle_reload_key, gpio.PULLUP, gpio.BOTH)
gpio.debounce(RELOAD_PIN, 50, 0) -- 50ms防抖

log.info("reload_app", "RELOAD按键初始化完成 (按住5秒恢复出厂设置)")
