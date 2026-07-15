--[[
@module  main
@summary QMC5883L 三轴地磁传感器 Demo 入口
@version 1.0
@date    2026.07.14
@author  江访
]]

--[[
=== 演示内容 ===

本 demo 演示 exs_qmc5883l 扩展库的完整功能，顺序为：
HELLO→[1/3]→[2/3]→[3/3]→End
1、初始化和数据读取（[1/3]）
2、量程切换演示（[2/3]）
3、输出速率切换（[3/3]）

]]

--[[
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
-- main.lua - 程序入口文件

PROJECT = "QMC5883L_Demo"    -- 项目命名
VERSION = "001.999.000"    -- 项目版本号

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 加载 qmc5883l_demo.lua 演示模块
require "qmc5883l_demo"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!
