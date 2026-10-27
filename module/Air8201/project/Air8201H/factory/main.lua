--[[
@module  main
@summary Air8201H 出厂固件主入口（GNSS 常开 + 30s 上报 + V3 产测一体）
@version 1.0
@date    2026.10.23
@usage
本固件为 Air8201H（主控 Air780EHM）专用工程，烧录前无需改 BOARD_DEFAULT（已锁定 8201H）。

启动链：
1. fskv.init() → board.init()（T0 板型识别 + I/O 1.8V 电压域 + 管脚复用，纯字符串判定无 I/O）
2. V3 开机自动分流（BOOT_MODE="auto"）：
   ① fskv 有返工标记 model_retest    → 产测（返工，不动 OTP1）
   ② fskv 有首测标记 model_firsttest → 产测（首测中途复位后回到产测）
   ③ 无标记且 OTP1 空 → 产测（首测，先落 model_firsttest 保护标记）
   ④ 无标记且 OTP1 有值 → 正常模式
3. 正常模式：sim_slot 卡槽选择 → FOTA → start_app（云连接 + GNSS 开机常开 + 30s 周期帧）
   无 GNSS 定位时回退 LBS 基站定位照发一帧（定位方式 2=GPS / 1=LBS）。

产测通道：USB 虚拟串口 uart.VUART_0（单通道；UART1 仅产测内部与 5101 蓝牙模块通信），指令/管脚以 Air8201 已验证产测代码为准。
写号：MODEL→OTP1(PROD)，HVERSION→OTP1(PCB)；TEST_DONE 首测校验 OTP1 非空后删首测标记重启。
]]
PROJECT = "Air8201H"
VERSION = "004.000.067"
FOTA_MODE = 3  -- 3=libfota3(默认,只能合宙人员根据客户提供的IMEI升级,客户无法自行操作), 2=libfota2(IoT平台,客户自行管理)

-- ====== 项目密钥（FOTA升级使用，libfota3 和 libfota2 统一从此读取） ======
PRODUCT_KEY = "qXY4ibFBFnnRoEFPRTuCl3k1wu4vq1WX"
-- ==========================================================================

-- ====== 构建期兜底板型 BOARD_DEFAULT ======
-- 本工程为 Air8201H 专用，兜底锁定 "8201H"：hmeta.model() 取不到（固件缺库/开机未就绪）时仍按 8201H 跑。
-- hmeta.model() 能自报型号时自动识别照常生效（source=hmeta），本常量不参与。
BOARD_DEFAULT = "8201H"
-- ==========================================================================

-- 初始化 fskv（board.init 读取 board_force 覆盖项需要，产测/正常分流与 app/kvstore 亦依赖）
fskv.init()

-- ====== T0 板型识别（必须在任何"require 期求值引脚"的模块之前） ======
-- 纯字符串判定（hmeta.model 主判据 + rtos.bsp 交叉校验 + fskv board_force 覆盖），
-- 内部无 I/O、无 sys.wait，可安全在此同步调用。识别结果经 board.profile 注入 config。
local board = require("board")
board.init()
-- ======================================================

-- 正常启动流程：加载本地配置 → 启动云连接 → 启动 GNSS 30s 上报
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

    -- 4. 启动应用：GNSS 开机常开 + 30s 周期上报（无 fix 回退 LBS）
    local app = require("app")
    sys.wait(2000)
    app.start()
end

-- ========== 启动分流（V3：fskv 返工标记 + 首测中途保护标记 + OTP1 判空） ==========
-- BOOT_MODE 调试开关：
--   "auto"   按 fskv/OTP1 自动分流（量产默认）
--   "normal" 强制正常模式（调试业务用）
--   "factory" 强制产测模式（调试产测用）
local BOOT_MODE = "auto"
local retest = require("retest")
local RETEST_KEY = retest.KEY

-- OTP zone1 是否为空（未产测）。OTP 读取失败 / 非 table 一律按未产测处理
local function otp1_empty()
    local ok, prodmeta = pcall(require, "prodmeta")
    if not ok then
        log.warn("main", "prodmeta 加载失败，按未产测处理")
        return true
    end
    local ok2, all = pcall(prodmeta.get_all)
    if not ok2 or type(all) ~= "table" then
        log.warn("main", "OTP1 读取失败，按未产测处理")
        return true
    end
    return next(all) == nil
end

-- 产测模式：factory.lua 加载即自动初始化 USB 单通道收发
local function enter_factory(reason)
    log.info("main", "进入产测模式，原因:", reason)
    require("factory")
end

-- 正常模式返工入口：监听 USB 虚拟串口 VUART_0 的 MODEL_RETEST 指令。
-- MODEL_RETEST#CONFIRM → retest 写 fskv 标记并重启进产测；MODEL_RETEST?# → HAS/NONE。
-- 正常业务不使用 VUART_0，独立监听不影响其它功能。
local function start_retest_listener()
    sys.taskInit(function()
        local retest = require("retest")
        uart.setup(uart.VUART_0, 115200)
        local cache = ""
        uart.on(uart.VUART_0, "receive", function(id, len)
            while true do
                local data = uart.read(uart.VUART_0, 512)
                if not data or #data == 0 then break end
                cache = cache .. data
                -- 切帧：优先按换行符切（SSCOM 等串口助手默认发送区带 \r\n），
                -- 无换行时兼容以 # 收尾的整帧。不能按内部 # 切：命令本身含 #（MODEL_RETEST#CONFIRM）
                while true do
                    local s, e = cache:find("[\r\n]+")
                    local frame
                    if s then
                        frame = cache:sub(1, s - 1)
                        -- 帧尾可能有多个连续换行，一并丢弃后取剩余内容（避免残留换行重复切空帧）
                        local tail = select(2, cache:find("^[\r\n]+", s))
                        cache = cache:sub(tail + 1)
                    else
                        -- 无换行：仅当缓存以 # 结尾才视为一帧
                        if cache:sub(-1) ~= "#" then break end
                        frame = cache
                        cache = ""
                    end
                    local reply, handled = retest.on_data(frame)
                    if handled and reply then
                        uart.write(uart.VUART_0, reply .. "#\r\n")
                    end
                end
                -- 超长垃圾数据且无帧结束符，丢弃防止内存膨胀
                if #cache > 256 then cache = "" end
            end
        end)
        log.info("main", "正常模式返工入口已监听 VUART_0（MODEL_RETEST#CONFIRM）")
    end)
end

-- 正常模式
local function enter_normal(reason)
    log.info("main", "进入正常模式（板型:", tostring(board.id), "），原因:", reason)
    -- SIM 卡槽选择与热插拔检测（必须在任何联网动作之前），详见 sim_slot.lua
    local sim_slot = require("sim_slot")
    sim_slot.init()
    -- FOTA 升级：仅正常模式开机执行，之后每8小时自动检测一次，异步后台不阻塞开机
    local update = require("update")
    update.init()
    -- 正常模式返工入口（USB 监听 MODEL_RETEST）
    start_retest_listener()
    sys.taskInit(start_app)
end

if BOOT_MODE == "factory" then
    enter_factory("BOOT_MODE 强制产测")
elseif BOOT_MODE == "normal" then
    enter_normal("BOOT_MODE 强制正常")
else
    -- auto：先查 fskv 返工标记，再查首测进行中标记，最后查 OTP1
    if fskv.get(RETEST_KEY) then
        enter_factory("fskv 存在返工标记 model_retest")
    elseif retest.first_is_set() then
        enter_factory("fskv 存在首测标记 model_firsttest（首测中途曾复位）")
    elseif otp1_empty() then
        -- 裸板首次产测：落 model_firsttest 保护标记（带读回校验，重试 3 次）
        -- MODEL/HVERSION 写 OTP1 后，看门狗等复位类测试导致重启时，靠此标记兜回产测
        local marked = false
        for i = 1, 3 do
            if retest.first_set() then marked = true break end
            log.error("main", "首测标记写入失败，重试", i)
        end
        if marked then
            log.info("main", "裸板首测，model_firsttest 已写入")
        else
            -- 不堵产线：放行产测，仅告警（此板中途复位会失去保护，需人工关注）
            log.error("main", "警告：model_firsttest 写入 3 次均失败，首测中途将无复位保护")
        end
        enter_factory("OTP1 为空（首次产测）")
    else
        enter_normal("OTP1 已写号")
    end
end

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!
