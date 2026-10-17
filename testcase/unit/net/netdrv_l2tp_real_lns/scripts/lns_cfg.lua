-- 真实 LNS 连接参数
--
-- ⚠️ **账号和口令都不入库**。来源优先级:
--   1. 环境变量 L2TP_HOST / L2TP_USER / L2TP_PASS / L2TP_PEER (PC 模拟器)
--   2. /luadb/lns_secret.txt (PC 与真机都可读; 真机必用)
--      文件格式, 每行一条, # 开头为注释:
--        host=1.2.3.4          # 可选, 不写用下面的默认值
--        user=<账号>
--        pass=<口令>
--        peer=10.0.0.1         # 可选, 隧道内 HTTP 验证目标, 默认用 IPCP 网关
--   3. 都没有 -> M.ready == false, 套件给出明确提示后跳过 (不算 FAIL)
--
-- 这里只保留 LNS 地址作为默认值(联调目标), 账号/口令一律由上面两个来源提供。

local M = {
    host = "58.213.164.4",
    port = 1701,
    user = nil,
    pass = nil,
    -- 隧道内验证目标: LNS 网关, 实测其 80 端口会回 HTTP/1.1 301
    peer = nil,
    ready = false,
    source = "none",
}

local function env(name)
    if os and os.getenv then
        return os.getenv(name)
    end
    return nil
end

local function load_file()
    local txt = io.readFile("/luadb/lns_secret.txt")
    if not txt or #txt == 0 then
        return false
    end
    local got = false
    for line in string.gmatch(txt, "[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if #line > 0 and line:sub(1, 1) ~= "#" then
            local k, v = line:match("^([%w_]+)%s*=%s*(.+)$")
            if k == "host" then M.host = v; got = true end
            if k == "user" then M.user = v; got = true end
            if k == "pass" then M.pass = v; got = true end
            if k == "peer" then M.peer = v; got = true end
        end
    end
    return got
end

local from_file = load_file()

local used_env = false
local function env_override(name, key)
    local v = env(name)
    if v and #v > 0 then
        M[key] = v
        used_env = true
    end
end
env_override("L2TP_HOST", "host")
env_override("L2TP_USER", "user")
env_override("L2TP_PASS", "pass")
env_override("L2TP_PEER", "peer")

if used_env then
    M.source = "env"
elseif from_file then
    M.source = "file"
end
M.ready = (M.pass ~= nil and #M.pass > 0 and M.user ~= nil and #M.user > 0
           and M.host ~= nil and #M.host > 0)

return M
