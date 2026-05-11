-- nconv: var2-4 fn2-5 tag-short
--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2025.12.1
@author  江访
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；

对外接口：
1、tp_drv.init()：初始化触摸面板驱动
]]
--[[
初始化触摸面板驱动；

@api tp_drv.init()
@summary 配置并初始化GT911触摸控制器
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化触摸面板
local result = tp_drv.init()
if result then
    log.info("触摸面板初始化成功")
else
    log.error("触摸面板初始化失败")
end
]]
local tp_drv = {}
local rp = 3
local ip = 51

function tp_drv.init()
    gpio.setup(rp, 0) -- 设置GPIO4为输出模式，输出低电平
    gpio.close(rp)    -- 关闭GPIO4功能，恢复高阻态
    local iid = 1
    i2c.setup(iid)
    local r = tp.init("gt911", {
        port = iid,
        pin_rst = rp,
        pin_int = ip,
        int_type = 1,
        w = 1024,
        h = 600
    })
    log.info("tp", r)
    if _G.model_str:find("PC") then
        log.info("pc", "已启用鼠标点击功能")
    else
        if not r then
            log.error("ui", "触摸初始化失败")
        else
            -- 绑定触摸设备到AirUI输入设备
            airui.device_bind_touch(r)
            log.info("dev", "触摸初始化成功")
        end
    end
end

return tp_drv
