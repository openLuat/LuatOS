--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@usage
本demo演示的功能为：
演示excloud扩展库的使用。
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "excloud_test"
VERSION = "001.000.000"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)



-- 加载fota升级功能模块
require "fota"

-- 加载网络驱动设备功能模块
require "netdrv_device"

local ckecks_functions = require "checks_function"
local httptest = require "http_test"
-- 加载excloud测试模块
require "excloud_test"

excloud_message = {
    device_status =  {   
     module = rtos.bsp(),--模块
      core_version = rtos.version(),
        error_message = {
        last_element = {},
        send_message = "ok"
    }
},
   http_test= {}
          }
skipp_elem = {}
testConfig = {
    httpTest = true,
    jsonTest = true,
    i2cTest = true,
    airui = true
}


function testTask()
    if testConfig.httpTest then
       httptest.run_tests()
    end
    -- 其他测试模块可以根据需要取消注释
    
    log.info("testTask", "所有测试用例执行完毕,发送测试结果")
    -- excloud.send(excloud_message)
end

local function main_test()
    while true do
        sys.waitUntil("counte_test")
        -- 根据跳过的元素配置测试项
        for _, element in ipairs(skipp_elem) do
            -- log.info("跳过测试项:", element)
            if element == "airui" then
                testConfig.airui = false
            elseif element == "json" then
                testConfig.jsonTest = false
            elseif element == "i2c" then
                testConfig.i2cTest = false
            elseif element =="http" then
                testConfig.http =false
            end
        end

        sys.wait(500)
        testTask()

        -- log.info("110",json.encode(excloud_message))
    end
end
sys.taskInit(main_test)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
