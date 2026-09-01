--[[
@module  main
@summary Air8202G 应用主入口（Air780EGP，仅 G 版，无 H 版）— 默认寻宠模式版
@version 4.5
@date    2026.07.17
@usage
启动流程：
1. 强制 BOOT_MODE=2 进入正常模式（跳过产测）
2. 完成产测 → 加载本地持久化配置（db）→ 启动云平台连接（create）→ 启动 app
   （已禁用后台拉取网页端配置，只使用本地/默认配置）
3. 本版本默认开机进入寻宠模式（GPS定位，mode=2），不进入未激活模式（见 app.lua）
]]
PROJECT = "Air8202"
VERSION = "004.000.024"
FOTA_MODE = 3  -- 3=libfota3(默认,只能合宙人员根据客户提供的IMEI升级,客户无法自行操作), 2=libfota2(IoT平台,客户自行管理)

-- ====== 项目密钥（FOTA升级使用，libfota3 和 libfota2 统一从此读取） ======
PRODUCT_KEY = "qXY4ibFBFnnRoEFPRTuCl3k1wu4vq1WX"
-- ==========================================================================

-- ====== 开机模式选择（手动修改） ======
-- 0 = 自动（按产测标记 test_done 判断，已完成产测→正常模式，未完成→产测模式）
-- 1 = 强制进入产测模式（跳过产测标记判断，始终进产测）
-- 2 = 强制进入正常模式（跳过产测）【默认】
local BOOT_MODE = 2
-- ======================================

-- 初始化 fskv（app 模块需要，G版产测也用）
fskv.init()

-- ====== SIM 卡固定使用 SIM1（卡槽2），不使用 SIM0 ======
-- 必须在任何联网动作（FOTA / 驻网 / 云连接）之前执行
if mobile and mobile.simid then
    mobile.simid(1)
    log.info("main", "固定使用SIM1, 当前simid:", mobile.simid())
else
    log.error("main", "mobile.simid 不可用，SIM卡选择失败")
end
-- ==========================================================

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

    local config = require("config")

    -- 判断本地持久化配置是否为有效定位版配置（含非空 network 通道定义）
    -- 采集版/未配置/空 gnss 一律视为无有效配置，回退默认 AirCloud
    local has_valid_gnss = false
    if sheet and type(sheet.gnss) == "table" then
        local network = sheet.gnss.network
        if type(network) == "table" and type(network.conf) == "table" and #network.conf > 0 then
            has_valid_gnss = true
        end
    end

    if has_valid_gnss then
        -- 有本地有效定位版配置，应用到 config 模块
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
        log.info("main", "无有效定位版配置（采集版/未配置），使用默认配置")
        -- 默认配置：通道1 连接 AirCloud（TLV 直发合宙云平台）
        local create = require("create")
        create.start({gnss = {network = config.DEFAULT_NETWORK}})
    end

    -- 3. 后台异步获取最新配置 — 本版本已禁用，不向网页端拉取配置
    --    如需恢复，取消下方注释即可
    -- cfg_fetch.start()
    log.info("main", "已禁用网页端配置拉取，使用本地/默认配置")

    -- 4. 启动应用
    local app = require("app")
    sys.wait(2000)
    app.start()

    -- 5. 开机联网后单独执行一次 LBS 定位并上报（独立运行，不与其他逻辑冲突）
    local boot_lbs_report = require("boot_lbs_report")
    boot_lbs_report.start()
end

-- ========== 开机模式分发 ==========
-- BOOT_MODE=2：强制正常模式（跳过产测）【默认】
if BOOT_MODE == 2 then
    log.info("main", "BOOT_MODE=2 强制进入正常模式")
    sys.taskInit(start_app)
elseif BOOT_MODE == 1 then
    -- BOOT_MODE=1：强制进入产测模式
    log.info("main", "BOOT_MODE=1 强制进入产测模式")
    local factory = require("factory")
    -- factory 模块加载后自动启动产测，无需调用 init()
else
    -- ===== Air780EGP (8202G) 方案：使用 fskv 检测 =====
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
