
--- 模块功能：rsa示例
-- @module rsa
-- @author wendal
-- @release 2022.11.03

--[[
提醒: 本demo需要用到公钥和私钥, demo目录中的公钥私钥文件是演示用的, 实际使用请自行生成

生成公钥私钥, 可使用openssl命令, 或者找个网页生成. 2048 是RSA位数, 最高支持4096,但不推荐,因为很慢.

openssl genrsa -out privkey.pem 2048
openssl rsa -in privkey.pem -pubout -out public.pem


-- 下载脚本和资源到设备时, 务必加上本目录下的两个 pem 文件, 否则本demo无法运行.
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rsademo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 因为这是通用demo, air101/air103跑满速才不至于太慢-_-
if rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103" or rtos.bsp() == "AIR601"  then
    if mcu then
        mcu.setClk(240)
    end
end

sys.taskInit(function()
    sys.wait(100)
    local data = io.readFile("/luadb/fota_script.bin")
    local script_data = data:sub(256 + 1)
    log.info("数据大小", #script_data)
    local tmp = miniz.uncompress(script_data, 0)
    log.info("能成功不", tmp, script_data:toHex())
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
