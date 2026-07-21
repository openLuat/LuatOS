--[[
@module  main
@summary VL53L1X 飞行时间测距传感器 Demo 入口
@version 1.0
@date    2026.07.21
@author  江访
]]

--[[
=== 演示内容 ===

本 demo 演示 exs_vl53l1x 扩展库的完整功能，顺序为：
HELLO→[1/5]→[2/5]→[3/5]→[4/5]→[5/5]→End
1、标准测距演示（[1/5]）
2、测距模式切换（[2/5]）
3、中断读取演示（[3/5]）
4、休眠与唤醒（[4/5]）
5、持续测距演示（[5/5]）

]]

PROJECT = "VL53L1X_Demo"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

require "vl53l1x_demo"

sys.run()
