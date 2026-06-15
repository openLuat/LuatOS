--[[
sdcard_test.lua

PC 模拟器 + CH347/CH340 USB-SPI 桥接 + 真实 TF/SD 卡 验证脚本

参考: 合宙 AirMICROSD_1010 (Air780EHM + SD 卡) 官方 demo
      module/Air780EHM_Air780EHV_Air780EGH/demo/accessory_board/AirMICROSD_1010/tfcard_app.lua

目标:
  在 PC sim 真实硬件路径 (CH347 USB-SPI) 上, 通过 fatfs.SPI 挂载 SD 卡,
  验证 components/fatfs/diskio_spitf.c 中 SD reset/idle 80-clock 段
  已迁移到 luat_spi_trans_msgs (本批 patch), 行为正确无回归;
  并完整跑一遍 tfcard_app.lua 演示的 11 步文件操作.

⚠️ PC sim CH347 关键约束:
   - SPI bus_id 必须为 0
   - CS 由 CH347 内部硬编码 CS0 (0x80), GPIO8 是 CH347 GPIO 范围外, 控不到
   - 因此 spi.setup 与 fatfs.mount 的 cs_pin 在 PC sim 上无法用 GPIO 切换,
     只能依赖 CH347 自己的 CS0
   - 这与硬件 BSP (Air780EHM) 用 GPIO8 手动拉低/拉高的行为不同
   - 真硬件 Air780EHM 路径: 见官方 demo, 不在本脚本覆盖范围

⚠️ fatfs SD 协议:
   diskio_spitf.c 里 SD 卡的初始化序列 (CMD0/CMD8/CMD55/ACMD41/CMD58/CMD16
   等) 都通过 luat_spi_transfer 发送; 而 80-clock reset/idle 段是本批 patch
   迁移到 luat_spi_trans_msgs 的部分.
   ⇒ 见日志 "spitf reset trans_msgs SEND+RECV bus=0 len=80" 即证明 patch
     在 SD 路径上确实生效.

接线 (AirMICROSD_1010 配件板对应到 CH347):
   AirMICROSD_1010   CH347
   -------------     -----
   GND          ->   GND
   3V3          ->   3.3V
   spi_cs       ->   CS0
   spi_clk      ->   SCK
   spi_mosi     ->   MOSI
   spi_miso     ->   MISO

运行:
   D:\LuatOS\bsp\pc\build\out>luatos-lua.exe \
     --llt="<指向本 testcase 的 ini>"
]]

local SPI_ID    = 0
-- ⚠️ PC sim CH347: pin_cs 设 nil, 让 CH347 自己管 CS0
-- 真硬件 BSP: 改成实际 GPIO 编号 (e.g. 8)
local PIN_CS    = nil
local INIT_HZ   = 400 * 1000        -- 与官方 demo 一致, 400kHz 初始化
local FAST_HZ   = 24 * 1000 * 1000  -- 与官方 demo 一致, fatfs 内部高速切换
local MOUNT_PT  = "/sd"
local DIR_PATH  = "/sd/io_test"

local function setup_spi()
    -- spi.setup(id, cs, CPHA=0, CPOL=0, dataw=8, bandrate=400kHz)
    local rc = spi.setup(SPI_ID, PIN_CS, 0, 0, 8, INIT_HZ)
    log.info("sd", "spi.setup id=" .. SPI_ID .. " cs=" .. tostring(PIN_CS)
        .. " bw=" .. INIT_HZ .. " rc=" .. tostring(rc))
    -- 真硬件路径需要 gpio.setup(PIN_CS, 1) 拉高 CS, PC sim CH347 GPIO 0~7
    -- 之外不支持, 所以 PIN_CS=nil 时直接跳过.
    if PIN_CS then
        gpio.setup(PIN_CS, 1)
    end
    return rc
end

local function close_spi()
    spi.close(SPI_ID)
    log.info("sd", "spi.close")
end

local function safe_remove(path)
    if io and io.exists and io.exists(path) then
        os.remove(path)
    end
end

----------------------------------------------------------------------
-- 用例 1: SPI 初始化 + fatfs 挂载
--   覆盖路径:
--     fatfs.mount → diskio_spitf.c TF_Initialize →
--       80-clock reset/idle 段 (本批 patch 已迁到 luat_spi_trans_msgs)
--       + CMD0/CMD8/ACMD41/CMD58/CMD16 走 luat_spi_transfer
--   验证日志锚点 (新增 LLOGD):
--     [D] SPI_TF       : spitf reset trans_msgs SEND+RECV bus=0 len=80
--     [D] SPI_TF       : spitf idle  trans_msgs SEND+RECV bus=0 len=80
--     [D] luat.spi     : luat_spi_trans_msgs ENTER bus=0 cs=... count=2 ch347=1
----------------------------------------------------------------------
local function test_01_mount()
    log.info("sd", "===== test_01: SPI init + fatfs mount =====")

    setup_spi()

    -- fatfs.mount(fatfs.SPI, mount_pt, spi_id, pin_cs, max_speed [, ...])
    -- 与官方 demo 完全一致, 24MHz fatfs 内部会切换
    local cs_arg = PIN_CS or 0xFF  -- PC sim CS=nil 时用 0xFF 占位 (不会真控 GPIO)
    local mount_ok, mount_err = fatfs.mount(fatfs.SPI, MOUNT_PT,
                                            SPI_ID, cs_arg, FAST_HZ)
    if not mount_ok then
        log.error("sd", "fatfs.mount 失败 err=" .. tostring(mount_err))
        log.warn("sd", "可能原因:")
        log.warn("sd", "  1) 没插 SD 卡 (CH347+SD 卡没接好)")
        log.warn("sd", "  2) PC sim CH347 GPIO 控不到 CS (硬件限制)")
        log.warn("sd", "  3) 卡格式不被支持 (FAT32 友好, exFAT 需固件支持)")
        return false
    end
    log.info("sd", "fatfs.mount 挂载成功 err=" .. tostring(mount_err))
    return true
end

----------------------------------------------------------------------
-- 用例 2: 空间信息 + 挂载点列举
----------------------------------------------------------------------
local function test_02_getfree()
    log.info("sd", "===== test_02: getfree + lsmount =====")

    local data, err = fatfs.getfree(MOUNT_PT)
    if data then
        local total_kb = data.total_kb or 0
        local free_kb  = data.free_kb  or 0
        log.info("sd", string.format(
            "getfree total=%dKB free=%dKB (%.1f%% free)",
            total_kb, free_kb,
            total_kb > 0 and (free_kb * 100 / total_kb) or 0))
    else
        log.error("sd", "getfree 失败 err=" .. tostring(err))
        return false
    end

    local mounts = io.lsmount()
    log.info("sd", "lsmount=" .. (json and json.encode(mounts) or "?"))
    return true
end

----------------------------------------------------------------------
-- 用例 3: 完整文件操作回环 (照搬官方 tfcard_app.lua 11 步)
----------------------------------------------------------------------
local function test_03_file_io()
    log.info("sd", "===== test_03: file IO 11-step roundtrip =====")
    safe_remove(DIR_PATH .. "/test_a")
    safe_remove(DIR_PATH .. "/testline")
    safe_remove(DIR_PATH .. "/boottime")
    safe_remove(DIR_PATH .. "/renamed_file.txt")

    -- 1. 创建目录
    if io.mkdir(DIR_PATH) then
        log.info("sd", "[1] mkdir OK " .. DIR_PATH)
    elseif io.exists(DIR_PATH) then
        log.warn("sd", "[1] mkdir 已存在 " .. DIR_PATH)
    else
        log.error("sd", "[1] mkdir 失败 " .. DIR_PATH)
        return false
    end

    -- 2. 写入文件
    local file_path = DIR_PATH .. "/boottime"
    local f = io.open(file_path, "wb")
    if not f then
        log.error("sd", "[2] open wb 失败 " .. file_path)
        return false
    end
    f:write("LuatOS SPI msg API verification")
    f:close()
    log.info("sd", "[2] write OK " .. file_path)

    -- 3. exists
    if not io.exists(file_path) then
        log.error("sd", "[3] exists 失败")
        return false
    end
    log.info("sd", "[3] exists OK")

    -- 4. fileSize
    local sz = io.fileSize(file_path)
    if not sz then
        log.error("sd", "[4] fileSize 失败")
        return false
    end
    log.info("sd", "[4] fileSize=" .. sz)

    -- 5. read
    f = io.open(file_path, "rb")
    if not f then
        log.error("sd", "[5] open rb 失败")
        return false
    end
    local content = f:read("*a")
    f:close()
    log.info("sd", "[5] read content=" .. tostring(content))
    if content ~= "LuatOS SPI msg API verification" then
        log.error("sd", "[5] read 内容不匹配")
        return false
    end

    -- 6. 启动计数 (counter 文件)
    local count = tonumber(content) or 0
    count = count + 1
    f = io.open(file_path, "wb")
    if not f then return false end
    f:write(tostring(count))
    f:close()
    log.info("sd", "[6] counter -> " .. count)

    -- 7. 文件追加 a+
    local append_file = DIR_PATH .. "/test_a"
    f = io.open(append_file, "wb")
    f:write("ABC"); f:close()
    f = io.open(append_file, "a+")
    f:write("def"); f:close()
    f = io.open(append_file, "r")
    local s = f:read("*a"); f:close()
    if s ~= "ABCdef" then
        log.error("sd", "[7] 追加结果不匹配: " .. tostring(s))
        return false
    end
    log.info("sd", "[7] append OK content=" .. s)

    -- 8. 按行读取
    local line_file = DIR_PATH .. "/testline"
    f = io.open(line_file, "w")
    f:write("abc\n"); f:write("123\n"); f:write("wendal\n"); f:close()
    f = io.open(line_file, "r")
    local l1 = f:read("*l"); local l2 = f:read("*l"); local l3 = f:read("*l")
    f:close()
    log.info("sd", string.format("[8] lines: '%s' '%s' '%s'",
        tostring(l1), tostring(l2), tostring(l3)))
    if l1 ~= "abc" or l2 ~= "123" or l3 ~= "wendal" then
        log.error("sd", "[8] 按行读取失败")
        return false
    end

    -- 9. 重命名
    local new_path = DIR_PATH .. "/renamed_file.txt"
    local ok, err = os.rename(append_file, new_path)
    if not ok then
        log.error("sd", "[9] rename 失败 " .. tostring(err))
        return false
    end
    if not io.exists(new_path) or io.exists(append_file) then
        log.error("sd", "[9] rename 验证失败")
        return false
    end
    log.info("sd", "[9] rename OK " .. new_path)

    -- 10. 列举目录
    local ret, lst = io.lsdir(DIR_PATH, 50, 0)
    if ret then
        log.info("sd", "[10] lsdir=" .. (json and json.encode(lst) or "?"))
    else
        log.error("sd", "[10] lsdir 失败")
        return false
    end

    -- 11. 删除
    if not os.remove(new_path) then return false end
    if not os.remove(line_file) then return false end
    if not os.remove(file_path) then return false end
    if not io.rmdir(DIR_PATH) then return false end
    log.info("sd", "[11] cleanup OK")
    return true
end

----------------------------------------------------------------------
-- 用例 4: 大块连续写入 + 回读 (压一压 luat_spi_trans_msgs 在 fatfs 路径
--          上的吞吐, fatfs 内部分页用 sector_read/sector_write 走的就
--          是 luat_spi_transfer; reset/idle 段则走新 trans_msgs)
----------------------------------------------------------------------
local function test_04_big_io()
    log.info("sd", "===== test_04: big block write+read =====")
    local big = MOUNT_PT .. "/bigblob.bin"
    safe_remove(big)

    local CHUNK = 1024
    local TOTAL = 32 * 1024  -- 32 KB
    local pattern = string.rep(string.char(0x5A, 0xA5, 0x33, 0xCC), CHUNK / 4)

    local f = io.open(big, "wb")
    if not f then
        log.error("sd", "open wb 失败")
        return false
    end
    local n = 0
    while n < TOTAL do
        f:write(pattern); n = n + CHUNK
    end
    f:close()
    log.info("sd", "write " .. TOTAL .. " bytes done")

    local sz = io.fileSize(big)
    if sz ~= TOTAL then
        log.error("sd", string.format("size mismatch exp=%d got=%d", TOTAL, sz))
        return false
    end

    -- 抽读首块 + 末块
    f = io.open(big, "rb")
    if not f then return false end
    local first = f:read(CHUNK)
    -- 用绝对偏移定位末块, 避免 vfs 对 seek("end", -N) 语义的差异
    local seek_pos = TOTAL - CHUNK
    local pos, serr = f:seek("set", seek_pos)
    log.info("sd", string.format("seek to %d ret=%s err=%s",
        seek_pos, tostring(pos), tostring(serr)))
    local last = f:read(CHUNK)
    f:close()
    if first ~= pattern then
        log.error("sd", string.format(
            "首块校验失败 first_len=%d expect_len=%d",
            first and #first or 0, #pattern))
        return false
    end
    if last ~= pattern then
        log.error("sd", string.format(
            "末块校验失败 last_len=%d expect_len=%d",
            last and #last or 0, #pattern))
        if last and #last >= 4 then
            log.error("sd", string.format(
                "末块前 4 字节: %02X %02X %02X %02X (期望 5A A5 33 CC)",
                last:byte(1), last:byte(2), last:byte(3), last:byte(4)))
        end
        return false
    end
    log.info("sd", "read-back 校验 OK (32KB)")

    safe_remove(big)
    return true
end

----------------------------------------------------------------------
-- 收尾
----------------------------------------------------------------------
local function teardown(mount_ok)
    log.info("sd", "===== teardown =====")
    if mount_ok then
        if fatfs.unmount(MOUNT_PT) then
            log.info("sd", "fatfs.unmount 成功")
        else
            log.error("sd", "fatfs.unmount 失败")
        end
    end
    close_spi()
end

----------------------------------------------------------------------
-- 主任务
----------------------------------------------------------------------
sys.taskInit(function()
    sys.wait(1000)
    log.info("sd", "==================== START ====================")

    local r1 = test_01_mount()
    if not r1 then
        log.error("sd", "挂载失败 -> 跳过后续用例")
        teardown(false)
        os.exit(1)
        return
    end

    local r2 = test_02_getfree()
    local r3 = test_03_file_io()
    local r4 = test_04_big_io()

    teardown(true)
    log.info("sd", string.format(
        "===== ALL DONE: t01=%s t02=%s t03=%s t04=%s =====",
        tostring(r1), tostring(r2), tostring(r3), tostring(r4)))
    os.exit(0)
end)
