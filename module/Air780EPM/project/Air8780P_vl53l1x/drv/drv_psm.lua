--[[
@module  drv_psm
@summary PSM+模式（pm.power WORK_MODE 3）驱动配置功能模块
@version 1.0
@date    2026.07.23
@author  江访
@usage
本文件为PSM+模式驱动配置功能模块，提供了PSM+模式的配置模板，包括以下几点：
1、在进入PSM+模式前，配置深度休眠定时器（dtimer），设定唤醒时间
2、提供进入PSM+模式的入口函数，包括pm.power(pm.WORK_MODE, 3)、等待和重启兜底
3、在进入PSM+模式前，可以根据实际项目需求配置其他功能引脚

PSM+模式说明：
1、pm.power(pm.WORK_MODE, 3)配置后，并不会立即进入休眠
2、等所有协程都处于阻塞状态时，才会自动进入PSM+模式
3、进入PSM+模式后，RAM掉电，不执行任何脚本代码
4、RTC定时器到达或外部中断唤醒后，系统冷启动

本文件的对外接口只有1个：
1、sys.subscribe("DRV_SET_PSM", set_drv_psm)：订阅"DRV_SET_PSM"消息；
其他模块如果需要进入PSM+模式，先发布"DRV_SET_PSM"消息，然后阻塞本task即可。
]]

-- ==================== PSM+入口主函数 ====================

--[[
PSM+模式任务函数

订阅DRV_SET_PSM消息后，在task协程中执行此函数。
函数流程：
1、配置深度休眠定时器（设定唤醒时间）
2、调用pm.power(pm.WORK_MODE, 3)进入PSM+模式
3、等待80秒——如果未成功进入PSM+，强制重启

注意：
1、必须在调用前关闭所有外设（传感器等）
2、必须在调用前拉低LED
3、进入PSM+前需要先配置好深度休眠定时器dtimer
4、PSM+模式下，所有引脚状态保持进入前的电平

@param number sleep_min_s PSM+休眠时间（分钟）
]]
local function psm_task(sleep_min_s)
    log.info("drv_psm", "进入PSM+模式，休眠" .. sleep_min_s .. "分钟后唤醒")

    -- 设置RTC深度休眠定时器
    -- pm.dtimerStart(id, ms)
    -- id=0表示使用定时器0，到达时间后系统自动唤醒
    -- 此处的时长不要小于80秒
    local sleep_ms = sleep_min_s * 60 * 1000
    pm.dtimerStart(0, sleep_ms)
    log.info("drv_psm", "深度休眠定时器已设置:", sleep_ms, "ms")

    -- 在进入PSM+模式前，可以根据实际项目需求配置以下功能项：
    -- 1、飞行模式：PSM+模式下飞行模式自动开启，无需手动操作
    -- 2、USB功能：内核固件已自动关闭USB功能（2025年3月后版本）
    -- 3、AGPIO配置：根据硬件设计配置GPIO24~28的电平状态
    -- 详情可参考 lowpower/drv/drv_psm.lua 中的 set_psm_func_item()

    -- 配置最低功耗模式为PSM+模式
    -- pm.power(pm.WORK_MODE, 3)表示允许系统进入PSM+模式
    -- 执行后不会立即进入休眠，等所有协程阻塞后自动进入
    pm.power(pm.WORK_MODE, 3)

    -- 等待80秒：给内核固件足够时间进入PSM+
    -- 如果成功进入PSM+，此后的代码不会执行（RAM掉电）
    -- 如果没有进入（例如有协程未阻塞），80秒后强制重启
    sys.wait(80000)
    log.info("drv_psm", "进入PSM+失败，重启")
    rtos.reboot()
end

-- ==================== 事件处理 ====================

--[[
DRV_SET_PSM 事件处理函数

其他模块通过 sys.publish("DRV_SET_PSM", sleep_min_s) 触发：
    sleep_min_s参数为休眠时间（分钟）

注意：本订阅处理函数使用sys.taskInit创建独立协程执行psm_task
这是因为pm.power和内部sys.wait需要在协程中运行
]]
local function set_drv_psm(sleep_min_s)
    sys.taskInit(psm_task, sleep_min_s or 15)
end

-- ==================== 事件订阅 ====================

sys.subscribe("DRV_SET_PSM", set_drv_psm)

log.info("drv_psm", "模块已加载，等待DRV_SET_PSM消息")
