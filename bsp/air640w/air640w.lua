--[[
    This file is encode by "GBK"
]]
local sys = require "sys"

log.info("base", "LuatOS@Air640w 刷机工具")

if rtos.bsp() ~= "win32" then
    log.info("base", "当前仅支持win32操作")
    os.exit()
end

local self_conf = {
    basic = {
        COM_PORT = "COM20",
        USER_PATH = "user\\",
        LIB_PATH = "lib\\",
        MAIN_LUA_DEBUG = "false",
        LUA_DEBUG = "false"
    }
}

local function trim5(s)
    return s:match'^%s*(.*%S)' or ''
end

local function read_local_ini()
    local f = io.open("/local.ini")
    if f then
        local key = "basic"
        for line in f:lines() do
            line = trim5(line)
            if #line > 0 then
                if line:byte() == '[' and line:byte(line:len()) then
                    key = line:sub(2, line:len() - 1)
                    if key == "air640w" then key = "basic" end
                    if self_conf[key] == nil then
                        self_conf[key] = {}
                    end
                elseif line:find("=") then
                    local skey = line:sub(1, line:find("=") - 1)
                    local val = line:sub(line:find("=") + 1)
                    if skey and val then
                        self_conf[key][trim5(skey)] = trim5(val)
                    end
                end
            end
        end
        f:close()
    end
    log.info("config", json.encode(self_conf))
end
read_local_ini()

local cmds = {}
cmds["help"] = function(arg)
    log.info("help", "==============================")
    log.info("help", "lfs      打包文件系统")
    log.info("help", "dlrom    下载底层固件")
    log.info("help", "dlfs     下载文件系统")
    log.info("help", "dlfull   下载底层固件及文件系统")
    log.info("help", "==============================")
end

sys.taskInit(function()
    for _, arg in ipairs(win32.args()) do
        if cmds[arg] then
            cmds[arg]()
        elseif cmds["-" .. arg] then
            cmds[arg]()
        elseif arg:byte() == '-' and arg:find("=") then
            local skey = arg:sub(2, arg:find("=") - 1)
            local val = arg:sub(arg:find("=") + 1)
            if skey and val then
                self_conf["basic"][trim5(skey)] = trim5(val)
            end
        end
    end
    os.exit(0)
end)


sys.run()