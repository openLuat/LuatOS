--[[
@module  drv_i2c
@summary I2C1 总线句柄（GT911 触摸 + 板上 I2C 排针共用）
@version 1.0
@date    2026.10.15
@usage
local dev = require("drv_i2c").get()
i2c.send(dev, addr, data)

为什么默认用软件 I2C：
Air8101 硬件 I2C1 的引脚由 pinmux 决定，实测 pins.setup(pad, "I2C1_SCL")
无法把它从默认的 GPIO0/GPIO1 切过来（那两个脚是 UART1，接了 780ER2），
于是 i2c.setup(1) 始终跑到 GPIO0/1 上：既扫不到 GT911，又抢了产测串口。
软件 I2C 直接指定 GPIO 号，完全可控 —— 与核心板 demo 的做法一致。

要改回硬件 I2C：把 config 里 hw.tp.soft_i2c 设为 false。
]]

local M = {}
local dev = nil

local function soft_delay()
    local hw = (_G.project_config or {}).hw or {}
    local tp = hw.tp or {}
    if tp.i2c_delay then return tp.i2c_delay end

    local ok, devsel = pcall(require, "app_devsel")
    if ok and devsel.get() == "voc" then
        return (hw.voc or {}).i2c_delay or 20
    end
    return nil
end

function M.get()
    if dev then return dev end

    local c = _G.project_config.hw.tp

    if c.soft_i2c ~= false then
        -- 半周期延时（µs）：不传用内核默认 5（约 100kHz）。
        -- 杜邦线长 / 上拉弱 / 干扰大时读 CRC 老不过，把 hw.tp.i2c_delay 调大（10~20）通常就稳了。
        -- 空气质量模式另有更严的上限，见 soft_delay()。
        local delay = soft_delay()
        local d = i2c.createSoft(c.scl, c.sda, delay)
        if type(d) == "userdata" then
            dev = d
            local khz = delay and math.floor(1000 / (delay * 2) + 0.5) or nil
            log.info("drv_i2c", "软件 I2C SCL", c.scl, "SDA", c.sda,
                delay and ("半周期延时 " .. delay .. "us（约 " .. khz .. "kHz）")
                      or "半周期延时 内核默认（约 100kHz）")
            return dev
        end
        log.error("drv_i2c", "i2c.createSoft 失败，回落硬件 I2C")
    end

    local id = c.i2c_id or 1
    i2c.setup(id, i2c.SLOW)
    dev = id
    log.info("drv_i2c", "硬件 I2C", id)
    return dev
end

return M
