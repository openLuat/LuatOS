--[[
@module  air1601_pgfs_test
@summary Air1601 真机回归测试用例 (FTL 迁移验证)
@version 1.0.0
@date    2026-06-02

每个用例独立 setup/teardown, 不依赖用例执行顺序.
用例在 NOR flash (air1601 外部 SPI flash) 上验证:
  · 链接通过 (C 层改动没破坏 little_flash NOR 路径)
  · pgfs mount/IO 正常
  · CP 持久化/恢复 (umount → remount 后内容还在)
  · lf.pgfsctl 运行时控制 (lock_mode / powercut / bad_block_once / reset_runtime)
]]

local M = {}

-- ── constants ────────────────────────────────────────────────────
-- 按 bsp/air1601/README.md 验证过的 spi2 + cs4 + pwr50 组合
local SPI_BUS  = 2
local SPI_CS   = 4
local SPI_PWR  = 50
local SPI_SPEED = 2000000  -- 2 MHz, NOR flash 起步
local MOUNT_POINT = "/pgfs_regr"
local ERASE_BYTES = 0x8000  -- 抹 32 KB, 覆盖 SB+CP+FTL 状态区

-- ── helpers ──────────────────────────────────────────────────────

local function log_section(name)
    log.info("air1601.pgfs", "===== " .. name .. " =====")
end

local function setup_spi()
    if gpio and SPI_PWR then
        gpio.setup(SPI_PWR, 1, gpio.PULLUP)
    end
    sys.wait(50)
    local spi_dev = spi.deviceSetup(SPI_BUS, SPI_CS, 0, 0, 8, SPI_SPEED, spi.MSB, 1, 0)
    assert(spi_dev, "spi.deviceSetup failed (bus=" .. SPI_BUS .. ", cs=" .. SPI_CS .. ")")
    return spi_dev
end

local function setup_flash(spi_dev)
    local flash = lf.init(spi_dev)
    assert(flash, "lf.init failed - check SPI wiring / flash chip / pwr pin")
    return flash
end

-- 在干净 flash 上挂 pgfs, 失败返回 false
local function mount_pgfs(flash)
    -- 抹前 ERASE_BYTES, 清掉残留 SB/CP/FTL state
    if not lf.erase(flash, 0, ERASE_BYTES) then
        log.error("air1601.pgfs", "lf.erase(0, " .. ERASE_BYTES .. ") failed")
        return false
    end
    if not lf.mount(flash, MOUNT_POINT, 0, 0, "pgfs") then
        log.error("air1601.pgfs", "lf.mount(pgfs) failed")
        return false
    end
    return true
end

-- 用例可以调, 跑完后翻回干净状态
local function cleanup(flash)
    if lf.pgfsctl then
        -- 先 reset, 让 runtime 不再持有 mount 句柄
        pcall(lf.pgfsctl, "reset_runtime")
    end
    -- 再擦一次, 下个用例从干净 flash 开始
    if lf.erase then pcall(lf.erase, flash, 0, ERASE_BYTES) end
end

-- ── 1. lf.init + chip 探测 ───────────────────────────────────────

function M.test_lf_init()
    log_section("test_lf_init")
    local spi_dev = setup_spi()
    local flash = setup_flash(spi_dev)
    log.info("air1601.pgfs", "lf.init ok, flash=" .. tostring(flash))
    cleanup(flash)
    return true
end

-- ── 2. pgfs mount + fsstat ───────────────────────────────────────

function M.test_pgfs_mount()
    log_section("test_pgfs_mount")
    local spi_dev = setup_spi()
    local flash = setup_flash(spi_dev)

    if not mount_pgfs(flash) then
        cleanup(flash)
        return false
    end
    log.info("air1601.pgfs", "pgfs mounted at " .. MOUNT_POINT)

    local stat_ok, total, used, bsize, fstype = io.fsstat(MOUNT_POINT)
    if stat_ok then
        log.info("air1601.pgfs", string.format(
            "fsstat: total=%d used=%d block_size=%d fs=%s",
            total, used, bsize, tostring(fstype)))
    else
        log.warn("air1601.pgfs", "fsstat returned false (non-fatal)")
    end

    cleanup(flash)
    return true
end

-- ── 3. 基础 IO: 写读 round-trip ──────────────────────────────────

function M.test_basic_io()
    log_section("test_basic_io")
    local spi_dev = setup_spi()
    local flash = setup_flash(spi_dev)
    if not mount_pgfs(flash) then cleanup(flash) return false end

    local path = MOUNT_POINT .. "/hello.txt"
    -- 唯一 payload: 优先 mcu.ticks2 (高+低 32 bit), 回退 rtos.tick, 再不行用 os.time
    local function now64()
        if mcu and mcu.ticks2 then
            local hi, lo = mcu.ticks2(1)
            return tostring(hi) .. "_" .. tostring(lo)
        elseif rtos and rtos.tick then
            return tostring(rtos.tick())
        else
            return tostring(os.time() or 0)
        end
    end
    local payload = "air1601_pgfs_" .. now64()

    local f = io.open(path, "wb")
    if not f then
        log.error("air1601.pgfs", "io.open(wb) failed: " .. path)
        cleanup(flash)
        return false
    end
    f:write(payload)
    f:close()
    log.info("air1601.pgfs", "wrote " .. #payload .. " bytes to " .. path)

    local f2 = io.open(path, "rb")
    if not f2 then
        log.error("air1601.pgfs", "io.open(rb) failed: " .. path)
        cleanup(flash)
        return false
    end
    local got = f2:read("*a")
    f2:close()

    if got ~= payload then
        log.error("air1601.pgfs",
            string.format("content mismatch: got %d bytes, expected %d", #got, #payload))
        cleanup(flash)
        return false
    end
    log.info("air1601.pgfs", "round-trip ok, content matches")

    cleanup(flash)
    return true
end

-- ── 4. umount + remount, 内容还在 (CP 恢复) ──────────────────────

function M.test_reopen_recover()
    log_section("test_reopen_recover")
    local spi_dev = setup_spi()
    local flash = setup_flash(spi_dev)
    if not mount_pgfs(flash) then cleanup(flash) return false end

    local path = MOUNT_POINT .. "/recover.txt"
    local expected = "persist_payload_for_recovery_v1"

    local f = io.open(path, "wb")
    if not f then
        log.error("air1601.pgfs", "write failed before umount: " .. path)
        cleanup(flash)
        return false
    end
    f:write(expected)
    f:close()
    log.info("air1601.pgfs", "wrote " .. #expected .. " bytes (will remount then read)")

    -- 显式 reset_runtime 触发 umount + 重新 mount 周期
    if lf.pgfsctl then
        local r = lf.pgfsctl("reset_runtime")
        log.info("air1601.pgfs", "pgfsctl reset_runtime -> " .. tostring(r))
    end

    -- 重新挂载 (同 mount_point, 同 offset)
    if not lf.mount(flash, MOUNT_POINT, 0, 0, "pgfs") then
        log.error("air1601.pgfs", "remount failed after reset_runtime")
        cleanup(flash)
        return false
    end

    local f2 = io.open(path, "rb")
    if not f2 then
        log.error("air1601.pgfs", "open(rb) after remount failed: " .. path)
        cleanup(flash)
        return false
    end
    local got = f2:read("*a")
    f2:close()

    if got ~= expected then
        log.error("air1601.pgfs",
            string.format("recovery mismatch: got %d bytes, expected %d", #got, #expected))
        cleanup(flash)
        return false
    end
    log.info("air1601.pgfs", "reopen recovery ok, content matches after umount/remount")

    cleanup(flash)
    return true
end

-- ── 5. lf.pgfsctl lock_mode ──────────────────────────────────────

function M.test_pgfsctl_lock()
    log_section("test_pgfsctl_lock")
    if not lf.pgfsctl then
        log.warn("air1601.pgfs", "lf.pgfsctl not available, skip")
        return true
    end
    local r1 = lf.pgfsctl("lock_mode", "on")
    log.info("air1601.pgfs", "lock_mode on -> " .. tostring(r1))
    local r2 = lf.pgfsctl("lock_mode", "off")
    log.info("air1601.pgfs", "lock_mode off -> " .. tostring(r2))
    if not r1 or not r2 then
        log.error("air1601.pgfs", "lock_mode toggle returned false")
        return false
    end
    return true
end

-- ── 6. lf.pgfsctl powercut_stage ─────────────────────────────────

function M.test_pgfsctl_powercut()
    log_section("test_pgfsctl_powercut")
    if not lf.pgfsctl then
        log.warn("air1601.pgfs", "lf.pgfsctl not available, skip")
        return true
    end
    local r1 = lf.pgfsctl("powercut_stage", "before_cp")
    log.info("air1601.pgfs", "powercut_stage before_cp -> " .. tostring(r1))
    if not r1 then
        log.error("air1601.pgfs", "powercut_stage returned false")
        return false
    end
    -- 立即 reset, 避免污染后续用例 (powercut 注入会让后续 fclose 失败)
    local r2 = lf.pgfsctl("reset_runtime")
    log.info("air1601.pgfs", "reset_runtime after powercut -> " .. tostring(r2))
    return true
end

-- ── 7. lf.pgfsctl bad_block_once (NOR 上是 no-op) ────────────────

function M.test_pgfsctl_badblock()
    log_section("test_pgfsctl_badblock")
    if not lf.pgfsctl then
        log.warn("air1601.pgfs", "lf.pgfsctl not available, skip")
        return true
    end
    local r1 = lf.pgfsctl("bad_block_once", true)
    log.info("air1601.pgfs", "bad_block_once on -> " .. tostring(r1))
    if not r1 then
        log.error("air1601.pgfs", "bad_block_once returned false")
        return false
    end
    -- 关掉 inject, 避免污染
    lf.pgfsctl("bad_block_once", false)
    lf.pgfsctl("reset_runtime")
    return true
end

-- ── 8. lf.pgfsctl reset_runtime ──────────────────────────────────

function M.test_pgfsctl_reset()
    log_section("test_pgfsctl_reset")
    if not lf.pgfsctl then
        log.warn("air1601.pgfs", "lf.pgfsctl not available, skip")
        return true
    end
    local r = lf.pgfsctl("reset_runtime")
    log.info("air1601.pgfs", "reset_runtime -> " .. tostring(r))
    return r ~= nil and r ~= false
end

return M
