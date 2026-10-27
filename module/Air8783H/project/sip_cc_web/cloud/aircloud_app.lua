--[[
@module  aircloud_app
@summary PCM 桥接项目的云端业务接入
@usage
在 SIP/CC 模块加载后汇总状态，向云端协议提供空闲判断。
空闲检查涵盖桥接清理、恢复、冷却及双方媒体释放，并用于配置重启和升级确认。
]]

-- Loaded after the original PCM modules; never changes their initialization order.
local settings=require "aircloud_settings"
local sip=require "sip_main"
local cell=require "cc_main"
local bridge=require "bridge"
local function status()
    local st=bridge.get_state()
    st.registered=sip.is_registered();st.connected=st.in_call
    st.cc_dial_error=cell.last_dial_error()
    st.error=st.cc_dial_error and st.cc_dial_error.error or nil
    st.state=st.in_call and "CONNECTED" or (st.waiting and "WAITING" or st.sip_state)
    return st
end
local function idle()
    local st=bridge.get_state()
    if st.waiting then return false,"bridge_waiting" end
    if st.cleanup_pending then return false,"cleanup_pending" end
    if st.recovering then return false,"recovering" end
    if st.cooldown_remaining_ms>0 then return false,"cooldown" end
    if st.sip_state~="sip_idle" then return false,"sip_busy" end
    if st.cc_state~="cc_idle" then return false,"cc_busy" end
    if not sip.is_media_idle() then return false,"sip_media_busy" end
    if not cell.is_media_idle() then return false,"cc_media_busy" end
    return true
end
require("update").init({idle=idle})
local aircloud_protocol = require "aircloud_protocol"
local excloud = require "aircloud_tcp_adapter"
local protocol=aircloud_protocol.new({status=status,idle=idle},excloud)
protocol.start()
return protocol
