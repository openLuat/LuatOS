
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "feishudemo"
VERSION = "1.0.0"

--[[
本demo是演示飞书的 "自定义机器人"
]]

--------------------------------------------------------------------------------------
-- webhook和secret要换成你自己机器人的值
-- webhook是钉钉分配给机器人的URL
-- secret是选取 "加签", 自动生成的密钥
-- 下面的给一个测试群发消息, 随时可能关掉, 换成你自己的值
local webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/568bfe5a-eda5-4a79-8348-9d21c572cc3b"
local secret = "XRtUovKq24De3zkNS9VHVf"
--------------------------------------------------------------------------------------

-- 飞书关于机器人的文档 https://open.feishu.cn/document/ukTMukTMukTM/ucTM5YjL3ETO24yNxkjN?lang=zh-CN

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")


wdt.init(3000)
sys.timerLoopStart(wdt.feed, 1000)

-- 因为这个demo适合所有能联网的设备
-- 统一联网函数, 按需要增删
sys.taskInit(function()
    if http == nil then
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本固件未包含http库, 请查证")
        end
    end
    local device_id = mcu.unique_id():toHex()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "uiot"
        local password = "12345678"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        device_id = wlan.getMac():toHex()
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2) -- 自动切换SIM卡
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
    elseif w5500 then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
    elseif mqtt then
        -- 适配的mqtt库也OK
        -- 没有其他操作, 单纯给个注释说明
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    log.info("wait IP_READY")
    sys.waitUntil("IP_READY")
    sys.publish("net_ready", device_id)
end)

sys.taskInit(function()
    -- 等待联网
    local _, device_id = sys.waitUntil("net_ready")
    sys.wait(500)
    socket.sntp() -- 如果是联网卡, 这里是需要sntp的, 否则时间不对
    sys.waitUntil("NTP_UPDATE", 5000)

    local rheaders = {}
    rheaders["Content-Type"] = "application/json"
    while 1 do
        -- LuatOS的时间戳只到秒,飞书也只需要秒
        local timestamp = tostring(os.time())
        -- timestamp = "1684673085314"
        local tmp = crypto.hmac_sha256("", timestamp .. "\n" .. secret)
        -- log.info("tmp", "hmac_sha256", tmp)
        -- log.info("tmp", "base64", tmp:fromHex():toBase64())
        local sign = crypto.hmac_sha256("", timestamp .. "\n" .. secret):fromHex():toBase64()
        log.info("timestamp", timestamp)
        log.info("sign", sign)
        -- 注意, 这里的参数跟钉钉不同, 钉钉有个access_token参数, 飞书没有
        local url = webhook
        log.info("url", url)
        -- json格式也需要按飞书的来
        local data = {msg_type="text"}
        data["timestamp"] = timestamp
        data["sign"] = sign
        -- text就是要发送的文本内容, 其他格式按飞书的要求拼接table就好了
        local text = "我的id是" .. tostring(device_id) .. "," .. (os.date()) .. "," .. rtos.bsp()
        data["content"] = {text=text}
        local rbody = (json.encode(data))
        log.info("feishu", rbody)
        local code,headers, body = http.request("POST", url, rheaders, rbody).wait()
        -- 正常会返回 200, {"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}
        -- 其他错误, 一般是密钥错了, 仔细检查吧
        log.info("feishu", code, body)
        sys.wait(60000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
