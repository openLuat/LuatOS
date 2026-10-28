--[[
@module  incoming_answer
@summary 来电接听策略：按来电快照配置，支持延迟自动接听，状态变化即失效
@version 1.0
@date    2026.10.27
@author  王世豪
@usage
- new() 创建策略对象
- start(config,callback) 依据 config.auto_answer / config.delay_auto_answer 启动定时
- cancel()/valid(token) 用 epoch 令牌失效旧定时器与排队动作
每次来电快照配置；auto_answer=false 时只振铃，需按键接听。
]]
-- Snapshot answer settings per incoming call; invalidate timers and queued actions.
local M={}
function M.new()
    local epoch,timer=0,nil
    local api={}
    function api.cancel()
        epoch=epoch+1
        if timer then sys.timerStop(timer);timer=nil end
    end
    function api.valid(token) return token==epoch end
    function api.start(config,callback)
        api.cancel()
        local token=epoch
        if not config.auto_answer then return end
        local function fire()
            if token~=epoch then return end
            timer=nil
            callback(token)
        end
        if config.delay_auto_answer==0 then fire()
        else timer=sys.timerStart(fire,config.delay_auto_answer*1000) end
    end
    return api
end
return M
