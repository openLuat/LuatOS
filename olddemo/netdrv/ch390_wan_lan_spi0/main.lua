--[[
CH390双网口SPI0复用演示程序
功能：通过单个SPI总线连接两个CH390芯片，实现WAN和LAN口功能
特点：
- 使用SPI0总线复用两个CH390设备
- WAN口：CS=GPIO12，用于外网连接
- LAN口：CS=GPIO8，用于内网管理
- 通过CS片选信号实现设备选择
- 支持DHCP、DNS代理、NAT转发等完整网关功能
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390_spi_mux"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

log.info("SPI复用", "CH390双网口演示程序启动")
log.info("硬件初始化", "配置CH390供电控制")

-- CH390 LAN口供电控制
log.info("LAN供电", "打开LAN口CH390供电 GPIO20")
gpio.setup(20, 1)  -- 打开LAN口供电

-- CH390 WAN口供电控制  
log.info("WAN供电", "打开WAN口CH390供电 GPIO29")
gpio.setup(29, 1)  -- 打开WAN口供电

-- 加载双网口复用核心逻辑
require "lan_wan"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

