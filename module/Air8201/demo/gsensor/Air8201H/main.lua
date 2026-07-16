--[[
@module   main
@summary  Air8201 DA267三轴加速度传感器demo主入口
@version  1.0
@date     2026.07.14
@usage
本demo演示的核心功能为：
1、DA267传感器I2C通信（I2C1, 地址0x26）
2、通过GPIO39中断引脚读取三轴加速度数据（X/Y/Z）
3、读取计步器数据
4、基于中断的运动/静止状态检测管理
5、传感器异常自动复位重连机制

注意事项：
- DA267通过I2C1（i2cId=1）通信，地址0x26，中断引脚GPIO39
- gpio24控制传感器供电，初始化时拉高
- 本传感器使用独立驱动（da267.lua），不能使用exvib扩展库（exvib仅支持DA221）
- manage.lua负责运动/静止状态判断逻辑
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，呈现递增关系，例如：1.1.1，1.1.2，1.1.3等等
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "Air201_da267"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require "sys"
sysplus = require("sysplus")

-- gnss的备电 和 gsensor的供电
local vbackup = gpio.setup(24, 1)

da267 = require "manage"

da267 = require "da267"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
