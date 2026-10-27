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
