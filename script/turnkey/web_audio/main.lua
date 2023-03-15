-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "web_audio"
VERSION = "1.0.0"

--[[
    如果没有外挂spi flash，就选用后缀是不带外挂flash的固件；
    如果外挂了spi flash，就选用后缀是带外挂flash的固件。
    区别：不带外部flash的版本，因为内存空间小，删除了大部分功能，仅供测试web_audio使用
	    带外部flash的版本功能齐全，和官方发布的固件功能相同。
        固件地址：https://gitee.com/openLuat/LuatOS/attach_files/1342571/download
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")
require "audio_play"
-- 根据自己的服务器修改以下参数
local mqtt_host = "lbsmqtt.airm2m.com"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = "audio"
local user_name = "username"
local password = "password"

local mqttc = nil

-- ************************云端音频MQTT 负载消息类型***************************************
-- 0---4字节大端文字长度--文字的gbk编码--1--4字节大端音频url长度--url的gbk编码
-- 0表示后面是普通文字。1表示后面是音频。两种任意组合。长度是后面编码的长度
-- ************************云端音频MQTT 负载消息类型***************************************
-- ************************HTTP         音频下载处理**************************************

--- gb2312编码 转化为 utf8编码
-- @string gb2312s gb2312编码数据
-- @return string data,utf8编码数据
-- @usage local data = common.gb2312ToUtf8(gb2312s)
function gb2312ToUtf8(gb2312s)
    local cd = iconv.open("ucs2", "gb2312")
    local ucs2s = cd:iconv(gb2312s)
    cd = iconv.open("utf8", "ucs2")
    return cd:iconv(ucs2s)
end

sys.subscribe("payload_msg", function()
    sys.taskInit(function()
        local result, data = sys.waitUntil("payload_msg")
        payload_table, payload_table_len = {}, 0
        local pbuff = zbuff.create(10240)
        local plen = pbuff:write(data)
        for i = 0, plen - 1, 1 do
            if pbuff[i] == 0 or pbuff[i] == 1 then
                if pbuff[i + 1] == 0 and pbuff[i + 2] == 0 and pbuff[i + 3] == 0 then
                    log.info("111")
                    payload_table[payload_table_len] = pbuff[i]
                    payload_table_len = payload_table_len + 1
                    payload_table[payload_table_len] = pbuff[i + 4]
                    payload_table_len = payload_table_len + 1
                    local a = pbuff[i + 4]
                    local s = pbuff:toStr(i + 5, a)
                    log.info("s", s)
                    payload_table[payload_table_len] = s
                    log.info("payload_table[payload_table_len]",
                             payload_table[payload_table_len])
                    payload_table_len = payload_table_len + 1
                end
            end
            --log.info("测试", pbuff[i], i)
        end
        log.info("payload_table_len", payload_table_len)
        for i = 0, payload_table_len, 3 do
            if i ~= 0 then sys.waitUntil("audio_end") end
            if payload_table[i] == 0 then -- tts播放
                local ttstext = payload_table[i + 2]
                log.info("音频", gb2312ToUtf8(ttstext))
                sys.publish("TTS_msg", gb2312ToUtf8(ttstext))
            elseif payload_table[i] == 1 then -- 音频文件播放
                local url = tostring(payload_table[i + 2])
                log.info("url", url)
                sys.publish("HTTP_msg", url)
            end

        end
    end)
end)

sys.taskInit(function()
    sys.wait(1000)
    LED = gpio.setup(27, 0, gpio.PULLUP)
    device_id = mobile.imei()
    local result= sys.waitUntil("IP_READY", 30000)
    if not result then
        log.info("网络连接失败")
    end
    mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, ca_file)
    mqttc:auth(client_id, user_name, password) -- client_id必填,其余选填
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        log.info("mqtt", "event", event, mqtt_client, data, payload)
        if event == "conack" then
            sys.publish("mqtt_conack")
            mqtt_client:subscribe("test20220929/" .. device_id)
        elseif event == "recv" then
            log.info("mqtt", "downlink", "topic", data, "payload",
                     payload:toHex())
            sys.publish("payload_msg", payload)
            -- mqttmsg(payload)
        elseif event == "sent" then
            log.info("mqtt", "sent", "pkgid", data)
        -- elseif event == "disconnect" then
        --     -- 非自动重连时,按需重启mqttc
        --     log.info("mqtt链接断开")
        --     -- mqtt_client:connect()
        end
    end)
    mqttc:connect()
    sys.wait(1000)
    local error = mqttc:ready()
    if not error then
        log.info("mqtt 连接失败")
    else
        log.info("mqtt 连接成功")
    end
    sys.waitUntil("mqtt_conack")
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
    end
    mqttc:close()
    mqttc = nil
end)

sys.taskInit(function()
    while 1 do
        -- 最普通的Http GET请求
        local result, data = sys.waitUntil("HTTP_msg")
        if result then
            log.info("data", data)
            local code, headers, body = http.request("GET", data, {}, "",
                                                     {dst = "/audio.mp3"})
                                            .wait()
            log.info("http", code, json.encode(headers or {}))
            if code == 200 then
                sys.wait(1000)
                log.info("fsize", fs.fsize("/audio.mp3"))
                sys.publish("Audio_msg")
            else
                log.info("http下载失败")
            end
        end
    end
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
