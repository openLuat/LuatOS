--[[
@module  main
@summary 主窗口导航应用入口：主窗口通过 publish 消息打开4个子窗口，子窗口关闭后返回主窗口
@version 1.0.0
@date    2026.06.03
@author  合宙
@usage
本 demo 演示的核心功能为：
1、主窗口包含4个按钮，分别对应4个不同颜色的子窗口
2、点击主窗口按钮，通过 sys.publish 消息打开对应子窗口
3、子窗口仅包含一个关闭按钮，点击后关闭当前窗口并 publish 返回主窗口
4、启动时默认打开主窗口

导航链路：主窗口 → 子窗口1/2/3/4 → 主窗口（循环）

更多说明参考本目录下的 readme.md 文件
]]

PROJECT = "WINDOW_NAV"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 先 require 所有窗口模块，完成 sys.subscribe 注册
require "win_main"
require "win_sub_1"
require "win_sub_2"
require "win_sub_3"
require "win_sub_4"

-- require 后 publish，确保订阅者已注册
sys.publish("OPEN_MAIN_WIN")

-- 进入事件循环（必需）
sys.run()
