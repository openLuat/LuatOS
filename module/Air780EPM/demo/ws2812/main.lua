--[[
@module  main
@summary LuatOS用户应用脚本文件入口，只负责模块加载调度
@version 1.0
@date    2026.08.18
@author  杨乔杉
@usage
本 demo 演示 WS2812 22×22 全彩点阵的多种动效，包括色块覆盖/灯珠检测、
彩虹渐变、蛇形扫描、星点闪烁、矩形收缩、滚动文字。

适用产品范围：合宙 Air1780P / Air1780H / Air1780HV。
灯板尺寸不是 22×22 时，请修改 ws2812_config.lua 中的 LED_W / LED_H / LED_COUNT。

硬件接线：
  WS2812 DIN → GPIO16 (PIN97)
  5V/GND     → 外接 5V 电源（亮度较高时建议 5V/10A 以上）

更多说明参考本目录下的 readme.md 文件。
]]

-- PROJECT / VERSION 必须定义为 ASCII 字符串，供 Luatools 识别项目和远程升级匹配版本
PROJECT = "WS2812_testdemo"
VERSION = "001.999.000"

log.info("main", "project name is ", PROJECT, "version is ", VERSION)

-- ==================== 模块加载（require） ====================
-- 加载顺序：ws2812_config 必须最先，因为它定义全局表 WS2812_CFG，
-- 后续所有效果模块和命令模块都直接读取它。
require "ws2812_config"

-- 效果模块：同一时间只启用一个循环渲染任务，其余保持注释，
-- 否则多个任务同时写灯带会造成画面错乱。

-- 色块覆盖 / LED 灯珠检测（默认启用）
require "ws2812_blocks_task"

-- 彩虹渐变
-- require "ws2812_rainbow_task"

-- 蛇形扫描
-- require "ws2812_snake_task"

-- 星点闪烁
-- require "ws2812_sparkle_task"

-- 矩形收缩扩散
-- require "ws2812_rect_task"

-- 滚动文字（"欢迎使用LuatOS"，依赖 ws2812_fonts）
-- require "ws2812_scroll_task"

-- 串口命令接口：通过 USB 虚拟串口运行时调节亮度和速度
-- 命令：b=NNN 亮度0~255、s=NNN 帧间隔20~2000ms、b? 查询亮度、s? 查询速度
require "ws2812_cmd"

-- sys.run() 启动 LuatOS 事件循环，正常运行时永不返回，后面不要加任何代码
sys.run()
