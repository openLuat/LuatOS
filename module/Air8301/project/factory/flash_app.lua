--[[
@module  flash_app
@summary SPI Flash挂载管理（8301出厂固件）
@version 1.0
@date    2026.09.24
@author  江访
@usage
SPI1/CS2=GPIO4 外部SPI NOR Flash。
使用 lf 库初始化和挂载 Flash 为文件系统。
- 发布 FLASH_MOUNT_STATUS(mounted, total_kb, used_kb, capacity_kb)
- 响应 REQUEST_STATUS_REFRESH 重新查询
- require 即启动挂载协程，无对外接口

说明：Air8301 硬件上 Flash 与双 CH390 共用 SPI1 总线，CH390 未初始化时会下拉
共享 CLK/MISO/MOSI，导致 Flash 读 JEDEC ID 失败。因此挂载必须等待 NETWORK_INIT_DONE。

⚠️ 产测模式已禁用开机自动挂载（IS_FACTORY_MODE == true）：SPI1 同一时间只能一个设备用，
开机即挂载会在 CH390 联网期间抢总线，且 CH390 停止/重启会重配 SPI1 把挂载打掉。
产测模式下 Flash 改由 prod_test.lua 的 FLASH_TEST 指令按需 初始化/挂载/写读/卸载（自包含）。
业务模式（IS_FACTORY_MODE ~= true）保持原有开机自动挂载行为不变。

因此本版本把「页面驱动的 Flash 查询」改为「缓存驱动」：
  - FLASH_MOUNT_STATUS 的结果缓存到内存（cache_*）
  - REQUEST_STATUS_REFRESH 只重发缓存，零 I/O（不再访问 SPI NAND）
  - 真实查询（io.fsstat）只在开机挂载后执行一次；后续如需重查，走内部查询协程
    并按 QUERY_MIN_INTERVAL_MS 节流，避免与网卡频繁争抢 SPI1
消息接口（FLASH_MOUNT_STATUS / REQUEST_STATUS_REFRESH）保持完全不变。
]]

local FLASH_MOUNT_POINT = "/flash"
local FLASH_SPI_CS = 4           -- SPI1_CS2 = GPIO4
local FLASH_SPI_ID = 1           -- SPI1
local FLASH_SPI_SPEED = 25600000 -- 25.6MHz

local flash_mounted = false
local flash_capacity_kb = 0   -- Flash 芯片总容量(KB)，由 lf.getInfo 获取，与文件系统可用容量无关

-- ===== 状态缓存（页面请求只重发缓存，绝不触发 SPI 访问）=====
local cache_valid = false                                  -- 缓存是否已产生过有效结果
local cache_mounted, cache_total_kb, cache_used_kb = false, 0, 0

-- ===== 真实查询节流（避免与 CH390 网卡频繁争抢 SPI1）=====
local QUERY_MIN_INTERVAL_MS = 5000                         -- 两次真实查询的最小间隔(ms)
local last_query_ms = 0

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
    -- 写入缓存：后续页面请求可直接复用，无需再访问 SPI NAND
    cache_valid = true
    cache_mounted = mounted
    cache_total_kb = total_kb or 0
    cache_used_kb = used_kb or 0
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
    -- 注意: 使用默认 lfs2 文件系统(不带 opts)
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
内部真实查询协程：按需执行 io.fsstat（含 SPI NAND 访问），并做节流。

为什么放进独立协程：
  1) io.fsstat 是同步阻塞调用，放在 sys.publish 的订阅回调里会阻塞整个事件循环；
  2) SPI1 上 Flash 与双 CH390H 共用总线，查询越频繁与网卡冲突的概率越高，
     因此用 QUERY_MIN_INTERVAL_MS 限流（页面反复开关也只按最低频率真正查询）。

@local
@function flash_query_task
]]
local function flash_query_task()
    while true do
        sys.waitUntil("FLASH_QUERY_INTERNAL")
        local now = mcu.ticks() or 0
        if now - last_query_ms >= QUERY_MIN_INTERVAL_MS then
            last_query_ms = now
            publish_mount_status()
        end
    end
end
sys.taskInit(flash_query_task)

--[[
REQUEST_STATUS_REFRESH 订阅回调：重发缓存状态（零 I/O）

页面（系统信息 / Flash 存储 / 系统分区页）打开或获得焦点时会请求刷新。
本回调**只**重发内存缓存，绝不访问 SPI NAND，因此不会与 CH390 网卡争抢 SPI1。
仅当缓存尚未就绪（开机查询未完成）时，才向内部查询协程投递一次真实查询。

@local
@function on_status_refresh
]]
local function on_status_refresh()
    if cache_valid then
        sys.publish("FLASH_MOUNT_STATUS", cache_mounted, cache_total_kb, cache_used_kb, flash_capacity_kb)
    else
        -- 缓存未就绪：异步投递真实查询（不阻塞本次事件回调）
        sys.publish("FLASH_QUERY_INTERNAL")
    end
end

sys.subscribe("REQUEST_STATUS_REFRESH", on_status_refresh)

-- 按运行模式决定是否开机自动挂载：
--   业务模式（IS_FACTORY_MODE ~= true）→ 保持原行为，开机自动挂载 /flash
--   产测模式（IS_FACTORY_MODE == true）→ 跳过自动挂载，由 prod_test 的 FLASH_TEST 指令按需挂载
--     （SPI1 上 Flash 与双 CH390 三设备互斥，开机挂载会与 CH390 抢总线导致读写失败）
if IS_FACTORY_MODE then
    log.info("flash_app", "产测模式: 跳过开机自动挂载, /flash 由 FLASH_TEST 指令按需挂载")
else
    sys.taskInit(flash_mount_task)
end
