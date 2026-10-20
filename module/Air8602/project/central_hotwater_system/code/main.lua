--[[
@module  main
@summary 太阳能热水工程控制系统 - 主入口
@version 001.000.001
@date    2026.10.12
@usage
main.lua 只做模块加载，不含任何界面 / 业务逻辑代码。
实际启动编排见 app_init。
]]

PROJECT = "SOLAR_HOTWATER"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

-- 加载启动编排模块（硬件初始化 -> 数据层 -> 打开主窗口）
require "app_init"

-- 用户代码已结束，结尾总是这一句
sys.run()
