-- Air153D 由 watchdog_app 自动喂狗；本驱动只读状态、提交手动喂狗请求。
-- 状态桥接：factory_new 的 watchdog_app 通过 WATCHDOG_STATUS(enabled, timeout_sec) /
-- WATCHDOG_LAST_FEED(ts) 播报，本驱动订阅缓存；参考库树若设了 _G.air8606_wdt_status
-- 则优先读它（兼容两棵树的状态口径）。
local M = {}
local instances = {}
local cfg = ((_G.project_config or {}).hw or {}).wdt or {}
local state = {
    enabled = false,
    auto_feed_period_s = cfg.auto_feed_period_s or 180,
    timeout_sec = nil,
    last_request = nil,
}
sys.subscribe("WATCHDOG_STATUS", function(enabled, timeout_sec)
    state.enabled = enabled == true
    if timeout_sec then state.timeout_sec = timeout_sec end
end)
sys.subscribe("WATCHDOG_LAST_FEED", function(ts)
    state.last_request = ts
end)
sys.publish("WATCHDOG_GET_STATUS_REQUEST")

local function snapshot()
    local ext = _G.air8606_wdt_status
    if type(ext) == "table" then return ext end
    return state
end

function M.init(params)
    if type(params) ~= "table" or not params.id then return false, "缺少看门狗配置" end
    if instances[params.id] then return false, "外设 ID 重复" end
    local h={id=params.id,name=params.name,params=params}
    h.status=function()
        local st = snapshot()
        return {enabled=st.enabled == true,wdt=st,
            info=string.format("Air153D | %s | 喂狗周期:%ss | STRAP:%s | 复位超时与电压有关",
                st.enabled and "自动喂狗运行" or "自动喂狗未就绪",
                tostring(st.auto_feed_period_s or st.timeout_sec or "--"), tostring(st.strap or "--"))}
    end
    h.start=function(self)
        if self:status().enabled then return true end
        return false, "自动喂狗由 watchdog_app 启动，请检查库与 GPIO1 配置"
    end
    -- factory_new 测试页收口会对全部成员调 stop：外部看门狗不可关闭，返回成功避免误报
    h.stop=function() return true, "外部看门狗由硬件管理，测试页不关闭" end
    h.feed=function(self)
        if not self:status().enabled then return false, "自动喂狗尚未就绪" end
        sys.publish("WATCHDOG_FEED_REQUEST")
        return true, "手动喂狗请求已提交；无芯片 ACK"
    end
    instances[params.id]=h
    return h
end
function M.get(id) return instances[id] end
return M
