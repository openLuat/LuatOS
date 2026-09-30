--[[
@module  sd_card
@summary TF/SD 卡挂载与文件保存（Air8602 寄存柜）
@version 1.0
@date    2026.09.29
@usage
    local sd_card = require "sd_card"
    sd_card.init()                          -- 挂载（需在 task 中调用；失败自动回退 /ram）
    local p = sd_card.path("cabinet.csv")   -- 返回实际可用保存路径
    sd_card.write(p, data)                  -- 写文件（data 为字符串）

说明：
1. SD_EN = GPIO74（高电平使能 SD 卡供电）。
   注意：GPIO65 已用作 485 方向脚（见 config.rs485.pin / uart_controller.lua），不可再用于 SD_EN。
2. SD 卡走 SPI1，CS0 = GPIO8（全型号通用）。
3. 挂载失败自动回退到 /ram，功能不中断（日志会提示）。
4. 挂载失败后有冷却（config.sd.retry_interval，默认 5 分钟）：冷却期内再调用 init() 直接返回，
   不再碰底层 —— 否则每个模块每次写文件都会重跑 3 轮挂载，把 SPI_TF/fatfs 日志刷满。
   整机不配 TF 卡时可把 config.sd.enabled 设为 false，一次都不试。
5. 以上引脚可由 config.sd 覆盖。
]]

local sd_card = {}

local config = require "config"

-- 挂载参数（可由 config.sd 覆盖）
local function load_cfg()
    local c = config.get("sd", {})
    return {
        enabled     = (c.enabled ~= false),          -- 是否尝试挂载（整机不配 TF 卡时设 false，一次都不试）
        spi_id      = c.spi_id or 1,                 -- SPI 接口 ID
        pin_cs      = c.pin_cs or 8,                 -- 片选 CS 引脚（CS0 = GPIO8）
        pin_en      = c.pin_en or 74,                -- SD_EN 供电使能引脚（高有效）
        init_speed  = c.init_speed or 400 * 1000,    -- 挂载前低速 400kHz
        speed       = c.speed or 24 * 1000 * 1000,   -- 挂载后工作频率 24MHz
        mount_point = c.mount_point or "/sd",        -- 挂载点
        fallback    = c.fallback or "/ram",          -- 回退目录
        retry_interval = c.retry_interval or 300000, -- 挂载失败后的冷却(ms)：这段时间内不再重复尝试
    }
end

local mounted = false      -- 是否真实挂载到 SD 卡
local inited = false       -- 是否已执行过挂载流程
local fail_ts = 0          -- 上次挂载失败时刻(ms)，用于失败冷却

-- 当前是否处于"不可用"状态（已尝试过且未挂载成功）
function sd_card.is_unavailable()
    return inited and not mounted
end

-- 挂载 SD 卡（失败回退 /ram；需在 task 中调用）
-- @param force 可选，true 时忽略失败冷却，强制再试一次
function sd_card.init(force)
    local cfg = load_cfg()
    if inited and mounted then return true end

    -- 整机不配 TF 卡：直接不试，避免底层反复打 SPI_TF / fatfs 日志
    if not cfg.enabled then
        if not inited then
            inited = true
            log.warn("sd_card", "SD 卡已在 config.sd.enabled=false 关闭，记录写入 " .. cfg.fallback)
        end
        return false
    end

    -- 失败冷却：无卡/卡异常时，底层每次 mount 都会打十几行 SPI_TF+fatfs 日志，而本项目多个模块
    --   （如 event_reporter 每次取日志目录）都会调用 init() —— 冷却期内直接返回，不再碰底层。
    if inited and not force and fail_ts > 0 then
        local elapsed = mcu.ticks() - fail_ts
        if elapsed >= 0 and elapsed < cfg.retry_interval then
            return false
        end
    end
    inited = true

    -- 1) SD 供电使能（高电平）
    gpio.setup(cfg.pin_en, 0)
    gpio.setup(cfg.pin_en, 1, gpio.PULLUP)
    sys.wait(300)   -- 等待卡供电稳定

    -- 2) SPI 低速初始化，片选拉高
    if not pcall(spi.setup, cfg.spi_id, nil, 0, 0, 8, cfg.init_speed) then
        log.warn("sd_card", "spi.setup 失败，SD 卡不可用")
    end
    pcall(gpio.setup, cfg.pin_cs, 1)

    -- 3) 挂载，失败则断电重启卡再重试
    local ok = false
    local last_err = nil
    for retry = 1, 3 do
        local pok, mok, merr = pcall(fatfs.mount, fatfs.SPI, cfg.mount_point,
                                     cfg.spi_id, cfg.pin_cs, cfg.speed)
        if pok and mok then
            ok = true
            log.info("sd_card", "SD 卡挂载成功" .. (retry > 1 and ("（第" .. retry .. "次）") or ""), cfg.mount_point)
            break
        end
        last_err = pok and merr or mok
        if retry < 3 then
            gpio.setup(cfg.pin_en, 0)
            sys.wait(200)
            gpio.setup(cfg.pin_en, 1, gpio.PULLUP)
            sys.wait(300)
        end
    end

    mounted = ok
    if not ok then
        fail_ts = mcu.ticks()
        -- 只打一条汇总日志：底层 SPI_TF/fatfs 的细节日志（E/SPI_TF cmd 0 … -6 / mount failed 等）
        --   由固件打印，脚本关不掉；把"每次调用都重试 3 轮"改成"冷却期内不重试"即可显著收敛。
        log.warn("sd_card", "SD 卡不可用(" .. tostring(last_err) .. ")，记录回退 " .. cfg.fallback
                 .. "；" .. math.floor(cfg.retry_interval / 1000) .. "s 内不再尝试挂载")
    end
    return ok
end

-- SD 卡是否可用
function sd_card.is_mounted()
    return mounted
end

-- 取可用保存路径（SD 可用时返回 /sd/xxx，否则 /ram/xxx）
function sd_card.path(name)
    local cfg = load_cfg()
    local dir = mounted and cfg.mount_point or cfg.fallback
    return dir .. "/" .. name
end

-- 写文件（data 为字符串）
function sd_card.write(path, data)
    if not path or not data then return false end
    local f = io.open(path, "wb")
    if not f then
        log.error("sd_card", "文件打开失败", path)
        return false
    end
    local ok = pcall(function()
        f:write(data)
    end)
    f:close()
    if not ok then
        log.error("sd_card", "文件写入失败", path)
        return false
    end
    log.info("sd_card", "已保存", path, #data, "字节")
    return true
end

return sd_card
