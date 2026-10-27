--[[
@module  sd_card
@summary TF/SD 卡挂载（SPI1 + SD_EN 上电时序 + 降速重试）与文件探测
@author  王世豪
@version 1.0
@date    2026.10.26

=== 硬件（Air8607）===
SD 卡走 SPI1：SPI1_CS = GPIO8，SD_EN = GPIO74（高电平供电）。
初始化顺序：SD_EN 放电 50ms -> 上电 -> 等 200ms 电压稳定
            -> spi.setup(400k) -> CS 拉高 -> fatfs.mount。

=== 降速重试 ===
首挂 40MHz，失败依次降到 24MHz / 10MHz，每级间隔 80ms。
不少卡吃不住 40MHz，只试一次就报错属于误判。

=== 不自动格式化 ===
fatfs.mount 第 8 参 auto_format 传 false —— 挂载失败绝不格式化用户的卡。

=== 判空注意 ===
fatfs 可能注册成 rotable（type() 返回 userdata 而非 table），
所以这里只判「非 nil 且有 mount 方法」，绝不能用 type(x) == "table" 去卡。
]]
local conf = require "conf"

local M = {}

local SD = conf.sd
local mounted = false
local last_err = nil

--[[文件是否存在（同时兼容 io.exists 与 io.dexist）
不同固件提供的接口名不一样（有的固件只有 io.dexist），两边都试一遍，
否则会出现「文件明明在卡上，程序却说找不到」的情况。
]]
function M.exists(p)
    if type(io.exists) == "function" then
        local ok, r = pcall(io.exists, p)
        if ok then return r == true end
    end
    if type(io.dexist) == "function" then
        local ok, r = pcall(io.dexist, p)
        if ok then return r == true end
    end
    return false
end

--[[单次挂载尝试：保守时钟建总线 + CS 拉高 + 指定速度挂载]]
local function do_mount(speed)
    spi.setup(SD.spi_id, nil, 0, 0, 8, 400000)
    gpio.setup(SD.pin_cs, 1)
    return fatfs.mount(fatfs.SPI, SD.mount, SD.spi_id, SD.pin_cs,
        speed, SD.pin_en, 100, false)
end

--[[挂载 SD 卡（幂等）
@return boolean ok, string|nil err
]]
function M.mount()
    if mounted then return true end

    log.info("sd", "fatfs 探测", "type(fatfs) =", type(fatfs))
    if not fatfs or type(fatfs.mount) ~= "function" then
        last_err = "固件缺少 fatfs 库"
        log.warn("sd", last_err)
        return false, last_err
    end

    -- 已经挂过（热复位前挂载点还在）
    if M.exists(SD.mount) then
        mounted = true
        log.info("sd", "挂载点已存在，跳过重复挂载", SD.mount)
        return true
    end

    -- SD 卡供电：先拉低放电，再拉高，等电压稳定后再访问
    if SD.pin_en then
        gpio.setup(SD.pin_en, 0)
        pcall(gpio.set, SD.pin_en, 0)
        sys.wait(50)
        gpio.setup(SD.pin_en, 1)
        pcall(gpio.set, SD.pin_en, 1)
        sys.wait(200)
    end

    local speeds = { SD.speed, 24 * 1000 * 1000, 10 * 1000 * 1000 }
    for i = 1, #speeds do
        local ok, err = do_mount(speeds[i])
        if ok then
            mounted = true
            last_err = nil
            log.info("sd", "挂载成功", SD.mount, "spi_id", SD.spi_id,
                "cs", SD.pin_cs, "speed", speeds[i])
            return true
        end
        last_err = tostring(err)
        log.warn("sd", "挂载失败", "speed", speeds[i], last_err)
        sys.wait(80)
    end

    log.error("sd", "挂载最终失败（卡未格式化 / 接触不良 / 卡不受支持）", last_err)
    return false, last_err
end

function M.is_mounted()
    return mounted
end

function M.last_error()
    return last_err
end

return M
