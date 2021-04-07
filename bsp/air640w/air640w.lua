--[[
    This file is encode by "GBK"
]]
local sys = require "sys"

log.info("base", "LuatOS@Air640w 刷机工具")

if rtos.bsp() ~= "win32" then
    log.info("base", "当前仅支持win32操作")
    os.exit()
end

Base_CWD = lfs.currentdir()
tool_debug = false

local self_conf = {
    basic = {
        COM_PORT = "COM20",
        USER_PATH = "user\\",
        LIB_PATH = "lib\\",
        MAIN_LUA_DEBUG = "false",
        LUA_DEBUG = "false",
        TOOLS_PATH = "tools\\"
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

local function lsdir(path, files, shortname)
    local exe = io.popen("dir /b " .. (shortname and " " or " /s ") .. path)
    if exe then
        for line in exe:lines() do
            table.insert(files, line)
        end
        exe:close()
    end
end

local function oscall(cmd, quite, cwd)
    if cwd and Base_CWD then
        lfs.chdir(cwd)
    end
    if tool_debug then
        log.info("cmd", cmd)
    end
    local exe = io.popen(cmd)
    if exe then
        for line in exe:lines() do
            if not quite then
                log.info("cmd", line)
            end
        end
        exe:close()
    end
    if cwd and Base_CWD then
        lfs.chdir(Base_CWD)
    end
end

local function create_tmproot()
    --local tmproot = os.getenv("Temp") .. "\\luatos"
    local tmproot = "tmp\\"
    log.info("tmpdir", tmproot)
    oscall("rmdir /S /Q \"" .. tmproot .. "\"")
    oscall("mkdir \"" .. tmproot .. "\"")
    return tmproot
end

local cmds = {}
cmds["help"] = function(arg)
    log.info("help", "==============================")
    log.info("help", "lfs      打包文件系统")
    log.info("help", "dlrom    下载底层固件")
    log.info("help", "dlfs     下载文件系统")
    log.info("help", "dlfull   下载底层固件及文件系统")
    log.info("help", "==============================")
end

local function build_flashx(rootpath)
    local files = {}
    lsdir(rootpath, files, true)
    local buff = zbuff.create(64*1024)
    -- 头部魔数
    buff:writeI16(0x1234)
    -- 逐个文件写入
    for _, name in ipairs(files) do
        if name ~= "flashx.bin" then
            -- 写入文件名
            buff:writeI16(0x0101)
            buff:writeI16(0x0)
            buff:writeI32(name:len())
            buff:write(name)
            -- 写入文件
            local f = io.open(rootpath .. "\\" .. name, "rb")
            if f == nil then
                log.error("文件读取失败!!!!!!!" .. name)
                os.exit(2)
                return -- impossible
            end
            local data = f:read("*a")
            buff:writeI16(0x0202)
            buff:writeI16(0x0)
            buff:writeI32(data:len())
            buff:write(data)
            f:close()
        end
    end
    local fdata = buff:toStr(0, buff:seek(0, zbuff.SEEK_CUR))
    io.writeFile(rootpath .. "\\flashx.bin", fdata)
    log.info("lfs", "flashx.bin is done", crypto.sha256(fdata))
end

cmds["lfs"] = function()
    -- 首先, 把用户的文件都取一下
    local files = {}
    lsdir(self_conf["basic"]["USER_PATH"] or "user\\", files)
    lsdir(self_conf["basic"]["LIB_PATH"] or "lib\\", files)
    for index, value in ipairs(files) do
        log.info("file", index ,value)
    end
    -- 创建临时目录, 把文件都拷贝过去
    local tmproot = create_tmproot()
    oscall("mkdir \"" .. tmproot .. "\"\\luafile")
    oscall("mkdir \"" .. tmproot .. "\"\\disk")
    for index, value in ipairs(files) do
        log.info("copy", index ,value)
        oscall("copy \"" .. value .. "\" " .. "\"" .. tmproot .. "\\luafile\\")
    end
    -- 对lua文件进行luac编译, 非lua文件就免了
    files = {}
    lsdir(tmproot .. "\\luafile", files, true)

    --local tools_path = self_conf["basic"]["TOOLS_PATH"]
    local luac_exe = self_conf["basic"]["TOOLS_PATH"] .. "luac_536_32bits.exe"
    local main_lua_debug = self_conf["basic"]["MAIN_LUA_DEBUG"] == "true"
    local lua_debug = self_conf["basic"]["LUA_DEBUG"] == "true"
    for _, name in ipairs(files) do
        local srcpath = tmproot .. "\\luafile\\" .. name
        if name:match(".+lua$") then
            local dstpath = tmproot .. "\\disk\\" .. name .. "c"
            local debug = lua_debug
            if name == "main.lua" and main_lua_debug then
                debug = true
            end
            oscall(luac_exe .. (debug and " -o " or " -s -o ") .. dstpath .." "..  srcpath, true)
        else
            local dstpath = tmproot .. "\\disk\\" .. name
            oscall("copy " .. srcpath .. " " .. dstpath)
        end
    end

    -- 文件已经全部都在%Temp%\luatos\disk 里面了

    -- 接下来, 生成flashx.bin
    build_flashx(tmproot .. "\\disk")
    -- 然后拷贝一份, 就是升级文件咯

end

cmds["dlfs"] = function ()
    -- 看看disk目录在不在

    -- 开始发送

    -- TODO 插入晨旭老早以前写的tools.lua, 发送文件到设备去
end

cmds["dlrom"] = function ()
    -- 检查FLS文件是否存在

    -- 通过xmodem协议发送固件
end

cmds["dlfull"] = function ()
    cmds["dlrom"]()
    cmds["dlfs"]()
end

sys.taskInit(function()
    sys.wait(10)
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
