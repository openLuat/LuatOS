--[[
日志口用户自定义指令 demo
配合 host/test_usercmd.py 上位机脚本使用

协议: PC 通过 0xA5 帧(cmd=SOC_CMD_USER_CMD=19, address=子指令号)下发
      设备回复统一走 log.usercmd_write 文本行: "UC|<子指令>|<状态>|<数据>\n"
子指令: 1=WRITE_BEGIN 2=WRITE_CHUNK 3=WRITE_END 4=READ 5=LS 6=MKDIR 7=RMDIR
]]
local sys = require "sys"

-- 降低日志级别, 减少后台任务日志对日志fifo的占用;
-- UC回复走 log.usercmd_write 原始写出, 不受级别过滤影响
log.setLevel("WARN")

-- 写会话状态
local wf = nil

local function reply(...)
    log.usercmd_write(table.concat({...}, "|") .. "\n")
end

local function to_hex(s)
    return (s:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

local function handle_cmd(cmd, data)
    if cmd == 1 then                 -- WRITE_BEGIN, payload=path
        if wf then wf:close() end
        wf = io.open(data, "w+b")
        reply("UC", 1, wf and "ok" or "err")
    elseif cmd == 2 then             -- WRITE_CHUNK, payload=4B LE offset + data
        if not wf then reply("UC", 2, "err"); return end
        local off = string.unpack("<I4", data)
        wf:seek("set", off)
        wf:write(data:sub(5))
        reply("UC", 2, "ok")
    elseif cmd == 3 then             -- WRITE_END
        local size = -1
        if wf then
            size = wf:seek()
            wf:close()
            wf = nil
        end
        reply("UC", 3, size >= 0 and "ok" or "err", size)
    elseif cmd == 4 then             -- READ, payload=path
        local f = io.open(data, "rb")
        if not f then reply("UC", 4, "err"); return end
        local content = f:read("*a") or ""
        f:close()
        reply("UC", 4, "b", #content)
        for i = 1, #content, 256 do
            reply("UC", 4, "h", to_hex(content:sub(i, i + 255)))
        end
        reply("UC", 4, "e")
    elseif cmd == 5 then             -- LS, payload=path, 返回条目名逗号分隔
        local ret, list = io.lsdir(data, 50, 0)
        if ret and list then
            local names = {}
            for i, e in ipairs(list) do
                names[i] = e.name or tostring(e)
            end
            reply("UC", 5, "ok", table.concat(names, ","))
        else
            reply("UC", 5, "err")
        end
    elseif cmd == 6 then             -- MKDIR, payload=path
        reply("UC", 6, io.mkdir(data) and "ok" or "err")
    elseif cmd == 7 then             -- RMDIR, payload=path
        reply("UC", 7, io.rmdir(data) and "ok" or "err")
    else
        reply("UC", cmd, "unknown")
    end
end

log.set_usercmd_cb(function(cmd, data)
    local ok = pcall(handle_cmd, cmd, data)
    if not ok then
        reply("UC", cmd, "err")
    end
end)

log.info("usercmd", "demo ready")

sys.run()
