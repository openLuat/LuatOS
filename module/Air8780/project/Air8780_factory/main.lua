--[[
@module  main
@summary Air780EPM 工厂测试工程 主程序入口
@version 1.1.0
@date    2026.09.10
@author  江访
@usage
精简自 air780ehm_turnkey_devboard，去除所有UI相关代码，保留：
- SHT30 温湿度传感器读取
- VOC 传感器读取
- CPU 温度
- LBS 基站经纬度
- AirCloud 数据上报
- LED灯控制（闪烁/常亮/熄灭）
- 外部看门狗（Air153D）

硬件配置：
- 主控芯片: Air780EPM (Air780EHM)
- 温湿度传感器: SHT30 (I2C)
- VOC传感器: AGS02MA (I2C)
- LED指示灯: GPIO27（高电平点亮）
- 看门狗: Air153D (GPIO24)

云端通信：
- 使用 AirCloud excloud 协议
- 上报频率: 默认180秒，可通过web端远程修改
- 支持下行命令: 设置上报频率、LED控制

Web管理界面：
- 设备监控: 实时显示传感器数据、CPU温度、信号强度
- 设备控制: 修改上报频率、LED闪烁/常亮/熄灭
- 历史数据: 查看历史传感器数据、轨迹地图
]]

-- ==================== 项目配置 ====================
PROJECT = "Air780EHM_Sensor"          -- 项目名称
VERSION = "001.001.000"               -- 版本号
PROJECT_KEY = "v5WS2xbYWEJAQ5zcbkQKaBlIgZdYGFhK"  -- AirCloud项目密钥

log.info("main", PROJECT, VERSION)

-- ==================== 加载应用模块 ====================
-- app_main 会按顺序加载以下模块：
-- 1. netdrv_device: 网络驱动（4G/以太网）
-- 2. aircloud_app: 云平台通信（数据上报、命令下发）
-- 3. sensor_app: 传感器读取（SHT30+VOC）
-- 4. led_app: LED灯控制
-- 5. watchdog_app: 外部看门狗
require "app_main"

-- 用户代码已结束
sys.run()
-- sys.run()之后不要加任何语句
