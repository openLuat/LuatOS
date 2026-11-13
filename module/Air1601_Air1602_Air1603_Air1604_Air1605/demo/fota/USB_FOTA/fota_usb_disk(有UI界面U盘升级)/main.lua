--[[
@module  main
@summary U盘FOTA升级(有UI界面版) 程序入口，总体调度应用逻辑
@version 1.0
@date    2026.11.11
@author  谌程
@usage
-- U盘FOTA升级demo（有UI界面通用版）
-- 适用模块：Air8603系列(W1~W5/M1~M5)、Air8605系列（换板只改 conf.lua 的 M.board 一行）
-- 板型差异（屏幕/触摸/上电时序）全部在 conf.lua 的 PROFILES 里，换板只改 M.board 一行
--
-- 【功能】
-- 开机后屏幕显示待机页，USB常驻主机模式；插入存有 *.bin 升级包的U盘后，
-- 自动扫描并弹出选择页，用户点选升级包 -> 点[确认升级] -> 二次确认 -> 显示进度页 ->
-- fota写入+MD5校验 -> 校验通过自动重启 -> bootloader应用升级（日志版本号变化确认结果）
--
-- 【与无UI版的区别】
-- 无UI版是"开机5秒自动进入升级模式，固定读取 /udisk/update.bin"；
-- 本版是"开机即主机模式(先检查U盘是否已插好) + 插U盘自动弹选择页
-- + 用户点选升级包 + 进度可视化 + 点✕关闭回待机页"，
-- 失败后不重启也能换包重试。fota写入链路与无UI版完全一致。
--
-- 【注意】USB切主机模式后，Type-C虚拟串口日志不可用，请接UART日志串口查看
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        本demo用Luatools制作U盘升级包时同样使用"XXX.YYY.ZZZ"三段格式，差分/整包制作工具会识别
]]
PROJECT = "FOTA_USB_DISK_UI"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    -- 配置喂狗超时时间为9秒钟
    wdt.init(9000)
    -- 启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end


-- ==================== 板载 Air153D 外部硬件看门狗 ====================
-- 8603 W 系列板载独立的外部看门狗芯片（Air153D），喂狗脚 GPIO57 经 NPN 三极管接芯片 WTDOG。
-- 该芯片上电即计时（STRAP 选 10 分钟 / 60 分钟 / 12 小时 / 24 小时），不喂狗会
-- 超时拉 PWR_OFF → 拉低主控 RESET_N → 整机周期性硬件复位（约 10 多分钟一次）。
-- 上面的 wdt.init(9000) 只喂芯片内部软件狗，喂不到这颗外部芯片。
-- 编译系统按 require 的字面文本决定扩展库打包范围，故这里保持字面写法；
-- exair153x_wdt.lua 已放在本目录，随脚本一起打包烧录即可。
-- 各板是否启用/喂狗脚在 conf.lua 对应 profile 的 hw 字段里配置。
local CFG = require "conf"
if CFG.hw and CFG.hw.ext_wdt_enable then
    local function load_exair153x_wdt()
        return require "exair153x_wdt"
    end
    local ok, ext_wdt = pcall(load_exair153x_wdt)
    if ok and type(ext_wdt) == "table" then
        -- init 内部会 gpio.setup 引脚并 sys.taskInit 一个独立自动喂狗任务：
        -- 首次喂狗立即执行，之后默认每 180 秒发一次脉冲，无需另加 sys.timerLoopStart。
        if not ext_wdt.init({ wdt_pin = CFG.hw.ext_wdt_pin }) then
            log.error("main", "external watchdog init failed, Air153D NOT fed")
        end
    else
        -- 库没打进固件时不会中断启动，但设备仍会被外部硬狗周期性复位，故显式报错
        log.error("main", "exair153x_wdt not packed in firmware, Air153D NOT fed")
    end
else
    -- 关闭喂狗只在「板子确实没有外部硬狗」时才安全
    log.warn("main", "external watchdog disabled by config; Air153D will reset the board periodically")
end


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 加载配置模块（板型profile/USB参数/配色/字号，换板只改里面的 M.board）
require "conf"
-- 加载显示+触摸+AirUI初始化模块（上电时序->显示->AirUI->字库->GT911->绑定触摸）
require "lcd_tp"
-- 加载UI模块（待机页/选择页/进度页 + msgbox弹窗，订阅业务事件）
require "ui"
-- 加载U盘FOTA升级业务核心（常驻HOST/挂载/列目录/升级/失败重试）
-- 该模块被require即自行启动（内部完成 显示/触摸初始化->建界面->常驻任务->点亮背光），用法同fota2 demo的require "update"
require "fota_usb_disk_ui"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
