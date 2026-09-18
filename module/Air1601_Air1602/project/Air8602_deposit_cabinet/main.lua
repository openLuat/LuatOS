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
-- 用 4G：require "network_4g"
-- 用 WiFi：require "netdrv_wifi"
require "netdrv_wifi"

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

-- 加载配置模块
local config = require "config"
config.init()

-- 系统初始化函数
local function system_init()
    log.info("main", "系统初始化开始")

    -- 初始化硬件（上电 + 屏幕 + 触摸）
    hardware.init()

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

    log.info("main", "系统初始化完成")
end

-- 启动系统初始化
sys.taskInit(system_init)

-- 启动主循环
sys.run()
