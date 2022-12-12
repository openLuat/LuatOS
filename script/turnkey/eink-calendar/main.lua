PROJECT = "wifidemo"
VERSION = "1.0.0"

--测试支持硬件：ESP32C3
--测试固件版本：LuatOS-SoC_V0003_ESP32C3[_USB].soc

local sys = require "sys"
require("sysplus")


-- 兼容V1001固件的
if http == nil and http2 then
    http = http2
end

--需要自行填写的东西
--wifi信息
local wifiName,wifiPassword = "Xiaomi_AX6000","Air123456"
--地区id，请前往https://api.luatos.org/luatos-calendar/v1/check-city/ 查询自己所在位置的id
local location = "101020100"
--天气接口信息，需要自己申请，具体参数请参考https://api.luatos.org/ 页面上的描述
local appid,appsecret = "27548549","3wdKWuRZ"

local function connectWifi()
    log.info("wlan", "wlan_init:", wlan.init())

    wlan.setMode(wlan.STATION)
    wlan.connect(wifiName,wifiPassword,1)

    -- 等待连上路由,此时还没获取到ip
    result, _ = sys.waitUntil("WLAN_STA_CONNECTED")
    log.info("wlan", "WLAN_STA_CONNECTED", result)
    -- 等到成功获取ip就代表连上局域网了
    result, data = sys.waitUntil("IP_READY")
    log.info("wlan", "IP_READY", result, data)
end

local function requestHttp()
    local code, headers, body = http.request("GET","http://apicn.luatos.org:23328/luatos-calendar/v1?mac=111&battery=10&location="..location.."&appid="..appid.."&appsecret="..appsecret).wait()
    if code == 200 then
        return body
    else
        log.info("http get failed",code, headers, body)
        sys.wait(500)
        return ""
    end
end

function refresh()
    log.info("refresh","start!")
    local data
    for i=1,5 do--重试最多五次
        collectgarbage("collect")
        data = requestHttp()
        collectgarbage("collect")
        if #data > 100 then
            break
        end
        log.info("load fail","retry!")
    end
    if #data < 100 then
        log.info("load fail","exit!")
        return
    end
    collectgarbage("collect")
    eink.model(eink.MODEL_1in54)
    log.info("eink.setup",eink.setup(0, 2,11,10,6,7))
    eink.setWin(200, 200, 2)
    eink.clear(1)
    log.info("eink", "end setup")
    eink.drawXbm(0, 0, 200, 200, data)
    -- 刷屏幕
    eink.show()
    eink.sleep()
    log.info("refresh","done")
end


sys.taskInit(function()
    --先连wifi
    connectWifi()
    while true do
        refresh()
        sys.wait(3600*1000)--一小时刷新一次吧
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
