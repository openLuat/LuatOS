--[[
@module  app_main
@summary 应用主入口模块
@version 1.1.0
@date    2026.09.10
@author  江访
@usage
应用模块加载入口，按依赖顺序加载各功能模块。

加载顺序说明：
1. netdrv_device: 网络驱动设备（最先加载，提供网络连接能力）
2. aircloud_app: 云平台应用（依赖网络，提供数据上报和命令下发）
3. sensor_app: 传感器应用（依赖云端，采集数据供上报）
4. led_app: LED控制应用（独立模块，响应云端LED命令）
5. watchdog_app: 看门狗应用（独立模块，防止系统死机）

模块间通信：
- sensor_app → aircloud_app: sys.publish("read_sht30_voc_rsp", temp, hum, voc)
- aircloud_app → sensor_app: sys.publish("set_report_cycle", seconds)
- aircloud_app → led_app: sys.publish("led_blink_request") / sys.publish("led_set_request", 0/1)
- led_app → aircloud_app: sys.publish("led_status", "on"/"off"/"blinking")
]]

-- ==================== 加载网络驱动 ====================
-- 根据硬件平台自动选择网卡驱动（4G/以太网/WiFi/PC模拟器）
require "netdrv_device"

-- ==================== 加载云平台模块 ====================
-- AirCloud excloud 协议，负责：
-- - 与云端建立TCP连接
-- - 定期上报传感器数据（温度、湿度、VOC、CPU温度、LBS经纬度）
-- - 接收并处理下行命令（设置上报频率、LED控制）
require "aircloud_app"

-- ==================== 加载传感器模块 ====================
-- 传感器数据采集，负责：
-- - 定时读取SHT30温湿度传感器（I2C）
-- - 定时读取VOC空气质量传感器（I2C）
-- - 上报频率可通过云端远程修改，保存到fskv断电不丢失
require "sensor_app"

-- ==================== 加载LED控制模块 ====================
-- LED指示灯控制，负责：
-- - 响应云端LED控制命令（闪烁5秒/常亮/熄灭）
-- - 使用GPIO27控制LED（高电平点亮）
require "led_app"

-- ==================== 加载看门狗模块 ====================
-- 外部看门狗（Air153D），负责：
-- - 定时喂狗防止系统死机
-- - 使用GPIO24控制看门狗芯片
require "watchdog_app"

