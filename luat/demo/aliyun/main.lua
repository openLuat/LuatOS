PROJECT = "aliyundemo"
VERSION = "1.0.0"
local sys = require "sys"

-- 一型一密优先使用fskv存储密钥
if fskv then
    fskv.init()
end

-- 联网函数,非必须
-- 使用一机一密演示，需要打开netready
-- require "netready"

-- 阿里云事件处理函数
require "testEvt"

-- 一机一密的演示
require "testYjym"

-- 一型一密的演示, 一定要修改成自己的信息才能跑通!!!
-- require "testYxym"

-- aliyun+低功耗的演示, 需要开启testYjym或者testYxym
-- require "testPm"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
