--[[
@module  flash_app
@summary SPI Flash挂载管理
@version 2.0
@date    2026.08.04
@author  江访
@usage
SPI1/CS2=GPIO4 外部SPI NOR Flash。
使用 lf 库初始化和挂载 Flash 为文件系统。
- 发布 FLASH_MOUNT_STATUS(mounted, total_kb, used_kb, capacity_kb)
- 响应 REQUEST_STATUS_REFRESH 重新查询
- require 即启动挂载协程，无对外接口

说明：Air8301 硬件上 Flash 与双 CH390 共用 SPI1 总线，CH390 未初始化时会下拉
共享 CLK/MISO/MOSI，导致 Flash 读 JEDEC ID 失败。因此挂载必须等待 NETWORK_INIT_DONE。
]]

local FLASH_MOUNT_POINT = "/flash"
local FLASH_SPI_CS = 4           -- SPI1_CS2 = GPIO4
local FLASH_SPI_ID = 1           -- SPI1
local FLASH_SPI_SPEED = 25600000 -- 25.6MHz

local flash_mounted = false
local flash_capacity_kb = 0   -- Flash 芯片总容量(KB)，由 lf.getInfo 获取，与文件系统可用容量无关

--[[
查询文件系统状态（挂载后）

@local
@function query_fs_status
@return boolean 是否已挂载
@return number 文件系统总容量KB
@return number 文件系统已用KB
]]
local function query_fs_status()
    if not flash_mounted then
        return false, 0, 0
    end

    -- io.fsstat 返回多个值: success, total_blocks, used_blocks, block_size, fs_type
    local success, total_blocks, used_blocks, block_size = io.fsstat(FLASH_MOUNT_POINT)
    if success then
        total_blocks = total_blocks or 0
        used_blocks = used_blocks or 0
        block_size = block_size or 0
        local total_kb = (total_blocks * block_size) / 1024
        local used_kb = (used_blocks * block_size) / 1024
        return true, total_kb, used_kb
    end

    return false, 0, 0
end

--[[
发布挂载状态消息：FLASH_MOUNT_STATUS(mounted, total_kb, used_kb, capacity_kb)

@local
@function publish_mount_status
]]
local function publish_mount_status()
    local mounted, total_kb, used_kb = query_fs_status()
    sys.publish("FLASH_MOUNT_STATUS", mounted, total_kb, used_kb, flash_capacity_kb)
end

--[[
挂载 Flash 协程（require 后自动启动，含多个 sys.wait 延时）：
等待网卡就绪 → spi 初始化 → lf 初始化 → 挂载 /flash → 查询容量 → 发布状态

@local
@function flash_mount_task
]]
local function flash_mount_task()
    log.info("flash_app", "mounting flash at", FLASH_MOUNT_POINT)

    -- 等待 CH390 网卡初始化完成(收到 NETWORK_INIT_DONE 消息)
    -- 原因: Air8301 硬件上 Flash 与双 CH390 共用 SPI1 总线, CH390 芯片在供电但未初始化时
    --       会下拉共享的 CLK/MISO/MOSI 信号, 导致 Flash 读 JEDEC ID 失败
    -- 若 network_app 被注释(未发布消息), 则等待 3 秒超时后仍尝试挂载
    sys.waitUntil("NETWORK_INIT_DONE", 3000)

    -- 使用 lf 库初始化和挂载 SPI Flash
    -- 先初始化 SPI Flash 设备
    local spi_flash_id = spi.deviceSetup(FLASH_SPI_ID, FLASH_SPI_CS, 0, 0, 8, FLASH_SPI_SPEED, spi.MSB, 1, 0)
    if not spi_flash_id then
        log.warn("flash_app", "spi device setup failed")
        publish_mount_status()
        return
    end

    -- 初始化 littlefs 设备 (SFDP header not found 对 NAND 是正常现象, 不影响挂载)
    local flash_dev = lf.init(spi_flash_id)
    if not flash_dev then
        -- CH390 初始化瞬间可能仍干扰 SPI 总线, 重试一次
        log.warn("flash_app", "lf.init failed, retry after 2s...")
        sys.wait(2000)
        flash_dev = lf.init(spi_flash_id)
        if not flash_dev then
            log.warn("flash_app", "lf.init retry failed")
            publish_mount_status()
            return
        end
    end

    -- 挂载文件系统
    -- 注意: 使用默认 lfs2 文件系统(不带 opts), 与官方 AirSPINAND demo 一致
    -- 不要传 "pgfs"/"pgfs_format", 前者需要固件编译 LUAT_USE_PGFS_COMPONENT 才支持,
    -- 后者不是合法选择器, 都会导致挂载失败
    local ok = lf.mount(flash_dev, FLASH_MOUNT_POINT)
    if not ok then
        log.warn("flash_app", "mount failed, retry once...")
        ok = lf.mount(flash_dev, FLASH_MOUNT_POINT)
        if not ok then
            log.error("flash_app", "mount retry failed")
            publish_mount_status()
            return
        end
    end

    flash_mounted = true
    log.info("flash_app", "mount success at", FLASH_MOUNT_POINT)

    -- 打印 Flash 芯片容量信息 (lf.getInfo 返回: 总容量, 编程页大小, 擦除块大小, 单位字节)
    local capacity, prog_size, erase_size = lf.getInfo(flash_dev)
    if capacity then
        flash_capacity_kb = capacity / 1024
        log.info("flash_app", string.format("Flash容量: %.2f MB (%d bytes), 页大小: %d, 块大小: %d",
            capacity / 1024 / 1024, capacity, prog_size, erase_size))
    end

    -- 打印文件系统实际可用容量 (io.fsstat 返回: success, 总块数, 已用块数, 块大小, 类型)
    local ok2, total_blocks, used_blocks, block_size, fs_type = io.fsstat(FLASH_MOUNT_POINT)
    if ok2 then
        local total_kb = (total_blocks * block_size) / 1024
        local used_kb = (used_blocks * block_size) / 1024
        local free_kb = total_kb - used_kb
        log.info("flash_app", string.format("文件系统: 总容量 %.2f MB, 已用 %.2f MB, 可用 %.2f MB, 类型 %s",
            total_kb / 1024, used_kb / 1024, free_kb / 1024, fs_type or "lfs2"))
    end

    publish_mount_status()
end

--[[
REQUEST_STATUS_REFRESH 订阅回调：重新查询并发布挂载状态（页面打开时主动拉取）

@local
@function on_status_refresh
]]
local function on_status_refresh()
    publish_mount_status()
end

sys.subscribe("REQUEST_STATUS_REFRESH", on_status_refresh)

sys.taskInit(flash_mount_task)
