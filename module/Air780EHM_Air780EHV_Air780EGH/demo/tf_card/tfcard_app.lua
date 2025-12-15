--[[
@module  onewire_multi_app
@summary OneWire多DS18B20温度传感器应用演示模块（带切换功能）
@version 002.002.000
@date    2025.11.25
@author  王棚嶙嶙
@usage
本模块演示多DS18B20温度传感器的完整功能：
1. 多传感器切换控制
2. 电源管理（GPIO控制）
3. 按键切换传感器
4. 多路温度同时监测
5. 使用引脚复用功能（pins.setup）
]]

log.info("onewire_multi_app", "多传感器模块版本: 002.002.000")

-- 设置所有GPIO引脚电压为3.3V，确保DS18B20传感器正常供电
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)

-- GPIO2和GPIO31控制电源，确保DS18B20供电正常
gpio.setup(2, 1)  -- GPIO2输出高电平
gpio.setup(31, 1) -- GPIO31输出高电平

-- 传感器配置
local sensor_config = {
    {pin = 2,  channel = 0, name = "GPIO2(默认)"},    -- GPIO2使用通道0
    {pin = 54, channel = 3, name = "引脚54(复用)"}    -- 引脚54使用通道3
}

local current_sensor = 1  -- 当前使用的传感器索引

-- DS18B20命令定义
local CMD_CONVERT_T = 0x44     -- 温度转换命令
local CMD_READ_SCRATCHPAD = 0xBE  -- 读取暂存器命令
local CMD_SKIP_ROM = 0xCC      -- 跳过ROM命令

-- 全局状态变量
local task_running = false
local switch_pressed = false

-- CRC8校验函数
local function crc8_check(data)
    if not data or #data == 0 then
        return false
    end
    
    local crc = 0
    for i = 1, #data - 1 do
        crc = crc ~ data:byte(i)
        for j = 1, 8 do
            if crc & 0x01 then
                crc = (crc >> 1) ~ 0x8C
            else
                crc = crc >> 1
            end
        end
    end
    
    return crc == data:byte(#data)
end

-- 计算温度值
local function calculate_temperature(data)
    if not data or #data < 2 then
        log.warn("onewire_multi_app", "温度数据无效或长度不足")
        return nil
    end
    
    local temp_raw = data:byte(1) + (data:byte(2) * 256)
    
    if temp_raw > 32767 then
        temp_raw = temp_raw - 65536
    end
    
    local temperature = temp_raw * 0.0625
    
    if temperature < -55.0 or temperature > 125.0 then
        log.warn("onewire_multi_app", "温度值超出有效范围:", temperature)
        return nil
    end
    
    return temperature
end

-- 电源控制函数
local function power_control(on)
    log.info("onewire_multi_app", "电源控制:", on and "开启" or "关闭")
    if on then
        sys.wait(100)  -- 等待电源稳定
    end
    return true
end

-- 初始化指定传感器
local function init_sensor(sensor_idx)
    local config = sensor_config[sensor_idx]
    
    log.info("onewire_multi_app", "初始化传感器:", config.name, "引脚:", config.pin, "通道:", config.channel)
    
    if config.pin == 54 then
        pins.setup(config.pin, "ONEWIRE")
        log.info("onewire_multi_app", "配置引脚54为ONEWIRE复用功能")
    end
    
    onewire.init(config.channel)
    onewire.timing(config.channel, false, 0, 480, 70, 70, 410, 70, 10, 10, 15, 70)
    
    log.info("onewire_multi_app", "传感器初始化完成:", config.name)
    return config.channel
end

-- 检测DS18B20设备是否存在
local function detect_ds18b20_device(channel)
    local present = onewire.reset(channel, true)
    if present then
        log.info("onewire_multi_app", "通道", channel, "检测到DS18B20设备")
    else
        log.warn("onewire_multi_app", "通道", channel, "未检测到DS18B20设备")
    end
    return present
end

-- 初始化OneWire总线
local function init_onewire_bus(channel)
    log.info("onewire_multi_app", "初始化OneWire总线，通道:", channel)
    onewire.init(channel)
    onewire.timing(channel, false, 0, 480, 70, 70, 410, 70, 10, 10, 15, 70)
    log.info("onewire_multi_app", "OneWire总线初始化完成，通道:", channel)
    return true
end

-- 读取DS18B20温度
local function read_ds18b20_temperature(channel)
    log.info("onewire_multi_app", "读取DS18B20温度，通道:", channel)
    
    local tbuff = zbuff.create(2)
    local rbuff = zbuff.create(9)
    
    local present = onewire.reset(channel, true)
    if not present then
        log.warn("onewire_multi_app", "通道", channel, "设备未响应")
        return nil
    end
    
    tbuff:set(0, CMD_SKIP_ROM)
    tbuff:set(1, CMD_CONVERT_T)
    local succ = onewire.tx(channel, tbuff, 0, 2, false, true, true)
    if not succ then
        log.warn("onewire_multi_app", "通道", channel, "发送温度转换命令失败")
        return nil
    end
    
    log.info("onewire_multi_app", "等待温度转换完成...")
    sys.wait(750)
    
    local succ = onewire.reset(channel, true)
    if not succ then
        log.warn("onewire_multi_app", "通道", channel, "读取时设备未响应")
        return nil
    end
    
    tbuff:set(0, CMD_SKIP_ROM)
    tbuff:set(1, CMD_READ_SCRATCHPAD)
    succ = onewire.tx(channel, tbuff, 0, 2, false, true, true)
    if not succ then
        log.warn("onewire_multi_app", "通道", channel, "发送读取命令失败")
        return nil
    end
    
    rbuff:resize(9)
    local succ, rx_len = onewire.rx(channel, 9, nil, rbuff, 0, false, false, false)
    if not succ or rx_len ~= 9 then
        log.warn("onewire_multi_app", "通道", channel, "温度数据接收失败，长度:", rx_len or 0)
        return nil
    end
    
    local crc8c = crypto.crc8(rbuff:query(0,8), 0x31, 0, true)
    if crc8c == rbuff[8] then
        local temp_low = rbuff[0]
        local temp_high = rbuff[1]
        local temp_raw = temp_low + (temp_high * 256)
        
        if temp_raw > 32767 then
            temp_raw = temp_raw - 65536
        end
        
        local temperature = temp_raw * 0.0625
        
        if temperature >= -55.0 and temperature <= 125.0 then
            log.info("onewire_multi_app", "温度读取成功，通道", channel, ":", string.format("%.2f°C", temperature))
            return temperature
        else
            log.warn("onewire_multi_app", "温度值超出有效范围:", temperature)
            return nil
        end
    else
        log.warn("onewire_multi_app", "CRC校验失败，期望:", string.format("0x%02X", crc8c), 
                 "实际:", string.format("0x%02X", rbuff[8]))
        return nil
    end
end

-- 切换传感器
local function switch_onewire_sensor()
    log.info("onewire_multi_app", "切换传感器...")
    
    local old_config = sensor_config[current_sensor]
    onewire.deinit(old_config.channel)
    
    current_sensor = (current_sensor % #sensor_config) + 1
    local new_config = sensor_config[current_sensor]
    
    local channel = init_sensor(current_sensor)
    
    log.info("onewire_multi_app", "切换到传感器:", new_config.name, "通道:", channel)
    return channel
end

-- 初始化硬件
local function init_hardware()
    log.info("onewire_multi_app", "初始化硬件配置...")
    
    gpio.setup(gpio.PWR_KEY, function()
        switch_pressed = true
        log.info("onewire_multi_app", "切换按键被按下")
    end, gpio.PULLUP, gpio.RISING)
    
    local channel = init_sensor(current_sensor)
    local detected = detect_ds18b20_device(channel)
    
    if not detected then
        log.warn("onewire_multi_app", "第一个传感器未检测到，尝试第二个传感器...")
        current_sensor = 2
        channel = init_sensor(current_sensor)
        detected = detect_ds18b20_device(channel)
    end
    
    log.info("onewire_multi_app", "硬件初始化完成")
    log.info("onewire_multi_app", "当前使用传感器:", sensor_config[current_sensor].name)
    
    return detected
end

-- 演示OneWire初始化功能
local function demonstrate_onewire_init()
    log.info("demo", "=== 1. 多通道onewire.init()演示 ===")
    for i, config in ipairs(sensor_config) do
        log.info("demo", "初始化通道", config.channel, "对应引脚", config.pin, config.name)
        onewire.init(config.channel)
    end
    log.info("demo", "OneWire初始化演示完成")
end

-- 演示时序配置功能
local function demonstrate_onewire_timing()
    log.info("demo", "=== 2. 多通道onewire.timing()演示 ===")
    for i, config in ipairs(sensor_config) do
        log.info("demo", "配置通道", config.channel, "的DS18B20标准时序")
        onewire.timing(config.channel, false, 0, 480, 70, 70, 410, 70, 10, 10, 15, 70)
    end
    log.info("demo", "时序配置演示完成")
end

-- 演示设备检测功能
local function demonstrate_device_detection()
    log.info("demo", "=== 3. 多通道设备检测演示 ===")
    for i, config in ipairs(sensor_config) do
        local present = onewire.reset(config.channel, true)
        log.info("demo", "通道", config.channel, config.name, "检测状态:", present and "检测到设备" or "未检测到设备")
    end
    log.info("demo", "设备检测演示完成")
end

-- 演示电源控制功能
local function demonstrate_power_control()
    log.info("demo", "=== 4. 电源控制演示 ===")
    power_control(true)
    power_control(false)
    log.info("demo", "电源控制演示完成")
end

-- 演示传感器切换功能
local function demonstrate_sensor_switching()
    log.info("demo", "=== 5. 传感器切换功能演示 ===")
    local original_sensor = current_sensor
    
    for i = 1, #sensor_config do
        local channel = switch_onewire_sensor()
        local detected = detect_ds18b20_device(channel)
        log.info("demo", "切换到传感器", current_sensor, "检测状态:", detected and "成功" or "失败")
        sys.wait(500)
    end
    
    current_sensor = original_sensor
    init_sensor(current_sensor)
    log.info("demo", "传感器切换演示完成，恢复原始传感器")
end

-- 演示位操作功能
local function demonstrate_bit_operations()
    log.info("demo", "=== 6. 位操作功能演示 ===")
    for i, config in ipairs(sensor_config) do
        onewire.bit(config.channel, 1)
        log.info("demo", "通道", config.channel, "发送位: 1")
        
        local bit_value = onewire.bit(config.channel)
        log.info("demo", "通道", config.channel, "读取位值:", bit_value)
    end
    log.info("demo", "位操作演示完成")
end

-- 演示调试模式功能
local function demonstrate_debug_mode()
    log.info("demo", "=== 7. 调试模式演示 ===")
    log.info("demo", "调试模式当前状态: 关闭（可通过取消注释开启）")
    -- for i, config in ipairs(sensor_config) do
    --     onewire.debug(config.channel, true)
    --     log.info("demo", "开启通道", config.channel, "的调试模式")
    -- end
    log.info("demo", "调试模式演示完成")
end

-- 演示资源释放功能
local function demonstrate_resource_cleanup()
    log.info("demo", "=== 8. 资源释放演示 ===")
    for i, config in ipairs(sensor_config) do
        onewire.deinit(config.channel)
        log.info("demo", "释放通道", config.channel, "的资源")
    end
    log.info("demo", "资源释放演示完成")
    
    -- 重新初始化所有通道
    for i, config in ipairs(sensor_config) do
        init_sensor(i)
    end
end

-- 演示多传感器OneWire API接口
local function demonstrate_multi_onewire_apis()
    log.info("onewire_multi_app", "开始演示多传感器OneWire API接口...")
    
    demonstrate_onewire_init()
    demonstrate_onewire_timing()
    demonstrate_device_detection()
    demonstrate_power_control()
    demonstrate_sensor_switching()
    demonstrate_bit_operations()
    demonstrate_debug_mode()
    demonstrate_resource_cleanup()
    
    log.info("onewire_multi_app", "多传感器API演示完成")
end

-- 多传感器应用主函数
local function multi_sensor_app_main()
    log.info("onewire_multi_app", "启动多传感器应用")
    
    if not init_hardware() then
        log.error("onewire_multi_app", "所有传感器都未检测到，请检查硬件连接")
        log.warn("onewire_multi_app", "硬件连接提示：")
        log.warn("onewire_multi_app", "1. 传感器1连接GPIO2 (默认OneWire功能)")
        log.warn("onewire_multi_app", "2. 传感器2连接引脚54 (复用为GPIO3/ONEWIRE)")
        log.warn("onewire_multi_app", "3. 确保GPIO31/GPIO2已设置为高电平供电")
        return
    end
    
    task_running = true
    log.info("onewire_multi_app", "开始多传感器连续监测...")
    log.info("onewire_multi_app", "按PWR_KEY按键可切换传感器")
    
    while task_running do
        if switch_pressed then
            switch_pressed = false
            switch_onewire_sensor()
        end
        
        local config = sensor_config[current_sensor]
        local temperature = read_ds18b20_temperature(config.channel)
        
        if temperature then
            log.info("onewire_multi_app", 
                "传感器" .. current_sensor .. "(" .. config.name .. "):", 
                string.format("%.2f°C", temperature))
        else
            log.warn("onewire_multi_app", "传感器" .. current_sensor .. "读取失败")
        end
        
        sys.wait(1000)
    end
    
    for i, config in ipairs(sensor_config) do
        onewire.deinit(config.channel)
    end
    
    log.info("onewire_multi_app", "多传感器应用结束")
end

-- 启动多传感器应用任务
local function start_multi_sensor_app()
    sys.taskInit(function()
        demonstrate_multi_onewire_apis()
        multi_sensor_app_main()
    end)
end

-- 模块初始化函数
local function init_module()
    log.info("onewire_multi_app", "多传感器应用模块初始化")
    start_multi_sensor_app()
end

-- 启动模块
init_module()

log.info("onewire_multi_app", "多传感器应用模块加载完成")