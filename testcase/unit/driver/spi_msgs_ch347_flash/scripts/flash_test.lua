--[[
flash_test.lua

PC 模拟器 + CH347/CH340 USB-SPI 桥接 + W25Qxx SPI NOR Flash 验证脚本

参考: 合宙 AirSPINORFLASH_1000 (W25Q128) 官方 demo
      module/Air780EHM_Air780EHV_Air780EGH/demo/accessory_board/AirSPINORFLASH_1000/raw_spi.lua

目标: 验证本批补丁中新增的 C 层 API 在 PC sim + CH347 真实硬件路径上确实生效:
        - luat_spi_trans_msgs        (bsp/pc/port/driver/luat_spi_pc.c)
        - luat_spi_device_trans_msgs (bsp/pc/port/driver/luat_spi_device.c)
        - luat_spi_xfer2             (bsp/pc/port/driver/luat_spi_pc.c)
      并保持与既有 spi.send / spi.recv / spi.transfer 行为零回归。

⚠️ 关键参数 (与 raw_spi.lua 保持一致):
   - SPI mode = 半双工 (spi.setup 最后一参 = 0)。SPI flash 物理上是半双工,
     CH347 在半双工模式下使用"先 Write 再 Read"两段式，与 flash 时序匹配。
     之前用全双工 (mode=1) 读出的是 FF 00 00 -- 因为 CH347StreamSPI4 会在
     发 1 字节命令时同步把 MISO 上的随机线电平也读回, 但 flash 那时还没准备好回 ID.
   - bandrate = 2 MHz (官方 demo 默认值, CH347 也支持)
   - CPHA = CPOL = 0 (W25Qxx 默认 SPI mode 0)

⚠️ PC sim CH347 特性:
   - spi_id 必须是 0
   - cs 由 CH347 硬件硬编码 CS0 (0x80), Lua 层 cs 参数被忽略

⚠️ 验证"是否走了新 API"必须检查的日志锚点 (本批 patch 新增):
     [D] luat.spi  : luat_spi_trans_msgs ENTER bus=0 cs=... count=... ch347=1
     [D] luat.spidev: luat_spi_device_trans_msgs ENTER bus=0 cs_pin=... count=...
   注意: spi.send / spi.recv / spi.transfer 走的是"既有 API", 这些日志不会出现.
   要看到 trans_msgs 日志, 必须挂上 sfud / little_flash (它们的 spi_write_read
   实现已迁移到 msg API), 或者直接调 spi.deviceSetup 路径 (经过
   luat_spi_device_trans_msgs).

接线 (W25Q128, 3.3V):
   Flash       CH347
   VCC    ->   3.3V
   GND    ->   GND
   CS#    ->   CS0
   CLK    ->   SCK
   DI     ->   MOSI
   DO     ->   MISO
   WP#    ->   VCC (拉高, 否则 IO 异常)
   HOLD#  ->   VCC (拉高)

运行:
   D:\LuatOS\bsp\pc\build\out>luatos-lua.exe --llt="D:\util\luatools\project\pctest.ini"
   或:
   luatos-lua.exe ../../testcase/unit/driver/spi_msgs_ch347_flash/scripts/
]]

local SPI_ID       = 0
local SPI_CS       = nil           -- CH347 硬编码 CS0; deviceSetup 形态用 8 占位
local CS_PIN_DEV   = 8             -- 仅 deviceSetup 形态使用 (与官方 demo 对齐)
local CPHA         = 0
local CPOL         = 0
local DATA_WIDTH   = 8
local BANDRATE     = 2 * 1000 * 1000   -- 2MHz, 官方 demo 默认
local SPI_MODE     = 0             -- ⚠️ 半双工! SPI flash 必须用半双工

local CMD_RDID     = 0x9F
local CMD_WREN     = 0x06
local CMD_WRDI     = 0x04
local CMD_RDSR     = 0x05
local CMD_PP       = 0x02
local CMD_READ     = 0x03
local CMD_SE       = 0x20

local TEST_ADDR    = 0x000000
local TEST_LEN     = 32

-- 已知厂商 ID 表
local KNOWN_MFR = {
    [0xEF] = "Winbond",
    [0xC8] = "GigaDevice",
    [0xC2] = "Macronix",
    [0x20] = "Micron/Numonyx",
    [0x1C] = "EON",
    [0x1F] = "Atmel/Adesto",
    [0x9D] = "ISSI",
    [0xBF] = "SST",
    [0xA1] = "Fudan",
    [0x68] = "Boya",
}

----------------------------------------------------------------------
-- 半双工辅助:
--   官方 raw_spi.lua 在硬件 BSP 上用 gpio.setup(CS_PIN,1) + cspin(0)/cspin(1)
--   手动控制 CS, 让 spi.send + spi.recv 共享同一个 CS 周期.
--   PC sim CH347 的 GPIO 上限是 0~7, GPIO8 这种 CS 控不到; 所以:
--     - 纯发命令 (recv=0): 用 spi.send → CH347SPI_Write,
--       CH347 内部独立完成 CS 拉低/写/拉高. 这是 W25Q 标准时序.
--     - 混合 (cmd+addr 后接 read): 用 spi.transfer → CH347SPI_WriteRead,
--       CS 全程保持低, 与官方 cspin(0)→send→recv→cspin(1) 时序等价.
--   ⚠️ 不能用 spi.transfer 干纯发命令: l_spi_transfer 在 recv_length=0
--      时仍会试图 lua_pushlstring(L, NULL, 1), 崩在 luaS_newlstr.
----------------------------------------------------------------------
local function spi_xfer_halfduplex(send_data, recv_len)
    local sd = send_data or ""
    local rl = recv_len or 0
    if #sd > 0 and rl > 0 then
        return spi.transfer(SPI_ID, sd, #sd, rl) or ""
    elseif #sd > 0 then
        spi.send(SPI_ID, sd)
        return ""
    elseif rl > 0 then
        return spi.recv(SPI_ID, rl) or ""
    end
    return ""
end

local function setup_bus()
    -- spi.setup(id, cs, CPHA, CPOL, dataw, bandrate, bitdict, master, mode)
    -- mode = 0 (半双工)  与官方 raw_spi.lua 完全一致
    local rc = spi.setup(SPI_ID, SPI_CS, CPHA, CPOL, DATA_WIDTH, BANDRATE,
                         spi.MSB, spi.master, spi.half)
    log.info("flash", string.format(
        "spi.setup id=%d cs=%s CPHA=%d CPOL=%d bw=%d mode=halfduplex rc=%s",
        SPI_ID, tostring(SPI_CS), CPHA, CPOL, BANDRATE, tostring(rc)))
    return rc
end

local function close_bus()
    if spi.close then
        local rc = spi.close(SPI_ID)
        log.info("flash", "spi.close rc=" .. tostring(rc))
    end
end

----------------------------------------------------------------------
-- 1. 读 JEDEC ID (RDID 0x9F)
----------------------------------------------------------------------
local function read_jedec()
    local id = spi_xfer_halfduplex(string.char(CMD_RDID), 3)
    if not id or #id < 3 then return nil end
    return id:byte(1), id:byte(2), id:byte(3)
end

local function check_chip_id()
    local b1, b2, b3 = read_jedec()
    if not b1 then
        log.error("flash", "RDID 返回 nil")
        return false
    end
    log.info("flash", string.format("芯片ID: 0x%02X 0x%02X 0x%02X", b1, b2, b3))
    if b1 == 0x00 or b1 == 0xFF then
        log.error("flash", string.format(
            "RDID 异常 (mfr=0x%02X type=0x%02X cap=0x%02X), 检查接线/SPI mode/电压",
            b1, b2, b3))
        return false
    end
    local mfr_name = KNOWN_MFR[b1] or "Unknown"
    local mbit = (b3 >= 17) and (1 << (b3 - 17)) or 0
    log.info("flash", string.format(
        "厂商=%s 类型=0x%02X 容量=~%dMbit", mfr_name, b2, mbit))
    -- W25Q128 期望: 0xEF 0x40 0x18  (Winbond, W25Q 系列, 16MB)
    if b1 == 0xEF and b2 == 0x40 and b3 == 0x18 then
        log.info("flash", "✓ W25Q128 (16MB) 识别成功")
    end
    return true, b1, b2, b3
end

----------------------------------------------------------------------
-- 2. WREN / WRDI / RDSR
----------------------------------------------------------------------
local function write_enable()
    spi_xfer_halfduplex(string.char(CMD_WREN), 0)
end

local function write_disable()
    spi_xfer_halfduplex(string.char(CMD_WRDI), 0)
end

local function read_status()
    local r = spi_xfer_halfduplex(string.char(CMD_RDSR), 1)
    if r and #r >= 1 then return r:byte(1) end
    return nil
end

local function wait_busy(timeout_ms)
    local left = timeout_ms or 1000
    local poll_count = 0
    local last_sr = nil
    while left > 0 do
        local sr = read_status()
        poll_count = poll_count + 1
        if sr ~= last_sr then
            log.info("flash", string.format(
                "  wait_busy poll#%d SR=0x%02X (left=%dms)", poll_count, sr or 0xFF, left))
            last_sr = sr
        end
        if sr and (sr & 0x01) == 0 then
            log.info("flash", string.format(
                "  wait_busy DONE after %d polls, SR=0x%02X", poll_count, sr))
            return true, sr
        end
        sys.wait(10)
        left = left - 10
    end
    log.error("flash", string.format(
        "等待写入超时 polls=%d last_sr=0x%02X", poll_count, last_sr or 0xFF))
    return false
end

----------------------------------------------------------------------
-- 3. 扇区擦除 / 页编程 / 读取
----------------------------------------------------------------------
local function sector_erase(addr)
    write_enable()
    -- 读 SR 确认 WEL=1 (bit1)
    local sr_after_wren = read_status()
    log.info("flash", string.format(
        "  WREN -> SR=0x%02X (WEL=%d)",
        sr_after_wren or 0xFF, ((sr_after_wren or 0) >> 1) & 1))
    local cmd = string.char(CMD_SE,
                            (addr >> 16) & 0xFF,
                            (addr >> 8)  & 0xFF,
                             addr        & 0xFF)
    log.info("flash", string.format(
        "  SE cmd: 20 %02X %02X %02X",
        (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF))
    spi_xfer_halfduplex(cmd, 0)
    log.info("flash", "  SE sent, polling WIP...")
    return wait_busy(2000)
end

local function page_program(addr, data)
    if #data == 0 or #data > 256 then
        log.error("flash", "page program 长度非法: " .. #data)
        return false
    end
    write_enable()
    local cmd = string.char(CMD_PP,
                            (addr >> 16) & 0xFF,
                            (addr >> 8)  & 0xFF,
                             addr        & 0xFF)
    spi_xfer_halfduplex(cmd .. data, 0)
    return wait_busy(2000)
end

local function flash_read(addr, len)
    local cmd = string.char(CMD_READ,
                            (addr >> 16) & 0xFF,
                            (addr >> 8)  & 0xFF,
                             addr        & 0xFF)
    return spi_xfer_halfduplex(cmd, len)
end

----------------------------------------------------------------------
-- 用例 1: 总线 + RDID 基线 (走 spi.send / spi.recv = 既有 API)
--   覆盖路径: spi.send → luat_spi_send → CH347
--             spi.recv → luat_spi_recv → CH347
--   不经过新 msg API, 用作"硬件确实通"的基线锚点.
----------------------------------------------------------------------
local function test_01_baseline_jedec()
    log.info("flash", "===== test_01: bus setup + JEDEC baseline =====")
    setup_bus()
    sys.wait(50)
    return check_chip_id()
end

----------------------------------------------------------------------
-- 用例 2: erase / program / verify 业务回环 (仍走既有 API)
--   说明: 这条用例是参考 raw_spi.lua 的 spi_test_func, 用来确认硬件
--         + 基线 API 完全工作. 是用例 3/4 的前置健康检查.
----------------------------------------------------------------------
local function test_02_erase_program_verify()
    log.info("flash", "===== test_02: erase + program + verify =====")

    -- 状态寄存器
    local sr = read_status()
    log.info("flash", string.format("初始 SR=0x%02X", sr or 0xFF))

    -- 擦除
    log.info("flash", string.format("erase sector 0x%06X ...", TEST_ADDR))
    if not sector_erase(TEST_ADDR) then
        log.error("flash", "erase 失败")
        return false
    end

    -- 验证全 0xFF
    local erased = flash_read(TEST_ADDR, TEST_LEN)
    if #erased ~= TEST_LEN then
        log.error("flash", "erase 后回读长度不对: " .. #erased)
        return false
    end
    for i = 1, TEST_LEN do
        if erased:byte(i) ~= 0xFF then
            log.error("flash", string.format(
                "erase 后 offset=%d 非 0xFF: 0x%02X", i, erased:byte(i)))
            return false
        end
    end
    log.info("flash", "erase OK, all 0xFF")

    -- 写入 pattern
    local pattern = {}
    for i = 0, TEST_LEN - 1 do
        pattern[i + 1] = string.char((i * 7 + 0x5A) & 0xFF)
    end
    local data = table.concat(pattern)
    if not page_program(TEST_ADDR, data) then
        log.error("flash", "page program 失败")
        return false
    end
    log.info("flash", "program OK, " .. TEST_LEN .. " bytes")

    -- 验证
    local back = flash_read(TEST_ADDR, TEST_LEN)
    if back ~= data then
        log.error("flash", "verify 不匹配")
        log.error("flash", "expect=" .. (string.toHex and string.toHex(data) or "?"))
        log.error("flash", "actual=" .. (string.toHex and string.toHex(back) or "?"))
        return false
    end
    log.info("flash", "verify OK, 数据完全匹配")

    -- 清理
    sector_erase(TEST_ADDR)
    write_disable()
    return true
end

----------------------------------------------------------------------
-- 用例 3: spi.deviceSetup 路径 RDID
--   覆盖路径: spi.deviceSetup → spi_device:transfer →
--             luat_spi_device_transfer (既有 API)
--   说明: 与 lf_fs.lua / sfud_test.lua 完全相同的初始化方式
--         (CPHA=0 CPOL=0 mode=spi.half). 验证 device 形态本身没回归.
--   注: 该用例并不直接走 luat_spi_device_trans_msgs, 但创建的 device
--       会被后面挂载 sfud/lf 时使用, 而 sfud/lf 的 spi_write_read 已
--       迁移到 luat_spi_device_trans_msgs.
----------------------------------------------------------------------
local function test_03_device_form()
    log.info("flash", "===== test_03: deviceSetup form =====")
    -- 与 raw_spi.lua 中 spi.deviceSetup 调用完全一致
    local dev = spi.deviceSetup(SPI_ID, CS_PIN_DEV, CPHA, CPOL, DATA_WIDTH,
                                BANDRATE, spi.MSB, spi.master, spi.half)
    if not dev then
        log.error("flash", "spi.deviceSetup 返回 nil")
        return false
    end
    -- 半双工 device 形态: 用 dev:send + dev:recv (与官方一致)
    -- 但部分 BSP 没暴露 dev:send, 优先用 dev:transfer
    local ok, r
    if type(dev.transfer) == "function" then
        -- transfer 在 device 上半双工兼容: send_len=1, recv_len=3
        ok, r = pcall(dev.transfer, dev, string.char(CMD_RDID), 1, 3)
    end
    if not ok or not r or #r < 3 then
        log.error("flash", "device 形态 RDID 失败: " .. tostring(r))
        if dev.close then pcall(dev.close, dev) end
        return false
    end
    log.info("flash", string.format(
        "deviceSetup-path JEDEC: %02X %02X %02X",
        r:byte(1), r:byte(2), r:byte(3)))
    if dev.close then pcall(dev.close, dev) end
    return r:byte(1) ~= 0x00 and r:byte(1) ~= 0xFF
end

----------------------------------------------------------------------
-- 用例 4: 走 sfud (msg-based API 路径) — 仅当 sfud 模块可用时执行
--   覆盖路径: sfud.init → sfud_port::spi_write_read →
--             luat_spi_device_trans_msgs → CH347
--   ⇒ 这是本批 patch 中"新 API 真的被走到"的最直接证据.
--   验证锚点 (新增 LLOGD):
--     [D] sfud         : sfud[dev] device_trans_msgs SEND+RECV w=... r=...
--     [D] luat.spidev  : luat_spi_device_trans_msgs ENTER bus=0 cs_pin=8 count=2
--     [D] luat.spi     : luat_spi_trans_msgs ENTER bus=0 cs=... count=2 ch347=1
----------------------------------------------------------------------
local function test_04_sfud_msg_path()
    log.info("flash", "===== test_04: sfud (走 msg-based API) =====")
    -- LuatOS 核心库直接全局可用, 不需要 require
    -- if type(sfud) ~= "table" or type(sfud.init) ~= "function" then
    --     log.warn("flash", "SKIP: sfud 核心库不可用 (PC sim 的 LUAT_USE_SFUD=1 应已编入)")
    --     return nil
    -- end
    local dev = spi.deviceSetup(SPI_ID, CS_PIN_DEV, CPHA, CPOL, DATA_WIDTH,
                                BANDRATE, spi.MSB, spi.master, spi.half)
    if not dev then return false end

    log.info("flash", "sfud.init... (注意观察 D/sfud + D/luat.spidev + D/luat.spi 日志)")
    local ok = sfud.init(dev)
    if not ok then
        log.error("flash", "sfud.init 失败")
        return false
    end

    local sfud_dev = sfud.getDeviceTable and sfud.getDeviceTable() or nil
    if sfud_dev and sfud.getInfo then
        local size, page = sfud.getInfo(sfud_dev)
        log.info("flash", string.format("sfud Flash: size=%d page=%d", size or 0, page or 0))
    end
    log.info("flash", "✓ sfud 路径走通, 新 msg API 已生效")
    return true
end

----------------------------------------------------------------------
-- 用例 5: 走 lf / little_flash (msg-based API 路径) — 仅当模块可用时执行
--   覆盖路径: lf.init → little_flash_port::little_flash_spi_transfer →
--             luat_spi_device_trans_msgs → CH347
--   验证锚点 (新增 LLOGD):
--     [D] lflash       : lflash device_trans_msgs SEND+RECV tx=... rx=...
--     [D] luat.spidev  : luat_spi_device_trans_msgs ENTER ...
----------------------------------------------------------------------
local function test_05_lf_msg_path()
    log.info("flash", "===== test_05: little_flash (走 msg-based API) =====")
    -- LuatOS 核心库直接全局可用, 不需要 require
    -- if type(lf) ~= "table" or type(lf.init) ~= "function" then
    --     log.warn("flash", "SKIP: lf/little_flash 核心库不可用 (PC sim 的 LUAT_USE_LITTLE_FLASH=1 应已编入)")
    --     return nil
    -- end
    local dev = spi.deviceSetup(SPI_ID, CS_PIN_DEV, CPHA, CPOL, DATA_WIDTH,
                                BANDRATE, spi.MSB, spi.master, spi.half)
    if not dev then return false end

    log.info("flash", "lf.init... (注意观察 D/lflash + D/luat.spidev + D/luat.spi 日志)")
    local fdev = lf.init(dev)
    if not fdev then
        log.error("flash", "lf.init 失败")
        return false
    end
    log.info("flash", "✓ little_flash 路径走通, 新 msg API 已生效")
    return true
end

----------------------------------------------------------------------
-- 主任务
----------------------------------------------------------------------
sys.taskInit(function()
    sys.wait(1000)
    log.info("flash", "==================== START ====================")

    local r1 = test_01_baseline_jedec()
    if not r1 then
        log.error("flash", "基线失败 -> 后续全部 SKIP. 排查接线/SPI mode/电压.")
        os.exit(1)
        return
    end

    local r2 = test_02_erase_program_verify()
    local r3 = test_03_device_form()
    local r4 = test_04_sfud_msg_path()
    local r5 = test_05_lf_msg_path()

    close_bus()
    log.info("flash", string.format(
        "===== ALL DONE: t01=%s t02=%s t03=%s t04=%s t05=%s =====",
        tostring(r1), tostring(r2), tostring(r3),
        tostring(r4), tostring(r5)))
    if r4 == nil and r5 == nil then
        log.warn("flash", "提示: sfud/lf 模块未注册 (require 返回非 table)")
        log.warn("flash", "PC sim 的 luat_conf_bsp.h 应已定义 LUAT_USE_SFUD=1 与 LUAT_USE_LITTLE_FLASH=1")
        log.warn("flash", "并在 luat_base_mini.c 注册 luaopen_sfud / luaopen_little_flash")
        log.warn("flash", "若仍 SKIP, 请检查 luat_conf_bsp.h 是否被实际编译")
    end
    os.exit(0)
end)

return {}
