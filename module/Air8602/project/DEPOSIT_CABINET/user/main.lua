--[[
@module  main
@summary 8602寄存柜项目主入口
@version 001.999.001
@date    2026.08.31
@author  王城钧
@usage
系统主入口：加载硬件/业务/网络/串口/界面模块后，启动系统初始化任务并进入主循环。
通过 sys.publish("OPEN_EXPRESS_CABINET_WIN") 打开主窗口。
]]

PROJECT = "DEPOSIT_CABINET"
VERSION = "001.999.001"

log.info("main", PROJECT, VERSION)

--Air8601 4G_RST  拉低
-- gpio.setup(64, 0, gpio.PULLDOWN)

--Air8602 4G_RST  拉低
gpio.setup(58, 0, gpio.PULLDOWN)

-- 加载硬件初始化模块
local hardware = require "hardware"

-- 初始化屏幕密度缩放系数
hardware.init_density_scale()

-- 加载窗口管理扩展库，挂到全局 _G.exwin
_G.exwin = require "exwin"

-- 初始化 KV 数据库
fskv.init()

-- 加载业务模块
require "server_api"
require "ecbusiness"
require "aircloud"

-- 加载网络模块（require 即自动初始化，无需手动 init）
-- ★ 按硬件版本二选一（WiFi 版本 / 4G 版本）：
--   WiFi 版本 → require "netdrv_wifi"（Air6205 走 UART3 airlink）
--   4G 版本   → require "network_4g"（Air780ER2 走 UART3 airlink）
require "network_4g"

-- 加载串口控制器（485 锁）
require "uart_controller"

-- 加载寄存柜界面模块
require "ecabinet"
require "ecboxstatus"
require "ecsend"
require "ecrecv"
require "eccourier"
require "eccourier_detail"
require "echelp"

-- 事件记录模块（开箱/关箱/存件/取件事件 → 本地 CSV 流水 + AirCloud 上报）
require "event_reporter"

-- 加载配置模块
local config = require "config"
config.init()

-- 系统初始化函数
local function system_init()
    log.info("main", "系统初始化开始")

    -- 初始化硬件（上电 + 屏幕 + 触摸）
    hardware.init()

    -- 挂载 TF/SD 卡：SD_EN=GPIO74，SPI1 CS0=GPIO8（失败自动回退 /ram），开机即挂载
    -- 开箱/关箱等事件流水写入 /sd/log/cabinet_event_YYYYMMDD.csv
    sys.taskInit(function()
        local sd_card = require "sd_card"
        sd_card.init()
    end)

    -- 时间同步（SNTP）：RTC 掉电不保存，不校时的话 os.time() 会停在 2020-01-01，
    -- 事件时间戳（本地 CSV + 云端 TLV 的 TIMESTAMP/ts）就是错的。
    -- 做法与 8601 工程一致（libfota3.wait_time_sync）：socket.sntp() + 等 NTP_UPDATE。
    sys.taskInit(function()
        for _ = 1, 30 do                     -- 等网络就绪，最多 30 秒
            if socket.adapter(socket.dft()) then break end
            sys.wait(1000)
        end
        if not socket.adapter(socket.dft()) then
            log.warn("main", "网络未就绪，跳过时间同步")
            return
        end
        -- 时区：config.system.time_zone（+8）；API 不存在时忽略，不影响校时
        pcall(function() os.setTimezone(config.get("system.time_zone", 8)) end)
        socket.sntp()
        if sys.waitUntil("NTP_UPDATE", 30000) then
            log.info("main", "时间同步完成", os.date("%Y-%m-%d %H:%M:%S"), "tamp", os.time())
        else
            log.warn("main", "时间同步超时")
        end
    end)

    -- 等待 AirUI 首帧渲染完成后再打开窗口，避免开机白屏
    sys.wait(100)

    -- 打开主窗口
    sys.publish("OPEN_EXPRESS_CABINET_WIN")

    -- 读取锁状态
    sys.publish("READ_BOX_STATUS")

    -- 测试接口：模拟服务器下发存件命令
    local aircloud = require "aircloud"
    aircloud.test_send_save_command(1, "665501")  -- 柜子1，取件码665501
    aircloud.test_send_save_command(2, "778899")  -- 柜子2，取件码778899
    aircloud.test_send_save_command(3, "123456")  -- 柜子3，取件码123456

    -- 开机欢迎语：系统初始化完成后立即播报
    -- ectts 内部是队列 + 后台任务（等 500ms 初始化音频，播放失败自动重试 3 次），
    -- 这里只入队，不会阻塞开机流程
    local ectts = require "ectts"
    ectts.say("欢迎使用合宙智能寄存柜")

    log.info("main", "系统初始化完成")
end

-- 启动系统初始化
sys.taskInit(system_init)

-- 启动主循环
sys.run()
