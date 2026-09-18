--[[
@module  sd_card
@summary TF/SD 卡挂载与文件保存（Air8601 寄存柜整机）
@version 1.0
@date    2026.09.17
@usage
    local sd_card = require "sd_card"
    sd_card.init()                      -- 挂载（需在 task 中调用；失败自动回退 /ram）
    local p = sd_card.path("face.jpg")  -- 返回实际可用保存路径
    sd_card.write(p, data)              -- 写二进制文件

说明：
1. SD_EN = GPIO65（高电平使能 SD 卡供电），hardware.power_on 的上电时序已处理，
   本模块再次拉高并等待供电稳定，提高热插拔/复位后的挂载成功率。
2. SD 卡走 SPI1，CS = GPIO8（参照 Air1601 平台默认）。
   ⚠️ 注意：本项目 config.rs485.pin = 8，GPIO8 同时是 485 方向控制脚。
   若实测 SD 挂载失败或 485 通讯异常，请把 sd.pin_cs / rs485.pin 改成实际硬件引脚。
3. 挂载失败自动回退到 /ram，功能不中断（日志会提示）。
]]

local sd_card = {}

local config = require "config"

-- 挂载参数（可由 config.sd 覆盖）
local function load_cfg()
    local c = config.get("sd", {})
    return {
        spi_id     = c.spi_id or 1,                 -- SPI 接口 ID
        pin_cs     = c.pin_cs or 8,                 -- 片选 CS 引脚
        pin_en     = c.pin_en or 65,                -- SD_EN 供电使能引脚（高有效）
        init_speed = c.init_speed or 400 * 1000,    -- 挂载前低速 400kHz
        speed      = c.speed or 24 * 1000 * 1000,   -- 挂载后工作频率 24MHz
        mount_point = c.mount_point or "/sd",       -- 挂载点
        fallback   = c.fallback or "/ram",          -- 回退目录
    }
end

local mounted = false      -- 是否真实挂载到 SD 卡
local inited = false       -- 是否已执行过挂载流程

-- 挂载 SD 卡（失败回退 /ram；需在 task 中调用）
function sd_card.init()
    local cfg = load_cfg()
    if inited and mounted then return true end
    inited = true

    -- 1) SD 供电使能（高电平）
    gpio.setup(cfg.pin_en, 0)
    gpio.setup(cfg.pin_en, 1, gpio.PULLUP)
    sys.wait(300)   -- 等待卡供电稳定（大容量卡需更长时间）

    -- 2) SPI 低速初始化，片选拉高
    if not pcall(spi.setup, cfg.spi_id, nil, 0, 0, 8, cfg.init_speed) then
        log.warn("sd_card", "spi.setup 失败，SD 卡不可用")
    end
    pcall(gpio.setup, cfg.pin_cs, 1)

    -- 3) 挂载，失败则断电重启卡再重试
    local ok = false
    for retry = 1, 3 do
        -- pcall 包裹 fatfs.mount 本身（内部无 sys.wait，可安全 yield 外部）
        local pok, mok, merr = pcall(fatfs.mount, fatfs.SPI, cfg.mount_point,
                                     cfg.spi_id, cfg.pin_cs, cfg.speed)
        if pok and mok then
            ok = true
            log.info("sd_card", "SD 卡挂载成功", cfg.mount_point)
            break
        end
        log.warn("sd_card", "SD 卡挂载失败(第" .. retry .. "次):", pok and merr or mok)
        if retry < 3 then
            gpio.setup(cfg.pin_en, 0)
            sys.wait(200)
            gpio.setup(cfg.pin_en, 1, gpio.PULLUP)
            sys.wait(300)
        end
    end

    mounted = ok
    if not ok then
        log.warn("sd_card", "SD 卡不可用，照片回退保存到 " .. cfg.fallback)
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

-- 写二进制文件（data 为字符串）
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
