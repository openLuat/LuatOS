-- app_main.lua - 应用主模块(Air1601版本)

require "sensor_app"
require "airlink_mobile_info"

local function update_time_task()
    while true do
        local time_str = os.date("%H:%M")
        sys.publish("TIME_UPDATE", time_str)
        sys.wait(1000)
    end
end

local function network_status_task()
    while true do
        local adapter = socket.LWIP_USER0
        if netdrv.ready(adapter) then
            local ip = socket.localIP(adapter)
            log.info("network", "AirLink IP:", ip)
            local csq = 6
            sys.publish("LTE_CSQ_UPDATE", csq)
        end
        sys.wait(5000)
    end
end

sys.taskInit(update_time_task)
sys.taskInit(network_status_task)
