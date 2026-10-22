--[[
@module  wx_call
@summary 微信通话通道状态（顶栏状态显示 + 与业务信令对接的统一入口）
@version 1.0.0
@date    2026.10.21
@usage
  -- 业务层（MQTT / 小程序信令 / 云端通话回调）收到微信侧状态时：
  wx_call.set("ringing", "张三")     -- idle / connecting / ringing / talking
  -- 界面通过消息刷新：
  sys.subscribe("WX_CALL_STATE", function(state, peer) ... end)
]]

local cfg = require "hw_config"

local wx = {
    state = "offline",        -- offline = 通话后端未就绪
    peer  = cfg.call.peer,
}

local NAMES = {
    offline    = "未就绪",
    idle       = "空闲",
    connecting = "连接中",
    ringing    = "来电",
    talking    = "通话中",
}

function wx.name(state)
    return NAMES[state or wx.state] or tostring(state)
end

--- 更新微信通话状态，并广播给界面/业务层
-- @param state string idle / connecting / ringing / talking
-- @param peer string|nil 对端名称
function wx.set(state, peer)
    if peer and #peer > 0 then
        wx.peer = peer
    end
    if wx.state == state then return end
    wx.state = state
    log.info("wx_call", "state ->", state, wx.peer)
    sys.publish("WX_CALL_STATE", state, wx.peer)
end

function wx.get()
    return wx.state, wx.peer
end

return wx
