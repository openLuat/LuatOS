local pcconf_tests = {}

local function read_pcconf_file()
    local fd, err = io.open("pcconf/pcconf.json", "rb")
    assert(fd, "打开 pcconf/pcconf.json 失败: " .. tostring(err))
    local raw = fd:read("*a")
    fd:close()
    assert(raw and #raw > 0, "pcconf/pcconf.json 内容为空")
    local data, decode_err = json.decode(raw)
    assert(data and type(data) == "table", "pcconf.json 不是合法JSON: " .. tostring(decode_err))
    return data
end

local function envnum(name)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return nil
    end
    return tonumber(value)
end

local function assert_refresh_interval(value)
    assert(value == 1 or value == 5 or value == 15, "refresh_interval 只能是 1/5/15")
end

function pcconf_tests.test_schema_and_migration()
    local cfg = read_pcconf_file()

    assert(type(cfg.schema_version) == "number", "schema_version 缺失")
    assert(cfg.schema_version >= 1, "schema_version 非法")

    assert(type(cfg.web_console) == "table", "web_console 配置缺失")
    assert(type(cfg.web_console.enabled) == "number", "web_console.enabled 缺失")
    assert(type(cfg.web_console.port) == "number", "web_console.port 缺失")
    assert(type(cfg.web_console.refresh_interval) == "number", "web_console.refresh_interval 缺失")
    assert_refresh_interval(cfg.web_console.refresh_interval)

    assert(type(cfg.storage) == "table", "storage 配置缺失")
    assert(type(cfg.storage.tf_enabled) == "number", "storage.tf_enabled 缺失")
    assert(type(cfg.storage.nor_enabled) == "number", "storage.nor_enabled 缺失")
    assert(type(cfg.storage.nand_enabled) == "number", "storage.nand_enabled 缺失")
    assert(type(cfg.storage.tf_capacity_mb) == "number", "storage.tf_capacity_mb 缺失")
    assert(type(cfg.storage.nor_capacity_mb) == "number", "storage.nor_capacity_mb 缺失")
    assert(type(cfg.storage.nand_capacity_mb) == "number", "storage.nand_capacity_mb 缺失")
    assert(type(cfg.storage.nor_model) == "string", "storage.nor_model 缺失")
    assert(type(cfg.storage.nand_model) == "string", "storage.nand_model 缺失")

    assert(type(cfg.network) == "table", "network 配置缺失")
    assert(type(cfg.network.enabled) == "number", "network.enabled 缺失")

    assert(type(cfg.simulator) == "table", "simulator 配置缺失")
    assert(type(cfg.simulator.enabled) == "number", "simulator.enabled 缺失")

    local expected_enabled = envnum("PCCONF_EXPECT_WEB_ENABLED")
    local expected_port = envnum("PCCONF_EXPECT_WEB_PORT")
    local expected_refresh = envnum("PCCONF_EXPECT_WEB_REFRESH")
    if expected_enabled ~= nil then
        assert(cfg.web_console.enabled == expected_enabled, "web_console.enabled 迁移值不符合预期")
    end
    if expected_port ~= nil then
        assert(cfg.web_console.port == expected_port, "web_console.port 迁移值不符合预期")
    end
    if expected_refresh ~= nil then
        assert(cfg.web_console.refresh_interval == expected_refresh, "web_console.refresh_interval 迁移值不符合预期")
    end
end

function pcconf_tests.test_network_toggle_runtime()
    local cfg = read_pcconf_file()
    local expected_enabled = envnum("PCCONF_EXPECT_NETWORK_ENABLED")

    assert(type(cfg.network) == "table", "network 配置缺失")
    assert(type(cfg.network.enabled) == "number", "network.enabled 缺失")
    if expected_enabled ~= nil then
        assert(cfg.network.enabled == expected_enabled, "network.enabled 迁移值不符合预期")
    end

    if expected_enabled == 0 then
        assert(wlan and type(wlan.init) == "function", "wlan 模块缺失")
        assert(wlan.init(), "wlan.init 应成功")
        sys.wait(200)
        assert(not wlan.ready(), "network.enabled=0 时 wlan.ready 应为 false")

        local ret = wlan.connect("luatos1234", "12341234")
        assert(ret == false, "network.enabled=0 时 wlan.connect 应失败")

        wlan.scan()
        assert(not sys.waitUntil("WLAN_SCAN_DONE", 1000), "network.enabled=0 时不应收到扫描完成事件")
        assert(not sys.waitUntil("IP_READY", 1000), "network.enabled=0 时不应收到 IP_READY")
    end
end

function pcconf_tests.test_storage_config_runtime_mapping()
    local cfg = read_pcconf_file()
    local storage = cfg.storage
    assert(storage and type(storage) == "table", "storage 节缺失")

    local bus_id, cs_tf, speed = 20, 23, 24 * 1000 * 1000
    local nand_bus, nand_cs = 0, 17

    local spi_setup_ret = spi.setup(bus_id, cs_tf, 0, 0, 8, speed, spi.MSB, 1, 1)
    assert(spi_setup_ret == 0, "spi.setup(tf) 失败: " .. tostring(spi_setup_ret))
    fatfs.unmount("/sd")
    local expected_tf_enabled = envnum("PCCONF_EXPECT_TF_ENABLED")
    if expected_tf_enabled == nil then
        expected_tf_enabled = storage.tf_enabled
    end
    local tf_ok, tf_err = fatfs.mount(fatfs.SPI, "/sd", bus_id, cs_tf, speed)
    if expected_tf_enabled == 1 then
        assert(tf_ok == true, "tf_enabled=1 时 fatfs.mount 应成功: " .. tostring(tf_err))
        local tf_size = io.fileSize("spidrv/tf.bin")
        local expected_bytes = (tonumber(storage.tf_capacity_mb) or 0) * 1024 * 1024
        assert(tf_size == expected_bytes, string.format("tf.bin 大小不匹配, got=%s expect=%s", tostring(tf_size), tostring(expected_bytes)))
        fatfs.unmount("/sd")
    else
        assert(tf_ok ~= true, "tf_enabled=0 时 fatfs.mount 应失败")
    end

    local expected_nand_enabled = envnum("PCCONF_EXPECT_NAND_ENABLED")
    if expected_nand_enabled == nil then
        expected_nand_enabled = storage.nand_enabled
    end
    local nand_dev = spi.deviceSetup(nand_bus, nand_cs, 0, 0, 8, 2 * 1000 * 1000, spi.MSB, 1, 0)
    assert(nand_dev, "spi.deviceSetup(nand) 失败")
    local nand_flash = lf.init(nand_dev)
    if expected_nand_enabled == 1 then
        assert(nand_flash, "nand_enabled=1 时 lf.init 应成功")
        local capacity = lf.getInfo(nand_flash)
        local expected_capacity = (tonumber(storage.nand_capacity_mb) or 0) * 1024 * 1024
        assert(capacity == expected_capacity, string.format("nand capacity 不匹配, got=%s expect=%s", tostring(capacity), tostring(expected_capacity)))
    else
        assert(not nand_flash, "nand_enabled=0 时 lf.init 应失败")
    end
    if nand_dev.close then nand_dev:close() end
end

return pcconf_tests
