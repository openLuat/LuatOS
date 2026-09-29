--[[
@module  netdrv_device
@summary 网络驱动设备选择模块
@version 1.0
@date    2026.09.27
@author  王世豪
@usage
8784 出厂固件业务模式使用 4G 网卡，加载 netdrv_4g 完成网络适配。
8784 硬件只有 4G，故官方 netdrv_device 的其余选项（netdrv_wifi / netdrv_eth_spi /
netdrv_multiple / netdrv_pc）本项目均不加载。
本文件没有对外接口，在 app_main.lua 中 require 即可加载运行。
]]

-- 加载“4G网卡”驱动模块
require "netdrv_4g"
