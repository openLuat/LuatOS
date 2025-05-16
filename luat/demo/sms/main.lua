-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "smsdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require "sysplus" -- http库需要这个sysplus

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
log.info("main", "sms demo")

-- 辅助发送http请求, 因为http库需要在task里运行
function http_post(url, headers, body)
    sys.taskInit(function()
        local code, headers, body = http.request("POST", url, headers, body).wait()
        log.info("resp", code)
    end)
end

function sms_handler(num, txt)
    -- num 手机号码
    -- txt 文本内容
    log.info("sms", num, txt, txt:toHex())

    -- http演示1, 发json
    local body = json.encode({phone=num, txt=txt})
    local headers = {}
    headers["Content-Type"] = "application/json"
    log.info("json", body)
    http_post("http://www.luatos.com/api/sms/blackhole", headers, body)
    -- http演示2, 发表单的
    headers = {}
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    local body = string.format("phone=%s&txt=%s", num:urlEncode(), txt:urlEncode())
    log.info("params", body)
    http_post("http://www.luatos.com/api/sms/blackhole", headers, body)
    -- http演示3, 不需要headers,直接发
    http_post("http://www.luatos.com/api/sms/blackhole", nil, num .. "," .. txt)
    -- 如需发送到钉钉, 参考 demo/dingding
    -- 如需发送到飞书, 参考 demo/feishu
end

--------------------------------------------------------------------
-- 接收短信, 支持多种方式, 选一种就可以了
-- 1. 设置回调函数
--sms.setNewSmsCb(sms_handler)
-- 2. 订阅系统消息
--sys.subscribe("SMS_INC", sms_handler)
-- 3. 在task里等着
sys.taskInit(function()
    while 1 do
        local ret, num, txt = sys.waitUntil("SMS_INC", 300000)
        if num then
            -- 方案1, 交给自定义函数处理
            sms_handler(num, txt)
            -- 方案2, 因为这里是task内, 可以直接调用http.request
            -- local body = json.encode({phone=num, txt=txt})
            -- local headers = {}
            -- headers["Content-Type"] = "application/json"
            -- log.info("json", body)
            -- local code, headers, body = http.request("POST", "http://www.luatos.com/api/sms/blackhole", headers, body).wait()
            -- log.info("resp", code)
        end
    end
end)

-------------------------------------------------------------------
-- 发送短信, 直接调用sms.send就行, 是不是task无所谓
sys.taskInit(function()
    sys.wait(10000)
    -- 中移动卡查短信
    -- sms.send("+8610086", "301")
    -- 联通卡查话费
    sms.send("10010", "101")
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
