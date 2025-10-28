--[[
@module  sms_forward
@summary 短信信息转发驱动模块
@version 1.0
@date    2025.9.15
@author  马亚丹
@usage
本文件为来电信息转发驱动模块，核心业务逻辑为：
1、配置飞书，钉钉，企业微信机器人的webhook和secret（加签）。
2、send_sms()，发送短信的功能函数，等待CC_IND消息后，手机卡可以进行收发短信。
3、receive_sms()，接收短信处理的功能函数，收到短信后获取来信号码和短信内容，通过回调函数sms_handler(num, txt)转发到指定的机器人。

直接使用Air8000开发板板硬件测试即可；

本文件没有对外接口，直接在main.lua中require "sms_forward"就可以加载运行；
]]
--------------------------------------------------------------------------------------
-- webhook_feishu和secret_feishu要换成你自己机器人的值
-- webhook_feishu是钉钉分配给机器人的URL
-- secret_feishu是选取 "加签", 自动生成的密钥
-- 下面的给一个测试群发消息, 随时可能关掉, 请换成你自己的值
local webhook_feishu = "https://open.feishu.cn/open-apis/bot/v2/hook/bb089165-4b73-4f80-9ed0-da0c908b44e5"
local secret_feishu = "dp9w8i5IZrrZQpLW0bTcI"

local webhook_dingding =
"https://oapi.dingtalk.com/robot/send?access_token=03f4753ec6aa6f0524fb85907c94b17f3fa0fed3107d4e8f4eee1d4a97855f4d"
local secret_dingding = "SECac5b455d6b567f64073a456e91feec6ad26c0f8f7dcca85dd2ce6c23ea466c52"


local webhook_weixin = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=71017f82-e027-4c5d-a618-eb4ee01750e9"
-- 飞书关于机器人的文档 https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN


--1.功能函数：短信转发到飞书
local function feishu_post_sms(num, rctxt)
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"

    -- LuatOS的时间戳只到秒,飞书也只需要秒
    local timestamp = tostring(os.time())
    local sign = crypto.hmac_sha256("", timestamp .. "\n" .. secret_feishu):fromHex():toBase64()
    log.info("timestamp", timestamp)
    log.info("sign", sign)
    -- 注意, 这里的参数跟钉钉不同, 钉钉有个access_token参数, 飞书没有
    local url = webhook_feishu
    log.info("url", url)
    -- json格式也需要按飞书的来
    local data = { msg_type = "text" }
    data["timestamp"] = timestamp
    data["sign"] = sign
    -- text就是要发送的文本内容, 其他格式按飞书的要求拼接table就好了
    local text = "我的id是" ..
        tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp() .. ",    " .. num .. "发来短信，内容是:" .. rctxt
    data["content"] = { text = text }
    local rbody = (json.encode(data))
    log.info("feishu", rbody)
    local code, headers, body = http.request("POST", url, rheaders, rbody).wait()
    -- 正常会返回 200, {"errcode":0,"errmsg":"ok"}
    -- 其他错误, 一般是密钥错了, 仔细检查吧
    log.info("feishu", code, body)
end

--2.功能函数：短信转发到钉钉
local function dingding_post(num, rctxt)
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    -- LuatOS的时间戳只到秒,但钉钉需要毫秒，补3个零
    local timestamp = tostring(os.time()) .. "000"
    local sign = crypto.hmac_sha256(timestamp .. "\n" .. secret_dingding, secret_dingding):fromHex():toBase64()
        :urlEncode()
    log.info("timestamp", timestamp)
    log.info("sign", sign)
    local url = webhook_dingding .. "&timestamp=" .. timestamp .. "&sign=" .. sign
    log.info("url", url)
    local data = { msgtype = "text" }
    -- content就是要发送的文本内容, 其他格式按钉钉的要求拼接table就好了
    local content = "我的id是" ..
        tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp() .. ",    " .. num .. "发来短信，内容是:" .. rctxt
    data["text"] = { content = content }
    local rbody = (json.encode(data))
    log.info("dingding", rbody)
    local code, headers, body = http.request("POST", url, rheaders, (json.encode(data))).wait()
    -- 正常会返回 200, {"errcode":0,"errmsg":"ok"}
    -- 其他错误, 一般是密钥错了, 仔细检查吧
    log.info("dingding", code, body)
end

--3.功能函数：短信转发到企业微信
local function weixin_post(num, rctxt)
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"

    local timestamp = tostring(os.time()) .. "000"
    log.info("timestamp", timestamp)
    local url = webhook_weixin .. "&timestamp=" .. timestamp
    log.info("url", url)
    local data = { msgtype = "text" }
    -- content就是要发送的文本内容, 其他格式按钉钉的要求拼接table就好了
    local content = "我的id是" ..
        tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp() .. ",    " .. num .. "发来短信，内容是:" .. rctxt
    data["text"] = { content = content }
    local rbody = (json.encode(data))
    log.info("weixin", rbody)
    local code, headers, body = http.request("POST", url, rheaders, (json.encode(data))).wait()
    -- 正常会返回 200, {"errcode":0,"errmsg":"ok"}
    -- 其他错误, 一般是密钥错了, 仔细检查吧
    log.info("weixin", code, body)
end





--4.功能函数：接收短信的回调函数
local function sms_handler(num, txt)
    -- num 给我发短信的手机号码
    -- txt 收到的短信文本内容


    log.info("转发到飞书")
    feishu_post_sms(num, txt)


    
    log.info("转发到钉钉")
    dingding_post(num, txt)

    
    log.info("转发到微信")
    weixin_post(num, txt)
end


--------------------------------------------------------------------
--5. 功能函数：接收短信, 支持多种方式, 选一种就可以了
-----5.1. 设置回调函数
--sms.setNewSmsCb(sms_handler)
-----5.2. 订阅系统消息
--sys.subscribe("SMS_INC", sms_handler)
-- 5.3. 在task里等着
local function receive_sms()
    while 1 do
        local ret, num, txt = sys.waitUntil("SMS_INC", 300000)
        if num then
            log.info("num是", num)
            log.info("收到来自" .. num .. "的短信：" .. txt)

            sms_handler(num, txt)
        end
    end
end

-------------------------------------------------------------------
-- 6.功能函数：发送短信, 直接调用sms.send就行, 是不是task无所谓
local function send_sms()
    --系统消息CC_IND到了才能收发短信
    --按照规范的做法，这里应该等待"SMS_READY"消息，
    --目前内核固件正在开发支持"SMS_READY"消息功能，
    --等开发好了之后，再使用"SMS_READY"消息，
    --当前阶段，先使用"CC_IND"替代
    sys.waitUntil("CC_IND")
    log.info("发送短信前wait CC_IND")
    -- -- 时间同步，以免转发时携带的时间不对
    -- log.info("时间同步", socket.sntp())
    -- sys.waitUntil("NTP_UPDATE", 5000)
    local cont = 1
    while 1 do
        log.info("现在可以收发短信")

        --获取本机号码，如果卡商没写入会返回nil
        log.info("mobile.number(id) = ", mobile.number())
        --获取本机iccid，失败返回nil
        log.info("mobile.iccid(id) = ", mobile.iccid())
        --获取本机simid，失败返回-1
        log.info("mobile.simid(id) = ", mobile.simid())
        --获取本机imsi，失败返回nil
        log.info("mobile.imsi(index) = ", mobile.imsi())

        --给自己发短信
        --local result = sms.send("1593868****", "test")

        --电信卡给10001发送“102”查话费
        local result = sms.send("10001", "102")
        if result then
            --sms.send 的同步结果仅表示任务启动成功，
            --最终发送状态需通过异步事件 "SMS_SEND_RESULT" 获取；
            --目前内核固件正在开发支持"SMS_SEND_RESULT"消息功能
            --当前阶段，sys.waitUntil等不到这个消息，最终5秒超时退出。
            sys.waitUntil("SMS_SEND_RESULT",5*1000)
            log.info("给10001发送查询短信", "这是第" .. cont .. "次发送", " 发送结果：", result)
        else
            log.warn("sms", "短信发送失败")
        end
        cont = cont + 1
        sys.wait(10 * 60 * 1000)
    end
end


--发送短信
sys.taskInit(send_sms)
--接收短信
sys.taskInit(receive_sms)
