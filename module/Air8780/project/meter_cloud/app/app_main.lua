-- @module  app_main
-- @summary 模块加载与初始化顺序编排
-- @version 001.000.000
-- @date    2026.10.27
-- @author  OpenLuat
-- @BSD License
--[[
加载顺序（顺序有讲究）：
0. board_hw：板级资源 —— 必须最先执行，pm.ioVol(AIR780EPM, 3.3V) 要在
             任何 UART/GPIO 初始化之前生效，否则先初始化的脚副电平会停在默认值
   ① 所有 GPIO 高电平 3.3V
   ② SIM 卡槽定死为卡槽1(SIM0)，必须早于联网，见 board_hw.sim_select
   ③ RS485 芯片供电 GPIO25 拉高；GPIO23（EN/方向脚）交 uart.setup 硬件换向，勿手动拉高
   ④ 运放电源 GPIO22 默认关（真正做模拟量检测时调 board_hw.opamp_power(true)）
   ⑤ NET LED GPIO27、Reload 键 GPIO30（输入上拉）、看门狗 GPIO28、ADC 0/1/2
1. netdrv_device：网络适配层（4G / PC 模拟器）
2. meter_app：RS485 Modbus-RTU 电表采集（串口2，硬件自动换向）
3. aircloud_app：AirCloud 上报
]]

-- 注意：require 只返回模块表，不会创建同名全局变量，必须用局部变量接收
local board_hw = require "board_hw"
board_hw.init()

require "netdrv_device" -- 网络
require "meter_app"     -- 485 电表采集
require "ctrl_app"      -- 开关控制（电表继电器 0x05/0x0F + DI 反馈）
require "alarm_app"     -- 越限报警（订阅 METER_DATA，阈值可远程配）
require "aircloud_app"  -- AirCloud 上报

-- 网络灯：电表采集正常常亮，通信超时则闪烁（本地一眼看出链路状态）
sys.subscribe("METER_STATUS", function(e)
    if e and e.online then
        board_hw.net_led(true)
    else
        board_hw.net_led(nil) -- nil → 恢复闪烁
    end
end)

-- Reload 长按：现场复位
-- 注意：调试期先只打日志不重启，避免按键电平误判导致"开机即重启"的死循环；
-- 现场确认 GPIO30 空闲为高电平后，再把 rtos.reboot() 打开。
sys.subscribe("RELOAD_KEY_LONG", function()
    log.warn("app", "Reload 长按触发（当前仅记录，未执行重启）")
    -- sys.wait(100)
    -- rtos.reboot()
end)
