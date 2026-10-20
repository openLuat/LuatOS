--[[
@module  prod_nand
@summary 产测项 NAND_TEST#：SPI NAND 读写校验（优先复用内核已挂载的文件系统）
@usage   NAND_TEST#
@return  string —— "OK" / "ERROR"
说明
1. 内核启动时**通常已经自己挂载 little_flash**（日志里那句
   `sfd_lfs mount ret -84, exec auto-format`），挂载点一般是 /little_flash。
   同一颗 NAND 再被脚本 mount 一次会出现"写得进、读不到"的怪现象
   （两个文件系统实例共享同一颗芯片），所以这里**先探测已挂载点，能复用就复用**；
2. 没有任何已挂载点时，才自己做：NAND_EN 上电 → SPI0 deviceSetup(CS=49) → lf.init → lf.mount；
3. 写入后延时再读，读不到重试几次（文件系统同步有延迟）；
4. 自己挂载的情况测完会 unmount + 释放 SPI0；复用内核挂载点的则不动它
   （SPI0 平时由文件系统按需访问，不访问 NAND 时不影响 ETH_TEST）。
]]

local SPI_ID    = 0
local BAUD      = 4 * 1000 * 1000
local MOUNTS    = { "/little_flash", "/nand" }   -- 候选挂载点，存在即用（不用 "/"）
local TEST_NAME = "/factory_test.txt"
local TEST_CONTENT = "Air8101B_NAND_TEST_OK"

local function get_lf()
    if lf and lf.init then
        log.info("prod_nand", "little_flash: 全局可用")
        return lf
    end

    local LF_NAME = "lf"
    local ok, mod = pcall(require, LF_NAME)
    if ok and mod and mod.init then
        log.info("prod_nand", "little_flash: require 加载成功")
        return mod
    end

    log.error("prod_nand", "little_flash 不可用；候选:",
        "lf=" .. tostring(lf),
        "little_flash=" .. tostring(little_flash))
    return nil
end

-- 找到第一个可用的挂载点
local function find_mount()
    for _, p in ipairs(MOUNTS) do
        local ok, exists = pcall(io.dexist, p)
        log.info("prod_nand", "挂载点探测", p, tostring(ok and exists or false))
        if ok and exists then return p end
    end
    return nil
end

return function(arg)
    local c = _G.project_config.hw.nand

    if c.ldo then
        gpio.setup(c.ldo, 1)
        log.info("prod_nand", "LDO 使能 GPIO" .. c.ldo .. " = 1")
    end
    gpio.setup(c.en, 1)             -- NAND_EN 供电（复用时也保持上电）
    sys.wait(50)

    local mount_point = find_mount()
    local spi_dev, lf_mod

    if mount_point then
        log.info("prod_nand", "复用内核已挂载的文件系统:", mount_point)
    else
        -- 内核没挂载 → 自己来（挂到 MOUNTS[1]，与内核习惯一致）
        lf_mod = get_lf()
        if not lf_mod then return "ERROR" end

        -- 硬件 CS = GPIO15（官方 demo CS_PIN，内核日志也是 cs 15）
        local cs = c.cs or 15
        log.info("prod_nand", "SPI0 deviceSetup: cs=", cs, "baud=", BAUD)
        spi_dev = spi.deviceSetup(SPI_ID, cs, 0, 0, 8, BAUD, spi.MSB, 1, 0)
        if not spi_dev then
            log.error("prod_nand", "SPI0 初始化失败")
            return "ERROR"
        end

        local flash = lf_mod.init(spi_dev)
        if not flash then
            log.error("prod_nand", "NAND 初始化失败（查 NAND_EN/CS=49、模块焊接）")
            pcall(spi_dev.close, spi_dev)
            return "ERROR"
        end

        mount_point = MOUNTS[1]
        local mounted = lf_mod.mount(flash, mount_point)
        if not mounted then
            mounted = lf_mod.mount(flash, mount_point)   -- 首次偶发失败，重试一次
        end
        if not mounted then
            log.error("prod_nand", "LittleFS 挂载失败:", mount_point)
            pcall(spi_dev.close, spi_dev)
            return "ERROR"
        end
        log.info("prod_nand", "已自行挂载:", mount_point)
    end

    local test_file = mount_point .. TEST_NAME
    local result = "ERROR"

    local f = io.open(test_file, "wb")
    if f then
        f:write(TEST_CONTENT)
        f:close()

        -- 写入后文件系统同步有延迟：读不到就多试几次
        local content
        for i = 1, 3 do
            sys.wait(80)
            f = io.open(test_file, "rb")
            if f then
                content = f:read("*a")
                f:close()
            end
            if content == TEST_CONTENT then break end
            log.info("prod_nand", "第", i, "次读回:", tostring(content))
        end

        if content == TEST_CONTENT then
            result = "OK"
        else
            log.error("prod_nand", "读写校验不一致，读回:", tostring(content))
        end
    else
        log.error("prod_nand", "测试文件创建失败:", test_file)
    end

    -- 收尾：清文件；只有"自己挂载"的情况才卸载并释放 SPI0
    pcall(os.remove, test_file)
    if spi_dev then
        pcall(lf_mod.unmount, mount_point)
        pcall(spi_dev.close, spi_dev)
        log.info("prod_nand", "已自行卸载并释放 SPI0")
    end

    log.info("prod_nand", "NAND 测试结束，结果:", result, "路径:", test_file)
    return result
end
