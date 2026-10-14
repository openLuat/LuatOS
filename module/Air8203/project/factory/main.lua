--[[
@module  main
@summary 应用主入口（Air8203 工业模组，单产品线）
@version 0.1（框架版）
@date    2026.09.28

=== 启动链（与 8202G 同构，但按 8203 硬件重排） ===
  0. fskv.init()              → 持久化就绪（board.init 读 board_force 需要）
  1. board.init()             → T0 识别子型号（H/V/U/N + 1/2/3 变体），构建 profile
  2. ★ wdt.init()             → **尽早开始喂狗**（P0）
     8203 的看门狗是 BLE 芯片 MS1631C 兼任（见 board.lua 注释），
     超时时长【待核】。8202G 项目里 Air153C 是 240s 固定超时，
     但因"注网期间任务阻塞漏喂狗"导致过插卡反复重启的事故（【官网-faq 2026-08-24】案例 24）。
     → 所以喂狗任务必须独立协程、先于一切联网动作启动，且不依赖任何业务状态。
  3. ble_link.init()          → BLE 串口建链（它同时是喂狗通道 / 唤醒源 / 海外 APN 配置口）
  4. sim_slot.init()          → SIM 在位检测与选卡
  5. update.init()            → FOTA 开机检测（异步，不阻塞）
  6. start_app()：
       cfg_fetch.init()  → 加载本地/默认配置
       create.start()    → 云平台连接（AirCloud TLV 主通道）
       app.start()       → 业务模块初始化 + active_mode 主循环
       boot_lbs_report.start()
  7. sys.run()

=== 当前功能开关一览（2026-09-28 现场要求） ===
  ✅ 已启用：联网上报主链路 / GNSS（UART2 @115200）/ 对外 DI-DO / 音频（仅 V 系列）
  ❌ 暂未启用：
     · RS485      → config.RS485_CONFIG.ENABLE = false，仅日志提示（等明确 485 设备）
     · 低功耗     → config.LOWPOWER_CONFIG.ENABLE = false，固定常规模式（等电池功能）
     · 电池电量   → 硬件尚不支持，modules/battery.lua 缩减为日志打印
     · 看门狗     → 喂狗机制【待核】，wdt_app.lua 只告警不动作
  🔄 补偿机制：net_guard.lua —— 单卡 SIM0 且 CD 脚未接，靠"30s 无网进出飞行模式"兜底

=== 与 8202G 的三处结构性差异 ===
  ① 无多型号兼容：board 只认 8203 的 12 个子型号，业务层永不出现 8201/8202 判断
  ② 无 IO 电压域/管脚复用下发：原理图已固定 3.3V 域、I2C1 上拉为常接电阻
     （若某系列实测需要，再按 8202G 的 apply_io_volt/apply_pinmux 模式补）
  ③ 新增三条 8203 专属链路：喂狗（BLE）、RS485 收发、对外数字 IO
]]

PROJECT = "Air8203"
VERSION = "005.000.001"
FOTA_MODE = 3   -- 3=libfota3（合宙按 IMEI 升级） 2=libfota2（IoT 平台自管）

-- ====== 项目密钥（FOTA 使用） ======
-- 【待办】换成 8203 在合宙平台的 ProjectKey（沿用 8202 的 key 会导致升级串台）
PRODUCT_KEY = "qXY4ibFBFnnRoEFPRTuCl3k1wu4vq1WX"
-- ==================================

-- ====== ★ 构建期兜底：主控系列（H/V/U/N）======
-- 仅在"型号自报失败"时生效。取值 "H"/"V"/"U"/"N"；nil = 不兜底。
-- ⚠️ 给哪个系列出固件就改成哪个，改完必须重烧；切勿把某系列的固件烧到别的系列板上。
BOARD_DEFAULT = "V"

-- ====== ★ 构建期常量：收发器变体（1=隔离485 / 2=非隔离485 / 3=UART）======
-- 8203 的 12 个子型号靠"板载收发器接法"区分，而这一点**主控无法自报**，
-- 因此必须由构建期指定（或现场用 fskv board_force 覆盖）。
BOARD_VARIANT = 2
-- =========================================================

-- 初始化 fskv（board.init 读取 board_force 需要）
fskv.init()

-- ====== T0 板型识别（必须在任何 require-期求值引脚的模块之前）======
local board = require("board")
board.init()
-- ==================================================================

-- ====== ★ 看门狗：尽早启动喂狗任务（P0）======
-- 必须在联网/业务之前：注网、socket 阻塞都可能长时间占用任务，
-- 而喂狗任务独立协程运行，不受业务阻塞影响（【官网-faq】pt.24 的教训）。
-- 【待核】8203 的喂狗形式与超时时长确认前，本模块只输出告警、不假设机制。
-- ⚠️ 文件名是 wdt_app.lua 而**不是** wdt.lua —— 避免与合宙核心库 `wdt` 同名
--    （核心库在固件启动时即注册进 package.loaded，同名脚本会被核心库顶掉、根本加载不到）
local wdt_app = require("wdt_app")
wdt_app.init()
-- ============================================

-- ====== BLE 链路（MS1631C：兼作看门狗 / 唤醒源 / 海外 APN 配置口）======
-- 【待核】串口号、波特率、AT 指令集确认前，本模块只做骨架初始化
local ble_link = require("ble_link")
ble_link.init()
-- =====================================================================

-- ====== SIM 卡槽选择与在位检测 ======
-- ★【已确认】8203 只支持**单卡 SIM0**，且卡座 CD 脚未接 → 不做在位检测（board.lua sim 段已关）
local sim_slot = require("sim_slot")
sim_slot.init()
-- ===================================

-- ====== ★ 网络注册看护（单卡 + CD 未接的补偿机制）======
-- 上电 30s 未注册 → 进出一次飞行模式；连续 3 次仍失败 → 每 30 分钟再试一次；
-- 一旦注册成功，本任务自行退出，不再干预网络（详见 net_guard.lua）
local net_guard = require("net_guard")
net_guard.start()
-- ====================================================

-- ====== FOTA 升级：开机即执行，之后每 8 小时自动检测 ======
local update = require("update")
update.init()
-- ======================================================

-- 正常启动流程
local function start_app()
    log.info("main", "启动应用（型号:", tostring(board.id), " 系列:", tostring(board.series), "）")

    -- 1. 加载本地持久化配置（参考 iRTU default.init）
    local cfg_fetch = require("cfg_fetch")
    local sheet = cfg_fetch.init()
    local config = require("config")

    -- 判断本地配置是否为有效"定位版"配置（含非空 network 通道定义）
    local has_valid = false
    if sheet and type(sheet.gnss) == "table"
        and type(sheet.gnss.network) == "table"
        and type(sheet.gnss.network.conf) == "table"
        and #sheet.gnss.network.conf > 0 then
        has_valid = true
    end

    if has_valid then
        config.load_from_server(sheet.gnss, sheet.project_key)
        log.info("main", "已加载本地持久化配置，param_ver:", sheet.param_ver)
        local remote = require("remote")
        remote.init()
        local create = require("create")
        create.start(sheet)
    else
        log.info("main", "无有效定位版配置，使用默认配置（AirCloud TLV）")
        local create = require("create")
        create.start({ gnss = { network = config.DEFAULT_NETWORK } })
    end

    -- 2. 启动 8203 专属业务链路
    --    对外数字 IO（DI 中断→上报；DO 远程控制）
    local dio = require("dio")
    dio.init()
    --    RS485 / UART3 对外口
    --    ★【已确认 2026-09-28】485 **暂不启用**：config.RS485_CONFIG.ENABLE=false，
    --      此处保留调用只为让 rs485.init() 打出那条"暂未启用"的提示日志，
    --      它内部不会建串口、不会操作方向脚、不会起接收任务
    local rs485 = require("rs485")
    rs485.init()

    -- 3. 启动应用主逻辑
    local app = require("app")
    sys.wait(2000)
    app.start()

    -- 4. 开机联网后单独执行一次 LBS 定位并上报
    local boot_lbs_report = require("boot_lbs_report")
    boot_lbs_report.start()
end

log.info("main", "启动应用（型号:", tostring(board.id), "）")
sys.taskInit(start_app)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run() 之后不要加任何语句!!!!!
