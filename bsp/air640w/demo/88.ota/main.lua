
-- 必须有PROJECT和VERSION这两个信息

-- 这个DEMO需要V0003及以上的固件

PROJECT = "otademo"
VERSION = "1.0.0"
PROJECT_KEY = "5aae50f068d9408c92b0fb5911834029"

log.info("version", VERSION) -- 打印版本号,就能知道是否升级成功

local sys = require "sys"

wlan.connect("uiot", "1234567890")

-- 生成OTA的URL
local iot_url = "http://iot.nutz.cn/api/site/firmware_upgrade"
local ota_url = string.format("%s?project_key=%s&imei=%s&firmware_name=%s&version=%s", 
                        iot_url,
                        PROJECT_KEY, 
                        wlan.getMac(),
                        PROJECT .. "_" .. rtos.firmware(),
                        VERSION
                    )

log.info("ota", "url", ota_url)

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            -- 联网后轮询
            http.get(ota_url, {dw="/update.bin"}, function(code,headers,body)
                if code == 200 then
                    -- 当且仅当服务器返回200时,升级文件下载成功
                    log.info("ota", "http ota ok!!", "reboot!!")
                    rtos.reboot()
                else
                    log.info("ota", "resp", code, body)
                end
            end)
            sys.wait(120*1000)
        else
            sys.wait(3000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
