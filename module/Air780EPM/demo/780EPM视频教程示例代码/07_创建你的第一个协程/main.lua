-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "task"--项目名称
VERSION = "1.0.0"--程序版本号

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")--引入sys系统调度

log.info("main", PROJECT)--打印一下项目名称

function test()--定义一个函数，名字就是test()
    while 1 do
        log.info(PROJECT, "我是一个函数")
        sys.wait(1000)--等待1000毫秒后，执行下一个语句
        log.info("这个函数的作用就是", "等待一秒后打印这条信息")
    end
    
end

-- 创建任务test并执行
sys.taskInit(test)--这里就是创建了一个协程


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!