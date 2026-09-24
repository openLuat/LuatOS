--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑 
@version 1.0
@date    2026.09.24
@author  朱天华
@usage
本demo演示的核心功能为：
1、多网融合驱动：netdrv_device.lua → net_config.lua + net_drv.lua
   使用 exnetif.set_priority_order 同时管理 WiFi + 双以太网 + 4G，
   支持运行时动态切网和配置保存
2、AirCloud数据上报：aircloud_data.lua 定时上报设备数据到AirCloud平台，
   并处理云端下发的继电器控制命令，同时启用 AirCloud 运维日志
3、airlbs定位：airlbs_app.lua 通过多基站+多wifi定位获取设备经纬度
4、modbus功能：
    - RTU从站：rtu_slave_regmap.lua（寄存器映射表 + 从站响应，接485串口板连电脑）
    - RTU主站：relay_ctrl.lua（隔离485 UART1，控制4路继电器模块 + 状态回读）
    - TCP主站：tcp_modbus_master.lua（网口1，读以太网温湿度变送器）
    - TCP从站：tcp_slave.lua（网口2, 端口502）
5、HTTP Web管理界面：httpsrv_web.lua（网口1端口80，PC浏览器访问192.168.1.183）
6、三色LED控制：led.lua（红/绿/蓝三路互斥，仅由 AirCloud 云端命令或 Web 页面控制，无自动灯效）
7、网络看门狗：net_watchdog.lua（网络业务长时间无通信且无IP时软件重启）
8、产测模式（双模合一，参考 Air8780 出厂固件分发逻辑）：
   开机按 fskv 标记 test_done 分流
   - 未完成产测（新板首次上电）→ require "factory" 进入产测模式
     （独占 USB 虚拟串口，产测指令见 firmware/doc/产测指令文档.md）
   - 已完成产测（TEST_DONE# 已置位）→ 加载下方全部业务模块，进入用户模式
   产测模式与业务模式资源互斥（UART1/UART3/双网口/三色 LED），不会同时运行
更多说明参考本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "Air8300_DataCollector"
VERSION = "001.999.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)
log.info("8300出厂固件：485温湿度传感器已替换为485继电器模块，温湿度改由Modbus TCP采集")


--[[
开机模式调试开关（出厂默认 "auto"）：
    "auto"    → 按产测标记 test_done 自动分流（出货标准行为）
    "normal"  → 强制进入业务模式（调试用，跳过产测）
    "factory" → 强制进入产测模式（重测用，无需清 fskv）
]]
local BOOT_MODE = "auto"


-- 添加软狗防止程序卡死（若固件支持 wdt）
if wdt then
    wdt.init(9000)                          -- 初始化 watchdog 设置为 9s
    sys.timerLoopStart(wdt.feed, 3000)      -- 3s 喂一次狗
end


-- 初始化 fskv（产测标记 test_done 存储）
fskv.init()


-- 开机模式判定：调试开关优先，其次按产测标记 test_done
local function get_boot_mode()
    if BOOT_MODE == "factory" then
        return "factory"
    end
    if BOOT_MODE == "normal" then
        return "normal"
    end
    if fskv.get("test_done") then
        return "normal"
    end
    return "factory"
end


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


if get_boot_mode() == "factory" then

    -- ================= 产测模式 =================
    log.info("main", "未完成产测，进入产测模式")
    require "factory"

else

    -- ================= 用户模式（业务） =================
    log.info("main", "已完成产测，进入用户模式")
    -- 打印产测阶段写入的工业模组型号(PROD)和硬件版本(PCB)（OTP 存储，重刷固件不丢）
    -- 注意：变量名用 prodmeta，不用 pm（LuatOS 有 pm 电源管理库，易混淆）
    do
        local prodmeta = require "prodmeta"
        log.info("main", "模组型号 PROD:", prodmeta.get("PROD"), "硬件版本 PCB:", prodmeta.get("PCB"))
    end

    -- 网络驱动设备功能模块
    require "netdrv_device"


    -- 开启以太网wan（使用静态 IP 地址）
    -- 已迁移到 net_drv.lua，由 exnetif.set_priority_order 统一管理
    -- require "netdrv_eth_static"


    -- airlbs 定位（多基站+多wifi定位）
    require "airlbs_app"

    -- RTU从站：寄存器映射表 + 从站响应
    require "rtu_slave_regmap"

    -- TCP Modbus从站
    require "tcp_slave"

    -- GPIO 控制
    require "gpio_ctrl"

    -- FOTA 远程升级
    require "fota_app"

    -- RTU Modbus主站：隔离485（UART1）控制4路继电器模块 + 状态回读
    require "relay_ctrl"

    -- TCP Modbus主站：网口1读取以太网温湿度变送器
    require "tcp_modbus_master"

    -- AirCloud 数据上报（依赖 relay_ctrl 的继电器状态）
    require "aircloud_data"

    -- 功耗管理
    require "power_mgr"

    -- HTTP Web管理界面
    require "httpsrv_web"

    -- 三色LED控制（AirCloud 云端命令 / Web 页面控制）
    require "led"

    -- 网络环境检测看门狗（网络业务喂狗超时且无IP时软件重启）
    require "net_watchdog"

end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
