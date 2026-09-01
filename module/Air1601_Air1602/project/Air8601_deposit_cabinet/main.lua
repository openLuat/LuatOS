--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.08.26
@author  王城钧
@usage
本工程为智能寄存柜（存件/取件/刷脸）应用：
1、硬件初始化：hardware.lua（GPIO上电、LCD、触摸、背光）
2、WiFi联网：netdrv_wifi.lua（Air1601 + Air6205，airlink UART3 桥接）
3、服务器通信：server_api.lua（云端API）
4、业务逻辑：ecbusiness.lua（存取件、柜子初始化）
5、AirCloud：aircloud.lua（取件码管理、云端指令）
6、485锁控：uart_controller.lua（开锁、读锁状态）
7、界面模块：ecabinet/ecboxstatus/ecsend/ecrecv/eccourier/eccourier_detail/echelp
8、人脸识别：face_manager/ecface/ecface_manage（AirCAMERA_1034 模组）
9、FOTA升级：fota_manager.lua
更多说明参考本目录下的readme.md文件
]]


PROJECT = "DEPOSIT_CABINET"
VERSION = "001.999.001"

-- 打印项目名和版本号
log.info("main", PROJECT, VERSION)


-- 硬件初始化模块（GPIO上电、LCD、触摸、背光）
local hardware = require "hardware"
hardware.init_density_scale()

-- 窗口管理扩展库（挂到全局 _G.exwin）
_G.exwin = require "exwin"

-- 初始化 KV 数据库
fskv.init()

-- 配置模块
local config = require "config"

-- 服务器接口模块
require "server_api"

-- 业务逻辑模块
require "ecbusiness"

-- AirCloud 模块
require "aircloud"

-- 网络模块（WiFi）
require "netdrv_wifi"

-- 485 锁控模块
require "uart_controller"

-- 界面模块
require "ecabinet"
require "ecboxstatus"
require "ecsend"
require "ecrecv"
require "eccourier"
require "eccourier_detail"
require "echelp"

-- 人脸识别模块
require "face_manager"
require "ecface"
require "ecface_manage"

-- FOTA 升级模块
require "fota_manager"

-- 看门狗初始化（关键！）：
-- Air1601 系统默认看门狗超时约 25 秒，而 fota 写 flash 是 CPU 阻塞操作（整包约 25 秒），
-- 期间 Lua VM 被 C 阻塞调用占住，任何 Lua 定时器喂狗都会失效 → wdt timeout 死机。
-- 解决：① 超时放大到 60 秒（覆盖写 flash 最长时间）② 每 3 秒定时喂狗。
if wdt then
    wdt.init(60000)
    sys.timerLoopStart(wdt.feed, 3000)
    log.info("main", "看门狗已初始化，超时 60 秒，每 3 秒喂狗")
end


-- 系统初始化任务：硬件上电 → 等待就绪 → 启动人脸/FOTA → 打开主窗口
local function system_init()
    -- 初始化硬件（上电 + 屏幕 + 触摸）
    hardware.init()

    -- 等待 AirUI 首帧渲染，避免白屏
    sys.wait(100)

    -- 延迟 300ms 初始化人脸模块：等 LCD/触摸完全就绪后再启动，
    -- 避免 camera.init 与 lcd.init 竞争资源导致屏幕异常
    sys.timerStart(function()
        local face_manager = require "face_manager"
        face_manager.init()
    end, 300)

    -- FOTA 升级：网络就绪后延迟启动（避免与初始化抢资源）
    local fota_cfg = config.get("fota", {})
    if fota_cfg.enabled then
        sys.timerStart(function()
            pcall(function()
                local fota_manager = require "fota_manager"
                fota_manager.start()
            end)
        end, 3000)
    end

    -- 打开主窗口、读取锁状态
    sys.publish("OPEN_EXPRESS_CABINET_WIN")
    sys.publish("READ_BOX_STATUS")

    -- 预下载小程序码：网络就绪后后台下载一次，存件窗口打开时直接显示真实码（避免每次现下等待）
    sys.taskInit(function()
        -- 等待网络就绪（最多等待 30 秒）
        for i = 1, 30 do
            if socket.adapter(socket.dft()) then break end
            sys.wait(1000)
        end
        if not socket.adapter(socket.dft()) then
            log.warn("main", "网络未就绪，跳过小程序码预下载")
            return
        end
        pcall(function()
            local server_api = require "server_api"
            local qr_path = "/qr_code_v288.jpeg"
            if io.exists(qr_path) then
                log.info("main", "小程序码文件已存在，跳过预下载")
                return
            end
            log.info("main", "开始预下载小程序码")
            server_api.generate_wechat_qr_code()
        end)
    end)

    log.info("main", "系统初始化完成")
end

sys.taskInit(system_init)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
