--[[
@module  main
@summary AiP650E 数码管驱动芯片测试 Demo 入口
@version 1.0
@date    2026.07.13
@author  江访
]]

--[[
=== 演示内容 ===

本 demo 演示 exs_aip650e 扩展库的完整功能，顺序为：
HELLO→[1/6]→[2/6]→[3/6]→[4/6]→[5/6]→[6/6]→End
1、数码管字符串显示（[1/6]）
2、按键检测轮询（[2/6]）
3、按键回调演示（[3/6]）
4、亮度调节（[4/6]）
5、7段/8段模式切换（[5/6]）
6、综合演示-温度/时钟/睡眠（[6/6]）
]]

PROJECT = "AiP650E_Demo"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

-- 加载 aip650e_demo.lua 演示模块
require "aip650e_demo"

-- 主入口固定以 sys.run() 结尾
sys.run()
