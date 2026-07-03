--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.07.24
@author  马梦阳
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_4g：socket.LWIP_GP，4G网卡；

注意：Air8201H 基于 Air780EHM 模组，未引出 SPI 接口，无法外挂 SPI 以太网卡，
因此不支持 netdrv_eth_spi(SPI以太网卡) 和 netdrv_multiple(以太网+4G多网卡)两种方式，
仅可使用 4G 网卡。如需以太网联网请使用 Air8201G。

本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]


-- 加载“4G网卡”驱动模块
require "netdrv_4g"
