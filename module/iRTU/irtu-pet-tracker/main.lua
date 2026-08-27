--[[
@module  main
@summary Air8201 应用主入口（手动选择硬件版本）
@version 4.5
@date    2026.07.17
@usage
启动流程：
1. 手动设置 IS_H_VERSION 选择硬件版本
   - false = 8201G（默认，使用 fskv 检测产测）
   - true  = 8201H（使用 OTP 检测产测）
2. 未完成产测 → 进入对应工厂测试模式
3. 已完成产测 → 加载本地持久化配置（db）→ 启动云平台连接（create）→ 启动 app
   （同时后台异步获取最新配置，有新版则重启）
]]
PROJECT = "Air8201"
VERSION = "004.000.001"
FOTA_MODE = 3  -- 3=libfota3(默认,只能合宙人员根据客户提供的IMEI升级,客户无法自行操作), 2=libfota2(IoT平台,客户自行管理)

-- ====== 项目密钥（FOTA升级使用，libfota3 和 libfota2 统一从此读取） ======
PRODUCT_KEY = "qXY4ibFBFnnRoEFPRTuCl3k1wu4vq1WX"
-- PRODUCT_KEY = "jzCWA93RipkNPHMrYLcOa6R5areHNxU7"
-- ==========================================================================

-- ====== 硬件版本选择（手动修改） ======
-- false = 8201G（Air780EG），true = 8201H（Air780EH）
local IS_H_VERSION = false
-- ======================================

-- ====== 开机模式选择（手动修改） ======
-- 0 = 自动（按产测标记 test_done 判断，已完成产测→正常模式，未完成→产测模式）
-- 1 = 强制进入产测模式（跳过产测标记判断，始终进产测）
-- 2 = 强制进入正常模式（未激活绑定窗口，跳过产测）
local BOOT_MODE = 2
-- ======================================

-- 初始化 fskv（app 模块需要，G版产测也用）
fskv.init()

-- ====== FOTA 升级：开机即执行（与工作模式无关），之后每8小时自动检测一次 ======
-- update.init() 内部为异步后台执行，不阻塞开机流程
local update = require("update")
update.init()
-- ============================================================

-- 正常启动流程：加载本地配置 → 启动云连接 → 启动 app → 后台异步获取最新配置
local function start_app()
    log.info("main", "出厂测试已完成，加载配置")

    -- 1. 加载本地持久化配置（参考 iRTU default.init）
    local cfg_fetch = require("cfg_fetch")
    local sheet = cfg_fetch.init()

    if sheet and sheet.gnss then
        -- 有本地持久化配置，应用到 config 模块
        local config = require("config")
        config.load_from_server(sheet.gnss, sheet.project_key)
        log.info("main", "已加载本地持久化配置，param_ver:", sheet.param_ver)

        -- 先初始化远程控制模块，确保能接收后续的下行命令
        local remote = require("remote")
        remote.init()

        -- 2. 启动云平台连接（参考 iRTU create.start）
        local create = require("create")
        create.start(sheet)
        log.info("main", "云平台连接已启动")
    else
        log.info("main", "无本地持久化配置，使用默认配置")
    end

    -- 3. 启动后台异步获取最新配置（参考 iRTU sys.taskInit(config_init)）
    cfg_fetch.start()

    -- 4. 启动应用
    local app = require("app")
    sys.wait(2000)
    app.start()
end

-- ========== 开机模式分发 ==========
-- BOOT_MODE=2：强制正常模式（跳过产测）
if BOOT_MODE == 2 then
    log.info("main", "BOOT_MODE=2 强制进入正常模式")
    sys.taskInit(start_app)
elseif BOOT_MODE == 1 then
    -- BOOT_MODE=1：强制进入产测模式
    log.info("main", "BOOT_MODE=1 强制进入产测模式")
    if IS_H_VERSION then
        local factory_h = require("factory_h")
        factory_h.init()
    else
        local factory = require("factory")
        -- factory 模块加载后自动启动产测，无需调用 init()
    end
elseif IS_H_VERSION then
    -- ===== Air780EH (8201H) 方案：使用 OTP 检测 =====
    local factory_h = require("factory_h")
    local status = factory_h.get_status()
    log.info("main", "H版 OTP test_done:", status.test_done)

    if status.test_done then
        sys.taskInit(start_app)
    else
        log.info("main", "进入H版产测模式（UART+USB双通道）")
        factory_h.init()
    end
else
    -- ===== Air780EG (8201G) 方案：使用 fskv 检测 =====
    local test_done = fskv.get("test_done")
    log.info("main", "G版 test_done:", test_done)

    if test_done then
        sys.taskInit(start_app)
    else
        log.info("main", "进入G版产测模式（USB单通道）")
        local factory = require("factory")
        -- factory 模块加载后自动启动产测，无需调用 init()
    end
end

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!