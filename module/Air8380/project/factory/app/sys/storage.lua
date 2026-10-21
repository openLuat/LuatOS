--[[
@module  storage
@summary 板载 SPI Flash 挂载与文件读写（little_flash / lf 核心库）
@version 1.0
@date    2026.10.20

用途：
1. 把板载 SPI Flash 挂载成 littlefs 文件系统（默认 /little_flash）；
2. 提供追加写运行日志（掉电不丢），供现场排障、售后回读；
3. 后续可把内置网页静态资源、升级包缓存放这里，避免占用脚本区。

设计原则：Flash 属于"增强能力"，挂载失败只告警、不阻塞主流程，
        设备没有外部 Flash 或型号暂不匹配时，4G/WiFi/网口/Web 仍要能正常工作。
]]

local board = require "board"

local M = {}

local mount_point = (board.flash and board.flash.mount) or "/little_flash"
local mounted = false
local dev = nil
local spi_dev_keep = nil     -- 必须长期持有：局部变量被 GC 后 SPI 设备失效，lf 读写会失败
local MAX_LOG_BYTES = 256 * 1024      -- 单个日志文件上限，超出后轮转
local LOG_NAME = "app.log"

local function log_path()
    return mount_point .. "/log/" .. LOG_NAME
end

-- 挂载文件系统
function M.mount()
    if not (board.flash and board.flash.enabled) then
        log.info("storage", "board.flash 未启用，跳过挂载")
        return false
    end
    if mounted then return true end

    local ok, err = pcall(function()
        -- 与 CH390H 共用 SPI1：先把 NAND 片选置高（失选），避免初始化瞬间被误选中
        gpio.setup(board.flash.cs, 1, gpio.PULLUP)
        -- SPI 设备：mode0、8bit、MSB
        -- NAND 只能半双工 2MHz，速率取 board.flash.spi_speed
        local spi_dev = spi.deviceSetup(board.spi.id, board.flash.cs,
            0, 0, 8, board.flash.spi_speed, spi.MSB, 1, 0)
        assert(spi_dev, "spi.deviceSetup 失败")
        spi_dev_keep = spi_dev          -- 保持引用，避免被 GC 回收
        dev = lf.init(spi_dev)
        assert(dev, "lf.init 失败")

        local ret = lf.mount(dev, mount_point)
        if ret ~= true and ret ~= 0 then
            error("lf.mount 返回 " .. tostring(ret))
        end
    end)
    if not ok then
        log.warn("storage", "Flash 挂载失败:", err)
        -- 首次使用或分区表变更时需要格式化，成功后再挂一次
        if board.flash.format_if_fail and dev and lf and lf.format then
            local fmt_ok, fmt_err = pcall(lf.format, dev)
            if fmt_ok then
                local m_ok, m_err = pcall(lf.mount, dev, mount_point)
                if m_ok then
                    mounted = true
                    log.info("storage", "格式化后挂载成功:", mount_point)
                    return true
                end
                log.warn("storage", "格式化后仍挂载失败:", m_err)
            else
                log.warn("storage", "格式化失败:", fmt_err)
            end
        end
        return false
    end

    -- 建日志目录（失败不影响挂载结论）
    pcall(function()
        if io and io.mkdir then io.mkdir(mount_point .. "/log") end
    end)
    mounted = true
    log.info("storage", "Flash 挂载成功:", mount_point)
    return true
end

function M.is_mounted() return mounted end

function M.capacity()
    -- 不同内核的容量接口不一致，这里只做尽力而为的查询，取不到就返回 nil
    if not mounted then return nil end
    return nil
end

-- 追加一行日志（自动加时间戳）；挂载失败时静默降级为纯串口日志
function M.log(tag, msg)
    if not mounted then return false end
    local line = string.format("%s [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(tag or "-"), tostring(msg or ""))
    local ok = pcall(function()
        local path = log_path()
        local size = io.fileSize(path) or 0
        if size > MAX_LOG_BYTES then os.remove(path) end
        local f = io.open(path, "a")
        if f then
            f:write(line)
            f:close()
        end
    end)
    return ok
end

-- ===================== 板载 Flash 固定值 =====================
-- 用途：平台下发指令读取，验证 Flash 挂载与读写通路
local FIXED_NAME = "fixed.txt"
local FIXED_DEFAULT = "1234567890"      -- 固定值内容，按需修改

local function fixed_path()
    return mount_point .. "/" .. FIXED_NAME
end

-- 首次使用写入固定值；文件已存在则不覆盖
function M.ensure_fixed(value)
    if not mounted then return false end
    local path = fixed_path()
    if (io.fileSize(path) or 0) > 0 then return true end
    local ok = pcall(function()
        local f = io.open(path, "w")
        if f then
            f:write(value or FIXED_DEFAULT)
            f:close()
        end
    end)
    return ok
end

-- 读回固定值；未挂载或未写入返回 nil
function M.get_fixed()
    if not mounted then return nil end
    local path = fixed_path()
    if (io.fileSize(path) or 0) <= 0 then return nil end
    local ok, data = pcall(io.readFile, path)
    if not ok or not data or #data == 0 then return nil end
    return data
end

function M.clear_log()
    if not mounted then return false end
    pcall(os.remove, log_path())
    return true
end

return M
