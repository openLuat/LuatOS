--[[
@module  sdcard_mount_app
@summary SD卡挂载功能模块
@version 1.1
@date    2026.03.06
@author  拓毅恒
@usage
SD卡挂载功能模块
功能：等待网络连接成功后挂载SD卡，为摄像头控制功能提供基础环境。

特性：
- 支持Air8101核心板的SD卡挂载
- 自动检测网络连接状态
- 提供SD卡空间信息查询

本文件没有对外接口，直接在main.lua中require "sdcard_mount_app"就可以加载运行。
]]

-- 挂载SD卡
local function sdcard_mount_task()
    -- 等待网络就绪事件
    sys.waitUntil("NET_CONNECT_OK")

    -- 供电控制 (Air8101专用)
    -- gpio13为8101TF卡的供电控制引脚，在挂载前需要设置为高电平，不能省略
    gpio.setup(13, 1)
    
    -- 在Air8101核心板上TF卡的的pin_cs为gpio3，spi_id为1.请根据实际硬件修改
    local spi_id, pin_cs = 1, 3
    spi.setup(spi_id, nil, 0, 0, 400 * 1000)
    -- 初始化后拉高pin_cs,准备开始挂载TF卡
    gpio.setup(pin_cs, 1)
    -- 开始进行tf卡挂载
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
    if mount_ok then
        log.info("fatfs.mount", "挂载成功", mount_err)
    else
        log.error("fatfs.mount", "挂载失败", mount_err)
        return false
    end

    -- 获取SD卡的可用空间信息并打印
    local data, err = fatfs.getfree("/sd")
    if data then
        --打印SD卡的可用空间信息
        log.info("fatfs", "getfree", json.encode(data))
    else
        -- 打印错误信息
        log.info("fatfs", "getfree", "err", err)
        return false
    end
end

sys.taskInit(sdcard_mount_task)