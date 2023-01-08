
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "otademo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local bin_path = "/luadb/"
local bin_name = "update.bin"
local tar_path = "/"

--[[ 
ota流程就是把update.bin放在根目录(esp为"/spiffs/" 其余为"/")，重启后会自动升级.
update.bin制作方法:luatools中点击生成量产文件,将 SOC量产及远程升级文件 目录中的XXX.ota文件更名为update.bin即可
]]

sys.taskInit(function()
    log.info("-----------------old-------------------")
    local update = io.open(bin_path..bin_name, "rb")
    local update_data = update:read("*a")
    -- log.info(bin_name, "bin_data", update_data)

    local bin = io.open(tar_path..bin_name, "wb")
    bin:write(update_data)
    update:close()
    bin:close()

    rtos.reboot()   
    
    -- local bin = io.open(tar_path..bin_name, "rb")
    -- local bin_data = bin:read("*a")
    -- log.info(bin_name, "bin_data", bin_data)
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
