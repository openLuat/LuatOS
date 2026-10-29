-- @module  main
-- @summary 电表采集 + AirCloud 上报 demo（Air780EPM 方案）
-- @version 001.000.000
-- @date    2026.10.26
-- @author  OpenLuat
-- @demo    https://gitee.com/openluat/LuatOS
-- @BSD License
--[[
本 demo 功能：
1. 板载 RS485（串口2），Modbus-RTU 采集三相电表数据
2. 通过 AirCloud（合宙 IOT 通用报文协议）上报采集数据
3. 通过 Web 端（web/index.html）查看实时/历史数据

接线：
  RS485-A/B -> 电表 485 接线端子（A 对 A、B 对 B）
  板级资源统一由 app/board_hw.lua 管理：
    pm.ioVol(ALL_GPIO, 3300) 全 GPIO 高电平 3.3V（最先执行）
    GPIO25 485 芯片供电（上电拉高）、GPIO23 RS485 EN/方向脚（交 uart 硬件换向）
    GPIO22 运放电源（默认关）、GPIO24 可控电源输出（默认关）
    GPIO27 NET LED、GPIO30 Reload 键、GPIO28 硬件看门狗（可选）
    SIM 卡槽固定卡槽1(SIM0)；卡槽2 复用 GPIO4/5/6，暂不启用
    ADC2 供电电压 / ADC0 模拟量1 / ADC1 模拟量2

需要在 iot.openluat.com 创建项目获取 PROJECT_KEY 后填入下方。
]]

PROJECT      = "Air8780_MeterCloud"
VERSION      = "001.000.000"
PROJECT_KEY  = "v5WS2xbYWEJAQ5zcbkQKaBlIgZdYGFhK" -- TODO: 换成自己的 AirCloud 项目密钥

log.info("main", PROJECT, VERSION)

require "app_main"

sys.run()
