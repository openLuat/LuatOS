local storage = {}

local function ensure_dir(path, mount_point)
    local current = ""
    for part in path:gmatch("[^/]+") do
        current = current .. "/" .. part
        if current ~= mount_point and not io.dexist(current) and not io.mkdir(current) then
            return false, current
        end
    end
    return true
end

function storage.mount(sd_config, record_dir)
    local cfg = sd_config or {}
    local mount_point = cfg.mount_point or "/sd"

    local free = fatfs.getfree(mount_point)
    if not free then
        local exmux = require "exmux"
        local hardware_env = cfg.hardware_env or "DEV_BOARD_8000_V2.0"
        local spi_id = cfg.spi_id or 1
        local cs_pin = cfg.cs_pin or 20
        local spi_hz = cfg.spi_hz or 24 * 1000 * 1000

        exmux.setup(hardware_env)
        exmux.open("spi" .. tostring(spi_id))
        spi.setup(spi_id, nil, 0, 0, 8, 2000000)
        gpio.setup(cs_pin, 1)

        -- 最后一个 false 表示挂载失败时绝不自动格式化测试卡。
        local ok, err = fatfs.mount(fatfs.SPI, mount_point, spi_id, cs_pin, spi_hz, nil, 1, false)
        if not ok then
            return false, "fatfs.mount: " .. tostring(err)
        end
        free = fatfs.getfree(mount_point)
    end

    log.info("sip_record.sd", "TF 卡已挂载", json.encode(free or {}))
    local ok, failed_path = ensure_dir(record_dir, mount_point)
    if not ok then
        return false, "mkdir failed: " .. tostring(failed_path)
    end
    return true
end

return storage
