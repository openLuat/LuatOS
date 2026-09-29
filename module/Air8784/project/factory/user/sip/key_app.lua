--[[
@module  key_app
@summary 8784 功能按键模块（SOS 接听 / 呼叫，UP 短按播留言 + 长按挂断）
@version 1.3
@date    2026.09.28
@author  王世豪
@usage
本模块为按键业务模块，核心业务逻辑为：
1、GPIO23 拉高作为上拉参考电压（VREF，开机常开，main.lua 已打开，此处幂等设置）；
2、SOS 键（GPIO20）：按下即触发，发 SIP_APP_MAIN_PRIMARY_REQ，由业务层按状态分流
   来电中接听，空闲时向 config.dial_number（IMEI+1）拨号，
   通话中默认忽略（config.keys.sos_preempt_in_call = false）；
   因为呼叫目标就是来电方（都是 IMEI+1），用户不需要自己判断"现在是来电还是空闲"，
   按下去一定是跟对方说话；
3、UP 键（GPIO21）区分长短按：
   - 短按（松开时不足 long_press_ms）：发 MSG_PLAY_REQ 播放预置留言
     （由 msg_player 判断是否空闲；通话中 / 来电中被忽略，不会抢通话通道）；
   - 长按（按住达到 long_press_ms 立即触发，不等松开）：按 config.keys.long_press_action 执行，
     当前配置 hangup = 挂断 / 拒接；
   长按触发后松开不再补发短按，避免一次按压既挂断又播留言；
4、两键均为按下拉低（内部上拉），带消抖；


本文件没有对外接口，直接在其他功能模块中 require "key_app" 即可加载运行；
]]

local config = require "config"
local cfg = config.keys
if not cfg.enabled then
    log.info("key_app", "按键功能已关闭")
    return
end

local TAG = "key_app"

-- 上拉参考电压（与 main.lua 一致，重复 setup 幂等）
gpio.setup(cfg.vref_gpio, 1)

-- ==================== SOS：来电接听 / 空闲呼出 ====================
local function on_sos_pressed()
    log.info(TAG, "SOS 按下", "目标", config.dial_number)
    sys.publish("SIP_APP_MAIN_PRIMARY_REQ")
end

gpio.setup(cfg.sos_gpio, on_sos_pressed, gpio.PULLUP, gpio.FALLING)
gpio.debounce(cfg.sos_gpio, cfg.debounce_ms, 1)

-- ==================== UP：短按播留言 / 长按挂断 ====================
local long_timer = nil    -- 长按判定定时器句柄
local long_fired = false  -- 本次按压是否已触发过长按

local function on_up_short()
    log.info(TAG, "UP 短按", "播放留言")
    sys.publish("MSG_PLAY_REQ")
end

local function on_up_long()
    long_fired = true
    log.info(TAG, "UP 长按", "动作", cfg.long_press_action)
    if cfg.long_press_action == "hangup" then
        sys.publish("SIP_APP_MAIN_HANGUP_REQ", "UP_LONG")
    else
        -- 默认 dial：与 SOS 同目标，向 config.dial_number（IMEI+1）呼出
        sys.publish("SIP_APP_MAIN_DIAL_REQ", config.dial_number)
    end
end

-- UP 用双边沿：按下(level 0)起判定定时器，松开(level 1)结算
local function on_up_edge()
    local level = gpio.get(cfg.up_gpio)
    if level == 0 then
        long_fired = false
        if long_timer then sys.timerStop(long_timer) end
        long_timer = sys.timerStart(function()
            long_timer = nil
            -- 到点时再确认一次电平仍为按下，防抖动误判
            if gpio.get(cfg.up_gpio) == 0 then
                on_up_long()
            end
        end, cfg.long_press_ms)
    else
        if long_timer then
            sys.timerStop(long_timer)
            long_timer = nil
        end
        if not long_fired then
            on_up_short()
        end
    end
end

gpio.setup(cfg.up_gpio, on_up_edge, gpio.PULLUP, gpio.BOTH)
gpio.debounce(cfg.up_gpio, cfg.debounce_ms, 1)

log.info(TAG, "按键已就绪",
    "SOS=GPIO" .. cfg.sos_gpio,
    "UP=GPIO" .. cfg.up_gpio,
    "长按阈值=" .. cfg.long_press_ms .. "ms",
    "长按动作=" .. tostring(cfg.long_press_action))
