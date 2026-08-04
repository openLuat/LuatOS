--[[
@module  do_app
@summary DO继电器控制管理
@version 2.0
@date    2026.08.04
@author  江访
@usage
GPIO24(DO1) + GPIO25(DO2)，高电平导通，默认关闭（board_init 已初始化）。
- 订阅 DO_SET_REQUEST(ch, state)
]]

local DO1_PIN = 24
local DO2_PIN = 25

--[[
DO控制请求处理：设置指定通道继电器状态

@local
@function on_do_set_request
@param ch number 通道号：1=DO1, 2=DO2
@param state number/boolean 1/true=导通, 0/false=关闭
]]
local function on_do_set_request(ch, state)
    local s = (state == 0 or state == false) and 0 or 1
    if ch == 1 then
        gpio.set(DO1_PIN, s)
        log.info("do_app", "DO1:", s)
    elseif ch == 2 then
        gpio.set(DO2_PIN, s)
        log.info("do_app", "DO2:", s)
    else
        log.warn("do_app", "invalid channel:", ch)
    end
end

sys.subscribe("DO_SET_REQUEST", on_do_set_request)
