
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 暂不支持https请求!!!!!!

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            sys.wait(2000)
            --http.get("http://www.baidu.com/content-search.xml", nil, function(code,headers,data)
            --    log.info("http", code, data)
            --    sys.publish("HTTP_OK")
            --end) 
            -- sys.waitUntil("HTTP_OK", 15000)
            -- 返回当前毫秒数
            --http.get("http://site0.cn/api/httptest/simple/time", {}, function(code,headers,data)
            --    log.info("http", code, data)
            --    sys.publish("HTTP_OK")
            --end)
            -- sys.waitUntil("HTTP_OK", 15000)
             -- 返回当前毫秒数
            http.post("http://site0.cn/api/httptest/simple/date", {body=string.rep("1234567890", 100)}, function(code,headers,data)
                log.info("http", code, data)
                sys.publish("HTTP_OK")
            end)
            sys.waitUntil("HTTP_OK", 15000)

            sys.wait(60000)
        else
            sys.wait(3000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
