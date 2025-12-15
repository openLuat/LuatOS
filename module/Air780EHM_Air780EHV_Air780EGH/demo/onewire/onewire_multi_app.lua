--[[
@module  onewire_multi_app
@summary OneWire多DS18B20温度传感器应用演示模块（54和23切换版本）
@version 1.0.0
@date    2025.11.25
@author  王棚嶙
@usage
本模块演示多DS18B20温度传感器的完整功能：
1. 双传感器切换控制（引脚54和23）
2. 电源管理（GPIO控制）
3. 按键切换传感器
4. 双路温度同时监测
5. 使用引脚复用功能（pins.setup）
]]

log.info("onewire_multi_app", "多传感器模块版本: 1.0.0")

-- 设置所有GPIO引脚电压为3.3V，确保DS18B20传感器正常供电
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)

-- 和GPIO31控制传感器电源使能，确保DS18B20供电正常
gpio.setup(31, 1)

-- 硬件配置（双设备模式：支持引脚54和23切换）
local onewire_pin = 54
local switchover_pin = gpio.PWR_KEY

-- DS18B20命令定义
local CMD_CONVERT_T = 0x44
local CMD_READ_SCRATCHPAD = 0xBE
local CMD_READ_ROM = 0x33

-- 全局状态变量
local pwr_key_pressed = false

-- PWR_KEY按键中断处理函数
-- 功能：处理引脚切换按键事件，设置标志位供主循环查询
local function handle_pwr_key_interrupt()
    pwr_key_pressed = true
    log.info("onewire_multi_app", "切换按键被按下")
end

-- 初始化硬件配置
local function init_hardware()
    log.info("onewire_multi_app", "初始化硬件配置...")
    
    -- 配置PWR_KEY按键，使用上升沿触发并添加防抖
    gpio.debounce(switchover_pin, 100)
    gpio.setup(switchover_pin, handle_pwr_key_interrupt, gpio.PULLUP, gpio.RISING)
    
    -- 初始配置当前引脚为ONEWIRE功能
    pins.setup(onewire_pin, "ONEWIRE")
    
    log.info("onewire_multi_app", "硬件初始化完成")
    log.info("onewire_multi_app", "初始引脚: 引脚" .. onewire_pin .. " (ONEWIRE功能)")
    log.info("onewire_multi_app", "切换按键: PWR_KEY")
    log.info("onewire_multi_app", "支持引脚: 54 和 23 循环切换")
    log.info("onewire_multi_app", "电源控制: GPIO31/GPIO2 (已设置为高电平)")
    
    return true
end


-- 时序要求：DS18B20上电后需要稳定时间，100ms延时确保电源稳定
-- 技术背景：DS18B20在电源切换后需要tREC（恢复时间）完成内部初始化
-- 实际测试：无延时可能导致设备检测失败或温度读取异常
-- 建议值：最小50ms，推荐100ms以确保可靠性
local function power_stabilization_delay()
    log.info("onewire_multi_app", "电源稳定延时（确保DS18B20内部电路就绪）")
    sys.wait(100)  -- DS18B20 tREC恢复时间，最小50ms，推荐100ms
end

-- 单总线分时使用引脚切换（同一条总线，分时复用）
-- 核心逻辑：使用GPIO54和GPIO23两个引脚连接同一条OneWire总线，实现分时复用
-- 应用场景：当需要在同一总线上分时访问不同设备时使用
-- 技术原理：通过切换总线连接引脚，实现同一条物理总线的分时使用
-- 切换效果：
-- - GPIO54：当前时间段连接设备A（ROM ID: 28-9F-C4-93-00-00-00-14）
-- - GPIO23：切换到时间段连接设备B（ROM ID: 28-59-F2-53-00-00-00-14）
-- 注意：这不是多总线并行，而是单总线的分时复用策略
local function switch_onewire_pin()
    log.info("onewire_multi_app", "切换OneWire引脚...")
    
    -- 关闭当前OneWire总线
    onewire.deinit(0)
    
    
    -- 分时复用切换逻辑
    -- 技术原理：将当前不使用的引脚配置为GPIO功能并输出高电平
    -- 目的：确保非活动设备处于高阻态，避免干扰当前连接的设备
    -- 电气特性：GPIO设置为开漏输出模式，高电平由上拉电阻提供
    if onewire_pin == 54 then
        -- 从54切换到23
        -- 将PIN54配置为GPIO3功能，不再作为OneWire使用
        log.info("onewire_multi_app", "将PIN54配置为GPIO3", pins.setup(54, "GPIO3"))
        -- 设置GPIO3为高电平输出（开漏模式，高电平由上拉电阻提供）
        log.info("onewire_multi_app", "将GPIO3设置为高电平输出(OneWire总线空闲状态)", gpio.setup(3, 1))
        onewire_pin = 23
        log.info("onewire_multi_app", "切换到引脚23")
    else
        -- 从23切换到54
        -- 将PIN23配置为GPIO2功能，不再作为OneWire使用
        log.info("onewire_multi_app", "将PIN23配置为GPIO2", pins.setup(23, "GPIO2"))
        -- 设置GPIO2为高电平输出（开漏模式，高电平由上拉电阻提供）
        log.info("onewire_multi_app", "将GPIO2设置为高电平输出(OneWire总线空闲状态)", gpio.setup(2, 1))
        onewire_pin = 54
        log.info("onewire_multi_app", "切换到引脚54")
    end
    
    log.info("onewire_multi_app", "当前使用引脚:", onewire_pin)
    
    -- 配置新引脚为ONEWIRE功能
    -- 分时复用原理：将选中的引脚配置为OneWire功能，连接到对应设备
    -- 连接过程：先断开之前的设备连接，再连接新的设备
    -- 电气特性：确保当前连接的设备具有完整的OneWire通信能力
    log.info("onewire_multi_app", "将引脚" .. onewire_pin .. "配置为ONEWIRE功能", pins.setup(onewire_pin, "ONEWIRE"))
    
    log.info("onewire_multi_app", "引脚切换完成，当前使用: 引脚" .. onewire_pin)
end

-- 初始化OneWire总线
local function init_onewire_bus()
    log.info("onewire_multi_app", "初始化OneWire总线，通道: 0")
    
    -- 配置当前引脚
    pins.setup(onewire_pin, "ONEWIRE")
    
    -- 初始化OneWire总线
    onewire.init(0)
    
    -- 配置DS18B20标准时序参数
    onewire.timing(0, false, 0, 500, 500, 15, 240, 70, 1, 15, 10, 2)
    
    log.info("onewire_multi_app", "OneWire总线初始化完成，通道: 0，引脚:" .. onewire_pin)
    
    return true
end

-- 检测DS18B20设备是否存在（分时复用场景）
-- 分时逻辑：在当前连接的引脚上发送复位脉冲，检测该设备响应
-- 单总线场景：只有当前连接的引脚上的设备会响应复位脉冲
-- 返回值：true表示当前引脚连接的设备响应，false表示无设备响应
local function detect_ds18b20_device()
    log.info("onewire_multi_app", "检测DS18B20设备，引脚: " .. onewire_pin)
    
    -- 发送复位脉冲并检测设备
    local present = onewire.reset(0, true)
    
    if present then
        log.info("onewire_multi_app", "检测到DS18B20设备响应")
        return true
    else
        log.warn("onewire_multi_app", "未检测到DS18B20设备响应")
        return false
    end
end

-- 读取DS18B20温度（单总线分时复用）
-- 核心流程：读ROM ID → 选设备 → 温度转换 → 读数据 → CRC校验
local function read_ds18b20_temperature()
    log.info("onewire_multi_app", "开始读取DS18B20温度，引脚: " .. onewire_pin)
    
    local tbuff = zbuff.create(10)
    local succ, crc8c, range, t
    local rbuff = zbuff.create(9)
    
    -- 读取设备ROM ID（每个设备唯一）
    log.info("onewire_multi_app", "读取设备ROM ID（64位唯一标识）")
    
    local id = zbuff.create(8)
    id:set()
    
    succ, rx_data = onewire.rx(0, 8, 0x33, id, false, true, true)
    if not succ then
        log.warn("onewire_multi_app", "读取ROM ID失败")
        return nil
    end
    
    -- 检查设备类型码（DS18B20应为0x28）
    if id[0] ~= 0x28 then
        log.warn("onewire_multi_app", "非DS18B20设备，类型码:", mcu.x32(id[0]))
        return nil
    end
    
    -- CRC校验设备ID
    crc8c = crypto.crc8(id:query(0, 7), 0x31, 0, true)
    if crc8c ~= id[7] then
        log.warn("onewire_multi_app", "ROM ID CRC校验不对", 
                "计算值:", mcu.x32(crc8c), "期望值:", mcu.x32(id[7]))
        log.info("onewire_multi_app", "完整ROM ID:", id:query(0, 7):toHex())
        return nil
    end
    
    log.info("onewire_multi_app", "ROM ID校验成功:", id:query(0, 7):toHex())
    
    -- 通过MATCH ROM选择设备（确保只选中目标设备）
    log.info("onewire_multi_app", "开始温度转换（通过ROM匹配选择设备）")
    
    -- 构建命令缓冲区：MATCH ROM(0x55) + 目标设备ROM ID + 温度转换命令(0x44)
    -- 0x55是MATCH ROM命令，后面必须跟64位目标设备的ROM ID
    tbuff:write(0x55)     -- MATCH ROM命令
    tbuff:copy(nil, id)  -- 复制64位ROM ID（确保选择正确的设备）
    tbuff:write(0xb8)
    tbuff[tbuff:used() - 1] = 0x44  -- CONVERT T温度转换命令
    
    succ = onewire.tx(0, tbuff, false, true, true)
    if not succ then
        log.warn("onewire_multi_app", "发送温度转换命令失败")
        return nil
    end

    -- 第三步：等待转换完成
    log.info("onewire_multi_app", "等待温度转换完成")
    
    -- 等待一段时间让转换完成
    sys.wait(750)
    
    -- 发送复位脉冲检查设备
    succ = onewire.reset(0, true)
    if not succ then
        log.warn("onewire_multi_app", "等待转换完成时设备未响应")
        return nil
    end
    
    -- 检查转换是否完成
    if onewire.bit(0) > 0 then
        log.info("onewire_multi_app", "温度转换完成")
    end
    
    -- 第四步：读取温度数据
    log.info("onewire_multi_app", "读取温度数据")
    
    -- 构建读取命令：匹配ROM(0x55) + ROM ID + 读取暂存器命令(0xBE)
    tbuff[tbuff:used() - 1] = 0xbe
    succ = onewire.tx(0, tbuff, false, true, true)
    if not succ then
        log.warn("onewire_multi_app", "发送读取命令失败")
        return nil
    end
    
    -- 接收9字节温度数据
    succ, rx_data = onewire.rx(0, 9, nil, rbuff, false, false, false)
    if not succ then
        log.warn("onewire_multi_app", "温度数据接收失败")
        return nil
    end
    
    -- 第五步：CRC校验和温度计算
    log.info("onewire_multi_app", "CRC校验和温度计算")
    
    -- CRC校验
    crc8c = crypto.crc8(rbuff:toStr(0, 8), 0x31, 0, true)
    if crc8c == rbuff[8] then
        -- 计算温度值
        range = (rbuff[4] >> 5) & 0x03
        t = rbuff:query(0, 2, false, true)
        t = t * (5000 >> range)
        t = t / 10000
        
        -- 范围检查
        if t >= -55.0 and t <= 125.0 then
            log.info("onewire_multi_app", "温度读取成功:", string.format("%.2f°C", t))
            return t
        else
            log.warn("onewire_multi_app", "温度值超出有效范围:", t)
            return nil
        end
    else
        log.warn("onewire_multi_app", "温度数据CRC校验不对", 
                "计算值:", mcu.x32(crc8c), "期望值:", mcu.x32(rbuff[8]))
        return nil
    end
end

-- 简化版温度读取（用于快速测试）
local function quick_read_ds18b20()
    log.info("onewire_multi_app", "快速读取温度，引脚: " .. onewire_pin)
    
    -- 首先检测设备是否存在
    if not detect_ds18b20_device() then
        return nil
    end
    
    -- 使用完整读取函数
    return read_ds18b20_temperature()
end

-- 单总线分时复用主函数（同一条总线，分时访问不同设备）
local function multi_sensor_app_main()
    log.info("onewire_multi_app", "启动双传感器应用（引脚54和23）")
    
    -- 初始化硬件
    if not init_hardware() then
        log.error("onewire_multi_app", "硬件初始化失败，任务无法启动")
        return
    end
    
    -- 初始化OneWire总线
    init_onewire_bus()
    
    -- 电源稳定延时：确保DS18B20内部电路就绪
    power_stabilization_delay()
    
    -- 检测设备
    local device_present = detect_ds18b20_device()
    
    if not device_present then
        log.error("onewire_multi_app", "未检测到设备响应")
        log.warn("onewire_multi_app", "硬件连接提示：")
        log.warn("onewire_multi_app", "1. 传感器连接引脚54或23")
        log.warn("onewire_multi_app", "2. 确保GPIO31/GPIO2已设置为高电平供电")
        log.warn("onewire_multi_app", "3. 确保4.7kΩ上拉电阻正确安装")
        log.warn("onewire_multi_app", "4. 检查传感器VDD、GND、DQ连接")
        -- 关闭OneWire总线
        onewire.deinit(0)
        return
    end
    
    log.info("onewire_multi_app", "开始双传感器连续监测...")
    log.info("onewire_multi_app", "按PWR_KEY按键可切换引脚(54和23)")
    
  -- 主循环：按键切换设备，分时读取温度
    local read_count = 0
    local success_count = 0
    
    while true do
        read_count = read_count + 1
        
        -- 检查按键状态
        if pwr_key_pressed then
            pwr_key_pressed = false
            switch_onewire_pin()
            
            -- 重新初始化OneWire总线
            init_onewire_bus()
        end
        
        log.info("onewire_multi_app", "第" .. read_count .. "次读取，引脚:" .. onewire_pin)
        
        -- 尝试读取温度
        local temperature = read_ds18b20_temperature()
        
        if temperature then
            success_count = success_count + 1
            log.info("onewire_multi_app", "引脚" .. onewire_pin .. "温度:", 
                    string.format("%.2f°C", temperature), 
                    "成功率:", string.format("%.1f%%", success_count/read_count*100))
            
            -- 简单的温度报警逻辑
            if temperature > 30 then
                log.warn("onewire_multi_app", "温度偏高:", string.format("%.2f°C", temperature))
            elseif temperature < 10 then
                log.warn("onewire_multi_app", "温度偏低:", string.format("%.2f°C", temperature))
            end
        else
            log.warn("onewire_multi_app", "本次读取失败")
            log.info("onewire_multi_app", "成功率:", string.format("%.1f%%", success_count/read_count*100))
        end
        
        -- 等待下一次读取
        sys.wait(2000)
    end
end
log.info("onewire_multi_app", "双传感器应用模块加载完成（54和23切换）")
-- 启动多传感器应用任务
sys.taskInit(multi_sensor_app_main)

