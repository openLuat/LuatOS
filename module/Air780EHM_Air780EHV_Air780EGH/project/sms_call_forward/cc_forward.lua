--[[
@module  cc_forward
@summary 来电信息转发驱动模块
@version 1.0
@date    2025.9.15
@author  马亚丹
@usage
本文件为来电信息转发驱动模块，核心业务逻辑为：
1、配置飞书，钉钉，企业微信机器人的webhook和secret（加签）。
2、cc_setup()，初始化电话功能，做好接收来电的准备。
3、cc_state(state)，电话状态判断并获取来电号码，来电或者挂断等不同情况做不同处理。
4、cc_forward()，来电号码信息转发到指定机器人

直接使用Air780EHV核心板硬件测试即可；

本文件没有对外接口，直接在main.lua中require "cc_forward"就可以加载运行；
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



-- status，通话状态，string类型，取值如下:

-- "READY":通话准备完成，可以拨打电话或者呼入电话了

-- "INCOMINGCALL"：有电话呼入

-- "CONNECTED"：电话已经接通

-- "DISCONNECTED"：电话被对方挂断

-- "SPEECH_START"：通话开始

-- "MAKE_CALL_OK"：拨打电话请求成功

-- "MAKE_CALL_FAILED"：拨打电话请求失败

-- "ANSWER_CALL_DONE"：接听电话请求完成

-- "HANGUP_CALL_DONE"：挂断电话请求完成

-- "PLAY"：开始有音频输出

local cnt = 0
local phone_num = nil
local multimedia_id = 0 -- 音频通道 0




--1.功能函数：来电转发到飞书
local function feishu_post_cc(num)
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
    local text = "我的id是" .. tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp() .. ",    " .. num .. "来电"
    data["content"] = { text = text }
    local rbody = (json.encode(data))
    log.info("feishu", rbody)
    local code, headers, body = http.request("POST", url, rheaders, rbody).wait()
    -- 正常会返回 200, {"errcode":0,"errmsg":"ok"}
    -- 其他错误, 一般是密钥错了, 仔细检查吧
    log.info("feishu", code, body)
end

--2.功能函数：来电转发到钉钉
local function dingding_post_cc(num)
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
        tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp() .. ",    " .. num .. "来电"
    data["text"] = { content = content }
    local rbody = (json.encode(data))
    log.info("dingding", rbody)
    local code, headers, body = http.request("POST", url, rheaders, (json.encode(data))).wait()
    -- 正常会返回 200, {"errcode":0,"errmsg":"ok"}
    -- 其他错误, 一般是密钥错了, 仔细检查吧
    log.info("dingding", code, body)
end

--3.功能函数：来电转发到企业微信
local function weixin_post_cc(num)
    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    local timestamp = tostring(os.time()) .. "000"

    log.info("timestamp", timestamp)
    local url = webhook_weixin .. "&timestamp=" .. timestamp
    log.info("url", url)
    local data = { msgtype = "text" }
    -- content就是要发送的文本内容, 其他格式按钉钉的要求拼接table就好了
    local content = "我的id是" ..
        tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp() .. ",    " .. num .. "来电"
    data["text"] = { content = content }
    local rbody = (json.encode(data))
    log.info("weixin", rbody)
    local code, headers, body = http.request("POST", url, rheaders, (json.encode(data))).wait()
    -- 正常会返回 200, {"errcode":0,"errmsg":"ok"}
    -- 其他错误, 一般是密钥错了, 仔细检查吧
    log.info("weixin", code, body)
end




--4.初始化cc
local function cc_setup()
    --查看网卡适配器的联网状态是否IP_READY,true表示已经准备好可以联网了,false暂时不可以联网
    while not socket.adapter(socket.dft()) do
        log.warn("cc", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息，设置默认网络适配器编号
    log.info("cc", "recv IP_READY", socket.dft())

    --初始化电话功能
    local cc_int = cc.init(multimedia_id)
    if cc_int then
        return true
    else
        lngo.info("初始化电话功能失败")
    end
end

--5.转发号码
local function cc_forward()
    log.info(" 来电号码转发到飞书")
    feishu_post_cc(phone_num)


    log.info("来电号码转发到钉钉")
    dingding_post_cc(phone_num)


    log.info("来电号码转发到微信")
    weixin_post_cc(phone_num)
end

--6.来电判断
local function cc_state(state)
    if state == "READY" then
        log.info("通话准备完成，可以拨打电话或者呼入电话了")
        --有电话呼入
    elseif state == "INCOMINGCALL" then
        if cnt == 0 then
            log.info("获取最后一次通话的号码")
            phone_num = cc.lastNum()
            log.info("来电号码是：", phone_num)
            if phone_num then
                --转发通知来电
                sys.taskInit(cc_forward)
            end
        end
        cnt = cnt + 1
        if cnt > 3 then
            --自动接听
            --cc.accept(0)

            --响4声以后自动自动挂断
            cc.hangUp()
            cnt = 0
        end
        --电话被对方挂断
    elseif state == "DISCONNECTED" then
        cnt = 0
    end
end

--7.功能测试主函数
local function test_fun()
    if not cc_setup() then
        return
    end
    sys.subscribe("CC_IND", cc_state)
end
sys.taskInit(test_fun)
