--[[
@module  main
@summary 笔记应用入口
@version 1.0.0
@date    2026.04.09
@author  晁丹
@usage
笔记应用，支持笔记的一些基本功能
--]]

PROJECT = "NOTE"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载BLE从机窗口
require "note_win"

-- 发布打开窗口事件
sys.publish("OPEN_NOTE_WIN")

-- 运行系统
sys.run()
