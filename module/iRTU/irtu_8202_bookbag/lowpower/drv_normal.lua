--[[
@module  drv_normal
@summary 常规模式pm.power(pm.WORK_MODE, 0)驱动配置功能模块
@version 1.0
@date    2026.03.17
@author  孟伟
@usage
本文件为 Air8201 项目常规模式pm.power(pm.WORK_MODE, 0)驱动配置功能模块。
Air8201 项目常规模式特点：
- 适用于寻宠模式（DEVICE_MODE.FIND）和智能模式（DEVICE_MODE.SMART）
- 需要保持较高的定位频率和响应速度
- 传感器和蓝牙功能保持开启
- 支持GPS、WiFi、LBS多源定位

对外接口：
sys.subscribe("DRV_SET_NORMAL", set_drv_normal)：订阅"DRV_SET_NORMAL"消息；
其他应用模块如果需要配置常规模式，直接sys.publish("DRV_SET_NORMAL")即可；
]]

-- 获取当前使用的模组型号
local module = hmeta.model()

log.info("drv_normal", "当前使用的模组是：", module)

local function normal_task()
    log.info("drv_normal", "进入常规模式任务")

    -- 配置最低功耗模式为常规模式
    pm.power(pm.WORK_MODE, 0)
    
    log.info("drv_normal", "常规模式配置完成")
end

local function set_drv_normal()
    sys.taskInit(normal_task)
end

sys.subscribe("DRV_SET_NORMAL", set_drv_normal)
