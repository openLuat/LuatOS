--[[
@module  fota_file
@summary 文件系统FOTA升级功能模块
@version 1.0
@date    2025.10.24
@author  孟伟
@usage
-- V1.1：
-- 更新TF/SD卡挂载方式，使用SPI挂载
-- V1.0：
-- 文件系统FOTA升级功能
-- 提供从文件系统直接读取升级包进行固件升级的功能
-- 可以使用luatools工具的烧录系统文件功能将升级包直接烧录到文件系统中，

本文件没有对外接口，直接在main.lua中require "fota_file"就可以加载运行；
]]


local function fileUpgradeTask()
    -- 等待系统稳定后再开始升级
    sys.wait(10000)
    -- 供电控制 (Air8101专用)
    --gpio13为8101TF卡的供电控制引脚，在挂载前需要设置为高电平，不能省略
    gpio.setup(13, 1)
    
    -- 在Air8101核心板上TF卡的的pin_cs为gpio3，spi_id为1.请根据实际硬件修改
    local spi_id, pin_cs = 1, 3
    spi.setup(spi_id, nil, 0, 0, 8, 2000000)
    --初始化后拉高pin_cs,准备开始挂载TF卡
    gpio.setup(pin_cs, 1)
    -- ########## 开始进行tf卡挂载 ##########
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
    if mount_ok then
        log.info("fatfs.mount", "挂载成功", mount_err)
        log.info("FOTA_FILE", "=== 开始文件系统升级 ===")
    else
        log.error("fatfs.mount", "挂载失败", mount_err)
        log.error("FOTA_FILE", "SD卡挂载失败，无法进行文件系统升级")
        -- 调用fota.finish(false)结束升级流程，参数false表示升级流程失败
        fota.finish(false)
        -- 尝试卸载（如果需要）
        fatfs.unmount("/sd")
        return
    end

    -- ########## 获取SD卡的可用空间信息并打印。 ########## 
    local data, err = fatfs.getfree("/sd")
    if data then
        --打印SD卡的可用空间信息
        log.info("fatfs", "getfree", json.encode(data))
    else
        --打印错误信息
        log.info("fatfs", "getfree", "err", err)
    end

    -- 步骤1: 初始化FOTA流程
    log.info("FOTA_FILE", "初始化FOTA...")
    if not fota.init() then
        log.error("FOTA_FILE", "FOTA初始化失败")
        return
    end

    -- 步骤2: 等待底层准备就绪
    log.info("FOTA_FILE", "等待底层准备...")
    -- while not fota.wait() do
    --     sys.wait(100)
    -- end
    log.info("FOTA_FILE", "底层准备就绪")

    -- 步骤3: 从文件系统读取升级包并启动升级
    local filePath = "/sd/update.bin"
    log.info("FOTA_FILE", "开始读取升级文件：", filePath)
    local result, isDone, cache = fota.file(filePath)
    log.info("FOTA_FILE", "升级文件写入flash中的fota分区结果", result, isDone, cache)

    -- 步骤4: 结束写入fota分区
    log.info("FOTA_FILE", "结束写入fota分区...")
    local result, isDone = fota.isDone()
    log.info("FOTA_FILE", "写入fota分区状态", "结果:", result, "完成:", isDone)
    if result then
        -- 步骤5: 处理写入结果
        if isDone then
            -- 升级文件成功写入flash中的fota分区，准备重启设备；
            -- 设备重启后，在初始化阶段的运行过程中会自动应用fota分区中的数据完成升级，最终升级结果可以通过观察日志中的版本号来区分。
            log.info("FOTA_FILE", "升级成功，准备重启设备")
            -- 调用fota.finish(true)结束升级流程，参数true表示正确走完流程。
            fota.finish(true)
            -- 可选：删除升级包文件
            -- os.remove("/update.bin")
            sys.wait(2000)
            rtos.reboot()
        else
            log.error("FOTA_FILE", "升级失败")
            -- -- 调用fota.finish(false)结束升级流程，参数false表示升级流程失败。
            fota.finish(false)
        end
    else
        log.error("FOTA_FILE", "升级失败：检查写入状态失败")
        -- -- 调用fota.finish(false)结束升级流程，参数false表示升级流程失败。
        fota.finish(false)
    end
end

-- 启动文件升级任务
sys.taskInit(fileUpgradeTask)
