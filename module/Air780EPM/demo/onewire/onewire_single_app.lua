--[[
@module  onewire_single_app
@summary OneWire单DS18B20温度传感器应用演示模块（GPIO2默认模式）
@version 1.0.0
@date    2025.11.25
@author  王棚嶙
@usage
本模块演示单DS18B20温度传感器的完整功能：
1. 使用GPIO2默认OneWire功能
2. 硬件通道0模式，无需引脚复用
3. 优化的时序参数和错误处理
4. 连续温度监测
5. 完整的OneWire API接口演示
]]


log.info("onewire_single_app", "单传感器模块版本:1.0.0")

-- 设置所有GPIO引脚电压为3.3V，确保DS18B20传感器正常供电
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)

-- DS18B20命令定义
local CMD_CONVERT_T = 0x44
local CMD_READ_SCRATCHPAD = 0xBE
local CMD_SKIP_ROM = 0xCC
local CMD_READ_ROM = 0x33

-- 单传感器应用主函数
local function single_sensor_app_main()
    log.info("onewire_single_app", "启动单传感器应用")
    
    -- 初始化OneWire总线（使用硬件通道0模式）
    log.info("onewire_single_app", "初始化OneWire总线...")
    onewire.init(0)
    onewire.timing(0, false, 0, 500, 500, 15, 240, 70, 1, 15, 10, 2)
    log.info("onewire_single_app", "OneWire总线初始化完成，使用GPIO2默认引脚")
    
    
    
    -- 检测DS18B20设备
    log.info("onewire_single_app", "检测DS18B20设备...")
    
    local succ, rx_data
    local id = zbuff.create(8)
    local crc8c
    
    -- 清空ID缓冲区
    id:set()
    
    -- 读取设备ROM ID（使用手动配置的引脚）
    succ, rx_data = onewire.rx(0, 8, 0x33, id, false, true, true)
    
    local detected = false
    local device_id = nil
    
    if succ then
        -- 检查家族码（DS18B20为0x28）
        if id[0] == 0x28 then
            -- CRC校验
            crc8c = crypto.crc8(id:query(0,7), 0x31, 0, true)
            if crc8c == id[7] then
                log.info("onewire_single_app", "探测到DS18B20", id:query(0, 7):toHex())
                detected = true
                device_id = id
            else
                log.warn("onewire_single_app", "ROM ID CRC校验不对", mcu.x32(crc8c), mcu.x32(id[7]))
            end
        else
            log.warn("onewire_single_app", "ROM ID不正确", mcu.x32(id[0]))
        end
    else
        log.warn("onewire_single_app", "未检测到DS18B20设备，请检查硬件连接")
        log.info("onewire_single_app", "硬件连接提示:")
        log.info("onewire_single_app", "1. DS18B20 DATA引脚 -> GPIO2 (默认OneWire功能)")
        log.info("onewire_single_app", "2. 确保上拉电阻4.7kΩ连接DATA到3.3V")
        log.info("onewire_single_app", "3. 使用硬件通道0模式，无需引脚复用配置")
    end
    
    if not detected then
        log.warn("onewire_single_app", "设备检测失败，任务无法启动")
        log.info("onewire_single_app", "单传感器应用启动完成")
        onewire.deinit(0)
        return
    end
    
    log.info("onewire_single_app", "开始连续温度监测...")
    
    -- 读取DS18B20温度数据（单总线单设备模式）
    -- 与多传感器模式的对比：
    -- - 单传感器：使用SKIP ROM(0xCC)直接通信，无需ROM ID
    -- - 多传感器：使用MATCH ROM(0x55)选择设备，需要目标ROM ID
    -- 
    -- 单设备读取流程：
    -- 1. SKIP ROM：发送0xCC命令，跳过ROM ID识别
    -- 2. 温度转换：发送CONVERT T(0x44)启动温度转换
    -- 3. 读取数据：发送READ SCRATCHPAD(0xBE)读取温度数据
    -- 4. CRC校验：验证数据完整性
    -- 
    -- 优势：通信简单高效，无需设备寻址
    -- 限制：只能用于总线上只有一个设备的场景
    local function read_temperature(dev_id)
        local tbuff = zbuff.create(10)
        local rbuff = zbuff.create(9)
        local succ, crc8c, range, t
        
        -- 发送SKIP ROM命令(0xCC) - 跳过ROM识别，直接与设备通信
        -- 工作原理：所有设备都会响应SKIP ROM命令，无需发送64位ROM ID
        -- 适用场景：总线上只有一个设备，无需设备寻址和选择
        -- 优势：通信效率高，无需传输ROM ID，简化通信流程
        -- 风险：如果总线上有多个设备，所有设备会同时响应，造成冲突
        tbuff:write(0xcc)
        
        -- 发送温度转换命令
        tbuff[tbuff:used() - 1] = 0x44
        succ = onewire.tx(0, tbuff, false, true, true)
        if not succ then
            log.warn("onewire_single_app", "发送温度转换命令失败")
            return nil
        end
        
        -- 等待转换完成（使用位检测）
        local conversion_complete = false
        local max_wait = 100
        local wait_count = 0
        
        while wait_count < max_wait do
            succ = onewire.reset(0, true)
            if not succ then
                log.warn("onewire_single_app", "等待转换完成时设备未响应")
                return nil
            end
            if onewire.bit(0) > 0 then
                log.info("onewire_single_app", "温度转换完成")
                conversion_complete = true
                break
            end
            sys.wait(10)
            wait_count = wait_count + 1
        end
        
        if not conversion_complete then
            log.warn("onewire_single_app", "温度转换超时")
            return nil
        end
        
        -- 读取温度数据
        tbuff[tbuff:used() - 1] = 0xBE
        succ = onewire.tx(0, tbuff, false, true, true)
        if not succ then
            log.warn("onewire_single_app", "发送读取命令失败")
            return nil
        end
        
        succ, rx_data = onewire.rx(0, 9, nil, rbuff, false, false, false)
        if not succ or rbuff:used() ~= 9 then
            log.warn("onewire_single_app", "温度数据读取失败")
            return nil
        end
        
        -- CRC校验
        crc8c = crypto.crc8(rbuff:toStr(0,8), 0x31, 0, true)
        if crc8c == rbuff[8] then
            range = (rbuff[4] >> 5) & 0x03
            t = rbuff:query(0,2,false,true)
            t = t * (5000 >> range)
            t = t / 10000
            log.info("onewire_single_app", "温度读取成功:", string.format("%.2f°C", t))
            return t
        else
            log.warn("onewire_single_app", "RAM DATA CRC校验不对", mcu.x32(crc8c), mcu.x32(rbuff[8]))
            return nil
        end
    end
    
    -- 主循环 - 连续温度监测
    while true do
        local temperature = read_temperature(device_id)
        
        if temperature then
            -- 简单的温度报警逻辑（示例）
            if temperature > 30 then
                log.warn("onewire_single_app", "温度偏高:", string.format("%.2f°C", temperature))
            elseif temperature < 10 then
                log.warn("onewire_single_app", "温度偏低:", string.format("%.2f°C", temperature))
            else
                log.info("onewire_single_app", "温度正常:", string.format("%.2f°C", temperature))
            end
        else
            log.warn("onewire_single_app", "本次读取失败，继续下一次")
        end
        
        -- 等待下一次读取
        sys.wait(3000)
    end
    
    log.info("onewire_single_app", "单传感器连续读取任务结束")
    log.info("onewire_single_app", "单传感器应用启动完成")
end

log.info("onewire_single_app", "单传感器应用模块加载完成")

-- 启动单传感器应用任务
sys.taskInit(single_sensor_app_main)