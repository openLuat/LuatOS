--[[
@module  sensor_vl53l1x
@summary Air8780P VL53L1X激光测距传感器驱动封装模块
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件为VL53L1X激光测距传感器的驱动封装模块，核心业务逻辑为：
1、传感器初始化（I2C配置、模式选择）
2、传感器数据采集（多次采样取平均）
3、传感器关闭

本文件的对外接口有3个：
1、sensor_vl53l1x.init(scl, sda, range_mode)：初始化传感器
2、sensor_vl53l1x.collect_data(sensor_samples)：采集传感器数据，返回平均值
3、sensor_vl53l1x.close()：关闭传感器
]]

-- ==================== 加载扩展库 ====================

-- exs_vl53l1x: VL53L1X传感器扩展库，提供底层I2C通信和测距控制
-- 使用前需确认固件中包含此扩展库
local exs_vl53l1x = require "exs_vl53l1x"

-- ==================== 模块表 ====================

-- sensor_vl53l1x 为模块对外接口表，所有对外函数注册在此表上
-- 调用方通过 local sensor_vl53l1x = require "sensor_vl53l1x" 获取本表
local sensor_vl53l1x = {}

-- ==================== API：初始化 ====================

--[[
初始化VL53L1X激光测距传感器

sensor_vl53l1x.init(scl, sda, range_mode)

本函数完成以下工作：
1、配置I2C引脚（软件I2C模式）
2、等待传感器固件就绪
3、写入预设模式配置（standard/short/long）
4、校验芯片ID（MID=0xEA, MT=0xCC）

@param number scl
含义：I2C时钟线SCL的GPIO引脚号
取值范围：0~最大GPIO号，视具体模组而定
是否必选：必选
示例值：1（Air8780P上的GPIO1）

@param number sda
含义：I2C数据线SDA的GPIO引脚号
取值范围：0~最大GPIO号，视具体模组而定
是否必选：必选
示例值：2（Air8780P上的GPIO2）

@param string range_mode
含义：测距模式
取值范围：
    "short"   — 短距离模式，最远约1.36m，抗环境光能力强
    "standard"— 标准模式，最远约2.9m，通用场景
    "long"    — 长距离模式，最远约4.6m，需要较好的环境光条件
是否必选：可选
默认值："standard"

@return boolean
含义：初始化是否成功
取值范围：
    true  — 初始化成功，传感器可正常使用
    false — 初始化失败，请检查I2C接线和传感器供电

@usage
-- 基本用法：GPIO1=SCL, GPIO2=SDA, 标准模式
local ok = sensor_vl53l1x.init(1, 2, "standard")
if not ok then
    log.error("sensor_vl53l1x", "传感器初始化失败")
    return
end

-- 短距离模式（抗强光）
local ok = sensor_vl53l1x.init(1, 2, "short")

-- 长距离模式
local ok = sensor_vl53l1x.init(1, 2, "long")
]]
function sensor_vl53l1x.init(scl, sda, range_mode)
    range_mode = range_mode or "standard"
    log.info("sensor_vl53l1x", "正在初始化VL53L1X传感器, mode=" .. range_mode)

    -- 调用扩展库setup接口，传入I2C引脚和测距模式
    -- exs_vl53l1x.setup内部会完成：
    --   1. i2c.setup初始化I2C总线
    --   2. 等待传感器固件启动（轮询寄存器0x00E5）
    --   3. 写入预设模式配置
    --   4. 验证芯片型号
    local ok = exs_vl53l1x.setup({
        scl = scl,
        sda = sda,
        range_mode = range_mode,
    })
    if not ok then
        log.error("sensor_vl53l1x", "VL53L1X初始化失败，请检查接线和供电")
        return false
    end
    log.info("sensor_vl53l1x", "VL53L1X初始化成功")
    return true
end

-- ==================== API：数据采集 ====================

--[[
采集传感器数据，多次采样后取平均值

sensor_vl53l1x.collect_data(sensor_samples)

本函数完成以下工作：
1、按指定次数循环采集测距数据
2、每次采集间隔500ms，等待传感器就绪
3、过滤无效数据（status不为0的帧）
4、计算有效数据的平均值（四舍五入取整）

注意：本函数内部有 sys.wait()，必须在协程中调用

@param number sensor_samples
含义：每次唤醒后采集的次数
取值范围：正整数，建议1~10
    1   — 单次采集，速度快但可能因瞬间干扰产生偏差
    3   — 默认值，三次取平均，兼顾速度和精度
    5~10 — 多次采集，精度高但耗时较长（每次间隔500ms）
是否必选：可选
默认值：3

@return table
含义：采集成功时返回数据表，包含以下字段
    distance_list : table，原始距离值数组（单位mm），例如 {267, 261, 265}
    avg_distance  : number，有效数据的平均值（单位mm，四舍五入取整）
    valid_count   : number，有效数据的帧数

@return nil
含义：所有采集数据均无效时返回nil
可能原因：
    1、传感器前方有遮挡物
    2、传感器距离目标过近（<10mm）
    3、环境光过强或目标表面反射率过低

@usage
-- 默认采集3次
local data = sensor_vl53l1x.collect_data(3)
if data then
    log.info("sensor_vl53l1x", "平均距离=" .. data.avg_distance .. "mm")
    log.info("sensor_vl53l1x", "原始数据=" .. table.concat(data.distance_list, ","))
else
    log.warn("sensor_vl53l1x", "未测到有效距离")
end
]]
function sensor_vl53l1x.collect_data(sensor_samples)
    sensor_samples = sensor_samples or 3
    log.info("sensor_vl53l1x", "开始采集传感器数据，采集次数=" .. sensor_samples)

    -- distances: 存储有效距离值的数组
    -- valid_count: 有效数据帧数计数器
    local distances = {}
    local valid_count = 0

    -- 循环采集：每次采集前等待500ms让传感器完成测距
    for i = 1, sensor_samples do
        sys.wait(500)

        -- exs_vl53l1x.get_data() 返回数据结构：
        -- {
        --     distance   = number,  -- 测距值（单位mm）
        --     status     = number,  -- 状态码，0=成功
        --     status_str = string,  -- 状态描述文字
        --     sigma      = number,  -- 标准差（可选）
        -- }
        local data = exs_vl53l1x.get_data()

        -- 判断数据是否有效：status==0 表示测距成功
        if data and data.status == 0 then
            distances[#distances + 1] = data.distance
            valid_count = valid_count + 1
            log.info("sensor_vl53l1x", string.format("采集[%d/%d] 距离=%dmm 状态=%s",
                i, sensor_samples, data.distance, data.status_str))
        else
            local status_str = (data and data.status_str) or "无数据"
            log.warn("sensor_vl53l1x", string.format("采集[%d/%d] 无效数据 状态=%s",
                i, sensor_samples, status_str))
        end
    end

    -- 没有有效数据时返回nil
    if valid_count == 0 then
        log.error("sensor_vl53l1x", "所有采集数据均无效")
        return nil
    end

    -- 计算平均值（四舍五入取整）
    local sum = 0
    for _, d in ipairs(distances) do
        sum = sum + d
    end
    local avg_distance = math.floor(sum / #distances + 0.5)

    log.info("sensor_vl53l1x", string.format("采集完成: 有效%d帧, 平均距离=%dmm",
        valid_count, avg_distance))

    -- 返回数据表
    return {
        distance_list = distances,  -- 原始距离数组，用于MQTT上报详细数据
        avg_distance = avg_distance, -- 平均距离，用于excloud上报
        valid_count = valid_count,   -- 有效帧数，用于判断数据质量
    }
end

-- ==================== API：关闭传感器 ====================

--[[
关闭VL53L1X传感器

sensor_vl53l1x.close()

本函数完成以下工作：
1、调用扩展库close接口停止测距
2、释放I2C总线资源
3、传感器进入待机模式，降低功耗

建议在以下场景调用：
    1、数据采集完成后立即关闭，减少功耗
    2、进入PSM+休眠前必须关闭
    3、设备异常重启前

@usage
sensor_vl53l1x.close()
]]
function sensor_vl53l1x.close()
    log.info("sensor_vl53l1x", "关闭VL53L1X传感器")
    exs_vl53l1x.close()
end

return sensor_vl53l1x
