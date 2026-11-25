--[[
@module  sd_card
@summary TF 卡挂载（Air8607：SPI1 / CS=GPIO8 / SD_EN=GPIO74），失败可降级
@version 1.0.0
@note 依据 module/Air8607/project/wsh_desktop_clock/code/drv/sd_card.lua 验证过的做法：
      - 顺序：SD_EN 放电 50ms → 上电 → 等 200ms → spi.setup(400k) → CS 拉高 → fatfs.mount；
      - 首挂 40MHz，失败依次降 24MHz / 10MHz（不少卡吃不住 40MHz，只试一次属误判）；
      - 第 8 参 auto_format = false：挂载失败绝不动用户的卡；
      - fatfs 可能是 userdata，判空只能「非 nil 且有 mount 方法」。
      TF 卡只承载「可选」的贴图替换，挂不上不影响面板启动。
]]
local M = {}

local CONF = {
    spi_id = 1,
    pin_cs = 8,
    pin_en = 74,
    mount  = "/sd",
    speeds = { 40 * 1000 * 1000, 24 * 1000 * 1000, 10 * 1000 * 1000 },
}

local mounted = false
local last_err = nil
local tried = false

local function exists(p)
    if type(io.exists) == "function" then
        local ok, r = pcall(io.exists, p)
        if ok and r then return true end
    end
    if type(io.dexist) == "function" then
        local ok, r = pcall(io.dexist, p)
        if ok and r then return true end
    end
    return false
end

local function do_mount(speed)
    spi.setup(CONF.spi_id, nil, 0, 0, 8, 400000)
    gpio.setup(CONF.pin_cs, 1)
    return fatfs.mount(fatfs.SPI, CONF.mount, CONF.spi_id, CONF.pin_cs,
        speed, CONF.pin_en, 100, false)
end

--- 挂载 TF 卡（幂等）。返回 ok, err
function M.mount()
    if mounted then return true end
    if tried then return false, last_err end
    tried = true

    if not (fatfs and type(fatfs.mount) == "function") then
        last_err = "固件缺少 fatfs 库"
        log.warn("sd_card", "TF 卡不可用（降级：贴图只用内置 /luadb/）", last_err)
        return false, last_err
    end
    if not (spi and gpio) then
        last_err = "固件缺少 spi/gpio 库"
        log.warn("sd_card", "TF 卡不可用（降级）", last_err)
        return false, last_err
    end

    if exists(CONF.mount) then
        mounted = true
        log.info("sd_card", "挂载点已存在，跳过重复挂载", CONF.mount)
        return true
    end

    -- SD_EN 放电 → 上电 → 等电压稳定
    pcall(function()
        gpio.setup(CONF.pin_en, 0)
        gpio.set(CONF.pin_en, 0)
    end)
    sys.wait(50)
    pcall(function()
        gpio.setup(CONF.pin_en, 1)
        gpio.set(CONF.pin_en, 1)
    end)
    sys.wait(200)

    for i = 1, #CONF.speeds do
        local ok, err = pcall(do_mount, CONF.speeds[i])
        if ok and err then
            mounted = true
            last_err = nil
            log.info("sd_card", "TF 卡挂载成功", CONF.mount, "speed", CONF.speeds[i])
            return true
        end
        last_err = tostring(err)
        log.warn("sd_card", "挂载失败，降速重试", CONF.speeds[i], last_err)
    end

    log.warn("sd_card", "TF 卡挂载最终失败（降级：贴图只用内置 /luadb/）", last_err)
    return false, last_err
end

function M.is_mounted() return mounted end
function M.last_error() return last_err end

return M
