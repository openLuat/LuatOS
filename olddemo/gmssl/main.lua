
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gmssldemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)


sys.taskInit(function()
    -- 测试sm2算法, 含密钥生成
    require "sm2test"
    -- 测试sm3算法
    require "sm3test"
    -- 测试sm4算法
    require "sm4test"
    -- 测试sm2签名和验签
    log.info("????")
    require "sm2sign"

    log.info("=====================================")
    log.info("gmssl", "ALL Done")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
