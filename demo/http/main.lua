
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require

1. 如需上传大文件,请使用 httpplus 库, 对应demo/httpplus
2. 
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

require "netready"
require "test_get"
require "test_post"
require "test_download"
require "test_fileupload"
require "test_gzip"



sys.taskInit(function()
    sys.wait(100)

    -------------------------------------
    -------- HTTP 演示代码 --------------
    -------------------------------------
    sys.waitUntil("net_ready") -- 等联网

    while 1 do
        -- 演示GET请求
        demo_http_get()
        -- 表单提交
        -- demo_http_post_form()
        -- POST一个json字符串
        -- demo_http_post_json()
        -- 上传文件, mulitform形式
        -- demo_http_post_file()
        -- 文件下载
        -- demo_http_download()
        -- gzip压缩的响应, 以和风天气为例
        -- demo_http_get_gzip()

        sys.wait(1000)
        -- 打印一下内存状态
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        sys.wait(600000)
    end
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
