--[[
@module  exs_da267
@summary DA267 三轴加速度传感器扩展库（DA267）
@version 1.1
@date    2026.07.20
@author  王世豪
@usage
本文件为 DA267 三轴加速度传感器的 LuatOS 扩展库，核心功能为：
1、初始化 DA267，配置 I2C 通信参数和测量量程
2、读取加速度原始数据和转换后的重力加速度值（g值）
3、读取计步数并清零计步器
4、配置运动检测中断和阈值
5、启用/禁用计步器功能
6、实现运动状态管理，支持静止/运动状态判断

本文件的对外接口有 15 个：
1、exs_da267.setup(init_cfg)：初始化 DA267
2、exs_da267.get_data()：读取三轴加速度数据（单位：g）
3、exs_da267.get_steps()：读取计步数
4、exs_da267.reset_steps()：清零计步器
5、exs_da267.set_range(range)：设置测量量程
6、exs_da267.set_int_threshold(x, y, z)：设置运动检测中断阈值
7、exs_da267.enable_step_counter(enable)：启用/禁用计步器
8、exs_da267.set_callback(callback)：设置中断回调函数
9、exs_da267.get_chip_id()：获取芯片ID
10、exs_da267.enable_motion(enable)：启用/禁用运动状态管理
11、exs_da267.is_moving()：获取当前运动状态
12、exs_da267.set_motion_params(params)：设置运动状态管理参数
13、exs_da267.get_config()：获取当前配置信息
14、exs_da267.close()：关闭传感器
15、exs_da267.version()：获取版本号

-- 版本更新说明
-- 版本号：202607201700
-- 1、更新时间：2026-07-20 17:00
-- 2、更新内容
--    优化 DA267 运动状态判断机制，去掉运动状态管理中的超时参数

-- 版本号：202607171813700
-- 1、更新时间：2026-07-17 18:13
-- 2、更新内容
--    初版，实现 DA267 传感器驱动所有基础功能
--    支持 I2C 通信接口
--    支持 ±2g/±4g/±8g/±16g 四档量程
--    支持读取三轴加速度数据（单位：g）
--    支持计步器功能，包括读取和清零计步数
--    支持运动状态管理，基于中断历史窗口判断静止/运动状态
--    支持设置运动检测中断阈值
--    支持启用/禁用计步器功能
--    支持获取传感器配置信息
]]

local exs_da267 = {}

-- ==================== 模块常量 ====================

-- 寄存器定义（DA267 数据手册）
local REG_CHIP_ID = 0x01                    -- 芯片ID寄存器（只读，值为0x13表示DA267）
local REG_ACC_X_LSB = 0x02                   -- X轴加速度数据寄存器（LSB，8位），连续读取6字节获取XYZ数据
local REG_STEPS_LSB = 0x0D                   -- 计步数数据寄存器（LSB，8位），连续读取2字节获取完整计步数
local REG_RESOLUTION_RANGE = 0x0F            -- 分辨率和量程配置寄存器
local REG_MODE_ODR = 0x10                    -- 模式和输出数据速率配置寄存器
local REG_MODE_AXIS = 0x11                   -- 模式和轴启用配置寄存器
local REG_INT_SET1 = 0x16                    -- 中断设置1寄存器（配置点击、运动检测中断）
local REG_INT_MAP1 = 0x19                    -- 中断映射1寄存器（将中断源映射到INT1或INT2）
local REG_ACTIVE_DUR = 0x38                  -- 有效运动检测持续时间配置寄存器
local REG_ACTIVE_X_THS = 0x39                -- X轴有效运动检测阈值配置寄存器
local REG_ACTIVE_Y_THS = 0x3A                -- Y轴有效运动检测阈值配置寄存器
local REG_ACTIVE_Z_THS = 0x3B                -- Z轴有效运动检测阈值配置寄存器
local REG_STEP_FILTER = 0x33                 -- 计步器过滤器配置寄存器

-- 量程常量
exs_da267.RANGE_2G = 2
exs_da267.RANGE_4G = 4
exs_da267.RANGE_8G = 8
exs_da267.RANGE_16G = 16

-- ==================== 内部状态 ====================
local ctx = {
    inited = false,
    i2c_id = 1,
    addr = 0x26,
    int_pin = nil,
    range = 2,
    sensitivity = 16384,
    int_callback = nil,
    motion_enable = false,
    motion_state = false,  -- false=静止, true=运动
    motion_window = 8,  -- 历史窗口（秒）
    motion_threshold = 4,  -- 进入运动状态的中断次数
    motion_count = 0,  -- 当前窗口内的中断计数
    motion_timer = nil,  -- 窗口计时定时器
    step_counter_enable = false  -- 是否启用计步器功能
}

--[[
获取库版本信息
@api exs_da267.version()
@return string 库版本号，格式：年月日时分
@usage
log.info("da267", "version:", exs_da267.version())
]]
function exs_da267.version()
    return "202607201700"
end

-- 定时器超时处理函数
local function motion_timeout_handler()
    -- 超时且未达到阈值，判断为静止状态
    if ctx.motion_state then
        ctx.motion_state = false
        log.info("exs_da267", "回到静止状态")
        if ctx.step_counter_enable then
            i2c.send(ctx.i2c_id, ctx.addr, {0x33, 0x25}, 1)
        end
        sys.publish("DA267_MOTION_STATE", false)
    end
    
    ctx.motion_count = 0
    ctx.motion_timer = nil
end

-- 内部状态检查函数
local function motion_check_internal()
    -- 检查是否已经达到运动状态
    if ctx.motion_count >= ctx.motion_threshold then
        -- 达到阈值，立即判断为运动状态
        if not ctx.motion_state then
            ctx.motion_state = true
            log.info("exs_da267", "进入运动状态")
            if ctx.step_counter_enable then
                i2c.send(ctx.i2c_id, ctx.addr, {0x33, 0x80}, 1)
            end
            sys.publish("DA267_MOTION_STATE", true)
        end
        
        -- 重置定时器和计数
        if ctx.motion_timer then
            sys.timerStop(ctx.motion_timer)
        end
        
        ctx.motion_count = 0
        ctx.motion_timer = sys.timerStart(motion_timeout_handler, ctx.motion_window * 1000)
        return
    end
    
    -- 未达到阈值，继续计时
    if not ctx.motion_timer then
        ctx.motion_timer = sys.timerStart(motion_timeout_handler, ctx.motion_window * 1000)
    end
end

-- ==================== 运动状态管理 ====================

-- 运动状态检查函数
local function motion_check()
    if not ctx.motion_enable then
        return
    end
    
    ctx.motion_count = ctx.motion_count + 1
    motion_check_internal()
end


-- 运动状态管理初始化
local function motion_init()
    ctx.motion_count = 0
    ctx.motion_timer = nil
end

-- ==================== 外部 API ====================

--[[
初始化 DA267 传感器
@api exs_da267.setup(param)
@param param table 初始化参数配置表
    i2c_id:number, I2C 总线编号，默认1
    addr:number, I2C 设备地址，默认0x26
    int_pin:number, 中断引脚，默认nil（禁用中断）
    range:number, 测量量程，支持2/4/8/16（±g），默认2，可选
        - 量程决定了加速度测量的范围和灵敏度
        - 量程与灵敏度的关系：
          - RANGE_2G (±2g, 3.91mg/LSB)：微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面
          - RANGE_4G (±4g, 7.81mg/LSB)：运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测
          - RANGE_8G (±8g, 15.63mg/LSB)：跌倒检测，用于人或物体瞬间跌倒时的检测，加速度量程8g；
          - RANGE_16G (±16g, 31.25mg/LSB)：适合高冲击场景（如安全监测、碰撞检测）
    motion_enable:boolean, 是否启用运动状态管理，默认false，可选
        - 启用后会持续监测运动状态
    motion_window:number, 历史窗口（秒），范围：1-60，默认8，可选
        - 用于统计运动状态判断的历史记录窗口
        - 窗口越小，运动状态判断越敏感
        - 窗口越大，运动状态判断越迟钝
    motion_threshold:number, 进入运动状态的中断次数，范围：1-20，默认4，可选
        - 进入运动状态所需的中断次数
        - 中断次数越小，运动状态判断越敏感
        - 中断次数越大，运动状态判断越迟钝
    step_counter_enable:boolean, 是否启用计步器功能，默认false，可选
@return boolean 成功返回true，失败返回false
@usage
local DA267_CONFIG = {
    i2c_id = 1,
    addr = 0x26,
    int_pin = 39,
    range = exs_da267.RANGE_2G,
    motion_enable = true,
    motion_window = 60,
    motion_threshold = 5,
    step_counter_enable = true
}

local setup_ok = exs_da267.setup(DA267_CONFIG)
if setup_ok then
    log.info("da267", "传感器初始化成功")
end

-- 设置中断回调（运行时动态设置）
local function da267_interrupt_callback()
    log.info("da267", "中断触发")
    local data = exs_da267.get_data()
    if data then
        log.debug("da267", string.format("X=%+.3f Y=%+.3f Z=%+.3f", 
            data.x, data.y, data.z))
    end
end

exs_da267.set_callback(da267_interrupt_callback)
]]
function exs_da267.setup(param)
    if type(param) ~= "table" then
        log.error("exs_da267", "参数必须为表")
        return false
    end

    ctx.i2c_id = param.i2c_id or 1
    ctx.addr = param.addr or 0x26
    ctx.int_pin = param.int_pin
    ctx.range = param.range or 2
    ctx.int_callback = nil -- 初始化时不设置中断回调，强制使用 set_callback 接口
    ctx.motion_enable = param.motion_enable or false
    ctx.motion_window = param.motion_window or 8
    ctx.motion_threshold = param.motion_threshold or 4
    ctx.motion_count = 0
    ctx.motion_timer = nil
    ctx.step_counter_enable = param.step_counter_enable or false
    if ctx.range ~= 2 and ctx.range ~= 4 and ctx.range ~= 8 and ctx.range ~= 16 then
        log.error("exs_da267", "无效的量程，支持2/4/8/16")
        return false
    end

    ctx.sensitivity = 32768 / ctx.range

    i2c.close(ctx.i2c_id)
    i2c.setup(ctx.i2c_id, i2c.SLOW)

    i2c.send(ctx.i2c_id, ctx.addr, {0x00, 0x24}, 1)
    sys.wait(5)

    local range_val = 0
    if ctx.range == 4 then range_val = 0x10
    elseif ctx.range == 8 then range_val = 0x20
    elseif ctx.range == 16 then range_val = 0x30
    end
    i2c.send(ctx.i2c_id, ctx.addr, {REG_RESOLUTION_RANGE, range_val}, 1)

    i2c.send(ctx.i2c_id, ctx.addr, {REG_MODE_ODR, 0x07}, 1)
    i2c.send(ctx.i2c_id, ctx.addr, {REG_MODE_AXIS, 0x34}, 1)

    i2c.send(ctx.i2c_id, ctx.addr, {REG_INT_SET1, 0x87}, 1)

    i2c.send(ctx.i2c_id, ctx.addr, {REG_ACTIVE_DUR, 0x03}, 1)
    i2c.send(ctx.i2c_id, ctx.addr, {REG_INT_MAP1, 0x04}, 1)

    i2c.send(ctx.i2c_id, ctx.addr, {REG_MODE_AXIS, 0x30}, 1)

    if ctx.int_pin then
        local function gpio_int_callback()
            if ctx.motion_enable then
                motion_check()
            end
            if ctx.int_callback then
                ctx.int_callback()
            end
        end
        gpio.setup(ctx.int_pin, gpio_int_callback, gpio.PULLUP, gpio.RISING)
    end

    -- 运动状态管理初始化
    if ctx.motion_enable then
        motion_init()
    end

    i2c.send(ctx.i2c_id, ctx.addr, REG_CHIP_ID, 1)
    local data = i2c.recv(ctx.i2c_id, ctx.addr, 1)
    if not data or #data ~= 1 or string.byte(data) ~= 0x13 then
        log.error("exs_da267", "芯片ID校验失败")
        return false
    end

    ctx.inited = true
    log.info("exs_da267", "初始化完成，量程:", ctx.range, "g")
    if ctx.motion_enable then
        log.info("exs_da267", "运动状态管理已启用，窗口:", ctx.motion_window, "秒，阈值:", ctx.motion_threshold, "次")
    end
    if ctx.step_counter_enable then
        -- 设备开机时默认是静止状态，所以需要设置计步器为停止状态
        i2c.send(ctx.i2c_id, ctx.addr, {REG_STEP_FILTER, 0x25}, 1)
        log.info("exs_da267", "计步器已初始化（静止状态）")
    end
    return true
end

--[[
读取三轴加速度数据
@api exs_da267.get_data()
@return table or nil {x, y, z} 单位 g，失败返回nil
@usage
local data = exs_da267.get_data()
if data then
    log.info("da267", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
end
]]
function exs_da267.get_data()
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return nil
    end

    i2c.send(ctx.i2c_id, ctx.addr, REG_ACC_X_LSB, 1)
    local data = i2c.recv(ctx.i2c_id, ctx.addr, 6)
    if not data or #data ~= 6 then
        log.error("exs_da267", "读取加速度数据失败")
        return nil
    end

    local xl, xm, yl, ym, zl, zm = string.byte(data, 1, 6)
    
    -- DA267 加速度数据为12位精度，需要右移4位
    local raw_x = (xm << 8 | xl) >> 4
    local raw_y = (ym << 8 | yl) >> 4
    local raw_z = (zm << 8 | zl) >> 4
    
    -- 符号位扩展（12位补码转16位补码）
    if raw_x > 2047 then raw_x = raw_x - 4096 end
    if raw_y > 2047 then raw_y = raw_y - 4096 end
    if raw_z > 2047 then raw_z = raw_z - 4096 end

    return {
        x = raw_x / ctx.sensitivity,
        y = raw_y / ctx.sensitivity,
        z = raw_z / ctx.sensitivity
    }
end

--[[
读取计步数
@api exs_da267.get_steps()
@return number/nil 成功返回计步数，失败返回nil
@usage
local steps = exs_da267.get_steps()
if steps then
    log.info("da267", "steps:", steps)
end
]]
function exs_da267.get_steps()
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return nil
    end

    i2c.send(ctx.i2c_id, ctx.addr, REG_STEPS_LSB, 1)
    local data = i2c.recv(ctx.i2c_id, ctx.addr, 2)
    if not data or #data ~= 2 then
        log.error("exs_da267", "读取计步数据失败")
        return nil
    end

    local xl, xm = string.byte(data, 1, 1), string.byte(data, 2, 2)
    local steps = ((xl << 8) + xm) // 2  -- DA267 计步器数值需要除以 2 才是真实步数
    
    return steps
end

--[[
清零计步数
@api exs_da267.reset_steps()
@return boolean 成功返回true，失败返回false
@usage
exs_da267.reset_steps()
if exs_da267.reset_steps() then
    log.info("da267", "计步数已清零")
end
]]
function exs_da267.reset_steps()
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return false
    end

    i2c.send(ctx.i2c_id, ctx.addr, {0x2E, 0x00}, 1)
    return true
end

--[[
设置测量量程
@api exs_da267.set_range(range)
@param range number 量程，支持2/4/8/16（±g）
@return boolean 成功返回true，失败返回false
@usage
exs_da267.set_range(exs_da267.RANGE_4G)  -- 设置为±4g量程
@note 量程选择建议：
      - RANGE_2G (±2g, 3.91mg/LSB)：微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面
      - RANGE_4G (±4g, 7.81mg/LSB)：运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测
      - RANGE_8G (±8g, 15.63mg/LSB)：跌倒检测，用于人或物体瞬间跌倒时的检测，加速度量程8g；
      - RANGE_16G (±16g, 31.25mg/LSB)：适合高冲击场景（如安全监测、碰撞检测）
]]
function exs_da267.set_range(range)
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return false
    end

    if range ~= 2 and range ~= 4 and range ~= 8 and range ~= 16 then
        log.error("exs_da267", "无效的量程，支持2/4/8/16")
        return false
    end

    local range_val = 0
    if range == 4 then range_val = 0x10
    elseif range == 8 then range_val = 0x20
    elseif range == 16 then range_val = 0x30
    end

    i2c.send(ctx.i2c_id, ctx.addr, {REG_RESOLUTION_RANGE, range_val}, 1)
    ctx.range = range
    ctx.sensitivity = 32768 / range

    log.info("exs_da267", "量程设置为:", range, "g")
    return true
end

--[[
设置运动检测中断阈值
@api exs_da267.set_int_threshold(x, y, z)
@param x number X轴阈值，范围1-255，越小越敏感，可选，默认6
@param y number Y轴阈值，范围1-255，越小越敏感，可选，默认6
@param z number Z轴阈值，范围1-255，越小越敏感，可选，默认6
@return boolean 成功返回true，失败返回false
@usage
-- 设置默认敏感度（6）
exs_da267.set_int_threshold(6, 6, 6)

-- 检测微小振动（3）
exs_da267.set_int_threshold(3, 3, 3)

-- 检测较大动作（16）
exs_da267.set_int_threshold(16, 16, 16)

@note 阈值单位为LSB（最低有效位），实际触发加速度=阈值×量程LSB系数
        各量程LSB系数：±2g=3.91mg, ±4g=7.81mg, ±8g=15.63mg, ±16g=31.25mg
        示例(阈值=6)：6*(±2g)→23.5mg, 6*(±4g)→46.9mg, 6*(±8g)→93.8mg, 6*(±16g)→187.5mg
        规律：量程越大，相同阈值的触发加速度越大，灵敏度越低
        阈值与量程的关系说明：
        - 量程决定了传感器测量加速度的范围（如±2g、±4g等）
        - 阈值决定了触发运动检测中断的加速度变化幅度
        - 相同阈值在不同量程下，实际触发加速度不同（量程越大，触发加速度越大）

        各阈值范围对应使用场景：
        - 1-8：高灵敏（微小震动检测，用于检测轻微震动的场景，例如用手敲击桌面）
        - 9-24：中灵敏（运动检测，用于电动车或汽车行驶时的检测和人行走和跑步时的检测）
        - 25-48：较高灵敏（跌倒检测，用于人或物体瞬间跌倒时的检测）
        - 49-255：低灵敏（高冲击场景检测，如安全监测、碰撞检测）
]]
function exs_da267.set_int_threshold(x, y, z)
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return false
    end

    x = x or 6
    y = y or 6
    z = z or 6

    -- 参数验证和转换
    local function validate_and_convert(threshold)
        -- 验证范围
        if type(threshold) ~= "number" then
            log.error("exs_da267", "阈值参数必须为数字")
            return 6
        end
        
        -- 确保在有效范围内
        if threshold < 1 or threshold > 255 then
            log.warn("exs_da267", string.format("阈值 %d 超出范围(1-255)，使用默认值 6", threshold))
            return 6
        end
        
        -- 转换为十六进制字节值
        local hex_val = bit32.band(threshold, 0xFF)
        log.debug("exs_da267", string.format("阈值 %d 转换为字节值 0x%02X", threshold, hex_val))
        return hex_val
    end

    -- 验证和转换每个轴的阈值
    local x_byte = validate_and_convert(x)
    local y_byte = validate_and_convert(y)
    local z_byte = validate_and_convert(z)

    -- 发送到传感器
    i2c.send(ctx.i2c_id, ctx.addr, {REG_ACTIVE_X_THS, x_byte}, 1)
    i2c.send(ctx.i2c_id, ctx.addr, {REG_ACTIVE_Y_THS, y_byte}, 1)
    i2c.send(ctx.i2c_id, ctx.addr, {REG_ACTIVE_Z_THS, z_byte}, 1)

    log.info("exs_da267", "中断阈值设置为: 0x" .. string.format("%02X", x_byte) .. ", 0x" .. string.format("%02X", y_byte) .. ", 0x" .. string.format("%02X", z_byte))
    return true
end

--[[
启用/禁用计步器功能
@api exs_da267.enable_step_counter(enable)
@param enable boolean true启用，false禁用
@return boolean 成功返回true，失败返回false
@usage
exs_da267.enable_step_counter(true)  -- 启用计步器
if exs_da267.enable_step_counter(false) then
    log.info("da267", "计步器已禁用")
end
]]
function exs_da267.enable_step_counter(enable)
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return false
    end

    if enable then
        i2c.send(ctx.i2c_id, ctx.addr, {REG_STEP_FILTER, 0x80}, 1)
        log.info("exs_da267", "计步器已启用")
    else
        i2c.send(ctx.i2c_id, ctx.addr, {REG_STEP_FILTER, 0x25}, 1)
        log.info("exs_da267", "计步器已禁用")
    end

    return true
end

--[[
设置中断回调函数
@api exs_da267.set_callback(callback)
@param callback function 中断回调函数
@return boolean 成功返回true，失败返回false
@usage
-- 定义回调函数
local function da267_interrupt_callback()
    log.info("da267", "中断触发")
    local data = exs_da267.get_data()
    if data then
        log.info("da267", string.format("X=%.3f Y=%.3f Z=%.3f g", data.x, data.y, data.z))
    end
end

-- 设置回调函数
exs_da267.set_callback(da267_interrupt_callback)
]]
function exs_da267.set_callback(callback)
    if type(callback) == "function" then
        ctx.int_callback = callback
        return true
    else
        log.error("exs_da267", "回调必须是函数")
        return false
    end
end

--[[
获取 DA267 芯片ID（用于芯片识别和自检）
@api exs_da267.get_chip_id()
@return number/nil 成功返回芯片ID（DA267 为 0x13），失败返回nil
@usage
local id = exs_da267.get_chip_id()
if id then
    log.info("da267", "chip_id:", string.format("0x%02X", id))
end
local chip_id = exs_da267.get_chip_id()
if chip_id == 0x13 then
    log.info("da267", "芯片ID验证成功")
else
    log.error("da267", "芯片ID验证失败")
end
]]
function exs_da267.get_chip_id()
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return nil
    end

    i2c.send(ctx.i2c_id, ctx.addr, REG_CHIP_ID, 1)
    local data = i2c.recv(ctx.i2c_id, ctx.addr, 1)
    if not data or #data ~= 1 then
        return nil
    end

    return string.byte(data)
end

--[[
启用/禁用运动状态管理
@api exs_da267.enable_motion(enable)
@param enable boolean 是否启用运动状态管理
@return boolean 操作成功返回true，失败返回false
@usage
exs_da267.enable_motion(true)  -- 启用运动状态管理
exs_da267.enable_motion(false) -- 禁用运动状态管理
if exs_da267.enable_motion(true) then
    log.info("da267", "运动状态管理已启用")
end
]]
function exs_da267.enable_motion(enable)
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return false
    end

    if enable and not ctx.motion_enable then
        ctx.motion_enable = true
        motion_init()
        log.info("exs_da267", "运动状态管理已启用")
    elseif not enable and ctx.motion_enable then
        ctx.motion_enable = false
        ctx.motion_history = nil
        ctx.motion_state = false
        log.info("exs_da267", "运动状态管理已禁用")
    end
    return true
end

--[[
获取当前运动状态
@api exs_da267.is_moving()
@return boolean 当前运动状态，true=运动，false=静止
@usage
local state = exs_da267.is_moving()
log.info("exs_da267", "运动状态:", state)
if exs_da267.is_moving() then
    log.info("da267", "设备正在运动")
else
    log.info("da267", "设备处于静止状态")
end
]]
function exs_da267.is_moving()
    return ctx.motion_state
end

--[[
设置运动状态管理参数
@api exs_da267.set_motion_params(params)
@table params 参数配置表
    window:number, 历史窗口（秒），范围：1-60，默认8，可选
    threshold:number, 进入运动状态的中断次数，范围：1-20，默认4，可选
@return boolean 操作成功返回true，失败返回false
@usage
exs_da267.set_motion_params({
    window = 8,
    threshold = 4
})
local params = {
    window = 10,    -- 历史窗口改为10秒
    threshold = 5    -- 进入运动状态阈值改为5次
}
if exs_da267.set_motion_params(params) then
    log.info("da267", "运动状态管理参数已更新")
end
@note 参数范围说明：
      - window（历史窗口）：1-60秒，用于统计运动状态判断的历史记录窗口
        - 窗口越小，运动状态判断越敏感
        - 窗口越大，运动状态判断越迟钝
      - threshold（中断阈值）：1-20次，进入运动状态所需的中断次数
        - 中断次数越小，运动状态判断越敏感
        - 中断次数越大，运动状态判断越迟钝
]]
function exs_da267.set_motion_params(params)
    if not ctx.inited then
        log.error("exs_da267", "未初始化")
        return false
    end

    -- 历史窗口参数验证
    if params.window and type(params.window) == "number" then
        local window = math.floor(params.window)
        if window >= 1 and window <= 60 then
            ctx.motion_window = window
        else
            log.warn("exs_da267", "历史窗口参数无效，使用默认值8秒")
        end
    end

    -- 中断阈值参数验证
    if params.threshold and type(params.threshold) == "number" then
        local threshold = math.floor(params.threshold)
        if threshold >= 1 and threshold <= 20 then
            ctx.motion_threshold = threshold
        else
            log.warn("exs_da267", "中断阈值参数无效，使用默认值4次")
        end
    end

    if ctx.motion_enable then
        ctx.motion_history = zbuff.create(ctx.motion_window, 0x00)
        ctx.last_int_time = {mcu.ticks2(2)}
    end

    log.info("exs_da267", "运动状态管理参数更新", 
        "window:", ctx.motion_window, 
        "threshold:", ctx.motion_threshold)
    return true
end

--[[
获取当前配置信息
@api exs_da267.get_config()
@return table/nil 成功返回当前配置表，失败返回nil
@usage
local config = exs_da267.get_config()
if config then
    log.info("da267", "range:", config.range, "sensitivity:", config.sensitivity)
end
local config = exs_da267.get_config()
if config then
    log.debug("da267", json.encode(config))
end
]]
function exs_da267.get_config()
    if not ctx.inited then
        return nil
    end

    return {
        i2c_id = ctx.i2c_id,
        addr = ctx.addr,
        int_pin = ctx.int_pin,
        range = ctx.range,
        sensitivity = ctx.sensitivity,
        inited = ctx.inited,
        motion_enable = ctx.motion_enable,
        motion_state = ctx.motion_state,
        motion_window = ctx.motion_window,
        motion_threshold = ctx.motion_threshold,
        motion_count = ctx.motion_count
    }
end

--[[
关闭 DA267 传感器
@api exs_da267.close()
@return boolean 成功返回true，失败返回false
@usage
exs_da267.close()
]]
function exs_da267.close()
    if not ctx.inited then
        log.warn("exs_da267", "传感器未初始化")
        return false
    end
    
    -- 进入休眠模式（寄存器级别）
    -- 使用与 DA221 相同的模式寄存器（0x11）的最高位（0x80）
    i2c.send(ctx.i2c_id, ctx.addr, {REG_MODE_AXIS, 0x80}, 1)

    -- 清除中断回调
    if ctx.int_pin then
        gpio.setup(ctx.int_pin, 0, gpio.PULLUP)
    end
    
    -- 清理定时器资源
    if ctx.motion_timer then
        sys.timerStop(ctx.motion_timer)
        ctx.motion_timer = nil
    end
    ctx.motion_count = 0
    
    ctx.inited = false
    log.info("exs_da267", "传感器已关闭并进入休眠模式")
    return true
end

log.debug("exs_da267", "version -> " .. exs_da267.version())

return exs_da267