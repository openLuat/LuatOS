--[[
@module  sd_mount
@summary SD/TF卡挂载（SPI模式）与空间查询
@version 1.0
@date    2026.11.06
@author  黄何
@usage
硬件（Air8603 原理图 P7「SPI接口SD卡」）：
    SPI1：CS = PIN49/GPIO8、CLK = PIN50/GPIO9、MISO = PIN51/GPIO10、MOSI = PIN52/GPIO11
    SD_EN = PIN26/GPIO74，高电平给卡供电，需要≥100ms爬升

★★ fatfs.mount 第8个参数 auto_format 必须传 false ★★
   默认是true（挂载失败就自动格式化）。插一张别人的卡进来就等于把卡清空，
   这不是"能不能用"的问题，是会丢数据的事故。
]]

local M = {}

local CFG = {
    mount  = "/sd",
    spi_id = 1,
    cs     = 8,             -- PIN49
    en     = 74,            -- PIN26：SD卡3.3V使能
    speed  = 24000000,      -- 24MHz；卡座电平转换差时降到10MHz
    low_speed = 400000,     -- 起卡先用400kHz
}

local mounted = false
local info = {}
local last_err

function M.is_mounted() return mounted end
function M.stat() return info or {} end
function M.last_err() return last_err end

local function refresh_free()
    if not (fatfs and fatfs.getfree) then return end
    local ok, data = pcall(fatfs.getfree, CFG.mount)
    if ok and type(data) == "table" then info = data end
end

-- 挂载SD卡
-- @return boolean, string|nil
function M.init()
    if mounted then return true end
    if not (fatfs and fatfs.mount) then
        last_err, mounted = "固件未包含fatfs库", false
        log.error("sd", last_err)
        return false, last_err
    end

    -- 1、SPI1低速起步，CS先拉高
    pcall(function()
        spi.setup(CFG.spi_id, nil, 0, 0, 8, CFG.low_speed)
        gpio.setup(CFG.cs, 1)
    end)

    -- 2、卡断电再上电，等电源爬升
    pcall(function() gpio.setup(CFG.en, 0) gpio.set(CFG.en, 0) end)
    sys.wait(100)
    pcall(function() gpio.setup(CFG.en, 1) gpio.set(CFG.en, 1) end)
    sys.wait(600)

    -- 3、挂载（★ 最后一参false = 禁止自动格式化）
    local ok, err
    local pok = pcall(function()
        ok, err = fatfs.mount(fatfs.SPI, CFG.mount, CFG.spi_id, CFG.cs,
                              CFG.speed, CFG.en, 100, false)
    end)
    if not pok or not ok then
        mounted = false
        last_err = string.format("SD卡挂载失败(err=%s)", tostring(err))
        log.error("sd", last_err, "—— 查：卡是否插好 / 是否FAT32 / SD_EN=GPIO74 / SPI1")
        return false, last_err
    end

    mounted = true
    refresh_free()
    log.info("sd", string.format("SD卡挂载成功 %s，总 %s KB / 剩 %s KB",
        CFG.mount, tostring(info.total_kb), tostring(info.free_kb)))
    return true
end

function M.free_kb()
    refresh_free()
    return info.free_kb or 0
end

function M.mount_point() return CFG.mount end

function M.unmount()
    if not mounted then return true end
    pcall(fatfs.unmount, CFG.mount)
    mounted = false
    log.info("sd", "已卸载 " .. CFG.mount)
    return true
end

return M
