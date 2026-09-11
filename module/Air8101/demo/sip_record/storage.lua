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

function storage.ensure_dir(path, mount_point)
    return ensure_dir(path, mount_point or "/")
end

function storage.mount(sd_config, record_dir)
    local cfg = sd_config or {}
    local mount_point = cfg.mount_point or "/sd"
    local power_pin = cfg.power_pin or 13
    local sdio_arg = cfg.sdio_arg or 24 * 1000 * 1000

    gpio.setup(power_pin, 1)

    local free = fatfs.getfree(mount_point)
    if not free then
        -- 第8个参数 false：挂载失败时不自动格式化测试卡。
        local ok, err = fatfs.mount(fatfs.SDIO, mount_point, sdio_arg, nil, nil, nil, nil, false)
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
