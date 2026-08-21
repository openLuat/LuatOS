--[[
@module  spl06_app
@summary SPL06-001 数字气压传感器演示模块，包含初始化、数据读取、海拔计算、过采样切换、模式切换与休眠唤醒演示用例
@version 1.0
@date    2026.08.21
@author  江访
@usage
本文件包含 SPL06-001 的逐项功能演示。
通过 exs_spl06 扩展库的 API 逐一演示初始化、数据读取、海拔计算、
过采样率切换、测量模式切换与休眠唤醒等功能。

通过 MODE 变量选择通信模式（改 MODE 的值即可，无需注释/取消注释代码）：
  MODE = 1  软件 I2C（默认推荐，仅需 scl/sda 引脚，任意 GPIO 均可，接线最灵活）
  MODE = 2  硬件 I2C（指定 i2c_id，占用 CPU 少）

Air8000 接线（软件 I2C）：
  SCL = GPIO1
  SDA = GPIO2
]]

-- 加载 exs_spl06 扩展库
local exs_spl06 = require "exs_spl06"

-- ==================== 通信模式选择 ====================
-- 改 MODE 的值选择通信模式：
--   1 = 软件 I2C（默认）   2 = 硬件 I2C
-- 各模式所需引脚/参数见下方 init_config，接线说明见 readme.md
local MODE = 1

local init_config
if MODE == 1 then
    -- 软件 I2C：SCL/SDA 用任意 GPIO，Air8000 接线示例用 GPIO1/GPIO2
    -- SPL06-001 支持双地址 0x76/0x77（由 SDO 引脚决定），不传 addr 时扩展库自动探测
    init_config = {scl = 1, sda = 2}
elseif MODE == 2 then
    -- 硬件 I2C：i2c_id 为总线号（Air8000 用 1，默认管脚 Pin66=SCL, Pin67=SDA），不传 scl/sda 时无总线恢复能力
    init_config = {i2c_id = 1}
else
    log.error("spl06_app", "MODE 取值错误，应为 1/2")
    return
end

--------------------------------------------------------------
-- [1/5] 初始化
-- - setup() 自动完成 I2C 地址自动探测、芯片 ID 校验、校准系数读取、
--   过采样率配置、缩放基准建立（16x 气压/8x 温度）
--------------------------------------------------------------
local function demo_init()
    log.info("spl06_app", "===== [1/5] 初始化 =====")

    local result = exs_spl06.setup(init_config)
    if not result then
        log.error("spl06_app", "初始化失败")
        log.error("spl06_app", "检查接线: VCC=3.3V GND SCL SDA，I2C 地址是否正确（如 0x76/0x77）")
        return false  -- 初始化失败必须返回 false
    end
    log.info("spl06_app", "SPL06-001 初始化成功，版本:", exs_spl06.version())
    return true
end

--------------------------------------------------------------
-- [2/5] 数据读取
-- - get_data() 返回气压(hPa)与温度(℃)，get_pressure()/get_temperature() 单次读取
--------------------------------------------------------------
local function demo_read_data()
    log.info("spl06_app", "===== [2/5] 数据读取 =====")
    log.info("spl06_app", "连续读取 5 次气压/温度（单位 hPa / ℃）")

    -- 连续读取 5 次气压/温度
    for i = 1, 5 do
        local data = exs_spl06.get_data()
        if data then
            log.info("spl06_app", string.format("第%d次: 气压=%.2fhPa 温度=%.1f℃",
                i, data.pressure, data.temperature))
        else
            log.error("spl06_app", string.format("第%d次读取失败", i))
        end
        sys.wait(1000)  -- 每隔 1 秒读取一次，1000ms
    end

    -- 演示单次读取接口
    local pressure = exs_spl06.get_pressure()
    local temperature = exs_spl06.get_temperature()
    log.info("spl06_app", string.format("单次气压=%.2fhPa 单次温度=%.1f℃",
        pressure or 0, temperature or 0))
end

--------------------------------------------------------------
-- [3/5] 海拔高度计算
-- - get_altitude() 按国际气压测高公式计算海拔（纯计算接口，不耗时）
-- - 默认海平面气压 1013.25hPa，也可传当地海平面气压提高精度
--------------------------------------------------------------
local function demo_altitude()
    log.info("spl06_app", "===== [3/5] 海拔高度计算 =====")

    local pressure = exs_spl06.get_pressure()
    if not pressure then
        log.error("spl06_app", "气压读取失败，跳过海拔计算")
        return
    end
    local h_default = exs_spl06.get_altitude(pressure)          -- 默认 1013.25hPa
    local h_custom = exs_spl06.get_altitude(pressure, 1005)     -- 自定义 1005hPa
    log.info("spl06_app", string.format("气压=%.2fhPa，默认海平面气压海拔=%.1f米，自定义1005hPa海拔=%.1f米",
        pressure, h_default, h_custom))
end

--------------------------------------------------------------
-- [4/5] 过采样率切换
-- - set_osr() 在线切换气压过采样率，切换后扩展库自动完成缩放因子动态自校准
-- - OSR 越高数据越稳定，但单次测量耗时越长；校准失败自动回退默认 16x/8x
--------------------------------------------------------------
local function demo_switch_osr()
    log.info("spl06_app", "===== [4/5] 过采样率切换 =====")
    log.info("spl06_app", "依次切换气压过采样率 1x/16x/64x（温度保持 8x），观察数据精度")

    -- 依次切换 3 档气压过采样率（1x/16x/64x）
    local osr_list = {0, 4, 6}
    local osr_names = {"1x", "16x", "64x"}
    for i = 1, #osr_list do
        local ok = exs_spl06.set_osr(osr_list[i], 3)
        if not ok then
            log.error("spl06_app", string.format("气压OSR切换为%d(%s)失败，已回退默认16x/8x", osr_list[i], osr_names[i]))
        end
        log.info("spl06_app", string.format("气压OSR=%d(%s)，开始采集", osr_list[i], osr_names[i]))
        local sum = 0
        local cnt = 0
        for j = 1, 5 do
            local data = exs_spl06.get_data()
            if data then
                sum = sum + data.pressure
                cnt = cnt + 1
                log.info("spl06_app", string.format("OSR=%d 第%d次: 气压=%.2fhPa 温度=%.1f℃",
                    osr_list[i], j, data.pressure, data.temperature))
            else
                log.error("spl06_app", "读取失败")
            end
            sys.wait(1000)  -- 每隔 1 秒读取一次，1000ms
        end
        if cnt > 0 then
            log.info("spl06_app", string.format("OSR=%d 平均气压=%.2fhPa", osr_list[i], sum / cnt))
        end
    end

    -- 恢复默认过采样（16x/8x）
    exs_spl06.set_osr(4, 3)
end

--------------------------------------------------------------
-- [5/5] 测量模式切换与休眠唤醒
-- - set_mode() 切换待机/单次气压/连续气压+温度测量模式
-- - sleep() 进入低功耗待机（电流<1µA），wakeup() 唤醒恢复连续测量
-- - 最后 close() 释放资源
--------------------------------------------------------------
local function demo_mode_and_sleep()
    log.info("spl06_app", "===== [5/5] 模式切换与休眠唤醒 =====")

    -- 待机模式（电流 < 1µA）
    exs_spl06.set_mode("standby")
    log.info("spl06_app", "已切换待机模式（standby）")

    -- 单次气压测量模式（测完自动回待机）
    exs_spl06.set_mode("pressure")
    log.info("spl06_app", "已切换单次气压测量模式（pressure）")

    -- 连续气压+温度测量模式（后台模式）
    exs_spl06.set_mode("both")
    log.info("spl06_app", "已切换连续气压+温度测量模式（both）")
    sys.wait(500)   -- 等待后台连续测量稳定，500ms
    local data = exs_spl06.get_data()
    if data then
        log.info("spl06_app", string.format("连续模式数据: 气压=%.2fhPa 温度=%.1f℃", data.pressure, data.temperature))
    end

    -- 休眠唤醒（睡眠 3 秒后唤醒）
    exs_spl06.sleep()
    log.info("spl06_app", "已进入睡眠（待机），3 秒后唤醒")
    sys.wait(3000)  -- 睡眠 3 秒，3000ms
    exs_spl06.wakeup()
    log.info("spl06_app", "已唤醒，恢复连续测量")
    sys.wait(500)   -- 等待连续测量恢复，500ms
    data = exs_spl06.get_data()
    if data then
        log.info("spl06_app", string.format("唤醒后数据: 气压=%.2fhPa 温度=%.1f℃", data.pressure, data.temperature))
    end

    -- 关闭传感器（进入待机并释放 I2C 资源）
    exs_spl06.close()
    log.info("spl06_app", "已关闭传感器")
end

--------------------------------------------------------------
-- 主任务：按 [1/5]~[5/5] 顺序执行全部演示
--------------------------------------------------------------
local function spl06_demo_task_func()
    log.info("spl06_app", "HELLO")
    sys.wait(1000)  -- 等待系统稳定，1000ms

    -- HELLO 开始 → [1/5] → [2/5] → [3/5] → [4/5] → [5/5] → End
    local ok = demo_init()
    if not ok then
        log.error("spl06_app", "初始化失败，演示终止")
        return
    end
    sys.wait(500)   -- 步骤间隔，500ms

    demo_read_data()
    sys.wait(500)   -- 步骤间隔，500ms

    demo_altitude()
    sys.wait(500)   -- 步骤间隔，500ms

    demo_switch_osr()
    sys.wait(500)   -- 步骤间隔，500ms

    demo_mode_and_sleep()

    log.info("spl06_app", "===== [演示完毕] =====")
    log.info("spl06_app", "End")
end

sys.taskInit(spl06_demo_task_func)
