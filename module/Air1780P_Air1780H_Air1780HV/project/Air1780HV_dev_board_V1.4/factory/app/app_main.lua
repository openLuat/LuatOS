--[[
@module  app_main
@summary 应用模块加载入口
@version 1.0.0
@date    2026.10.20
@usage
按依赖顺序加载各功能模块：
  1. netdrv_device: 网络驱动（以太网/PC 模拟器）
  2. aircloud_app:  AirCloud 云平台（数据上报 + 下行命令）
  3. sensor_app:    VOC + 485温湿度采集
  4. led_app:       LED 指示灯控制
  5. fota_app:      FOTA 固件升级（libfota3，自动检测/下载/重启）

模块间通信（sys.publish/subscribe）：
  - sensor_app → aircloud_app / ui: sys.publish("read_sensor_rsp", temp, hum, voc)
  - aircloud_app → sensor_app: sys.publish("set_report_cycle", seconds)
  - aircloud_app → led_app: sys.publish("led_blink_request") / sys.publish("led_set_request", 0/1)
  - fota_app → ui: sys.publish("FOTA_STATUS", status, msg, percent)
]]

-- 加载网络驱动（Air1780HV 无 4G，走板载 CH390H 以太网；PC 模拟器走 ETH0）
require "netdrv_device"

-- 加载 AirCloud 云平台模块
require "aircloud_app"

-- 加载传感器模块（VOC 空气质量 + 485温湿度）
require "sensor_app"

-- 加载 LED 控制模块（GPIO27）
require "led_app"

-- 加载 FOTA 固件升级模块
require "fota_app"
