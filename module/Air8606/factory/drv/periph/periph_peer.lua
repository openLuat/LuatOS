-- J15 is the EX2 LAN; its address and last lease come from the DHCP server.
local peer = require "air8606_peer"
local resources = require "air8606_resources"
local M = {}
local instances = {}
local function diagnose(self)
    if self.pending then return false, "诊断尚未完成" end
    self.pending = true
    self.last_error = nil
    local ok, data, err = true, nil, nil
    if not peer.status().online then
        ok, data, err = resources.await_request(function(cb) return peer.request("status", nil, cb) end)
    end
    if ok and (peer.status().eth or {}).role ~= "lan" then
        ok, err = false, "请更新 Air780EX2 的 J15 LAN 配套固件"
    end
    if ok then
        ok, data, err = resources.await_request(peer.eth_diag, peer.ETH_DIAG_TIMEOUT + 1000)
    end
    self.pending = false
    self.last_error = peer.error_text(err)
    if not ok then return false, self.last_error end
    local eth = data and data.eth
    if not eth or eth.role ~= "lan" or not eth.dhcp or not eth.dns or not eth.link
        or (eth.upstream ~= "J24" and eth.upstream ~= "4G") then
        self.last_error = "J15 LAN 服务尚未就绪"
        return false, self.last_error
    end
    return true, string.format("J15 网关 %s，上行 %s，最近租约 %s", eth.ip, eth.upstream, eth.client or "暂无")
end
function M.init(params)
    if type(params) ~= "table" or not params.id then return false, "缺少 EX2 外设配置" end
    if instances[params.id] then return false, "外设 ID 重复" end
    local h={id=params.id,name=params.name,params=params,pending=false}
    -- Enter the page immediately; the diagnostic button refreshes the EX2 snapshot.
    h.start=function() return true, "EX2 网口由伴随脚本管理，诊断请点页面「网口诊断」" end
    h.diagnose = diagnose
    -- 测试页收口会对全部成员调 stop：这里只做诊断，返回成功避免误报
    h.stop=function() return true, "EX2 网口由伴随脚本管理，无需关闭" end
    h.status=function(self)
        local s=peer.status()
        local eth=s.eth or {}
        local ip = eth.ip ~= "" and eth.ip or "--"
        local info=not s.online and peer.offline_hint(s) or
            (eth.role ~= "lan" and "请更新 Air780EX2 的 J15 LAN 配套固件" or
            string.format("J15 LAN | %s | 网关 %s", eth.link and "已接线" or "未接线", ip))
        if self.pending then info = info .. " | 正在诊断" end
        local err = self.last_error or (s.online and peer.error_text(eth.error))
        if err and err ~= info then info = info .. " | " .. err end
        return {enabled=s.online == true,info=info,eth=eth,online=s.online}
    end
    instances[params.id]=h
    return h
end
function M.get(id) return instances[id] end
return M
