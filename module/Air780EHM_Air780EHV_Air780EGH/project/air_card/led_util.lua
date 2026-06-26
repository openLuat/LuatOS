gpio_num = 27
gpio_num1 = 28
local led_util = {}

local last_record_status = 10
local last_device_status = 10
local led1 = ws2812.create(ws2812.GPIO, 1, gpio_num)
ws2812.args(led1, 0, 40, 35, 14, 8)
local led2 = ws2812.create(ws2812.GPIO, 1, gpio_num1)
ws2812.args(led2, 0, 40, 35, 14, 8)

function led_util.led1_red()
    ws2812.set(led1, 0, 0x100000)
    ws2812.send(led1)
    last_device_status = config.device_status_mode.no_network
end
function led_util.led1_green()
    ws2812.set(led1, 0, 0x001000)
    ws2812.send(led1)
    last_device_status = config.device_status_mode.mqtt_online
end
function led_util.led1_blue()
    ws2812.set(led1, 0, 0x000010)
    ws2812.send(led1)
    last_device_status = config.device_status_mode.no_mqtt
end
function led_util.led1_purple()
    ws2812.set(led1, 0, 0x100010)
    ws2812.send(led1)
    last_device_status = config.device_status_mode.ota
end

function led_util.led2_yellow()
    ws2812.set(led2, 0, 0x101000)
    ws2812.send(led2)
    last_record_status = config.record_status_mode.uploading
end
function led_util.led2_green()
    ws2812.set(led2, 0, 0x001000)
    ws2812.send(led2)
    last_record_status = config.record_status_mode.recording
end
function led_util.led2_red()
    ws2812.set(led2, 0, 0x100000)
    ws2812.send(led2)
    last_record_status = config.record_status_mode.record_error
end
function led_util.led2_purple()
    ws2812.set(led2, 0, 0x100010)
    ws2812.send(led2)
    last_record_status = config.record_status_mode.ota
end
function led_util.led2_off()
    ws2812.set(led2, 0, 0x000000)
    ws2812.send(led2)
    last_record_status = config.record_status_mode.no_record
end

function led_util.set_led1()
    if config.device_status == config.device_status_mode.mqtt_online then
        led_util.led1_green()
    elseif config.device_status == config.device_status_mode.no_mqtt then
        led_util.led1_blue()
    elseif config.device_status == config.device_status_mode.no_network then
        led_util.led1_red()
    end
end
-- uploading退出后恢复之前状态 no_record或者recording
function led_util.set_led2()
    if config.upload_status and last_record_status == config.record_status_mode.no_record then
        led_util.led2_yellow()
    elseif config.record_status == config.record_status_mode.no_record then
        led_util.led2_off()
    elseif config.record_status == config.record_status_mode.recording then
        led_util.led2_green()
    elseif config.record_status == config.record_status_mode.record_error then
        led_util.led2_red()
    end
end

local function led1_chack()
    led_util.set_led1()
    while true do
        sys.wait(2000)
        if config.device_status ~= last_device_status and not config.ota_status then
            led_util.set_led1()
            last_device_status = config.device_status
        end
    end
end

sys.taskInit(led1_chack)

local function led2_chack()
    while true do
        sys.wait(2000)
        if gpio_util.get_recording_mode() then
            config.record_status = config.record_status_mode.recording
        else
            config.record_status = config.record_status_mode.no_record
        end
        if config.record_error then
            config.record_status = config.record_status_mode.record_error
        end
        if config.record_status ~= last_record_status and not config.ota_status then
            led_util.set_led2()
            last_record_status = config.record_status
        end
    end
end

sys.taskInit(led2_chack)

return led_util
