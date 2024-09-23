/*
@module  sys
@summary sys库
@version 1.0
@date    2019.11.23
@video https://www.bilibili.com/video/BV1194y1o7q2
@tag LUAT_USE_GPIO
*/

/*
Task协程等待指定时长
@api sys.wait(timeout)
@int 等待时长,单位毫秒,必须大于0,否则无效
@return any 通常为nil,除非主动被唤醒(通常不会)
@usage
sys.taskInit(function()
    while 1 do
        sys.wait(500)
    end
end)
*/
void doc_sys_wait(void){};

/*
Task协程等待指定时长或者特定的topic
@api sys.waitUntil(topic, timeout)
@string 事件topic
@int 等待时长,单位毫秒,必须大于0,否则无效
@return boolean 如果是超时,返回false,否则返回true
@return any 对应topic的内容
@usage
sys.taskInit(function()
    // do something
    local result, data = sys.waitUntil("NET_READY", 30000)
    // do something else
end)
*/
void doc_sys_waitUntil(void){};

/*
创建一个Task协程
@api sys.taskInit(func, arg1, arg2, argN)
@function 待执行的函数,可以是匿名函数, 也可以是local或全局函数
@any 需要传递的参数1,可选 
@any 需要传递的参数2,可选 
@any 需要传递的参数N,可选 
@return task 协程对象
@usage
sys.taskInit(function(a, b, c)
    log.info("task", a, b, c) -- 打印 task A B C
end, "A", "B", "N")
*/
void doc_sys_taskInit(void){};

/*
创建一个定时器.非Task,函数里不能直接sys.waitXXX
@api sys.timerStart(func, timeout, arg1, arg2, argN)
@function 待执行的函数,可以是匿名函数, 也可以是local或全局函数
@int 延时时长,单位毫秒
@any 需要传递的参数1,可选 
@any 需要传递的参数2,可选 
@any 需要传递的参数N,可选 
@return int 定时器id
@usage
sys.timerStart(function(a, b, c)
    log.info("task", a, b, c) -- 1000毫秒后才会执行, 打印 task A B C
end, 1000, "A", "B", "N")
*/
void doc_sys_timerStart(void){};

/*
创建一个循环定时器.非Task,函数里不能直接sys.waitXXX
@api sys.timerLoopStart(func, timeout, arg1, arg2, argN)
@function 待执行的函数,可以是匿名函数, 也可以是local或全局函数
@int 延时时长,单位毫秒
@any 需要传递的参数1,可选 
@any 需要传递的参数2,可选 
@any 需要传递的参数N,可选 
@return int 定时器id
@usage
sys.timerLoopStart(function(a, b, c)
    log.info("task", a, b, c) -- 1000毫秒后才会执行, 打印 task A B C
end, 1000, "A", "B", "N")
*/
void doc_sys_timerLoopStart(void){};

/*
关闭一个定时器.
@api sys.timerStop(id)
@int 定时器id
@return nil 无返回值
@usage
local tcount = 0
local tid 
tid = sys.timerLoopStart(function(a, b, c)
    log.info("task", a, b, c) -- 1000毫秒后才会执行, 打印 task A B C
    if tcount > 10 then
        sys.timerStop(tid)
    end
    tcount = tcount + 1
end, 1000, "A", "B", "N")
*/
void doc_sys_timerStop(void){};


/*
关闭同一回调函数的所有定时器.
@api sys.timerStopAll(fnc)
@function fnc回调的函数
@return nil 无返回值
@usage
-- 关闭回调函数为publicTimerCbFnc的所有定时器
local function publicTimerCbFnc(tag)
log.info("publicTimerCbFnc",tag)
end
sys.timerStart(publicTimerCbFnc,8000,"first")
sys.timerStart(publicTimerCbFnc,8000,"second")
sys.timerStart(publicTimerCbFnc,8000,"third")
sys.timerStopAll(publicTimerCbFnc)
*/
void doc_sys_timerStopAll(void){};


/*
往特定topic通道发布一个消息
@api sys.publish(topic, arg1, agr2, argN)
@string topic的值
@any 附带的参数1
@any 附带的参数2
@any 附带的参数N
@return nil 无返回值
@usage
sys.publish("BT_READY", false)
*/
void doc_sys_publish(void){};

/*
订阅一个topic通道
@api sys.subscribe(topic, func)
@string topic的值
@function 回调函数, 注意, 不能直接使用sys.waitXXX
@return nil 无返回值
@usage
local function bt_cb(state)
    log.info("bt", state)
end
sys.subscribe("BT_READY", bt_cb)
sys.subscribe("BT_READY", function(state)
    log.info("sys", "Got BT_READY", state)
end)
*/
void doc_sys_subscribe(void){};

/*
取消订阅topic通道
@api sys.unsubscribe(topic, func)
@string topic的值
@function 回调函数, 注意, 不能直接使用sys.waitXXX
@return nil 无返回值
@usage
local function bt_cb(state)
    log.info("bt", state)
end
sys.unsubscribe("BT_READY", bt_cb)
*/
void doc_sys_unsubscribe(void){};

/*
sys库主循环方法,仅允许在main.lua的末尾调用
@api sys.run()
@return nil 无返回值. 这个方法几乎不可能返回.
@usage
-- 总是main.lua的结尾一句,将来也许会简化掉
sys.run()
-- 之后的代码不会被执行
*/
void doc_sys_run(void){};
