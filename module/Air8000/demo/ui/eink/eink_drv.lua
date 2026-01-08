--[[
@module  eink_drv
@summary eink墨水屏显示驱动模块，基于eink核心库
@version 1.0
@date    2025.12.18
@author  江访
@usage
本模块为eink墨水屏显示驱动功能模块，主要功能包括：
1、初始化微雪1.54寸墨水屏(eink.MODEL_1in54_V2)；
2、配置SPI通信参数和设备对象；

本文件无对外接口,require "eink_drv"即可加载运行
]]


--[[
初始化eink显示驱动；

@api eink_drv.init()
@summary 配置并初始化微雪1.54寸墨水屏
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化eink显示
local result = eink_drv.init()
if result then
    log.info("eink初始化成功")
else
    log.error("eink初始化失败")
end
]]

local function eink_drv_init()
    -- 按接线引脚正确配置GPIO号
    local spi_id = 1
    local pin_busy = 16
    local pin_reset = 17
    local pin_dc = 1
    local pin_cs = 2

    -- 开启异步刷新
    eink.async(1)

    -- 注意:eink初始化之前需要先初始化spi，使用spi对象方式初始化
    spi_eink = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 1)

    -- 初始化接到spi0的eink.MODEL_1in54_V2
    eink.init(eink.MODEL_1in54_V2,
        { port = "device", pin_dc = pin_dc, pin_busy = pin_busy, pin_rst = pin_reset },
        spi_eink)

    -- 设置显示窗口和方向
    eink.setWin(200, 200, 0)
    eink.clear(1, true)

    log.info("eink_drv.init")
end

eink_drv_init()
