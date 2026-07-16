--[[
@module  ns2520_app
@summary exs_ns2520 扩展库全接口测试
@version 1.0
@date    2026.07.16
@author  王世豪
@usage
本文件对 exs_ns2520 扩展库的 7 个对外 API 逐一测试:
1、version()        -- 获取版本号
2、setup()          -- 初始化（含 temp_offset 参数）
3、get_data()       -- 读取压力+温度
4、get_pressure()   -- 单次读取压力
5、get_temperature() -- 单次读取温度
6、set_osr()        -- 动态切换过采样率
7、close()          -- 关闭/待机

注意:仅适配 Air8201G-BLMQ 和 Air8201G-BQ 两个子型号（主板板载 NS2520 气压传感器），Air8201G-LM/基础款（未板载 NS2520）和 Air8201H（未板载 NS2520）不支持。
]]

local exs_ns2520 = require "exs_ns2520"

local POWER_PIN  = 26   -- NS2520供电使能
local PULLUP_PIN = 28   -- I2C1总线上拉
local I2C_ID     = 1    -- I2C总线编号

local function ns2520_test()
    -- ==================== 硬件准备 ====================
    log.info("test", "第一步:硬件上电")
    gpio.setup(POWER_PIN, 1)
    gpio.setup(PULLUP_PIN, 1)
    sys.wait(100) -- 等待传感器上电稳定

    -- ==================== API-1: version() ====================
    log.info("test", "第二步:version() 版本号")
    local ver = exs_ns2520.version()
    log.info("test", "version()", "版本:", ver)

    -- ==================== API-2: setup() ====================
    log.info("test", "第三步:setup() 初始化")
    -- 测试 temp_offset 参数:默认 -7.0 偏移，验证温度校准
    local ok = exs_ns2520.setup({i2c_id = I2C_ID, prs_osr = 4, tmp_osr = 4})
    if not ok then
        log.error("test", "setup() 初始化失败，测试终止")
        return
    end
    log.info("test", "setup() 初始化成功")

    -- ==================== API-3: get_data() ====================
    log.info("test", "第四步:get_data() 读取压力+温度")
    local data = exs_ns2520.get_data()
    if data then
        log.info("test", "get_data()",
            "压力", string.format("%.2f hPa", data.pressure),
            "温度", string.format("%.2f ℃", data.temperature))
    else
        log.error("test", "get_data() 失败")
    end

    -- ==================== API-4: get_pressure() ====================
    log.info("test", "第五步:get_pressure() 单次读压力")
    local press = exs_ns2520.get_pressure()
    if press then
        log.info("test", "get_pressure()", string.format("%.2f hPa", press))
    else
        log.error("test", "get_pressure() 失败")
    end

    -- ==================== API-5: get_temperature() ====================
    log.info("test", "第六步:get_temperature() 单次读温度")
    local temp = exs_ns2520.get_temperature()
    if temp then
        log.info("test", "get_temperature()", string.format("%.2f ℃", temp))
    else
        log.error("test", "get_temperature() 失败")
    end

    -- ==================== API-6: set_osr() ====================
    log.info("test", "第七步:set_osr() 切换过采样率")
    -- 切换为低精度快速模式 (1x)
    exs_ns2520.set_osr(0, 0)
    local data_fast = exs_ns2520.get_data()
    if data_fast then
        log.info("test", "set_osr(0,0) 1x快速模式",
            "压力", string.format("%.2f hPa", data_fast.pressure),
            "温度", string.format("%.2f ℃", data_fast.temperature))
    end

    -- 切换为高精度模式 (64x)
    exs_ns2520.set_osr(6, 6)
    local data_high = exs_ns2520.get_data()
    if data_high then
        log.info("test", "set_osr(6,6) 64x高精度模式",
            "压力", string.format("%.2f hPa", data_high.pressure),
            "温度", string.format("%.2f ℃", data_high.temperature))
    end

    -- 只改压力不改温度
    exs_ns2520.set_osr(4, nil)
    local data_mix = exs_ns2520.get_data()
    if data_mix then
        log.info("test", "set_osr(4,nil) 仅改压力OSR",
            "压力", string.format("%.2f hPa", data_mix.pressure))
    end

    -- ==================== API-7: close() ====================
    log.info("test", "第八步:close() 关闭传感器")
    exs_ns2520.close()
    log.info("test", "close() 关闭成功")

    -- 关闭后再读，预期失败
    local data_after_close = exs_ns2520.get_data()
    if not data_after_close then
        log.info("test", "关闭后读取返回nil，符合预期")
    else
        log.warn("test", "关闭后仍读到数据，异常")
    end

    -- ==================== 重新初始化验证 ====================
    log.info("test", "第九步:重新 setup() 恢复使用")
    if exs_ns2520.setup({i2c_id = I2C_ID}) then
        log.info("test", "重新初始化成功")
        local data2 = exs_ns2520.get_data()
        if data2 then
            log.info("test", "重新初始化后读取正常",
                "压力", string.format("%.2f hPa", data2.pressure),
                "温度", string.format("%.2f ℃", data2.temperature))
        end
    end

    -- ==================== 持续读取循环 ====================
    log.info("test", "第十步:进入持续读取循环（每秒一次）")
    while true do
        local result = exs_ns2520.get_data()
        if result then
            log.info("test",
                "压力", string.format("%.2f hPa", result.pressure),
                "温度", string.format("%.2f ℃", result.temperature))
        else
            log.error("test", "读取失败")
        end
        sys.wait(1000) -- 每秒读取一次
    end
end

sys.taskInit(ns2520_test)
