--[[
@module  aht20_app
@summary AHT20 温湿度传感器数据读取业务模块
@version 1.0
@date    2026.9.9
@author  许璐
@usage
本文件为 aht20_app 应用功能模块，核心业务逻辑为：
1、初始化 AHT20 温湿度传感器；
2、每隔 2 秒读取一次温湿度数据并打印；
3、连续读取失败时执行软复位并重新初始化。

本文件没有对外接口，直接在 main.lua 中 require "aht20_app" 就可以加载运行；
]]

-- 加载 exs_aht20 扩展库，注意文件名不带路径
local exs_aht20 = require "exs_aht20"


-- 采集周期，单位 ms；规格书要求采集周期大于 1 秒，防止传感器自热影响精度
local READ_INTERVAL = 2000

-- 连续读取失败达到该次数后，执行软复位并重新初始化
local MAX_FAIL_COUNT = 3

local i2cid = 1

--  初始化 AHT20 温湿度传感器
-- 返回 true 初始化成功，false 初始化失败
local function init_func()
    local result = exs_aht20.setup(i2cid)
    if not result then
        log.error("aht20_app", "初始化失败")
        return false
    end
    log.info("aht20_app初始化成功")
    return true
end

-- 每隔 2 秒读取一次温湿度数据并打印
-- 返回 true 读取成功，false 读取失败
local function read_data_func()
    local data = exs_aht20.get_data()
    if data then
        log.info("aht20_app", string.format("温度=%.2f℃ 湿度=%.2f%%RH", data.temp, data.hum))
        return true
    end
    log.warn("aht20_app", "读取失败，本次数据已丢弃")
    return false
end

-- 连续读取失败后的恢复：软复位并重新初始化
-- 返回 true 恢复成功，false 恢复失败
local function recovery_func()
    log.warn("aht20_app", "连续读取失败，执行软复位")
    if exs_aht20.reset() then
        return init_func()
    end
    return false
end

-- AHT20 温湿度采集主任务
local function aht20_task_func()
    sys.wait(100)       -- 等待系统稳定，100ms

    if not init_func() then return end

    local fail_count = 0
    while true do
        if read_data_func() then
            fail_count = 0                  -- 读取成功，清空连续失败计数
        else
            fail_count = fail_count + 1
            if fail_count >= MAX_FAIL_COUNT then
                if not recovery_func() then return end
                fail_count = 0
            end
        end
        sys.wait(READ_INTERVAL)             -- 采集周期 2 秒，规格书要求大于 1 秒
    end
end

sys.taskInit(aht20_task_func)
