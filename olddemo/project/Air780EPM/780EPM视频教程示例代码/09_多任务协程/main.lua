-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "multitasking"--多任务
VERSION = "1.0.0"--程序版本号

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")--引入sys系统调度
--打印一下项目名称
log.info("main", "多任务",PROJECT)
--=============================================================
--烧水的协程
function boil_water()--烧水 
    while 1 do
        log.info("开始烧水")
        sys.wait(5000)--烧水5秒后
        sys.publish("水烧开了")
        log.info("水壶提示并发消息：", "水烧开了！！！")
        break
    end    
end
--=============================================================
--扫地的协程
function sweep_floor()--扫地
    while 1 do
        local result = sys.waitUntil("水烧开了",1000)--等待超时时间1000ms，超过就返回false而且不等了
        if result then
            log.info("水烧开了：", "我去关火")
            sys.publish("水烧开了，不扫地了去沏茶")
            break
        else
            log.info("水还没烧开：", "我要继续扫地")
        end
    end    
end
--=============================================================
--沏茶的协程
function make_tea()--沏茶
    while 1 do
        local result = sys.waitUntil("水烧开了，不扫地了去沏茶")--一直等待超，程序阻塞到这里了
        if result then
            log.info( "收到消息了，可以沏茶了")
        end
    end    
end
--=============================================================
sys.taskInit(boil_water)--这里就是创建了烧水的协程
sys.taskInit(sweep_floor)--这里就是创建了扫地的协程
sys.taskInit(make_tea)--这里就是创建了沏茶的协程
--=============================================================
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!