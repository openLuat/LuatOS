--[[
@module  main
@summary 智能注塑车间 1# 产线监控总览 —— PLCUI 工程入口（纯加载器）
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件只做三件事：登记工程信息、打开可选的守护能力、把各功能模块拉进内存。
不写业务逻辑、不定义函数，末尾的 sys.run() 是运行时的主循环，缺了只会打印
「Lua VM exit!!」而没有任何报错，排查时优先看这一行在不在。

模块装载顺序即依赖顺序：
1、boot_app  —— 上电时序、显示与触摸初始化、界面载入、周期任务（末尾自挂主任务）
2、boot_app 会自行装载 data_app（业务数据）与 ui_app（界面刷新），无需在此重复装载
]]
---

-- 工程名与版本号，打包工具与日志都要读这两个全局量
PROJECT = "plcui_injection_line"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 硬狗：程序跑飞或卡死在死循环里时自动重启，9 秒超时，3 秒喂一次
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 错误日志转存到 luadb，每 600 秒落一个文件；开发阶段务必开着，定位崩溃全靠它
errDump.config(true, 600)

-- 差分升级：本工程默认不做远程升级，需要时再按「基础教程 - 差分升级」接入
-- 接入后升级期间界面停在当前页，升级成功自动重启，业务侧不用改动

-- 启动编排，装载后由它自己 taskInit 主任务，后续流程全在里面
require "boot_app"

-- 主循环，必须放在文件最后一行
sys.run()
