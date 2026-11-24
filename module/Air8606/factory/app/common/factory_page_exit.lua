-- Stop requests join the peripheral FIFO; navigation commits only after success.
local handoff = require "factory_handoff"
if type(handoff) ~= "table" then return end
local M = {}
function M.new(name, close_window)
    local gate = {active=false, closing=false, waiting=false, running=false, done=false}
    function gate.open(ids)
        gate.ids = ids
        gate.active, gate.closing, gate.waiting, gate.running, gate.done = true, false, false, false, false
        require("other_func_app").allow_page(ids)
    end
    function gate.request(next_page)
        if not gate.active or gate.waiting then return end
        gate.closing, gate.waiting = true, true
        local dialog = airui.msgbox({title="正在关闭", text="正在停止收发、保存文件并释放资源，请稍候...", buttons={"等待"}, on_action=function()end})
        if not gate.running and not gate.done then
            gate.error = nil
            local ok, err = pcall(require("other_func_app").quiesce_page, gate.ids)
            if not ok then gate.error=tostring(err) else
                gate.running=true
                handoff.enqueue(function()
                    local success, reason = pcall(function()
                        for _, id in ipairs(gate.ids) do
                            local stopped, why = require("other_func_app").set_enabled(id, false)
                            assert(stopped, why or "peripheral close failed")
                        end
                    end)
                    gate.running=false
                    gate.done=success
                    gate.error=not success and tostring(reason) or nil
                end)
            end
        end
        sys.taskInit(function()
            local waited=0
            while not gate.done and not gate.error and waited<30000 do
                sys.wait(20); waited=waited+20
            end
            dialog:hide()
            gate.waiting=false
            if not gate.done then
                log.error("factory_handoff",name.."_EXIT_BLOCKED",gate.error or "timeout")
                airui.msgbox({title="未离开页面",text=gate.error or "关闭超时，仍停留本页。请稍后点击返回重试。",buttons={"确定"},on_action=function(self)self:hide()end})
                return
            end
            gate.active=false
            close_window()
            log.info("factory_handoff",name.."_EXIT_DONE")
            if next_page then next_page() end
        end)
    end
    handoff.set_navigation_guard(function(next_page)
        if not gate.active then return false end
        gate.request(next_page); return true
    end, name)
    return gate
end
return M
