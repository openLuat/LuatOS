--[[
@module  netdrv_device
@summary 网络驱动设备功能模块
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
本文件为网络驱动设备功能模块，核心业务逻辑为：根据项目需求，选择并且配置合适的网卡(网络适配器)
1、netdrv_4g：socket.LWIP_GP，4G网卡；
2、netdrv_pc：pc模拟器上的网卡

注意：Air8201H 整机板，未引出 SPI 接口，无法外挂 SPI 以太网卡，
因此不支持 netdrv_eth_spi(SPI以太网卡) 和 netdrv_multiple(以太网+4G多网卡)两种方式，
仅可使用 4G 网卡(或 pc 模拟器网卡)。如需以太网联网请使用 Air8201G。

根据自己的项目需求，只需要require以上两种中的一种即可；


本文件没有对外接口，直接在main.lua中require "netdrv_device"就可以加载运行；
]]


-- 根据自己的项目需求，只需要require以下两种中的一种即可；

-- 加载“4G网卡”驱动模块
require "netdrv_4g"

-- 加载“pc模拟器网卡”驱动模块
-- require "netdrv_pc"
