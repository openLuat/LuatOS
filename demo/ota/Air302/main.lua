
-- 必须有PROJECT和VERSION这两个信息

-- 这个DEMO需要V0003及以上的固件

PROJECT = "otademo"
VERSION = "1.0.0"
PROJECT_KEY = "01kgGFLlsfAabFuwJosS4surDNWOQCVH"

log.info("version", VERSION) -- 打印版本号,就能知道是否升级成功

local sys = require "sys"

-- 生成OTA的URL
-- local iot_url = "http://iot.nutz.cn/api/site/firmware_upgrade"
local iot_url = "http://iot.openluat.com/api/site/firmware_upgrade"
local ota_url = string.format("%s?project_key=%s&imei=%s&firmware_name=%s&version=%s", 
                        iot_url,
                        PROJECT_KEY, 
                        nbiot.imei(),
                        PROJECT .. "_" .. rtos.firmware(),
                        VERSION
                    )

log.info("ota", "url", ota_url)

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            -- 联网后轮询
            sys.wait(2000)
            http.get(ota_url, {dw="/update.bin"}, function(code,headers,body)
                if code == 200 then
                    -- 当且仅当服务器返回200时,升级文件下载成功
                    log.info("ota", "http ota ok!!", "reboot!!")
                    rtos.reboot()
                else
                    log.info("ota", "resp", code, body)
                end
            end)
            -- sys.wait(60*60*1000) -- 一小时检查一次
            sys.wait(60*1000) -- 一小时检查一次
        else
            sys.wait(3000)
        end
    end
end)

-- 结尾总是这一句哦
sys.run()
