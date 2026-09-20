--[[
@module  netdrv_device
@summary 网络驱动设备（网卡选择：运行时自动适配真机 / PC 模拟器）
@version 1.1.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
参考官方 demo module/Air780EPM/demo/aircloud/netdrv_device.lua：
根据运行环境自动选择并加载对应网卡驱动——
1. 真机（Air8782P2）→ 加载 netdrv_4g（4G 网卡 socket.LWIP_GP）；
2. PC 模拟器 → 加载 netdrv_pc（模拟器网卡 socket.ETH0）。
判据：config_app.is_pc（在 sim_identity 覆盖 rtos.bsp 之前捕获，见 config_app 〇节）。
两种驱动均对外发布 NET_READY / NET_DISCONNECT，业务模块无需关心运行环境。
本模块无对外接口，直接 require "netdrv_device" 即加载运行。
]]

local config_app = require("config_app")

-- =========================================================================
-- 运行时自动探测运行环境，加载对应网卡驱动
-- 判据：使用 config_app.is_pc（在 sim_identity 覆盖 rtos.bsp 之前捕获；
--       官方 osapi/core/rtos.md：rtos.bsp() 在 PC 模拟器固定返回 "PC"）
-- =========================================================================
if config_app.is_pc then
    -- PC 模拟器环境：使用电脑网卡（socket.ETH0）
    log.info("netdrv_device", "检测到 PC 模拟器环境，加载 netdrv_pc（socket.ETH0）")
    require "netdrv_pc"
else
    -- 真机环境（Air8782P2 / Air780EPM）：使用 4G 网卡（socket.LWIP_GP）
    log.info("netdrv_device", "检测到真机环境，加载 netdrv_4g（socket.LWIP_GP）", rtos.bsp())
    require "netdrv_4g"
end
