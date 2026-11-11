--[[
@module  topbar
@summary 四页共用的顶栏与底部操作条刷新
@version 1.1
@date    2026.11.10
@usage
本文件把顶栏状态胶囊、报警徽标、时钟、导航徽标、启停按钮态集中到一处；
四页各自有一套同名组件，调用时传入当前页 id 即可。
组件访问统一走 ui_util，切页失败时不会因为 nil 把脚本打挂。

对外接口：
1、topbar.refresh(xml, page)
]]

local M = {}

local data_sim = require "data_sim"
local U = require "ui_util"

--[[
状态胶囊用的图与文字；
]]
local function pill_of()
    if data_sim.estop then
        return "pill_estop", "急停停机"
    end
    if not data_sim.running then
        return "pill_stop", "已停止"
    end
    if data_sim.mode == "manual" then
        return "pill_manual", "手动模式"
    end
    return "pill_run", "自动运行"
end

--[[
刷新指定页的顶栏与底部操作条；

@api topbar.refresh(xml, page)
@userdata xml plcui.load 返回的界面对象
@string page 页面 id
@return nil
]]
function M.refresh(xml, page)
    if not xml then return end
    local unack = data_sim.unack_count()

    local pill_src, pill_text = pill_of()
    U.src(xml, page, "pill", pill_src)
    U.set(xml, page, "pill_text", pill_text)

    U.src(xml, page, "bell", unack > 0 and "bell_on" or "bell_off")
    U.set(xml, page, "bell_num", unack > 0 and tostring(unack) or "")
    U.set(xml, page, "nav3_bd", unack > 0 and tostring(unack) or "")

    U.set(xml, page, "clock", os.date("%H:%M:%S"))

    if data_sim.running then
        U.src(xml, page, "btn_run", "btn_run_c")
        U.src(xml, page, "btn_stop", "btn_stop_n")
    else
        U.src(xml, page, "btn_run", "btn_run_n")
        U.src(xml, page, "btn_stop", "btn_stop_c")
    end
end

return M
