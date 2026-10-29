--[[
@module  sd_mount
@summary Air8607 TF 卡挂载（SPI1 / CS=GPIO8 / SD_EN=GPIO74）
@version 1.0
@date    2026.10.28
@usage
原理图 AIR8607_20261010_1200 第 2、6 页，与 projects/airui_vedio 相同：
  SPI1_CS   = PIN49 = GPIO8
  SPI1_CLK  = PIN50 = GPIO9
  SPI1_MISO = PIN51 = GPIO10
  SPI1_MOSI = PIN52 = GPIO11
  SD_EN     = PIN26 = GPIO74（高电平给卡供电，U600 使能）
时钟用工厂 eng_8607_10i_v0 的 60MHz，失败再降到 10MHz。不自动格式化。
瓦片放在 /sd/tiles/{z}/{x}/{y}.jpg。
]]

local sd_mount = {}

sd_mount.SPI_ID = 1
sd_mount.PIN_CS = 8
sd_mount.PIN_SD_EN = 74
sd_mount.MOUNT_POINT = "/sd"
sd_mount.SPI_INIT_HZ = 400000
sd_mount.SPI_HZ = 60 * 1000 * 1000

local mounted = false

local function power_cycle()
    gpio.setup(sd_mount.PIN_SD_EN, 0)
    gpio.set(sd_mount.PIN_SD_EN, 0)
    sys.wait(50)
    gpio.set(sd_mount.PIN_SD_EN, 1)
    sys.wait(200)
    log.info("sd_mount", "SD_EN GPIO" .. sd_mount.PIN_SD_EN .. " 已拉高")
end

function sd_mount.is_mounted()
    return mounted
end

--[[
挂载 TF 卡到 /sd。失败不自动格式化。
@return boolean, string
]]
function sd_mount.mount()
    if rtos.bsp() == "PC" then
        log.info("sd_mount", "PC 仿真跳过挂载")
        return false, "pc"
    end
    if mounted then
        return true, "already"
    end

    power_cycle()

    local speeds = { sd_mount.SPI_HZ, 10 * 1000 * 1000 }
    local last_err = "mount fail"
    for i = 1, #speeds do
        local spi_ret = spi.setup(sd_mount.SPI_ID, nil, 0, 0, 8, sd_mount.SPI_INIT_HZ)
        log.info("sd_mount", "spi.setup", spi_ret, "speed", speeds[i])
        gpio.setup(sd_mount.PIN_CS, 1)

        local ok, err = fatfs.mount(fatfs.SPI, sd_mount.MOUNT_POINT,
            sd_mount.SPI_ID, sd_mount.PIN_CS, speeds[i],
            sd_mount.PIN_SD_EN, 100, false)
        if ok then
            mounted = true
            log.info("sd_mount", "挂载成功", err, "speed", speeds[i])
            return true
        end
        last_err = tostring(err or "mount fail")
        log.warn("sd_mount", "挂载失败", "speed", speeds[i], last_err)
        sys.wait(80)
    end
    log.error("sd_mount", "挂载最终失败", last_err)
    return false, last_err
end

return sd_mount
