--[[
@module  main
@summary Air8784 出厂固件主入口（产测 + SIP 业务 + CC 业务合一）
@version 1.0
@date    2026.09.27
@author  王世豪
@usage
本工程为 Air8784 出厂固件（外挂 Air1103 语音芯片的 SIP 通话产品），
产测、SIP 云端通话、CC(SIP↔手机 VoLTE 中转) 三种模式合一：
    1. fskv.get("test_done") 判断：
       未完成产测 → require "factory" 进产测模式（USB VUART_0，指令以 # 结尾，19 条指令）
       已完成产测 → 业务模式，再由 fskv.get("work_mode") 分流：
          "sip"（默认）→ require "app_main" 进 SIP 云端通话模式
          "cc"        → require "cc_app_main" 进 CC 模式（SIP  ↔ 手机 VoLTE  桥接）
       （调试可用常量 BOOT_MODE 强制 auto / normal / factory / cc，跳过产测或直达指定模式）
    2. 业务模式：不请求网页端配置，开机直接使用预置参数（SIP 服务器 cc.luatos.com、账号 IMEI+0、
       目标手机号由 AirCloud 下发）；AirCloud 上报/下行常驻，两种业务模式都加载 aircloud_data
    3. SIP 模式：开机注册 SIP（账号 IMEI+0），SOS 键默认向 IMEI+1 拨号呼出、UP 键挂断，支持语音留言播放(msg_player)；
       CC 模式：手机呼入转拨 SIP(IMEI+1)，SIP 呼入转拨手机号(cc_target_phone)，两侧由 cc_bridge 桥接语音
    4. 上报：仅 AirCloud 基础心跳 + 周期上报（IMEI / ICCID / CSQ / CPU温度 / 电池电压 / 时间戳）
    5. 下行控制命令（Tag 19/21/1281）：cycle:秒数 / led:on|off|blink / mode:cc|sip / phone:号码 / status / update
    6. FOTA：开机即执行 libfota3 升级检测(update.init)，之后每 8 小时自动检测；仅合宙可据 IMEI 推送
]]

--[[
必须定义PROJECT和VERSION变量,Luatools工具会用到这两个变量,远程升级功能也会用到这两个变量
PROJECT：项目名,ascii string类型
        可以随便定义,只要不使用,就行
VERSION：项目版本号,ascii string类型
        如果使用合宙iot.openluat.com进行远程升级,必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字,三个X表示的数字可以相同,也可以不同,同理三个Y和三个Z表示的数字也是可以相同,可以不同
            因为历史原因,YYY这三位数字必须存在,但是没有任何用处,可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级,根据自己项目的需求,自定义格式即可
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air8784_Factory"
VERSION = "001.000.000"

-- 出厂固件版本：预置配置直接连接 AirCloud，不请求网页端配置
-- 此KEY值仅针对合宙官方IOT平台FOTA，如需使用请替换为项目对应KEY
-- 参考 https://docs.openluat.com/air780epm/luatos/app/ota/fota/
PRODUCT_KEY = "AVbrqZ5tldhyJV8oXqLqa2jPmTey2zMg"

-- ==================== 【调试用】启动模式选择 ====================
-- 可选值：
--   "auto"    按产测标记自动分流（出厂默认）：未产测 → 产测模式；已产测 → 业务模式
--   "normal"  强制进业务模式（跳过产测检查），调试 SIP / AirCloud 用，无需先跑产测
--   "factory" 强制进产测模式，调试产测指令用
--   "cc"      强制进 CC 模式（SIP↔手机中转），调试打手机号用
-- 注意：强制 "normal" 时若未写号，日志 PROD/PCB 打印为 nil，不影响业务功能
local BOOT_MODE = "auto"
-- ============================================================

log.info("main", PROJECT, VERSION)

-- 初始化 fskv（产测标记 test_done 存储）
fskv.init()

-- 打开全局上拉 VREF(GPIO23)：按键与外设上拉依赖此参考电压，产测与业务模式全程常开
gpio.setup(23, 1)

-- 硬狗防止程序卡死
if wdt then
    wdt.init(9000)                              -- 9 秒超时
    sys.timerLoopStart(wdt.feed, 3000)          -- 3 秒喂一次
end

-- ====== FOTA 升级：开机即执行（与工作模式无关），之后每8小时自动检测一次 ======
-- 使用 libfota3（只能合宙人员根据客户提供的IMEI升级，客户无法自行操作）
-- update.init() 内部为异步后台执行，不阻塞开机流程
local update = require("update")
update.init()
-- ============================================================

-- ==================== 开机模式分发 ====================
-- 业务模式由 fskv["work_mode"] 决定："sip"（默认，云端通话）/ "cc"（SIP↔手机中转）
-- 切换方式：AirCloud 下发 mode:cc / mode:sip，设备写标记后自动重启
local function decide_mode()
    if BOOT_MODE == "factory" then return "factory" end
    if BOOT_MODE == "cc" then return "cc" end
    if BOOT_MODE == "normal" then return fskv.get("work_mode") or "sip" end
    -- auto
    if not fskv.get("test_done") then return "factory" end
    return fskv.get("work_mode") or "sip"
end

local mode = decide_mode()

-- 全局工作模式标记：aircloud_data 据此判断 SIP 状态字段是否有效
-- （CC 模式不加载 sip_app_main，订阅不到 SIP_APP_STATE，上报会是假数据）
_G.WORK_MODE = mode

if mode == "factory" then
    log.info("main", "进入产测模式(USB 单通道)")
    require "factory"
else
    local prodmeta = require("prodmeta")
    log.info("main", "模组型号 PROD:", prodmeta.get("PROD"), "硬件版本 PCB:", prodmeta.get("PCB"))
    -- SIP + Air1103 依赖原生 crypto.checksum，缺失会在音频初始化阶段才报错，这里提前拦
    assert(crypto and type(crypto.checksum) == "function", "Native crypto.checksum is required for Air1103")

    if mode == "cc" then
        log.info("main", "进入业务模式:CC(SIP↔手机中转)")
        require "netdrv_device"
        require "cc_app_main"
    else
        log.info("main", "进入业务模式:SIP(云端通话)")
        require "app_main"
    end
    -- AirCloud 上报与云端下行：两种业务模式都加载
    require "aircloud_data"
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run() 之后不要添加任何语句!!!!!
