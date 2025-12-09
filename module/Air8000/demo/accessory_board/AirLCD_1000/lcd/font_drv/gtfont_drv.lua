--[[
@module  gtfont_drv
@summary GTFont矢量字库驱动模块
@version 1.0
@date    2025.12.3
@author  江访
@usage
本模块为GTFont矢量字库驱动功能模块，主要功能包括：
1、初始化AirFONTS_1000矢量字库小板的SPI接口；
2、配置SPI通信参数和设备对象；
3、初始化矢量字库核心功能；


说明：
1、gtfont核心库演示demo，是使用gtfont核心库来驱动合宙AirFONTS_1000矢量字库小板
2、在主程序mian.lua中require "gtfont_drv"即可执行加载本demo内的演示代码
3、通过使用gtfont_drv.init()对合宙AirFONTS_1000矢量字库小板进行初始化
4、通过使用 lcd.drawGtfontUtf8Gray(str,size,gray,x,y)接口在lcd屏幕上灰度显示 UTF8 字符串，支持10-192号字体
-- 在main.lua中require本模块即可自动初始化
require "gtfont_drv"
]]

--[[
初始化AirFONTS_1000矢量字库小板；
配置SPI接口和矢量字库；

@api init()
@summary 初始化AirFONTS_1000矢量字库小板
@return bool 成功返回true，失败返回false
@usage

]]
local function init()
    --创建一个SPI设备对象
    gtfont_spi = spi.deviceSetup(1 , 12, 0, 0, 8, 20*1000*1000, spi.MSB, 1, 0)
    log.error("AirFONTS_1000.init", "spi.deviceSetup", type(gtfont_spi))
    --检查SPI设备对象是否创建成功
    if type(gtfont_spi) ~= "userdata" then
        log.error("AirFONTS_1000.init", "spi.deviceSetup error", type(gtfont_spi))
    end

    --初始化矢量字库
    if not gtfont.init(gtfont_spi) then
        log.error("gtfont_drv.init", "gtfont_drv.init error")
    end

end

init()