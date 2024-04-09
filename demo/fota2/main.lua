
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fotademo"
VERSION = "1.0.0"

--[[
本demo 适用于 任何支持 fota 功能的模块, 包括:
1. Cat.1模块, 如: Air700E/Air600E/Air780E/Air780EP/Air780EPV
2. wifi模块, 如: ESP32C3/ESP32S3/Air601
3. 外挂以太网的模块, 例如 Air105 + W5500
]]

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "123" -- 到 iot.openluat.com 创建项目,获取正确的项目id

sys = require "sys"
libfota2 = require "libfota2"


-- 统一联网函数, 可自行删减
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持, 要根据实际情况修改ssid和password!!
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- EC618系列, 如Air780E/Air600E/Air700E
        -- mobile.simid(2) -- 自动切换SIM卡, 按需启用
        -- 模块默认会自动联网, 无需额外的操作
    elseif w5500 then
        -- w5500 以太网
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
    elseif socket then
        -- 适配了socket库也OK, 就当1秒联网吧
        sys.timerStart(sys.publish, 1000, "IP_READY")
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

-- 循环打印版本号, 方便看版本号变化, 非必须
sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("fota", "version", VERSION)
    end
end)

-- 升级结果的回调函数
local function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

-- 使用合宙iot平台进行升级, 支持自定义参数, 也可以不配置
local ota_opts = {
    -- 合宙IOT平台的默认升级URL, 不填就是这个默认值
    -- 如果是自建的OTA服务器, 则需要填写正确的URL, 例如 http://192.168.1.5:8000/update
    -- 如果自建OTA服务器,且url包含全部参数,不需要额外添加参数, 请在url前面添加 ### 
    -- url="http://iot.openluat.com/api/site/firmware_upgrade",
    -- 请求的版本号, 合宙IOT有一套版本号体系,不传就是合宙规则, 自建服务器的话当然是自行约定版本号了
    -- version=_G.VERSION,
    -- 其他更多参数, 请查阅libfota2的文档 https://wiki.luatos.com/api/libs/libfota2.html
}
sys.taskInit(function()
    -- 这个判断是提醒要设置PRODUCT_KEY的,实际生产请删除
    if "123" == _G.PRODUCT_KEY and not ota_opts.url then
        while 1 do
            sys.wait(1000)
            log.info("fota", "请修改正确的PRODUCT_KEY")
        end
    end
    -- 等待网络就行后开始检查升级
    sys.waitUntil("net_ready")
    sys.wait(500)
    libfota2.request(fota_cb, ota_opts)
    --演示按键触发升级, 这里假定使用GPIO0进行触发
    --sys.wait(1000)
    --gpio.debounce(0, 3000, 1)
    --gpio.setup(0, function()
    --     libfota2.request(fota_cb, ota_opts)
    --end, gpio.PULLUP)
end)
-- 演示定时自动升级, 每隔4小时自动检查一次
sys.timerLoopStart(libfota2.request, 4*3600000, fota_cb, ota_opts)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
