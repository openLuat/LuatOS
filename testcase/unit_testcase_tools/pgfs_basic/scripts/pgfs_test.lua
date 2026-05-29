local pgfs_tests = {}

local PGFS_SUPERBLOCK_A_ADDR = 0x0000
local PGFS_SUPERBLOCK_B_ADDR = 0x1000
local PGFS_CHECKPOINT_A_ADDR = 0x2000
local PGFS_CHECKPOINT_B_ADDR = 0x3000
local PGFS_ERASE_LEN = 0x4000

local PGFS_SB_MAGIC = 0x50474653
local PGFS_CP_MAGIC = 0x50474350
local PGFS_VERSION = 1
local s_spi_device = nil
local s_flash = nil
local s_mounted = false
local s_power_ready = false

local function is_pc()
    if hmeta and hmeta.model then
        return hmeta.model() == "PC"
    end
    return false
end

local function get_spi_bus()
    if os and os.getenv then
        local v = os.getenv("PGFS_SPI_BUS") or os.getenv("LF_SPI_BUS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if is_pc() then
        return 0
    end
    return 2
end

local function get_spi_cs()
    if os and os.getenv then
        local v = os.getenv("PGFS_SPI_CS") or os.getenv("LF_SPI_CS")
        if v and v ~= "" then
            local n = tonumber(v)
            if n then
                return n
            end
        end
    end
    if is_pc() then
        return 17
    end
    return 4
end

local function ensure_flash_power()
    if s_power_ready or is_pc() then
        return
    end
    if gpio and gpio.setup then
        gpio.setup(50, 1)
        sys.wait(20)
    end
    s_power_ready = true
end

local function setup_flash()
    if not s_spi_device then
        ensure_flash_power()
        s_spi_device = spi.deviceSetup(get_spi_bus(), get_spi_cs(), 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
        assert(s_spi_device, "spi.deviceSetup failed")
        s_flash = lf.init(s_spi_device)
        assert(s_flash, "lf.init failed")
    end
    assert(lf.erase(s_flash, 0, PGFS_ERASE_LEN), "lf.erase failed")
    sys.wait(30)
    assert(lf.pgfsctl("reset_runtime"), "pgfs reset_runtime failed")
    if not s_mounted then
        assert(lf.mount(s_flash, "/pgfs/", 0, 0, "pgfs"), "pgfs mount failed")
        s_mounted = true
    end
    return s_spi_device, s_flash
end

local function crc32_raw(data)
    return crypto.crc32(data, 0xFFFFFFFF, 0x04C11DB7, 0) & 0xFFFFFFFF
end

local function build_checkpoint(seq, total_blocks, used_blocks)
    local body_with_zero_crc = string.pack("<I4I2I2I4I4I4I4I4I4I4",
        PGFS_CP_MAGIC,
        PGFS_VERSION,
        0,
        seq,
        total_blocks,
        used_blocks,
        0,
        0,
        0,
        0)
    local crc = crc32_raw(body_with_zero_crc)
    return body_with_zero_crc:sub(1, -5) .. string.pack("<I4", crc), crc
end

local function build_superblock(seq, cp_addr, cp_len, cp_crc)
    local body_with_zero_crc = string.pack("<I4I2I2I4I4I4I4I4",
        PGFS_SB_MAGIC,
        PGFS_VERSION,
        0,
        seq,
        cp_addr,
        cp_len,
        cp_crc,
        0)
    local crc = crc32_raw(body_with_zero_crc)
    return body_with_zero_crc:sub(1, -5) .. string.pack("<I4", crc)
end

function pgfs_tests.test_generation_fallback_prefers_latest_valid()
    assert(string.pack, "string.pack is unavailable")
    assert(crypto and crypto.crc32, "crypto.crc32 is unavailable")

    local _, flash = setup_flash()
    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "lf.erase failed")

    local cp_a, cp_a_crc = build_checkpoint(1, 128, 11)
    local cp_b, cp_b_crc = build_checkpoint(2, 128, 22)
    local sb_a = build_superblock(1, PGFS_CHECKPOINT_A_ADDR, #cp_a, cp_a_crc)
    local sb_b = build_superblock(2, PGFS_CHECKPOINT_B_ADDR, #cp_b, cp_b_crc)

    local sb_b_corrupt = sb_b:sub(1, -2) .. string.char((sb_b:byte(-1) ~ 0xFF) & 0xFF)

    assert(lf.write(flash, PGFS_CHECKPOINT_A_ADDR, cp_a), "write cp_a failed")
    assert(lf.write(flash, PGFS_CHECKPOINT_B_ADDR, cp_b), "write cp_b failed")
    assert(lf.write(flash, PGFS_SUPERBLOCK_A_ADDR, sb_a), "write sb_a failed")
    assert(lf.write(flash, PGFS_SUPERBLOCK_B_ADDR, sb_b_corrupt), "write sb_b failed")

    assert(lf.pgfsctl("reset_runtime"), "reset_runtime after generation inject failed")
    local ok, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/pgfs/")
    assert(ok, "fs.fsstat(/pgfs/) failed")
    assert(fs_type == "pgfs", "expected pgfs fs type")
    assert(total_blocks == 128, "expected fallback generation total_blocks=128")
    assert(used_blocks == 11, "expected fallback generation used_blocks=11")
    assert(block_size > 0, "block_size should be positive")

end

function pgfs_tests.test_fclose_is_durable_boundary()
    setup_flash()

    local f = assert(io.open("/pgfs/durable.txt", "wb"))
    assert(f:write("commit_me"), "write failed")
    assert(f:close(), "close failed")

    assert(lf.pgfsctl("reset_runtime"), "reset_runtime failed")
    local after_reset = io.readFile("/pgfs/durable.txt")
    assert(after_reset == "commit_me", "data must survive reboot/remount")

end

function pgfs_tests.test_controlled_powercut_before_checkpoint()
    setup_flash()

    assert(lf.pgfsctl("powercut_stage", "before_checkpoint"), "set powercut_stage failed")
    local f = assert(io.open("/pgfs/powercut.txt", "wb"))
    assert(f:write("lost_on_powercut"), "write failed")
    local close_ok = f:close()
    assert(not close_ok, "close should fail under injected powercut")

    assert(lf.pgfsctl("powercut_stage", "none"), "clear powercut_stage failed")
    assert(io.writeFile("/pgfs/powercut.txt", "recovered"), "rewrite failed")
    local data = io.readFile("/pgfs/powercut.txt")
    assert(data == "recovered", "data mismatch after clearing injection")

end

function pgfs_tests.test_control_invalid_args()
    setup_flash()
    assert(not lf.pgfsctl("lock_mode", "invalid"), "invalid lock_mode should fail")
    assert(not lf.pgfsctl("powercut_stage", "invalid"), "invalid powercut_stage should fail")
    assert(not lf.pgfsctl("unknown_cmd", true), "unknown pgfsctl command should fail")
end

function pgfs_tests.test_c_layer_selftests()
    setup_flash()
    assert(lf.pgfsctl("run_c_tests"), "pgfs C-layer selftests failed")
end

function pgfs_tests.test_info_fast_path_and_rebuild()
    local _, flash = setup_flash()

    assert(io.writeFile("/pgfs/info_probe.txt", "ok"), "write probe failed")
    sys.wait(30)
    local ok1, total1 = fs.fsstat("/pgfs/")
    assert(ok1, "first fsstat failed")
    assert(total1 and total1 > 0, "first fsstat total should be >0")

    assert(lf.erase(flash, 0, PGFS_ERASE_LEN), "erase metadata area failed")
    local ok2, total2 = fs.fsstat("/pgfs/")
    assert(ok2, "second fsstat should rebuild and pass")
    assert(total2 and total2 > 0, "second fsstat total should be >0")

end

function pgfs_tests.test_getc_line_read_path()
    setup_flash()
    local path = "/pgfs/getc_probe.txt"
    assert(io.writeFile(path, "line1\nline2\n"), "prepare getc probe file failed")
    local f = assert(io.open(path, "rb"), "open getc probe file failed")

    local line1 = f:read("*l")
    assert(line1 == "line1", "first line mismatch: " .. tostring(line1))
    local line2 = f:read("*l")
    assert(line2 == "line2", "second line mismatch: " .. tostring(line2))
    local line3 = f:read("*l")
    assert(line3 == nil, "expected nil on eof, got " .. tostring(line3))
    assert(f:close(), "close getc probe file failed")
end

function pgfs_tests.test_directory_listing_and_existence()
    setup_flash()

    local root_dir = "/pgfs/folder_vars"
    local nested_dir = root_dir .. "/vars"
    local nested_file = nested_dir .. "/config.txt"

    assert(io.mkdir(root_dir), "mkdir root_dir failed")
    assert(io.mkdir(nested_dir), "mkdir nested_dir failed")
    assert(io.writeFile(nested_file, "alpha"), "write nested_file failed")

    assert(io.dexist("/pgfs/"), "mount root should exist")
    assert(io.dexist(root_dir), "root_dir should exist")
    assert(io.dexist(nested_dir), "nested_dir should exist")
    assert(not io.dexist(root_dir .. "/missing"), "missing dir should not exist")
    assert(not io.dexist(nested_file), "file path should not be treated as directory")

    local ok_root, root_entries = io.lsdir("/pgfs/")
    assert(ok_root and type(root_entries) == "table", "lsdir /pgfs/ failed")
    local found_root = false
    for _, item in ipairs(root_entries) do
        if item.name == "folder_vars" and item.type == 1 then
            found_root = true
        end
    end
    assert(found_root, "root listing missing folder_vars")

    local ok_nested, nested_entries = io.lsdir(root_dir)
    assert(ok_nested and type(nested_entries) == "table", "lsdir root_dir failed")
    local found_nested = false
    for _, item in ipairs(nested_entries) do
        if item.name == "vars" and item.type == 1 then
            found_nested = true
        end
    end
    assert(found_nested, "nested listing missing vars")

    local ok_vars, vars_entries = io.lsdir(nested_dir)
    assert(ok_vars and type(vars_entries) == "table", "lsdir nested_dir failed")
    local found_file = false
    for _, item in ipairs(vars_entries) do
        if item.name == "config.txt" and item.type == 0 then
            found_file = true
        end
    end
    assert(found_file, "nested listing missing config.txt")

    assert(os.remove(nested_file), "remove nested file failed")
    assert(io.rmdir(nested_dir), "remove nested dir failed")
    assert(io.rmdir(root_dir), "remove root dir failed")
end

return pgfs_tests
