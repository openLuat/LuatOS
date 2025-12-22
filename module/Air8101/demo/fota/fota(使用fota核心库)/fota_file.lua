--[[
@module  fota_file
@summary 文件系统FOTA升级功能模块
@version 1.0
@date    2025.10.24
@author  孟伟
@usage
-- 文件系统FOTA升级功能
-- 提供从文件系统直接读取升级包进行固件升级的功能
-- 可以使用luatools工具的烧录系统文件功能将升级包直接烧录到文件系统中，

本文件没有对外接口，直接在main.lua中require "fota_file"就可以加载运行；
]]


local function fileUpgradeTask()
    -- 等待系统稳定后再开始升级
    sys.wait(10000)
    gpio.setup(13, 1) -- TF卡供电控制（AIR8101专用）
    local mount_ok, mount_err = fatfs.mount(fatfs.SDIO, "/sd", 24 * 1000 * 1000)
    if mount_ok then
        log.info("fatfs.mount", "挂载成功", mount_err)
        local data, err = fatfs.getfree("/sd") -- 获取SD卡剩余空间信息
        if data then
            -- table: 若成功会返回table, 否则返回nil
            -- table 中包含 total_sectors（总扇区数量）, free_sectors（空闲扇区数量）, total_kb（总字节数,单位kb）, free_kb（空闲字节数, 单位kb）
            log.info("fatfs", "getfree", json.encode(data))
        else
            -- err: 导致失败的底层返回值
            log.info("fatfs", "err", err)
        end
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
