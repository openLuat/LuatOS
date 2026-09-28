gpio_util = {}

local adc_pin_0 = 0
adc.setRange(adc.ADC_RANGE_MIN)
--  计算电池电量,1.05-0.85
function gpio_util.get_battery_voltage()
    adc.open(adc_pin_0)
    local voltage = adc.get(adc_pin_0)
    adc.close(adc_pin_0)
    log.info("adc_pin_0", voltage)
    if voltage > 1030 then
        voltage = 1030
    end
    if voltage < 851 then
        return 0
    end
    local battery_level = math.floor((voltage - 850) / 1.8)
    -- 格式化为字符串，保留两位小数
    return battery_level
end

local recording_mode

function gpio_util.get_recording_mode()
    return recording_mode
end
gpio.setup(1, 1)
-- 临时用25
local gpio_pin = 22
gpio.setup(22, nil)

-- 防止开机时已经录音模式但是不触发回调
-- function record_on()
--     recording_mode = true
--     sys.publish("start_record")
--     led_util.led2_check_mode()
-- end
-- function record_off()
--     recording_mode = false
--     sys.publish("stop_record")
--     led_util.led2_check_mode()
-- end

-- 设置录音状态
function gpio_util.record_states(mode)
    recording_mode = mode
    if mode then
        sys.publish("start_record")
    else
        sys.publish("stop_record")
    end
end

local function recording_mode_chack()
    while true do
        sys.wait(500)
        if config.record_ctrl == -1 then -- GPIO控制录音模式
            local mode = (gpio.get(gpio_pin) == 0)
            if recording_mode==nil then -- 首次开机设置录音状态
                gpio_util.record_states(mode)
            elseif recording_mode ~= mode then -- 状态变化时设置录音状态
                gpio_util.record_states(mode)
            end
        else
            local mode = config.record_ctrl == "recording" --远程控制录音模式
            -- log.info("录音模式",mode,"recording_mode",recording_mode)
            if recording_mode==nil then -- 首次开机设置录音状态
                gpio_util.record_states(mode)
            elseif recording_mode ~= mode then -- 状态变化时设置录音状态
                gpio_util.record_states(mode)
            end
        end
    end
end

sys.taskInit(recording_mode_chack)

return gpio_util
