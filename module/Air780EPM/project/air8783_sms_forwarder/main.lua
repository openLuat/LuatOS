--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑 
@version 1.0
@date    2026.08.06
@author  王城钧
@usage
本demo演示的核心功能为：
1、通过AirCloud连接管理功能模块excloud_app.lua，实现设备与云平台的MQTT连接，包括：
- 应用层鉴权：通过TLV报文携带用户key+IMEI+MUID完成鉴权；
- 连接保活：启动心跳定时上报，维持连接活性；
- 运维日志：本地缓冲运行日志，定时上传云平台；
2、短信收发功能模块sms_bridge.lua，实现短信与应用报文的双向转换：
- 设备发送短信后，将短信发送结果（SMS_SENT）转换为TLV报文上传云平台；
- 短信送达状态（SMS_REPORT）解析后上传云平台；
- 收到云平台下发的短信指令（SMS_SEND）后，调起模组短信能力发送短信；
3、短信测试功能模块sms_app.lua，开机后自动执行上行短信测试用例；
4、短信调试日志功能模块sms_callback.lua，订阅短信事件并打印本地调试日志；
更多说明参考本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "8783_SMS"
VERSION = "001.999.009"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 加载短信调试功能模块
require "sms_callback"

-- 加载短信与应用协议桥接功能模块
require "sms_bridge"

-- 加载AirCloud（云平台）连接管理功能模块
require "excloud_app"

-- 加载短信测试应用功能模块
require "sms_app"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行