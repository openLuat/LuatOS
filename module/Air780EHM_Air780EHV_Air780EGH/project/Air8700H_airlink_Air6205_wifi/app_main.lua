--[[
@module  app_main
@summary 应用主任务 - 初始化WiFi热点并启动配置服务器
@version 1.0
@date    2026.09.14
@author  江访
@usage
本模块负责应用初始化流程，核心逻辑为：
1、加载配置并生成默认WiFi热点名称
2、通过SPI启动Air6205 WiFi AP热点
3、启动Web配置服务器

本模块没有对外接口，由main.lua通过require加载后自动运行。
--]]

local config          = require "config"
local airlink_wifi_ap = require "airlink_wifi_ap"
local http_config     = require "http_config"

--============================================================
-- 主任务：初始化WiFi热点并启动Web配置服务器
--============================================================

sys.taskInit(function()
    -- 1. 加载已保存的配置
    config.load()

    -- 2. 获取IMEI生成默认SSID
    local imei = config.get_imei()
    local default_ssid = config.default_ssid()
    log.info("app_main", "IMEI:", imei, "默认SSID:", default_ssid)

    -- 首次使用时设置默认SSID
    if config.get("ssid", "") == "" then
        config.set("ssid", default_ssid)
    end

    -- 3. 启动WiFi AP热点（通过SPI连接Air6205）
    local ok = airlink_wifi_ap.open({
        mode     = "spi",       -- 通信模式："spi"或"uart"
        ssid     = config.get("ssid"),
        password = config.get("password", ""),
        -- SPI引脚配置（根据实际硬件修改）
        spi_id    = 0,
        spi_cs    = 8,
        spi_rdy   = 33,
        spi_irq   = 24,
        spi_speed = 8*1000000,
        wifi_rst  = 32,
    })

    if not ok then
        log.info("app_main", "WiFi AP启动失败")
        return
    end

    -- 4. 启动HTTP配置服务器
    http_config.start()

    log.info("app_main", "热点名称:", config.get("ssid"))
end)
