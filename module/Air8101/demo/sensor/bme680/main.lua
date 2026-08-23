--[[
@module  main
@summary BME680 四合一环境传感器 Demo 入口
@version 1.0
@date    2026.08.08
@author  江访
]]

--[[
=== 演示内容 ===

本 demo 演示 exs_bme680 扩展库的完整功能，顺序为：
HELLO→[1/5]→[2/5]→[3/5]→[4/5]→[5/5]→End

1、初始化和数据读取（[1/5]）
2、IIR 滤波器切换演示（[2/5]）
3、过采样率切换演示（[3/5]）
4、气体加热器切换演示（[4/5]）
5、海拔高度测量与关闭（[5/5]）

更多说明参考本目录下的 readme.md 文件
]]

--[[
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]

PROJECT = "BME680_Demo"    -- 项目命名
VERSION = "001.999.000"    -- 项目版本号

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时/已使用/历史最高内存情况
-- 方便分析内存使用是否有异常
-- local function mem_check_func()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end
-- sys.timerLoopStart(mem_check_func, 3000)

-- 加载 bme680_demo.lua 演示模块（完整功能演示）
require "bme680_demo"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run() 之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
