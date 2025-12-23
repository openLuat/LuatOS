--[[
@module  ht1621_drv
@summary HT1621段码屏驱动模块 - 仅初始化
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为HT1621段码屏驱动初始化模块，仅包含初始化功能：
1、初始化ht1621液晶屏
2、返回seg对象供其他模块使用

本文件的对外接口有：
1、ht1621_drv.init()：初始化HT1621驱动并返回seg对象
]] 

local ht1621_drv = {}

--[[
初始化HT1621驱动
@api ht1621_drv.init()
@summary 初始化HT1621液晶屏
@return table seg对象，初始化成功返回seg，失败返回nil
@usage
seg = ht1621_drv.init()
if seg then
    log.info("HT1621驱动初始化成功")
end
]] 
function ht1621_drv.init()
    -- 初始化HT1621 (CS=22, DATA=24, WR=1)
    seg = ht1621.setup(22, 24, 1)
    
    if not seg then
        log.error("ht1621_drv", "HT1621初始化失败")
        return nil
    end
    
    -- 打开LCD显示
    ht1621.lcd(seg, true)

    -- 清屏
    for i = 0, 11 do
        ht1621.data(seg, i, 0x00)
    end
    
    log.info("ht1621_drv", "HT1621初始化完成")
    return seg
end

return ht1621_drv