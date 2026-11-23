-- EX2 侧 J15 网口由伴随脚本管理；主控只显示实况和请求诊断。
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
    if ok then
        ok, data, err = resources.await_request(peer.eth_diag, peer.ETH_DIAG_TIMEOUT + 1000)
    end
    self.pending = false
    self.last_error = peer.error_text(err)
    if not ok then return false, self.last_error end
    local diag = data and data.eth and data.eth.diag
    if not diag or diag.ok ~= true or diag.code ~= 200 or diag.bytes ~= 2048 then
        self.last_error = "J15 诊断应答不符，请核对 EX2 配套厂测固件"
        return false, self.last_error
    end
    return true, string.format("J15 HTTP %d，收到 %d 字节", diag.code, diag.bytes)
end
function M.init(params)
    if type(params) ~= "table" or not params.id then return false, "缺少 EX2 外设配置" end
    if instances[params.id] then return false, "外设 ID 重复" end
    local h={id=params.id,name=params.name,params=params,pending=false}
    -- factory_new 的行点击会先 OTHER_FUNC_SET(id, true) 再进页：诊断最长 30s，
    -- 不能挂在开关动作里（会堵 handoff FIFO），这里只做占位成功；真正的诊断走
    -- 页面上的「网口诊断」按钮（action 在独立 task 里跑）
    h.start=function() return true, "EX2 网口由伴随脚本管理，诊断请点页面「网口诊断」" end
    h.diagnose = diagnose
    -- 测试页收口会对全部成员调 stop：这里只做诊断，返回成功避免误报
    h.stop=function() return true, "EX2 网口由伴随脚本管理，无需关闭" end
    h.status=function(self)
        local s=peer.status()
        local eth=s.eth or {}
        local ip = eth.ip ~= "" and eth.ip or "--"
        local info=not s.online and peer.offline_hint(s) or
            string.format("J15 | PHY:%s | IP:%s", eth.link and "LINK" or "DOWN", ip)
        if self.pending then info = info .. " | 正在诊断" end
        local err = self.last_error or (s.online and peer.error_text(eth.error))
        if err and err ~= info then info = info .. " | " .. err end
        local diag = s.online and not self.pending and eth.diag
        return {enabled=s.online == true,info=info,eth=eth,diag=diag}
    end
    instances[params.id]=h
    return h
end
function M.get(id) return instances[id] end
return M
