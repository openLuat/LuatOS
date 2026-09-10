--[[
@module  main
@summary air780ehm_sensor_only 主程序入口（精简版，无UI）
@version 1.0.0
@date    2026.09.09
@author  江访
@usage
精简自 air780ehm_turnkey_devboard，去除所有UI相关代码，仅保留：
- SHT30 温湿度传感器读取
- VOC 传感器读取
- CPU 温度
- LBS 基站经纬度
- AirCloud 数据上报
]]

PROJECT = "Air780EHM_Sensor"
VERSION = "001.000.001"
PROJECT_KEY = "v5WS2xbYWEJAQ5zcbkQKaBlIgZdYGFhK"

log.info("main", PROJECT, VERSION)

-- 加载应用主模块（传感器 + 云端 + FOTA）
require "app_main"

-- 用户代码已结束
sys.run()
-- sys.run()之后不要加任何语句
