--[[
@module  airlink_uart_wdt
@summary airlink UART多网融合模块
@version 1.0
@date    2026.07.21
@author  马梦阳
@usage
本demo演示的核心功能为：
1. 初始化4G网络连接。
2. 启动看门狗功能。

使用示例：
require("airlink_uart_wdt")
]]

--============================================================
-- 全局配置参数
--============================================================

-- AirLink UART 配置
local AIRLINK_UART_ID = 1    -- UART ID
local AIRLINK_BAUD = 2000000 -- 波特率：2M

--============================================================
-- 模块加载
--============================================================

local exnetif = require "exnetif"
local exairlinkwdt = require("exairlinkwdt")

--============================================================
-- 看门狗初始化
--============================================================

local function init_airlink_wdt()
    sys.wait(5000)

    -- 初始化看门狗，TO_RESET 使用 GPIO6，默认空闲电平为 低电平
    -- 在设计双向互看门狗时，需要使用 三极管 进行连接
    -- 禁止直连，否则会导致看门狗功能异常，造成对端被误复位
    local success = exairlinkwdt.open({ reset_pin = 6 , reset_idle_level = 0 })
    if success then
        log.info("main", "看门狗启动成功")
    else
        log.error("main", "看门狗启动失败")
    end
end

--============================================================
-- 网络初始化
--============================================================

-- 初始化网络，使得Air8101可以外挂Air780ER2模块实现4G联网功能。
local function init_airlink_net()
    exnetif.set_priority_order({
        {                                           -- 开启4G虚拟网卡
            airlink_4G = {
                auto_socket_switch = false,         -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_UART,   -- airlink工作模式：UART模式
                airlink_uart_id = AIRLINK_UART_ID,  -- airlink使用的UART接口ID
                airlink_uart_baud = AIRLINK_BAUD,   -- airlink使用的UART波特率
                airlink_adapter = socket.LWIP_GP_GW -- Air8101使用socket.LWIP_GP_GW网卡标识
            }
        }
    })
end

--============================================================
-- 启动入口
--============================================================

-- 开启airlink
sys.taskInit(init_airlink_net)

-- 初始化看门狗
sys.taskInit(init_airlink_wdt)
