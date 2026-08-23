--[[
@module  da267_app
@summary DA267 加速度传感器功能测试应用模块
@version 1.0
@date    2026.07.17
@author  王世豪
@usage
本demo演示DA267加速度传感器通过I2C1读取三轴加速度数据、步数和运动状态的功能。
适配型号：
  Air8201H        支持（主板板载 DA267）
  Air8201G-BLMQ   支持（主板板载 DA267）
  Air8201G-BQ     支持（主板板载 DA267）
  Air8201G-LM     支持（主板板载 DA267）

主要功能：
- 读取三轴加速度数据（单位：g）
- 读取计步数
- 检测运动/静止状态
- 支持运动状态管理和超时检测
- 计步器功能支持与运动状态联动

使用说明：
- 传感器供电通过GPIO24控制
- 中断引脚连接到GPIO39
- 默认I2C地址为0x26
- 默认量程为±2g
- 运动检测阈值为最近5秒内4次中断
- 运动状态超时为15秒

]]

-- 传感器供电控制引脚
local POWER_PIN = 24

-- 导入 DA267 扩展库
local exs_da267 = require("exs_da267")

local function da267_motion_state_event_handler(state)
    log.debug("da267", "运动状态变化: " .. (state and "运动" or "静止"))
end

-- 配置参数
-- DA267 传感器初始化配置表，包含所有必要的参数设置
-- 注意：不再支持在 setup 函数中设置 callback，需使用 set_callback 函数
-- 优化参数以提高运动状态转换速度
local DA267_CONFIG = {
    i2c_id = 1,                     -- I2C 总线
    addr = 0x26,                    -- I2C 从设备地址，DA267 默认地址为 0x26
    int_pin = 39,                   -- 中断引脚，连接到 Air8201H 的 GPIO39
    motion_enable = true,           -- 是否启用运动检测功能
    step_counter_enable = true      -- 是否启用计步器功能
}

-- 持续监控模式
local function continuous_monitoring()
    log.info("da267", "进入持续监控模式，每秒打印一次数据")
    while true do
        -- 每秒打印一次数据
        local data = exs_da267.get_data()
        local steps = exs_da267.get_steps()
        local is_moving = exs_da267.is_moving()
        
        if data and steps then
            log.info("da267", string.format("X=%.3f Y=%.3f Z=%.3f g, 步数: %d, 运动状态: %s", 
                data.x, data.y, data.z, steps, is_moving and "运动" or "静止"))
        else
            log.warn("da267", "数据读取异常，传感器可能已断开")
        end
        
        sys.wait(1000)
    end
end

-- 主任务函数
local function main_task()
    -- 传感器供电
    gpio.setup(POWER_PIN, 1)
    
    -- 初始化 DA267 传感器
    log.info("da267", "初始化DA267传感器...")
    
    local init_result = exs_da267.setup(DA267_CONFIG)
    
    if init_result then
        log.info("da267", "DA267传感器初始化成功")
        -- 启动持续监控模式
        continuous_monitoring()
    else
        log.error("da267", "DA267传感器初始化失败")
        
        -- 尝试重新初始化
        while true do
            log.info("da267", "尝试重新初始化传感器...")
            sys.wait(3000)
            init_result = exs_da267.setup(DA267_CONFIG)
            
            if init_result then
                log.info("da267", "传感器重新初始化成功")
                break
            end
        end
    end
end

-- 启动主任务
sys.taskInit(main_task)

-- 添加系统事件监听
sys.subscribe("DA267_MOTION_STATE", da267_motion_state_event_handler)
