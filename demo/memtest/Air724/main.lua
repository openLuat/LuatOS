
--[[
    内存连续性测试, 测试字符串最大长度
]]

PROJECT = "memtest"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(3000, pmd.LDO_VLCD)
pmd.ldoset(3000, pmd.LDO_VCAM)
pmd.ldoset(3300, pmd.LDO_VIBR)

sys.taskInit(function()
    sys.wait(10000) -- 延时10秒启动
    --local netled = gpio.setup(1, 0)
    local count = 1
    local longstr = string.rep( "1024", 1024) -- 4kb
    local curstr = longstr
    while 1 do -- 大概500ms增加4kb的长度, 每秒增长8kb
        --netled(1)
        sys.wait(250)
        --netled(0)
        sys.wait(250)
        --curstr = curstr .. longstr
        log.info("luatos", "hi", count, #curstr)
        count = count + 1
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
