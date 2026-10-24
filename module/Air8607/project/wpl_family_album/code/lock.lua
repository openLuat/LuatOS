--[[
@module  lock
@summary 锁屏密码存取（fskv 优先，fskv 不可用时落到 SD 卡上的 .album_pwd）
@version 1.1
@date    2026.10.22

这台整机的固件没启用 fskv（日志：`fskv 不可用`），所以必须有第二个落点：
写在 SD 卡根目录 `.album_pwd`（4 字节，点开头，相册里看不到）。
app.start 会在显示锁屏前先挂 SD，所以读密码时卡已经就绪。
]]
local conf = require "conf"

local M = {}
local pwd = nil
local fskv_ok = nil
local KEY = "album_pwd"
local PWD_FILE = conf.sd.mount .. "/.album_pwd"

local function ensure()
    if fskv_ok ~= nil then return end
    fskv_ok = false
    if type(fskv) == "table" and fskv.init then
        local ok = pcall(fskv.init)
        if ok then fskv_ok = true end
    end
    if not fskv_ok then
        log.warn("lock", "fskv 不可用，密码改存到 SD 卡 " .. PWD_FILE)
    end
end

local function read_file_pwd()
    local f = io.open(PWD_FILE, "rb")
    if not f then return nil end
    local s = f:read(8)
    f:close()
    if type(s) == "string" and #s == conf.lock.digits and s:match("^%d+$") then
        return s
    end
    return nil
end

local function write_file_pwd(p)
    local f = io.open(PWD_FILE, "wb")
    if not f then return false end
    local ok = f:write(p)
    f:close()
    return ok and true or false
end

--[[当前密码]]
function M.get()
    ensure()
    if pwd then return pwd end
    if fskv_ok then
        local ok, v = pcall(fskv.get, KEY)
        if ok and type(v) == "string" and #v == conf.lock.digits then
            pwd = v
            return pwd
        end
    end
    local fp = read_file_pwd()
    if fp then
        pwd = fp
        return pwd
    end
    pwd = conf.lock.pwd
    return pwd
end

--[[修改密码]]
function M.set(new_pwd)
    ensure()
    pwd = new_pwd
    if fskv_ok then
        local ok, err = pcall(fskv.set, KEY, new_pwd)
        if not ok then log.warn("lock", "密码写入 fskv 失败", tostring(err)) end
    end
    local ok = write_file_pwd(new_pwd)
    if not ok then
        log.warn("lock", "密码写入 SD 失败，重启后会回到默认密码")
    end
    return true
end

function M.check(input)
    return input == M.get()
end

function M.enabled()
    return conf.lock.enabled ~= false
end

return M
