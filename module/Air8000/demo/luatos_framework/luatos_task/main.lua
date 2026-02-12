--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑 
@version 1.0
@date    2025.07.19
@author  朱天华
@usage
本demo演示的核心功能为：
基于sys核心库提供的api，演示LuatOS框架（task，msg，timer，调度器）如何使用

更多说明参考本目录下的readme.md文件
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "luatos_framework_luatos_task"
VERSION = "001.000.000"

-- 以下两行代码是为了演示：task运行异常时，不自动重启软件的功能配置
-- _G.COROUTINE_ERROR_ROLL_BACK = false
-- _G.COROUTINE_ERROR_RESTART = false


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)




-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 加载“task调度”演示功能模块
require "scheduling"

-- 加载“task访问共享资源”演示功能模块
-- require "shared_resource"

-- 加载“查看用户可用ram信息”演示功能模块
-- require "memory_valid"

-- 加载“单个task占用的ram资源”演示功能模块
-- require "memory_task"

-- 加载“创建task的数量”演示功能模块
-- require "task_count"

-- 加载“task任务处理函数”演示功能模块
-- require "task_func"

-- 加载“task创建时的可变参数”演示功能模块
-- require "variable_args"

-- 加载“非目标消息回调函数”演示功能模块
-- require "non_targeted_msg"

-- 加载“用户全局消息处理”演示功能模块
-- require "global_msg_receiver1"
-- require "global_msg_receiver2"
-- require "global_msg_sender"

-- 加载“用户定向消息处理”演示功能模块
-- require "tgted_msg_receiver"
-- require "targeted_msg_sender"

-- 加载“定时器”演示功能模块
-- require "timer"

-- 加载“task内外部运行环境典型错误”演示功能模块
-- require "task_inout_env_err"

-- 加载“高级task的sys.taskDel函数对内存资源释放”演示功能模块 
-- require "memory_task_delete"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
