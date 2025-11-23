
--- 模块功能：rsa示例
-- @module rsa
-- @author wendal
-- @release 2022.11.03


-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rsademo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    local gs = zbuff.create(64 *2, 0x30)
    local gs2 = zbuff.create(64 *2, 0x30)

    gs[0] = 0x31
    gs2:copy(12, gs, 0, 64)
    log.info("main", gs2:toStr())
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
