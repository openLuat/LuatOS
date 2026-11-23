-- Air510W 由 EX2 供电和接收，主控通过 air8606_peer 请求，收到 ACK 才报告启动。
local peer = require "air8606_peer"
local resources = require "air8606_resources"
local M = {}
local instances = {}
local function control(self, enable)
    if self.pending then return false, "GNSS 命令尚未完成" end
    self.pending = true
    local ok, _, err = resources.await_request(function(cb) return peer.gnss(enable, cb) end)
    self.pending = false
    self.last_error = peer.error_text(err)
    return ok, self.last_error
end
local function status(self)
    local snapshot = peer.status()
    local gnss = snapshot.gnss or {}
    local rmc, gga = gnss.rmc or {}, gnss.gga or {}
    local info
    if not snapshot.online then info = peer.offline_hint(snapshot)
    elseif not gnss.enabled then info = "GNSS 已停止"
    elseif gnss.fix then info = "定位有效"
    elseif (gnss.rx_bytes or 0) == 0 and gnss.last_rx == 0 then info = "UART1 已开启，等待 Air510W 串口数据"
    elseif gnss.last_rx == 0 then info = "UART1 已收数据，等待新的完整 NMEA"
    else info = "已收到 NMEA，等待卫星定位" end
    if snapshot.online and gnss.enabled and gnss.fix then
        info = info .. string.format(" | lat:%s lng:%s sat:%s alt:%s",
            tostring(rmc.lat or "--"), tostring(rmc.lng or "--"),
            tostring(gga.satellites_tracked or "--"), tostring(gga.altitude or "--"))
    end
    if self.pending then info = info .. " | 等待远端确认" end
    if self.last_error and self.last_error ~= info then info = info .. " | " .. self.last_error end
    return {enabled=snapshot.online and gnss.enabled == true,info=info,gnss=gnss,online=snapshot.online}
end
function M.init(params)
    if type(params) ~= "table" or not params.id then return false, "缺少 GNSS 配置" end
    if instances[params.id] then return false, "外设 ID 重复" end
    local h = {id=params.id,name=params.name,params=params,pending=false}
    h.start=function(self) return control(self, true) end
    h.stop=function(self) return control(self, false) end
    h.status=status
    instances[params.id] = h
    return h
end
function M.get(id) return instances[id] end
return M
