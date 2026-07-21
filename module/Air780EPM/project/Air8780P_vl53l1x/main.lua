--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.07.21
@author  江访
@usage
本demo演示Air8780P工业模组+VL53L1X激光测距传感器的低功耗数据采集与上报流程：
1、VL53L1X激光测距传感器数据采集
2、通过合宙iot平台(excloud)和MQTT上报传感器数据
3、支持libfota2远程升级
4、PSM+低功耗模式

更多说明参考本目录下的readme.md文件
]]

--[[
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
-- main.lua - 程序入口文件
PROJECT = "Air8780P_VL53L1X"
VERSION = "001.999.000"
PRODUCT_KEY = "PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ"  -- 用于合宙IOT平台FOTA升级，此处仅为示例，实际使用请修改为自己的PRODUCT_KEY

-- 打印项目名和版本号
log.info("main", PROJECT, VERSION)


-- 加载网络驱动设备功能模块（4G网卡）
require "netdrv_device"

-- 加载VL53L1X业务逻辑主模块
require "app_vl53l1x_main"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句
