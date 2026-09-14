--[[
@module  exs_aht20
@summary AHT20温湿度传感器驱动扩展库
@version(0.1)
@date    2026.9.11
@author  许璐
@usage
本扩展库提供 AHT20 温湿度传感器的 LuatOS 驱动，功能包括：
1、初始化（上电就绪等待、校准状态自检、校准寄存器初始化）
2、数据读取（温度、相对湿度，带数据校验）
3、异常恢复（软复位）

对外接口 5 个：
- exs_aht20.setup(i2c_id)：初始化传感器
- exs_aht20.get_data()：读取温湿度数据
- exs_aht20.reset()：软复位传感器
- exs_aht20.close()：释放资源
- exs_aht20.version()：获取版本号

=== 版本更新说明 ===
-- 版本号：202609111506
-- 1、更新时间：2026-09-11
-- 2、更新内容：
--   - setup 参数由 config 配置表简化为 i2c_id 数字，与 aht20_app.lua 的调用方式一致
--   - 移除软件 I2C 与 I2C 总线硬件恢复（无 scl/sda 引脚，无法位时序模拟恢复脉冲）
--   - 保留单次通信重试，用于滤除偶发干扰
]]

-- ==================== 模块表 ====================
local exs_aht20 = {}

-- ==================== 模块常量 ====================

-- AHT20 七位从机地址，出厂固定不可改（1 脚、6 脚均为 NC，无地址选择脚）
local DEV_ADDR          = 0x38

-- 触发测量命令，后面必须跟两个参数字节 0x33、0x00（规格书 5.4 节）
local CMD_TRIGGER       = 0xAC
local CMD_PARAM_1       = 0x33
local CMD_PARAM_2       = 0x00

-- 校准寄存器初始化命令，仅在校准位未使能时使用（规格书 5.4 节步骤 1）
local CMD_INIT_1        = 0x1B
local CMD_INIT_2        = 0x1C
local CMD_INIT_3        = 0x1E
local INIT_DATA_1       = 0x00
local INIT_DATA_2       = 0x00

-- 软复位命令；规格书未明列，来源于奥松官网例程，尚未真机确认，异常恢复时使用
local CMD_SOFT_RESET    = 0xBA

-- 状态字 Bit7：1 = 忙（测量中），0 = 闲（休眠态，数据可读）
local STATUS_BUSY       = 0x80

-- 状态字 Bit4+Bit3 校准使能判据，(status & 0x18) == 0x18 表示已校准
-- 注意：Bit4 在规格书表 9 中标注为保留位，但校准判据要求按 0x18 整体判断
local STATUS_CAL        = 0x18

-- 上电到可通信的等待时间，规格书 5.1 节要求不少于 100ms，此期间 SCL 保持高电平
local TIME_POWER_ON     = 100

-- 写校准寄存器的每条命令之间与初始化完成后的等待时间，规格书 5.4 节为 10ms
local TIME_INIT_REG     = 10

-- 软复位后的等待时间，等待芯片内部状态机复位完成
local TIME_AFTER_RESET  = 20

-- 触发测量后的转换时间，规格书 5.4 节步骤 3 要求 80ms
local TIME_MEASURE      = 80

-- 转换完成轮询间隔与总超时上限，超时返回 nil，避免无限阻塞
local TIME_POLL_STEP    = 10
local MEASURE_TIMEOUT   = 300

-- 单次通信失败后的重试等待时间，用于滤除偶发干扰
local TIME_RETRY        = 2

-- 一次连续读取 7 字节：状态字 + 6 字节温湿度数据 + 1 字节校验
local READ_LEN          = 7

-- 20 位原始值满量程，即 2^20 = 1048576（规格书 6.1 / 6.2 节换算公式分母）
local RAW_FULL          = 1048576

-- 湿度换算：RH = S_rh / 2^20 * 100，规格书 6.1 节
local HUMI_SCALE        = 100

-- 温度换算：T = S_t / 2^20 * 200 - 50，规格书 6.2 节
local TEMP_SCALE        = 200
local TEMP_OFFSET       = 50

-- 数据校验：CRC8，初值 0xFF，多项式 x^8+x^5+x^4+1（0x31），非反射，规格书 5.4 节
local CRC8_INIT         = 0xFF
local CRC8_POLY         = 0x31

-- 物理量合理范围，用于剔除明显异常的转换结果，规格书表 1 / 表 3
local HUMI_MIN          = 0
local HUMI_MAX          = 100
local TEMP_MIN          = -40
local TEMP_MAX          = 85

-- ==================== 内部变量 ====================

local g_i2c_id    = nil       -- I2C 总线 id（硬件 I2C 编号）
local g_i2c_speed = i2c.FAST  -- 通信速率，规格书表 8 要求最高 400kHz，速率过高会引起传感器自热
local g_ready     = false     -- 是否已初始化成功

-- ==================== 内部函数 ====================

-- 从传感器连续读取若干字节，失败后等待 2ms 重试一次，仍失败返回 nil
-- len：要读取的字节数
-- 返回读取到的字符串，nil 表示传感器无响应
local function read_bytes(len)
    local data = i2c.recv(g_i2c_id, DEV_ADDR, len)
    if type(data) ~= "string" or #data < len then
        sys.wait(TIME_RETRY)        -- 等待 2ms 后重试，滤除偶发干扰
        data = i2c.recv(g_i2c_id, DEV_ADDR, len)
        if type(data) ~= "string" or #data < len then
            return nil
        end
    end
    return data
end

-- 向传感器写入若干字节，失败后等待 2ms 重试一次
-- data：字节表，例如 {0xAC, 0x33, 0x00}
-- 返回 true 写入成功，false 写入失败
local function write_bytes(data)
    local ok = i2c.send(g_i2c_id, DEV_ADDR, data)
    if not ok then
        sys.wait(TIME_RETRY)        -- 等待 2ms 后重试，滤除偶发干扰
        ok = i2c.send(g_i2c_id, DEV_ADDR, data)
    end
    return ok
end

-- 读取传感器状态字（1 字节）
-- 读状态字本质是一次「地址 + 读位」的单字节读，不携带任何命令字
-- 返回 0~255 的状态字，nil 表示传感器无响应
local function read_status()
    local data = read_bytes(1)
    if not data then return nil end
    return data:byte(1)
end

-- 校准寄存器初始化：依次写 0x1B / 0x1C / 0x1E，每条命令后跟两个 0x00 数据字节
-- 规格书 5.4 节：仅在 (status & 0x18) != 0x18 时执行，正常采集过程中无需重复
-- 返回 true 三条命令全部写入成功，false 有命令写入失败
local function init_calibration()
    local cmd_list = { CMD_INIT_1, CMD_INIT_2, CMD_INIT_3 }
    for i = 1, #cmd_list do
        if not write_bytes({ cmd_list[i], INIT_DATA_1, INIT_DATA_2 }) then
            log.error("exs_aht20", "校准寄存器写入失败", string.format("cmd=0x%02X", cmd_list[i]))
            return false
        end
        sys.wait(TIME_INIT_REG)     -- 每条初始化命令之间等待 10ms，规格书 5.4 节要求
    end
    sys.wait(TIME_INIT_REG)         -- 初始化完成到首次触发测量之间再等待 10ms
    return true
end

-- 数据校验：CRC8，初值 0xFF，多项式 0x31，非反射（MSB 优先）
-- data：待校验数据，长度为 6 的字符串（状态字 + 温湿度数据的前 5 字节）
-- 返回 0~255 的校验值
local function crc8(data)
    local crc = CRC8_INIT
    for i = 1, #data do
        crc = crc ~ data:byte(i)
        for _ = 1, 8 do
            if (crc & 0x80) ~= 0 then
                crc = (crc << 1) ~ CRC8_POLY
            else
                crc = crc << 1
            end
            crc = crc & 0xFF
        end
    end
    return crc
end

-- ==================== 对外 API ====================

--[[
初始化 AHT20 温湿度传感器，完成通信初始化、上电就绪等待、芯片在线校验与校准状态自检
注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 等待上电稳定与校准初始化，在 task 外调用会报错）
注意事项：本库仅使用硬件 I2C，Caller 需自行保证对应 I2C 总线的 SCL/SDA 引脚复用已配置完成
@api exs_aht20.setup(i2c_id)
@param number i2c_id
参数含义：硬件 I2C 总线编号
数据类型：number
取值范围：0 / 1 等模组支持的硬件 I2C 编号
是否必选：是
注意事项：该编号对应的 SCL/SDA 引脚由模组硬件决定，需与传感器实际接线一致；本库按 400kHz 速率初始化该总线
参数示例：1
@return boolean
含义说明：初始化是否成功
数据类型：boolean
取值范围：true（成功），false（失败，参数错误或芯片无响应）
注意事项：失败时优先检查传感器供电与上拉电阻
返回示例：true
]]
function exs_aht20.setup(i2c_id)
    if type(i2c_id) ~= "number" then
        log.error("exs_aht20", "参数错误，setup 需要传入 I2C 总线编号", "正确用法：exs_aht20.setup(1)")
        return false
    end

    g_i2c_id = i2c_id
    i2c.setup(g_i2c_id, g_i2c_speed)

    -- 上电后必须等待不少于 100ms，此期间 SCL 保持高电平（规格书 5.1 节）
    sys.wait(TIME_POWER_ON)

    -- 芯片在线校验：读不到状态字说明供电或接线有问题，直接返回失败
    local status = read_status()
    if not status then
        log.error("exs_aht20", "芯片无响应，检查接线: VDD=3.3V GND SCL SDA，上电后需等待 100ms")
        return false
    end

    -- 校准位未使能时执行校准寄存器初始化（规格书 5.4 节步骤 1）
    if (status & STATUS_CAL) ~= STATUS_CAL then
        log.warn("exs_aht20", "校准位未使能，开始初始化校准寄存器", string.format("status=0x%02X", status))
        if not init_calibration() then return false end
        status = read_status()
        if not status then
            log.error("exs_aht20", "校准寄存器初始化后芯片无响应")
            return false
        end
        if (status & STATUS_CAL) ~= STATUS_CAL then
            -- 注意：Bit4 在规格书表 9 中标注为保留位，个别批次可能不置位
            -- 此处不强制判定失败，仍允许继续测量，避免正常芯片被误判为故障
            log.warn("exs_aht20", "校准位仍未使能，数据可能偏差，可尝试 reset() 后重新 setup",
                     string.format("status=0x%02X", status))
        end
    end

    g_ready = true
    log.info("exs_aht20", "初始化完成", string.format("status=0x%02X", status))
    return true
end

--[[
触发一次温湿度转换并读取物理量，内部已完成数据校验与合理性检查
注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 等待转换完成，在 task 外调用会报错）
@api exs_aht20.get_data()
@return table
含义说明：温湿度数据，读取失败返回 nil
数据类型：table 或 nil
取值范围：
    data.temp - 温度，单位 ℃，范围 -40~85
    data.hum  - 相对湿度，单位 %RH，范围 0~100
注意事项：两次调用间隔需大于 1 秒，采集过快会引起传感器自热导致读数偏差
返回示例：{temp = 26.31, hum = 52.17}
]]
function exs_aht20.get_data()
    if not g_ready then
        log.error("exs_aht20", "未初始化，请先调用 exs_aht20.setup(i2c_id)")
        return nil
    end

    -- 触发一次温湿度转换（规格书 5.4 节步骤 2）
    if not write_bytes({ CMD_TRIGGER, CMD_PARAM_1, CMD_PARAM_2 }) then
        log.error("exs_aht20", "触发测量失败")
        return nil
    end

    -- 先按规格书要求固定等待 80ms，再轮询状态字 Bit7，最长再等 300ms
    sys.wait(TIME_MEASURE)      -- 等待 AHT20 完成一次温湿度转换，规格书要求 80ms
    local wait_ms = 0
    while wait_ms < MEASURE_TIMEOUT do
        local status = read_status()
        if status and (status & STATUS_BUSY) == 0 then break end
        sys.wait(TIME_POLL_STEP)    -- 每 10ms 检测一次转换是否完成
        wait_ms = wait_ms + TIME_POLL_STEP
    end
    if wait_ms >= MEASURE_TIMEOUT then
        log.error("exs_aht20", "测量超时，传感器未在 380ms 内完成转换")
        return nil
    end

    -- 连续读取 7 字节：状态字 + 6 字节温湿度数据 + 1 字节校验
    local data = read_bytes(READ_LEN)
    if not data then
        log.error("exs_aht20", "读取数据失败")
        return nil
    end

    -- 前 6 字节参与校验，结果与第 7 字节比对，不一致说明传输受干扰，丢弃本次数据
    if crc8(data:sub(1, 6)) ~= data:byte(7) then
        log.error("exs_aht20", "数据校验失败，本次数据已丢弃")
        return nil
    end

    -- 湿度 20 位原始值：S2[19:12] + S3[11:4] + S4 高 4 位
    local humi_raw = (data:byte(2) << 12) | (data:byte(3) << 4) | (data:byte(4) >> 4)

    -- 温度 20 位原始值：S4 低 4 位[19:16] + S5[15:8] + S6[7:0]
    local temp_raw = ((data:byte(4) & 0x0F) << 16) | (data:byte(5) << 8) | data:byte(6)

    local hum  = HUMI_SCALE * humi_raw / RAW_FULL
    local temp = TEMP_SCALE * temp_raw / RAW_FULL - TEMP_OFFSET

    -- 剔除明显异常的转换结果，通常是传感器受污染、结露或通信受干扰导致
    if hum < HUMI_MIN or hum > HUMI_MAX or temp < TEMP_MIN or temp > TEMP_MAX then
        log.warn("exs_aht20", "数据超出合理范围，已丢弃",
                 string.format("hum=%.2f temp=%.2f", hum, temp))
        return nil
    end

    return { temp = temp, hum = hum }
end

--[[
软复位 AHT20，用于通信异常或校准状态异常后的恢复
注意事项：必须在 sys.taskInit() 创建的协程中调用（内部使用 sys.wait() 等待复位完成，在 task 外调用会报错）
注意事项：软复位会清空芯片校准状态，复位后必须重新调用 setup() 才能继续测量
@api exs_aht20.reset()
@return boolean
含义说明：软复位是否执行成功
数据类型：boolean
取值范围：true（成功），false（失败或未初始化）
注意事项：复位命令来源于芯片厂商官网例程，规格书未明列；若复位后仍无响应，请改用重新上电
返回示例：true
]]
function exs_aht20.reset()
    if not g_ready then
        log.error("exs_aht20", "未初始化，请先调用 exs_aht20.setup(i2c_id)")
        return false
    end

    local ok = write_bytes({ CMD_SOFT_RESET })
    sys.wait(TIME_AFTER_RESET)      -- 等待软复位生效，20ms
    if not ok then
        log.error("exs_aht20", "软复位失败")
        return false
    end

    g_ready = false                 -- 复位后校准状态被清空，必须重新 setup
    log.info("exs_aht20", "软复位完成，请重新调用 setup()")
    return true
end

--[[
释放传感器占用的通信资源
@api exs_aht20.close()
@return nil
含义说明：无返回值
数据类型：nil
注意事项：关闭后需重新 setup() 才能继续使用
]]
function exs_aht20.close()
    if not g_i2c_id then return end
    i2c.close(g_i2c_id)
    g_i2c_id = nil
    g_ready = false
    log.info("exs_aht20", "资源已释放")
end

--[[
获取扩展库版本号
@api exs_aht20.version()
@return string
含义说明：版本号，格式 yyyymmddhhmm
数据类型：string
取值范围：12 位数字字符串
注意事项：与文档「版本更新说明」中的版本号一致
返回示例："202609111506"
]]
function exs_aht20.version()
    return "202609111506"
end

return exs_aht20
