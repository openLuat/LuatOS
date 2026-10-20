--[[
@module  main
@summary Air8380 出厂固件入口（产测 + 用户双模合一）
@version 1.0
@date    2026.10.20

模式分流（与原「8380出厂产测」工程保持一致）：
  fskv 里有 retest_flag        → 产测模式（返工）
  OTP 里 PROD 为空             → 产测模式（首次）
  否则                          → 用户模式

注意：main.lua 的主 chunk 不是协程，**顶层不能调用 sys.wait**，
所以用户模式的初始化整体放在 sys.taskInit 里执行（LDO 上电后需要等待电源稳定）。
产测模式的 factory.lua 自带任务，直接 require 即可。
]]

PROJECT = "Air8380_Factory"
VERSION = "001.999.001"

log.info("main", PROJECT, VERSION)

-- 1. 软件看门狗：9 秒超时，3 秒喂一次（两种模式都要保护）
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 2. 参数存储
fskv.init()

-- 3. pm 兜底：个别内核没有 pm.reboot / pm.shutdown，产测里 RST/TEST_DONE 会直接调用
if not pm then pm = {} end
if not pm.reboot then pm.reboot = rtos.reboot end
if not pm.shutdown then pm.shutdown = rtos.reboot end

-- 4. 模式判定
-- BOOT_MODE 调试开关： "auto"（出货默认） / "factory"（强制产测） / "normal"（跳过产测）
local BOOT_MODE = "auto"

local prodmeta = require "prodmeta"

local function get_boot_mode()
    if BOOT_MODE == "factory" then return "factory" end
    if BOOT_MODE == "normal" then return "normal" end
    if fskv.get("retest_flag") then return "factory" end
    if prodmeta.get("PROD") == nil then return "factory" end
    return "normal"
end

-- 用户模式：LDO → SPI1 → Flash → 网络/上云/FOTA/看门狗
local function start_normal_mode()
    local board = require "board"
    require "app_config"

    -- 三路 LDO 上电（P3 U230 外供 / P3 U200 Flash / P4 U401 网口）
    local function ldo_on(cfg)
        if cfg and cfg.pin then
            gpio.setup(cfg.pin, cfg.on_level or 1)
            log.info("main", "LDO 使能 GPIO" .. cfg.pin)
        end
    end
    ldo_on(board.ldo.ext)
    ldo_on(board.ldo.flash)
    ldo_on(board.ldo.eth)

    -- 关键：网口与 NAND 共用 SPI1，上电后必须先把两路片选都置为失选（高电平），
    -- 否则 CH390H 复位默认电平可能选中它，MISO 上与 NAND 抢总线，导致 NAND 探测失败
    gpio.setup(board.flash.cs, 1, gpio.PULLUP)
    gpio.setup(board.eth.cs, 1, gpio.PULLUP)
    sys.wait(board.ldo.settle_ms or 50)

    -- SPI1 总线（CH390H 与 SPI NAND 共用，总线 26MHz，NAND 单独 2MHz）
    local spi_ret = spi.setup(board.spi.id, nil, 0, 0, 8, board.spi.speed)
    log.info("main", "SPI" .. tostring(board.spi.id) .. " 初始化 ret=" .. tostring(spi_ret)
        .. " speed=" .. tostring(board.spi.speed))

    -- 板载 SPI Flash 挂载（失败不阻塞主流程）
    local storage = require "storage"
    storage.mount()
    storage.ensure_fixed()        -- 首次挂载时写入固定值，供远程指令读取
    local log_ok = storage.log("boot", "启动 " .. PROJECT .. " " .. VERSION)
    log.info("main", "运行日志写入:", log_ok and "OK" or "FAIL")

    -- 错误日志上报
    if errDump then
        errDump.config(true, 600)
    end

    -- 业务模块
    require "net_drv"             -- 4G / 网口 / WiFi 多网融合
    require "status"              -- 状态聚合（AirCloud 上报使用）
    require "airlbs_app"          -- airlbs 定位（未配置 ID/Key 自动跳过）
    require "aircloud_app"        -- AirCloud 上报 / 运维日志 / 下行命令

    local fota_app = require "fota_app"
    fota_app.start()              -- 未配置 project_key 时自动跳过

    require "net_watchdog"        -- 网络看门狗

    log.info("main", "初始化完成，等待网络就绪")
end

local mode = get_boot_mode()

if mode == "factory" then
    -- ================= 产测模式 =================
    log.info("main", "进入产测模式", "retest=" .. tostring(fskv.get("retest_flag") and 1 or 0),
        "PROD=" .. tostring(prodmeta.get("PROD")))
    -- factory.lua 内部自行初始化 LDO / SPI1 / 网口 DHCP / Flash / USB 虚拟串口
    require "factory"
else
    -- ================= 用户模式 =================
    log.info("main", "进入用户模式", "PROD=" .. tostring(prodmeta.get("PROD")),
        "PCB=" .. tostring(prodmeta.get("PCB")))
    sys.taskInit(start_normal_mode)
end

-- 结尾总是这一句，之后不要加任何语句
sys.run()
