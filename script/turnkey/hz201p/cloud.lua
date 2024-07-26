-- 引入 ThingsCloud 接入库
-- 接入协议参考：ThingsCloud MQTT 接入文档 https://docs.thingscloud.xyz/guide/connect-device/mqtt.html
_G.ThingsCloud = require "ThingsCloud"

-- 进入 ThingsCloud 控制台：https://www.thingscloud.xyz
-- 创建设备，进入设备详情页的【连接】页面，复制设备证书和MQTT接入点地址。请勿泄露你的设备证书。
-- projectKey
local projectKey = "PyvS86eR0D"
-- typeKey
local typeKey = "b0c0eqsmta"
-- MQTT 接入点，只需主机名部分
local host = "sh-1-mqtt.iot-api.com"
-- apiEndpoint
local apiEndpoint = "http://sh-1-api.iot-api.com"



-- 设备成功连接云平台后，触发该函数
local function onConnect(result)
    if result then
        sys.publish("CLOUD_CONNECTED")
        _G_CONNECTED = true
        -- 当设备连接成功后
        -- 例如：切换设备的LED闪烁模式，提示用户设备已正常连接。
    end
end

-- 设备接收到云平台下发的属性时，触发该函数
local function onReceive(response)
    for k, v in pairs(response) do
        log.info("onReceive", k, v)
        if k == "phone" then
            -- 设备接收到云端下发的电话号码，开始拨打电话。
            sys.publish("AUDIO_CMD_RECEIVED","call",v)
        elseif k == "sleepMode" then
            -- 设备收到低功耗要求，更改低功耗模式
            attributes.set("isGPSOn", false)
            attributes.set("isFixed", "定位功能已关闭")
            attributes.set("lat", "无数据")
            attributes.set("lng", "无数据")
            --最后再更改变量
            attributes.set(k, v, true)
            sys.timerStart(sys.publish, 6000, "SLEEP_CMD_RECEIVED", v)
        else
            attributes.set(k, v, true)
        end
    end
end

-- 设备接收到云平台下发的命令时，触发该函数
local function onCommand(cmd)
    if cmd.method == "play" then
        -- 设备接收到云端下发的播放命令，开始播放音乐。
        log.info("play music")
        sys.publish("AUDIO_CMD_RECEIVED","music")
    end
end

-- 设备接入云平台的初始化逻辑，在独立协程中完成
sys.taskInit(function()
    -- 连接云平台，内部支持判断网络可用性、MQTT自动重连
    -- 这里采用了设备一机一密方式，需要为每个设备固件单独写入证书。另外也支持一型一密，相同设备类型下的所有设备使用相同固件。
    ThingsCloud.connect({
        host = host,
        projectKey = projectKey,
        typeKey = typeKey,
        apiEndpoint = apiEndpoint,
    })

    -- 注册各类事件的回调函数，在回调函数中编写所需的硬件端操作逻辑
    ThingsCloud.on("connect", onConnect)
    ThingsCloud.on("attributes_push", onReceive)
    ThingsCloud.on("command_send", onCommand)

    sys.waitUntil("CLOUD_CONNECTED") -- 连接成功
end)
