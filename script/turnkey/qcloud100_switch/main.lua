--[[
这个代码对应公众号文档 https://mp.weixin.qq.com/s/ST_8Uej8R7qLUsikfh3Xtw

针对的硬件是 ESP32系列
]]

PROJECT = "qcloud100"
VERSION = "1.0.0"

--测试支持硬件：ESP32C3/Air105/Air780E

local sys = require "sys"
require("sysplus")

--[[
使用指南
1. 登录腾讯云 https://cloud.tencent.com/ 扫码登录
2. 访问物联网平台 https://console.cloud.tencent.com/iotexplorer
3. 进入公共实例, 如果没有就开通
4. 如果没有项目, 点"新建项目", 名字随意, 例如 luatos
5. 这时,新项目就好出现在列表里, 点击进去
6. 接下来, 点"新建产品", 产品名称随意(例如abc), 品类选自定义品类, 通信方式选4G或者Wifi,认证方式选择密钥认证,数据协议选物模型
7. 左侧菜单, 选"设备管理", "添加设备", 产品选刚刚建好的, 输入一个英文的设备名称, 例如 abcdf, 确定后新设备出现在列表里
8. 点击该设备的"查看", 就能看到详情的信息, 逐个填好
9. 如果是wifi设备, 在当前文件搜索ssid,填好wifi名称和密码
10. 接下来刷机, 不懂刷机就到 wiki.luatos.com 看视频

补充说明, 物模型的设置:
1. 左侧菜单, "产品开发", 然后点之前建好的项目
2. 页面往下拉到底, 选择"新建自定义功能"
3. 为了跑通这个本例子, 需要新建3个属性, 对着界面逐个添加
   |功能类型|功能名称|标识符       |数据类型|取值范围    |
   |属性    |LED灯   |power_switch|布尔型  |不用选     |
   |属性    |电压    |vbat        |整型    | -1, 100000|
   |属性    |温度    |temp        |整型    | -1, 100000|

不要输入"|",那是分割符
]]
product_key = "K7NURKF5J3" -- 产品ID, 一串英文字母,填前面的双引号以内
device_id = "abcdf" -- 设备名称, 一定要改成自己的数据
device_secret = "ChhVXLtSPiTKFzGatB80Jw==" -- 设备密钥


sub_topic = "$thing/down/property/" .. product_key .. "/".. device_id
pub_topic = "$thing/up/property/" .. product_key .. "/".. device_id

adc.open(adc.CH_VBAT)
adc.open(adc.CH_CPU)

function on_btn()
    log.info("btn", "按键触发")
    -- 按一次, 上报一次电压值
    -- 格式参考 https://cloud.tencent.com/document/product/1081/34916
    if mqttc and mqttc:ready() then
        
        local data = {
            method = "report",
            clientToken = "123",
            params = {
                vbat = adc.get(adc.CH_VBAT), -- 读取电压值
                temp = adc.get(adc.CH_CPU)
                -- 如果新建更多物模型的属性, 这里可以继续填,注意格式,尤其是逗号
            }
        }
        local jdata = (json.encode(data))
        log.info("准备上传数据", jdata)
        -- 可以直接调用mqttc对象进行上报
        -- mqttc:publish(pub_topic, (json.encode(data)), 1)
        -- 也可以通过消息机制,传递到sys.waitUntil("mqtt_pub", 30000)语句进行间接上报
        sys.publish("mqtt_pub", pub_topic, jdata, 1)
    end
end

sys.taskInit(function()
    -- 统一联网函数
    if wlan and wlan.connect then -- ESP32系列, C3/S3都可以
        if rtos.bsp():startsWith("ESP32") then
            LED = gpio.setup(12, 0, gpio.PULLUP) -- 控制的灯对应的GPIO号
            gpio.debounce(9, 100, 1)
            BTN = gpio.setup(9, on_btn, gpio.PULLUP, gpio.FALLING) -- BOOT按键当按钮用
        else
            -- air101/air103,内测用
            LED = gpio.setup(pin.PB09, 0, gpio.PULLUP) -- 控制的灯对应的GPIO号
            gpio.debounce(pin.PA0, 100, 1)
            BTN = gpio.setup(pin.PA0, on_btn, gpio.PULLUP, gpio.FALLING) -- BOOT按键当按钮用
        end
        wlan.init()
        --
        -- ESP32系列, 这里要填wifi的名称和密码. 只支持2.4G频段
        --
        local ssid, password = "uiot", "12345678"
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
    elseif rtos.bsp() == "AIR105" then -- Air105走网卡,W5500
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        gpio.debounce(pin.PA10, 100, 1)
        BTN = gpio.setup(pin.PA10, on_btn, gpio.PULLUP, gpio.FALLING) -- BOOT按键当按钮用
        sys.wait(1000)
    elseif rtos.bsp() == "EC618" then -- Air780E,走4G一堆网络
        -- mobile.simid(2) -- 自动选卡, 如果不清楚在哪个卡槽,就取消注释
        LED = gpio.setup(27, 0, gpio.PULLUP)
        gpio.debounce(0, 100, 1)
        BTN = gpio.setup(0, on_btn, gpio.PULLUP, gpio.FALLING) -- BOOT按键当按钮用
    else
        while 1 do 
            sys.wait(1000)
            log.info("bsp", "未支持的模块", rtos.bsp())
        end
    end
    log.info("等待联网")
    local result, data = sys.waitUntil("IP_READY")
    log.info("wlan", "IP_READY", result, data)
    log.info("联网成功")
    sys.publish("net_ready")
end)

sys.taskInit(function()
    sys.waitUntil("net_ready")
    -- 往下就是连接到腾讯云了

    local client_id, user_name, password = iotauth.qcloud(product_key, device_id, device_secret, "sha1")
    log.info("mqtt参数", client_id, user_name, password)

    -- MQTT参数准备好了,开始连接,并监听数据下发
    mqttc = mqtt.create(nil, product_key .. ".iotcloud.tencentdevices.com", 1883)
    mqttc:auth(client_id, user_name, password)
    mqttc:keepalive(240) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制
    mqttc:on(
        function(mqtt_client, event, data, payload)
            if event == "conack"then
                -- 连上了,鉴权也ok
                sys.publish("mqtt_conack")
                log.info("mqtt", "mqtt已连接")
                mqtt_client:subscribe(sub_topic)
            elseif event == "recv" then
                log.info("mqtt", "收到消息", data, payload)
                local json = json.decode(payload)
                if json.method == "control" then
                    if json.params.power_switch == 1 then
                        LED(1)
                    elseif json.params.power_switch == 0 then
                        LED(0)
                    end
                end
            elseif event == "sent"then
                log.info("mqtt", "sent", "pkgid", data)
            end
        end
    )
    mqttc:connect()
    --sys.wait(1000)
    sys.waitUntil("mqtt_conack")
    while true do
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)    
        if ret then
            if topic == "close" then
                break
            end
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
