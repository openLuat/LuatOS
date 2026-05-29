local lf_fs_matrix_test = {}

local zip_path = "/luadb/pac_man.zip"

local function now_us()
    if mcu and mcu.ticks then
        return mcu.ticks()
    end
    return (os.time() or 0) * 1000 * 1000
end

local function rm_tree(path)
    local ok, entries = io.lsdir(path, 50, 0)
    if ok and type(entries) == "table" then
        for _, entry in ipairs(entries) do
            local name = entry.name or entry
            local ftype = entry.type or 0
            local child = path .. "/" .. name
            if ftype == 1 then
                rm_tree(child)
                os.remove(child)
            else
                os.remove(child)
            end
        end
    end
    os.remove(path)
end

local function mount_fs(flash, mount_point, fs_name, offset, size)
    if fs_name == "lfs2" then
        return lf.mount(flash, mount_point, offset, size)
    end
    return lf.mount(flash, mount_point, offset, size, fs_name)
end

local function run_file_ops(root)
    local file_path = root .. "/smoke.txt"
    local payload = ("lf_fs_matrix_%d"):format(now_us() % 100000)

    local f = io.open(file_path, "wb")
    if not f then return false, "create_failed" end
    f:write(payload)
    f:close()

    f = io.open(file_path, "rb")
    if not f then return false, "open_read_failed" end
    local got = f:read("*a")
    f:close()
    if got ~= payload then return false, "content_mismatch" end

    if not os.remove(file_path) then return false, "remove_failed" end
    return true, "ok"
end

local function run_write_perf(root)
    local file_path = root .. "/perf.bin"
    local block = string.rep("A", 1024)
    local loops = 64
    local f = io.open(file_path, "wb")
    if not f then return false, 0, "perf_open_failed" end
    local t0 = now_us()
    for i = 1, loops do
        f:write(block)
    end
    f:close()
    local elapsed_ms = math.floor((now_us() - t0 + 500) / 1000)
    os.remove(file_path)
    return true, elapsed_ms, "ok"
end

local function run_unzip(root)
    if not io.exists(zip_path) then
        return false, "zip_missing"
    end
    local out_dir = root .. "/unz/"
    rm_tree(out_dir)
    local t0 = now_us()
    local ok = miniz.unzip(zip_path, out_dir, true, 120000)
    local unzip_ms = math.floor((now_us() - t0 + 500) / 1000)
    if not ok then
        return false, "unzip_failed", unzip_ms
    end
    local check_file = out_dir .. "pac_man/main.lua"
    if not io.exists(check_file) then
        return false, "unzip_missing_main", unzip_ms
    end
    rm_tree(out_dir)
    return true, "ok", unzip_ms
end

function lf_fs_matrix_test.test_lf_three_fs_matrix()
    if not lf or not lf.init then
        log.info("LF_FS_MATRIX", "lf unavailable, skip")
        return
    end
    if not spi or not spi.deviceSetup then
        log.info("LF_FS_MATRIX", "spi unavailable, skip")
        return
    end

    local bus_id = 2
    local cs_pin = 4
    local speed = 20000000
    if rtos_bsp == "PC" then
        bus_id = 1
        speed = 2000000
    end

    local spi_dev = spi.deviceSetup(bus_id, cs_pin, 0, 0, 8, speed, spi.MSB, 1, 0)
    assert(spi_dev, "spi.deviceSetup failed")
    local flash = lf.init(spi_dev)
    assert(flash, "lf.init failed")

    local all_ok = true
    local ran_any = false
    local fs_target = nil
    if os and os.getenv then
        fs_target = os.getenv("LF_FS_TARGET")
    end
    local fs_list = {
        {name = "lfs2", offset = 0x0000000, size = 0x0800000},
        {name = "lfsn", offset = 0x0800000, size = 0x0800000},
        {name = "pgfs", offset = 0x1000000, size = 0x0800000}
    }
    for _, item in ipairs(fs_list) do
        if fs_target and fs_target ~= "" and item.name ~= fs_target then
            goto continue
        end
        local fs = item.name
        ran_any = true
        local mount_point = "/" .. fs .. "_mx"
        log.info("LF_FS_MATRIX_STAGE", string.format("fs=%s stage=start offset=0x%X size=0x%X", fs, item.offset, item.size))
        local ok_erase = lf.erase(flash, item.offset, 0x4000)
        if not ok_erase then
            log.info("LF_FS_MATRIX_RESULT", string.format("fs=%s stage=erase ok=0", fs))
            all_ok = false
        else
            local ok_mount = mount_fs(flash, mount_point, fs, item.offset, item.size)
            if not ok_mount then
                log.info("LF_FS_MATRIX_RESULT", string.format("fs=%s stage=mount ok=0", fs))
                all_ok = false
            else
                log.info("LF_FS_MATRIX_STAGE", string.format("fs=%s stage=mounted", fs))
                local file_ok, file_msg = run_file_ops(mount_point)
                local perf_ok, perf_ms, perf_msg = run_write_perf(mount_point)
                local unzip_ok, unzip_msg, unzip_ms = run_unzip(mount_point)
                log.info("LF_FS_MATRIX_RESULT",
                    string.format(
                        "fs=%s file_ok=%d perf_ok=%d perf_ms=%d unzip_ok=%d unzip_ms=%d detail=%s/%s/%s",
                        fs,
                        file_ok and 1 or 0,
                        perf_ok and 1 or 0,
                        perf_ms or -1,
                        unzip_ok and 1 or 0,
                        unzip_ms or -1,
                        file_msg or "na",
                        perf_msg or "na",
                        unzip_msg or "na"
                    )
                )
                if not (file_ok and perf_ok and unzip_ok) then
                    all_ok = false
                end
                rm_tree(mount_point)
            end
        end
        sys.wait(100)
        ::continue::
    end

    if fs_target and fs_target ~= "" then
        assert(ran_any, "unknown LF_FS_TARGET: " .. tostring(fs_target))
    end
    assert(all_ok, "lf fs matrix has failures")
end

return lf_fs_matrix_test
