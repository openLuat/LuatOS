--[[
@module  main
@summary ASRS-2400 立体库 PLC 主控屏 —— PLCUI 工程入口（纯加载器）
@version 1.0.0
@date    2026.11.22
@usage
本文件只做三件事：登记工程信息、打开可选的守护能力、把功能模块拉进内存。
不写业务逻辑、不定义函数；末尾的 sys.run() 是运行时主循环，
缺了只会打印「Lua VM exit!!」而没有任何报错，排查时优先看这一行在不在。
装载顺序即依赖顺序：boot_app 负责上电、显示、载入界面与周期任务，
它会自行装载 data_app（业务数据）与 ui_app（界面刷新），此处不重复装载。
]]

PROJECT = "mmy_asrs_plc"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 硬狗：程序跑飞或卡死在死循环里时自动重启，9 秒超时，3 秒喂一次
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 错误日志转存到 luadb，每 600 秒落一个文件；开发阶段务必开着
errDump.config(true, 600)

require "boot_app"

sys.run()
