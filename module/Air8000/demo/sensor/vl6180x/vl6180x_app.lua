--[[
@module  vl6180x_app
@summary VL6180X 飞行时间测距传感器演示模块，包含测距演示用例
@version 1.0
@date    2026.08.20
@author  江访
@usage
本文件包含 VL6180X 的逐项功能演示。
通过 exs_vl6180x 扩展库的 API 逐一演示标准测距、持续测距等功能。

通过 MODE 变量选择通信模式（改 MODE 的值即可，无需注释/取消注释代码）：
  MODE = 1  软件 I2C（默认推荐，仅需 scl/sda 引脚，任意 GPIO 均可，接线最灵活）
  MODE = 2  硬件 I2C（指定 i2c_id，占用 CPU 少）
]]

-- 加载 exs_vl6180x 扩展库
local exs_vl6180x = require "exs_vl6180x"

-- ==================== 通信模式选择 ====================
-- 改 MODE 的值选择通信模式：
--   1 = 软件 I2C（默认）   2 = 硬件 I2C
-- 各模式所需引脚/参数见下方 init_config，接线说明见 readme.md
local MODE = 1

local init_config
if MODE == 1 then
    -- 软件 I2C：SCL/SDA 用任意 GPIO，Air8000 接线示例用 GPIO1/GPIO2
    init_config = {scl = 1, sda = 2}
elseif MODE == 2 then
    -- 硬件 I2C：i2c_id 为总线号（Air8000 用 1），不传 scl/sda 时无总线恢复能力
    init_config = {i2c_id = 1}
else
    log.error("vl6180x_app", "MODE 取值错误，应为 1/2")
    return
end

--------------------------------------------------------------
-- [1/2] 标准测距演示
-- - setup() 自动完成芯片 ID 校验、I2C 总线恢复、测距参数配置
-- - get_range() 返回距离(mm)与测量状态 status_str
--------------------------------------------------------------
local function demo_standard_ranging()
    log.info("vl6180x_app", "===== [1/2] 标准测距 =====")

    local result = exs_vl6180x.setup(init_config)
    if not result then
        log.error("vl6180x_app", "初始化失败")
        log.error("vl6180x_app", "检查接线: VCC=3.3V GND SCL SDA，I2C 地址是否正确（如 0x29）")
        return false  -- 初始化失败必须返回 false
    end
    log.info("vl6180x_app", "VL6180X 初始化成功，版本:", exs_vl6180x.version())

    sys.wait(200)   -- 等待系统稳定，200ms
    for i = 1, 5 do
        local data = exs_vl6180x.get_range()
        if data then
            log.info("vl6180x_app", string.format("第%d次: 距离=%dmm 状态=%s",
                i, data.range_mm, data.status_str))
        else
            log.error("vl6180x_app", "读取测距数据失败")
        end
        sys.wait(1000)  -- 每隔 1 秒读取一次
    end

    exs_vl6180x.close()
    log.info("vl6180x_app", "---- [1/2] 完成 ----")
    return true
end

--------------------------------------------------------------
-- [2/2] 持续测距演示
-- - 每隔 1 秒读取一次距离数据，观察数据稳定性与状态码
--------------------------------------------------------------
local function demo_continuous_ranging()
    log.info("vl6180x_app", "===== [2/2] 持续测距演示 =====")

    local result = exs_vl6180x.setup(init_config)
    if not result then
        log.error("vl6180x_app", "初始化失败")
        log.error("vl6180x_app", "检查接线: VCC=3.3V GND SCL SDA，I2C 地址是否正确（如 0x29）")
        return false  -- 初始化失败必须返回 false
    end

    log.info("vl6180x_app", "每隔 1 秒读取一次距离数据，共 5 次")
    for i = 1, 5 do
        sys.wait(1000)  -- 每隔 1 秒读取一次
        local data = exs_vl6180x.get_range()
        if data then
            log.info("vl6180x_app", string.format("持续测距[%d]: 距离=%dmm 状态=%s",
                i, data.range_mm, data.status_str))
        else
            log.warn("vl6180x_app", string.format("持续测距[%d] 读取失败", i))
        end
    end

    exs_vl6180x.close()
    log.info("vl6180x_app", "---- [2/2] 完成 ----")
    return true
end

--------------------------------------------------------------
-- 主任务：按 [1/2]~[2/2] 顺序执行全部演示
--------------------------------------------------------------
local function vl6180x_demo_task_func()
    log.info("vl6180x_app", "HELLO")
    sys.wait(1000)  -- 等待系统稳定，1000ms

    -- HELLO 开始 → [1/2] → [2/2] → End
    local ok = demo_standard_ranging()
    if not ok then
        log.error("vl6180x_app", "初始化失败，演示终止")
        return
    end
    sys.wait(500)   -- 步骤间隔，500ms

    ok = demo_continuous_ranging()
    if not ok then
        log.error("vl6180x_app", "初始化失败，演示终止")
        return
    end
    sys.wait(500)   -- 步骤间隔，500ms

    log.info("vl6180x_app", "===== [演示完毕] =====")
    log.info("vl6180x_app", "End")
end

sys.taskInit(vl6180x_demo_task_func)
