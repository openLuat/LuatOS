--- 模块功能：Luat协程调度框架
--[[
@module sys
@summary LuaTask核心逻辑
@version 1.0
@date    2018.01.01
@author  稀饭/wendal/晨旭
@usage
-- sys一般会内嵌到固件内, 不需要手工添加到脚本列表,除非你正在修改sys.lua
-- 本文件修改后, 需要调用 update_lib_inline 对 vfs 中的C文件进行更新
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000)
    log.info("sys", "say hi")
end)

sys.run()
]]

local sys = {}

local table = _G.table
local unpack = table.unpack
local rtos = _G.rtos
local coroutine = _G.coroutine
local log = _G.log

-- lib脚本版本号，只要lib中的任何一个脚本做了修改，都需要更新此版本号
SCRIPT_LIB_VER = "2.3.2"

-- 任务定时器id最大值
local TASK_TIMER_ID_MAX = 0x1FFFFF
-- 消息定时器id最大值(请勿修改否则会发生msgId碰撞的危险)
local MSG_TIMER_ID_MAX = 0x7FFFFF

-- 任务定时器id（通过sys.wait或者sys.waitUntil接口创建定时器时动态分配的定时器id）
-- 定时器id的取值范围为0到TASK_TIMER_ID_MAX - 1
local taskTimerId = 0

-- 消息定时器id（通过sys.timerStart或者sys.timerLoopStart或者sys.waitMsg接口创建定时器时动态分配的定时器id）
-- 定时器id的取值范围为TASK_TIMER_ID_MAX +1 到 MSG_TIMER_ID_MAX
local msgId = TASK_TIMER_ID_MAX

-- 定时器处理表
-- 表中记录了两种类型的定时器
-- 第一种定时器记录的是定时器id和对应的回调函数
-- 第二种定时器记录的是定时器id和对应的task对象
-- 数据结构如下：
-- local timerPool = 
-- {
--     -- id1表示：通过sys.timerStart或者sys.timerLoopStart或者sys.waitMsg接口创建定时器时，sys.lua内部自动分配的定时器id
--     -- func1表示：定时器对应的回调函数，例如：sys.timerStart(blink_on, 5000)中的回调函数blink_on
--     [id1] = func1,

--     -- id2表示：通过sys.wait或者sys.waitUntil接口创建定时器时动态分配的定时器id
--     -- co2表示：创建定时器时，当前正常运行的协程（task）对象，例如：schedulig.lua中sys.wait所处的task对象
--     [id2] = co2,
-- 
--     ...
-- }
local timerPool = {}

-- 定时器回调函数参数表
-- 此处的定时器指的是timerPool中记录的第一种定时器
-- 数据结构如下：
-- local para = 
-- {
--     -- id1表示：通过sys.timerStart或者sys.timerLoopStart或者sys.waitMsg接口创建定时器时，sys.lua内部自动分配的定时器id
--     -- {...}表示：定时器对应的回调函数参数，例如：sys.timerStart(blink_on, 5000, "red", 1)中的{"red", 1}
--     [id1] = {...},

--     ...
-- }
local para = {}


--定时器是否循环表
--local loop = {}
--lua脚本运行出错时，是否回退为本地烧写的版本
--local sRollBack = true

_G.COROUTINE_ERROR_ROLL_BACK = true
_G.COROUTINE_ERROR_RESTART = true

-- 对coroutine.resume加一个修饰器用于捕获协程错误
--local rawcoresume = coroutine.resume
local function wrapper(co,...)
    local arg = {...}
    -- arg[1]为false，表示协程执行出错
    -- 此时arg[2]为错误信息描述字符串，例如：[string "hello_luatos.lua"]:27: attempt to perform arithmetic on a string value
    if not arg[1] then
        -- 可以获取到完整的当前协程的调用堆栈信息（包括函数调用链和行号），例如：
        -- stack traceback:
        -- [string "scheduling.lua"]:27: in function <[string "scheduling.lua"]:19>
        local traceBack = debug.traceback(co)


        -- arg[2]为错误信息描述：包括文件名，行数，错误信息字符串，例如：
        -- [string "scheduling.lua"]:27: attempt to perform arithmetic on a string value
        traceBack = (traceBack and traceBack~="") and (arg[2].."\r\n"..traceBack) or arg[2]
        log.error("coroutine.resume",traceBack)
        --if errDump and type(errDump.appendErr)=="function" then
        --    errDump.appendErr(traceBack)
        --end

        -- 此处COROUTINE_ERROR_ROLL_BACK变量设为了true，表示：
        -- 如果某一个协程运行错误，则启动一个500毫秒的定时器，500毫秒之后，执行assert(false, traceBack)
        -- 最终表现为：日志中输出traceBack的信息，然后Lua虚拟机异常退出，15秒后自动重启软件；例如：
        -- Luat:
        -- [string "sys.lua"]:434: [string "scheduling.lua"]:27: attempt to perform arithmetic on a string value
        -- stack traceback:
        --         [string "scheduling.lua"]:27: in function <[string "scheduling.lua"]:19>
        -- Lua VM exit!! reboot in 15000ms
        -- 根据这里的代码设计，我们可以知道，如果应用脚本中某一个task（协程）运行异常时，此时其余task的都还可以正常运行
        -- 如果不想自动重启软件，则可以在main.lua中的最开始的位置，设置：
        -- _G.COROUTINE_ERROR_ROLL_BACK = false
        -- _G.COROUTINE_ERROR_RESTART = false
        if _G.COROUTINE_ERROR_ROLL_BACK then
            sys.timerStart(assert,500,false,traceBack)
        elseif _G.COROUTINE_ERROR_RESTART then
            rtos.reboot()
        end
    -- else
    --     log.info("coroutine.resume return", unpack(arg))
    end
    return ...
end
sys.coresume = function(...)
    local arg = {...}
    -- 此处先执行coroutine.resume(...)，表示运行协程，运行时传入了协程对象和处理函数的可变参数
    -- coroutine.resume返回多个值：
    -- 第一个值是布尔值，表示协程是否执行成功
    -- 如果执行成功，第一个返回值为true
    --             后续的返回值是协程运行中，通过coroutine.yield接口使这个协程挂起时传递的参数；
    --                                    或者是协程正常运行结束的返回值（当协程执行完毕时）；
    -- 如果执行中出现错误，第一个返回值为false，第二个返回值是错误信息
    return wrapper(arg[1], coroutine.resume(...))
end


-- 判断当前运行环境是否在一个协程的处理函数中
-- 如果是，co为协程对象
function sys.check_task()
    local co, ismain = coroutine.running()
    if ismain then
        error(debug.traceback("attempt to yield from outside a coroutine"))
    end
    return co
end

--- Task任务延时函数，只能用于任务函数中
-- @number ms  整数，最大等待126322567毫秒
-- @return 定时结束返回nil,被其他线程唤起返回调用线程传入的参数
-- @usage sys.wait(30)
function sys.wait(ms)
    -- 参数检测，参数不能为负值
    --assert(ms > 0, "The wait time cannot be negative!")
    -- 判断当前运行环境是否在一个协程的处理函数中
    -- 如果是，co为协程对象
    local co = sys.check_task()

    -- 为定时器申请id
    -- 定时器id的取值范围为0 到 TASK_TIMER_ID_MAX - 1
    -- 将定时器id和协程对象记录到定时器处理表timerPool中
    -- timerPool[timerid] = co
    while true do
        if taskTimerId >= TASK_TIMER_ID_MAX - 1 then
            taskTimerId = 0
        else
            taskTimerId = taskTimerId + 1
        end
        if timerPool[taskTimerId] == nil then
            break
        end
    end
    local timerid = taskTimerId
    timerPool[timerid] = co

    -- 调用core的rtos定时器
    if 1 ~= rtos.timer_start(timerid, ms) then log.debug("rtos.timer_start error") return end

    -- 挂起调用的任务协程
    -- 协程恢复时：当再次调用coroutine.resume(co, ...)恢复协程时，resume传入的...参数会作为上此处yield的返回值。
    local message = {coroutine.yield()}
    
    -- 下面这段代码适用于以下场景，例如
    -- sys.waitUntil("SIM_IND", 120000)
    -- 在120秒定时器消息达到之前，首先产生了"SIM_IND"消息，会在上一行代码的coroutine.yield()返回，切换为运行状态
    -- 此时执行下面的代码，将正在运行的定时器停止运行，并且删除
    if #message ~= 0 then
        rtos.timer_stop(timerid)
        timerPool[timerid] = nil
        return unpack(message)
    end
end

--- Task任务的条件等待函数（包括事件消息和定时器消息等条件），只能用于任务函数中。
-- @param id 消息ID
-- @number ms 等待超时时间，单位ms，最大等待126322567毫秒
-- @return result 接收到消息返回true，超时返回false
-- @return data 接收到消息返回消息参数
-- @usage result, data = sys.waitUntil("SIM_IND", 120000)
function sys.waitUntil(id, ms)
    -- 判断当前运行环境是否在一个协程的处理函数中
    -- 如果是，co为协程对象
    local co = sys.check_task()

    -- 在全局消息订阅表subscribers中添加一条记录
    -- subscribers[id][co] = true
    -- 表示当前协程需要处理id表示的消息
    sys.subscribe(id, co)

    -- 如果传入了ms参数，表示配置了等待超时参数
    -- 此时直接执行sys.wait(ms)：在wait函数内部，创建运行定时器，并且挂起当前协程
    -- 当定时器超时消息到达或者id表示的消息达到时，当前协程切换为运行状态
    -- 当定时器超时消息触发的状态切换，此时返回值message为{sys.wait(ms)}，为{}
    -- 当id表示的消息触发的状态切换，此时返回值message为{sys.wait(ms)}，为{id, {...}}

    -- 如果没有传入ms参数，表示一直在等待id表示的消息
    -- 此时直接执行下一行代码中的coroutine.yield()，挂起当前协程
    -- 当id表示的消息达到时，当前协程切换为运行状态
    -- 此时返回值message为{coroutine.yield()}，为{id, {...}}
    local message = ms and {sys.wait(ms)} or {coroutine.yield()}

    -- 在全局消息订阅表subscribers中清除一条记录
    -- subscribers[id][co] = nil
    -- 表示当前协程不再需要处理id表示的消息
    sys.unsubscribe(id, co)

    -- 如果是id表示的消息到达退出了阻塞等待状态，则message[1] ~= nil为true
    -- 如果是定时器超时消息到达退出了阻塞等待状态，则message[1] ~= nil为false
    return message[1] ~= nil, unpack(message, 2, #message)
end

-- 此函数不给外部使用，忽略
--- 同上，但不返回等待结果
function sys.waitUntilMsg(id)
    local co = sys.check_task()
    sys.subscribe(id, co)
    local message = {coroutine.yield()}
    sys.unsubscribe(id, co)
    return unpack(message, 2, #message)
end

-- 此函数不给外部使用，忽略
--- Task任务的条件等待函数扩展（包括事件消息和定时器消息等条件），只能用于任务函数中。
-- @param id 消息ID
-- @number ms 等待超时时间，单位ms，最大等待126322567毫秒
-- @return message 接收到消息返回message，超时返回false
-- @return data 接收到消息返回消息参数
-- @usage result, data = sys.waitUntilExt("SIM_IND", 120000)
function sys.waitUntilExt(id, ms)
    local co = sys.check_task()
    sys.subscribe(id, co)
    local message = ms and {sys.wait(ms)} or {coroutine.yield()}
    sys.unsubscribe(id, co)
    if message[1] ~= nil then return unpack(message) end
    return false
end

--- 创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可
-- @param fun 任务函数名，用于resume唤醒时调用
-- @param ... 任务函数fun的可变参数
-- @return co  返回该任务的线程号
-- @usage sys.taskInit(task1,'a','b')
function sys.taskInit(fun, ...)
    -- 创建协程，返回协程对象co
    -- 创建一个Lua协程，协程的处理函数为fun，返回一个协程对象co
    -- 执行这一行代码之后，这个协程并不会运行，而是处于挂起状态
    local co = coroutine.create(fun)

    -- 启动运行协程，传入协程对象和任务处理函数携带的可变参数
    sys.coresume(co, ...)
    return co
end

------------------------------------------ rtos消息回调处理部分 ------------------------------------------
--[[
函数名：cmpTable
功能  ：比较两个table的内容是否相同，注意：table中不能再包含table
参数  ：
t1：第一个table
t2：第二个table
返回值：相同返回true，否则false
]]
local function cmpTable(t1, t2)
    if not t2 then return #t1 == 0 end
    if #t1 == #t2 then
        for i = 1, #t1 do
            if unpack(t1, i, i) ~= unpack(t2, i, i) then
                return false
            end
        end
        return true
    end
    return false
end

--- 关闭定时器
-- @param val 值为number时，识别为定时器ID，值为回调函数时，需要传参数
-- @param ... val值为函数时，函数的可变参数
-- @return 无
-- @usage timerStop(1)
function sys.timerStop(val, ...)
    -- val为number类型时，表示定时器id
    if type(val) == 'number' then
        -- 在定时器处理表timerPool中，清空定时器id val对应的处理函数记录
        -- 在定时器回调函数参数表para中，清空定时器id val对应的回调函数的参数记录
        timerPool[val], para[val] = nil, nil

        -- 调用内核固件的接口，停止并且删除定时器id val对应的定时器
        rtos.timer_stop(val)
    -- val为其他类型时（实际上仅支持function类型），表示定时器的回调函数
    else
        for k, v in pairs(timerPool) do
            -- 根据回调函数，从定时器处理表timerPool中找到定时器id
            -- v为function类型，下一行代码实际上判断的是v == val
            if type(v) == 'table' and v.cb == val or v == val then
                -- 根据定时器id，从定时器会回调函数参数表中，判断可变参数相同
                if cmpTable({...}, para[k]) then
                    rtos.timer_stop(k)
                    timerPool[k], para[k] = nil, nil
                    break
                end
            end
        end
    end
end

--- 关闭同一回调函数的所有定时器
-- @param fnc 定时器回调函数
-- @return 无
-- @usage timerStopAll(cbFnc)
function sys.timerStopAll(fnc)
    for k, v in pairs(timerPool) do
        -- 根据回调函数，从定时器处理表timerPool中找到定时器id
        -- v为function类型，下一行代码实际上判断的是v == fnc
        if type(v) == "table" and v.cb == fnc or v == fnc then
            rtos.timer_stop(k)
            timerPool[k], para[k] = nil, nil
        end
    end
end

function sys.timerAdvStart(fnc, ms, _repeat, ...)
    --回调函数和时长检测
    --assert(fnc ~= nil, "sys.timerStart(first param) is nil !")
    --assert(ms > 0, "sys.timerStart(Second parameter) is <= zero !")

    -- 关闭完全相同的定时器
    -- 定时器回调函数+回调参数的方式，可以唯一标识一个定时器
    -- 所以此处调用sys.timerStop接口，传入回调函数+回调参数，就可以关闭之前的重复定时器
    local arg = {...}
    if #arg == 0 then
        sys.timerStop(fnc)
    else
        sys.timerStop(fnc, ...)
    end

    -- 为定时器申请id
    -- 定时器id的取值范围为TASK_TIMER_ID_MAX +1 到 MSG_TIMER_ID_MAX
    -- 将定时器id和定时器回调函数记录到定时器处理表timerPool中
    -- timerPool[msgId] = fnc
    while true do
        if msgId >= MSG_TIMER_ID_MAX then msgId = TASK_TIMER_ID_MAX end
        msgId = msgId + 1
        if timerPool[msgId] == nil then
            timerPool[msgId] = fnc
            break
        end
    end
    --调用内核固件接口创建并且启动定时器
    if rtos.timer_start(msgId, ms, _repeat) ~= 1 then
        log.error("rtos.timer_start", "create fail!!!")
        return
    end

    --如果存在回调函数的可变参数，在定时器回调函数参数表para中保存参数
    if #arg ~= 0 then
        para[msgId] = arg
    end

    --返回定时器id
    return msgId
end

--- 开启一个定时器
-- @param fnc 定时器回调函数
-- @number ms 整数，最大定时126322567毫秒
-- @param ... 可变参数 fnc的参数
-- @return number 定时器ID，如果失败，返回nil
function sys.timerStart(fnc, ms, ...)
    return sys.timerAdvStart(fnc, ms, 0, ...)
end

--- 开启一个循环定时器
-- @param fnc 定时器回调函数
-- @number ms 整数，最大定时126322567毫秒
-- @param ... 可变参数 fnc的参数
-- @return number 定时器ID，如果失败，返回nil
function sys.timerLoopStart(fnc, ms, ...)
    return sys.timerAdvStart(fnc, ms, -1, ...)
end

--- 判断某个定时器是否处于开启状态
-- @param val 有两种形式
--一种是开启定时器时返回的定时器id，此形式时不需要再传入可变参数...就能唯一标记一个定时器
--另一种是开启定时器时的回调函数，此形式时必须再传入可变参数...才能唯一标记一个定时器
-- @param ... 可变参数
-- @return number 开启状态返回true，否则nil
function sys.timerIsActive(val, ...)
    -- 根据定时器id来判断
    if type(val) == "number" then
        return timerPool[val]
    -- 根据定时器回调函数和回调参数来判断
    else
        for k, v in pairs(timerPool) do
            if v == val then
                if cmpTable({...}, para[k]) then return true end
            end
        end
    end
end


------------------------------------------ LUA应用消息订阅/发布接口 ------------------------------------------
-- 全局消息订阅表
-- 数据结构如下：
-- local subscribers = 
-- {
--     [msg1] = 
--     {
--         cbfunc1 = true,  -- sys.subscribe(msg1, cbfunc1)
--         task1 = true,    -- 在task1的处理函数中，调用sys.waitUntil(msg1[, timeout])
--         cbfunc2 = true,
--         task2 = true,
--         ......
--         cbfuncN = true,
--         taskN = true,
--     },

--    [msg2] = { ...... },
--    [msg3] = { ...... },
--    ......,
--    [msgN] = { ...... }
-- }
local subscribers = {}

-- 全局消息队列
-- 数据结构如下：
-- local messageQueue = 
-- {
--     [1] = {msg1, {...}},    --sys.publish(msg1, ...)
--     [2] = {msg2, {...}},
--     [3] = {msg3, {...}},

--     ......,
--     [n] = { ...... }
-- }
local messageQueue = {}

--- 订阅消息
-- @param id 消息id
-- @param callback 消息回调处理
-- @usage subscribe("NET_STATUS_IND", callback)
function sys.subscribe(id, callback)
    --if not id or type(id) == "boolean" or (type(callback) ~= "function" and type(callback) ~= "thread") then
    --    log.warn("warning: sys.subscribe invalid parameter", id, callback)
    --    return
    --end
    --log.debug("sys", "subscribe", id, callback)
    -- 下面这段if语句的使用方法，在api文档中没有介绍，在demo代码中从来没有用到，忽略
    if type(id) == "table" then
        -- 支持多topic订阅
        for _, v in pairs(id) do sys.subscribe(v, callback) end
        return
    end

    -- 下面两行代码
    -- 在全局消息订阅表中，增加一条“消息和对应的回调函数”的记录
    if not subscribers[id] then subscribers[id] = {} end
    subscribers[id][callback] = true
end
--- 取消订阅消息
-- @param id 消息id
-- @param callback 消息回调处理
-- @usage unsubscribe("NET_STATUS_IND", callback)
function sys.unsubscribe(id, callback)
    --if not id or type(id) == "boolean" or (type(callback) ~= "function" and type(callback) ~= "thread") then
    --    log.warn("warning: sys.unsubscribe invalid parameter", id, callback)
    --    return
    --end
    --log.debug("sys", "unsubscribe", id, callback)
    -- 下面这段if语句的使用方法，在api文档中没有介绍，在demo代码中从来没有用到，忽略
    if type(id) == "table" then
        -- 支持多topic订阅
        for _, v in pairs(id) do sys.unsubscribe(v, callback) end
        return
    end

    -- 下面的if else语句
    -- 在全局消息订阅表中，删除一条“消息和对应的回调函数”的记录
    if subscribers[id] then
        subscribers[id][callback] = nil
    else
        return
    end

    
    -- 下面的几行代码
    -- 判断一下当前消息是否还有其他的订阅者
    -- 如果没有任何订阅者，则清除消息的记录
    for k, _ in pairs(subscribers[id]) do
        return
    end
    subscribers[id] = nil
end

--- 发布内部消息，存储在内部消息队列中
-- @param ... 可变参数，用户自定义
-- @return 无
-- @usage publish("NET_STATUS_IND")
function sys.publish(...)
    -- 在全局消息队列末尾插入记录一条全局消息
    table.insert(messageQueue, {...})
end

-- 循环分发处理全局消息队列messageQueue中的所有消息
local function dispatch()
    while true do
        if #messageQueue == 0 then
            break
        end
        
        -- 从全局消息队列messageQueue中取出来队首的消息
        local message = table.remove(messageQueue, 1)

        -- 根据取出的队首消息，在全部消息订阅表中查找是否有订阅者
        if subscribers[message[1]] then
            local tmpt = {}
            -- 将消息的所有订阅者（回调函数和task对象）临时存放到tmpt中
            for callback, _ in pairs(subscribers[message[1]]) do
                table.insert(tmpt, callback)
            end

            -- 遍历所有订阅者
            -- 根据订阅者类型，执行回调函数或者恢复运行task
            for _, callback in ipairs(tmpt) do
                if type(callback) == "function" then
                    callback(unpack(message, 2, #message))
                elseif type(callback) == "thread" then
                    sys.coresume(callback, unpack(message))
                end
            end
        end
    end
end

-- rtos消息回调
--local handlers = {}
--setmetatable(handlers, {__index = function() return function() end end, })

--- 注册rtos消息回调处理函数
-- @number id 消息类型id
-- @param handler 消息处理函数
-- @return 无
-- @usage rtos.on(rtos.MSG_KEYPAD, function(param) handle keypad message end)
--function sys.on(id, handler)
--    handlers[id] = handler
--end

------------------------------------------ Luat 主调度框架  ------------------------------------------
function sys.safeRun()
    -- 循环分发处理全局消息队列messageQueue中的所有消息
    dispatch()
    -- 阻塞读取内核消息队列中第一条消息
    local msg, param, exparam = rtos.receive(rtos.INF_TIMEOUT)
    -- log.info("rtos.receive", msg, param, exparam)
    -- 空消息?
    if not msg or msg == 0 then
        -- 如果走到了这里，说明rtos.receive在内核固件的业务逻辑中：
        -- 已经取出了一条消息，并且在内核固件中自动处理了，例如：
        -- uart接收到新数据的中断消息，会在rtos.receive中自动调用uart.on(uart_id, "receive", cbfun)中的cbfun
        -- log.info("sys.safeRun", "needn't handle")
    
    -- 从内核消息队列中读到了定时器消息
    -- msg为rtos.MSG_TIMER
    -- param为定时器id
    -- exparam表示是否为循环定时器
    elseif msg == rtos.MSG_TIMER and timerPool[param] then
        -- 任务定时器类型
        if param < TASK_TIMER_ID_MAX then
            local taskId = timerPool[param]
            -- 任务定时器只能是单次定时器，所以从定时器处理表中删除此定时器记录
            timerPool[param] = nil
            -- 将等待定时器消息的任务，由挂起阻塞状态切换为运行状态
            sys.coresume(taskId)
        -- 消息定时器类型
        else
            -- 取出来当前定时器对应的回调函数
            local cb = timerPool[param]
            -- 如果不是循环定时器，从定时器处理表中删除此定时器记录
            if exparam == 0 then timerPool[param] = nil end

            -- 当前定时器的回调函数有回调参数
            if para[param] ~= nil then
                cb(unpack(para[param]))
                -- 如果不是循环定时器，从定时器回调函数参数表中删除此定时器记录
                if exparam == 0 then para[param] = nil end
            -- 当前定时器的回调函数没有回调参数
            else
                cb()
            end
            --如果是循环定时器，继续启动此定时器
            --if loop[param] then rtos.timer_start(param, loop[param]) end
        end
    --其他消息（音频消息、充电管理消息、按键消息等）
    --elseif type(msg) == "number" then
    --    handlers[msg](param, exparam)
    --else
    --    handlers[msg.id](msg)
    end
end

--- run()从底层获取core消息并及时处理相关消息，查询定时器并调度各注册成功的任务线程运行和挂起
-- @return 无
-- @usage sys.run()
-- log.info("_G.SYSP", _G.SYSP)
-- _G.SYSP为nil，所以此处定义了sys.run()就是一直在循环执行sys.safeRun()
if _G.SYSP then
    function sys.run() end
else
    function sys.run()
        while true do
            sys.safeRun()
        end
    end
end

-- _G是Lua的全局环境表
-- 这里给_G定义了一个全局函数sys_pub
-- sys_pub的作用是：内核固件的C代码中直接发布全局消息，Lua脚本中订阅此全局消息的应用都可以接收处理，例如：网络环境准备就绪的消息"IP_READY"
_G.sys_pub = sys.publish

-- 并入原本的sysplus


-- 以下给异步C接口使用的几个api，在sys核心库中，没有开发给用户直接使用；忽略
----------------------------------------------
-- 提供给异步c接口使用, by 晨旭
sys.cwaitMt = {
    wait = function(t,r)
        return function()
            if r and type(r) == "table" then--新建等待失败的返回
                return table.unpack(r)
            end
            return sys.waitUntilMsg(t)
        end
    end,
    cb = function(t,r)
        return function(f)
            if type(f) ~= "function" then return end
            sys.taskInit(function ()
                if r and type(r) == "table" then
                    --sys.wait(1)--如果回调里调用了sys.publish，直接调用回调，会触发不了下一行的吧。。。
                    f(table.unpack(r))
                    return
                end
                f(sys.waitUntilMsg(t))
            end)
        end
    end,
}
sys.cwaitMt.__index = function(t,i)
    if sys.cwaitMt[i] then
        return sys.cwaitMt[i](rawget(t,"w"),rawget(t,"r"))
    else
        rawget(t,i)
    end
end
_G.sys_cw = function (w,...)
    local r = {...}
    local t = {w=w,r=(#r > 0 and r or nil)}
    setmetatable(t,sys.cwaitMt)
    return t
end

-------------------------------------------------------------------
------------- 基于任务的task扩展 by 李思琦---------------------------

-- 高级task的任务列表
-- 数据结构如下：
-- local taskList = 
-- {
--     ["task_name1"] =
--     {
--         -- 定向消息队列，用来存储sys.sendMsg("task_name1", param1, param2, param3, param4)给"task_name1"的高级task发布的param1, param2, param3, param4消息参数
--         -- table.insert(taskList["task_name1"].msgQueue, {param1, param2, param3, param4})
--         msgQueue = {{param1, param2, param3, param4}, {}, ...}, 

--         -- sys.waitMsg(taskName, target, ms)时，如果传入了ms超时时长，并且当前task在阻塞等待target消息；
--         -- 则To表示阻塞等待过程中，是否因为超时原因退出了阻塞等待状态
--         To = false, 

--         -- 非目标消息回调函数
--         cb = cbFun
--     }, 

--     ["task_name2"] =
--     {
--     },
-- 
--     ...
-- }
local taskList = {}

--- 创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可
-- @param fun 任务函数名，用于resume唤醒时调用
-- @param taskName 任务名称，用于唤醒任务的id
-- @param cbFun 接收到非目标消息时的回调函数
-- @param ... 任务函数fun的可变参数
-- @return co  返回该任务的线程号
-- @usage sys.taskInitEx(task1,'a',callback)
function sys.taskInitEx(fun, taskName, cbFun, ...)
    if taskName == nil then
        log.error("sys", "taskName is nil", debug.traceback())
        return
    end

    -- 在高级task任务列表中，申请此高级任务对应的定向消息队列、阻塞等待定向消息超时标志、非目标消息回调函数
    taskList[taskName]={msgQueue={}, To=false, cb=cbFun}

    -- 创建一个基础task
    return sys.taskInit(fun, ...)
end

--- 删除由taskInitEx创建的任务线程
-- @param taskName 任务名称，用于唤醒任务的id
-- @return 无
-- @usage sys.taskDel('a')
function sys.taskDel(taskName)
    -- 释放taskName对应的高级task全部信息表资源，
    -- 释放的是taskList[taskName] 对应的 {msgQueue={}, To=false, cb=cbFun}占用的内存
    -- 因为taskList是全局变量，会一直存在；
    -- 如果taskList[taskName]没有赋值为nil，则taskList[taskName]一直引用{msgQueue={}, To=false, cb=cbFun}
    -- 此时Lua的垃圾回收机制永远不会自动回收{msgQueue={}, To=false, cb=cbFun}所占用的内存
    -- 所以在高级task的任务处理函数执行结束，每个return语句正常退出前，或者最后执行结束自然退出前，
    -- 都要调用sys.taskDel(taskName)，释放{msgQueue={}, To=false, cb=cbFun}占用的内存
    -- 如果高级task的任务处理函数运行过程中，发生异常退出，这种情况下，即使我们写了sys.taskDel(taskName)，也不会被执行
    -- 遇到这种问题，需要怎么处理呢？分为以下两种情况：
    -- 1、目前的LuatOS设计，当task运行异常退出，默认会自动重启软件系统，
    --    这种情况下，软件都重启了，就不用考虑未释放的内存问题了；
    -- 2、如果你看懂了sys.lua的内部设计，当task运行异常退出时，可以控制不重启软件系统，
    --    这种情况下，就需要修改sys.lua的内部设计，可以自动释放异常退出的高级task对应的信息表资源内存，
    --    目前还没有实现这种功能，后续如果客户有需求，可以开发支持
    taskList[taskName]=nil
end

-- 等待定向消息定时器回调函数
local function waitTo(taskName)
    taskList[taskName].To = true
    sys.publish(taskName)
end

--- 等待接收一个目标消息
-- @param taskName 任务名称，用于唤醒任务的id
-- @param target 目标消息，如果为nil，则表示接收到任意消息都会退出
-- @param ms 超时时间，如果为nil，则表示无超时，永远等待
-- @return msg or false 成功返回table型的msg，超时返回false
-- @usage sys.waitMsg('a', 'b', 1000)
function sys.waitMsg(taskName, target, ms)
    -- 此接口只推荐在sys.taskInitEx创建的高级task的任务处理函数中使用
    if taskList[taskName] == nil then
        log.error("sys", "sys.taskInitEx启动的task才能使用waitMsg")
        return false
    end
    local msg = false
    local message = nil

    -- 如果定向消息队列中有消息
    while #taskList[taskName].msgQueue > 0 do
        -- 取出来队首的消息
        msg = table.remove(taskList[taskName].msgQueue, 1)

        -- 如果没有指定期望接收的消息，则表示期望接收任何消息
        -- 直接返回队首的消息给用户脚本去处理
        if target == nil then
            return msg
        end

        -- 如果队首消息是期望处理的消息
        -- 直接返回队首的消息给用户脚本去处理
        if (msg[1] == target) then
            return msg
        -- 如果队首消息不是期望处理的消息，并且也传入了非目标消息回调函数
        -- 则直接将队首消息丢给非目标消息回调函数去处理
        -- 然后while循环继续判断下一条消息
        elseif type(taskList[taskName].cb) == "function" then
            taskList[taskName].cb(msg)
        end
    end

    -- 走到了这里，说明定向消息队列中已经没有消息
    
    -- 使用当前task对象订阅名称为taskName的全局消息
    sys.subscribe(taskName, coroutine.running())

    -- 如果传入了ms参数，启动一个等待定向目标消息超时定时器
    sys.timerStop(waitTo, taskName)
    if ms and ms ~= 0 then
        sys.timerStart(waitTo, ms, taskName)
    end
    taskList[taskName].To = false


    local finish=false
    while not finish do
        -- 阻塞挂起当前task
        -- 以下两种情况，会退出挂起状态，切换为运行状态：
        -- 1、当调用sys.sendMsg接口向此定向消息队列中发送一条消息时，会publish一条名称为taskName的全局消息
        --    在sys.run()下次调度时，会分发处理这条全局消息，发现当前task订阅了这条全局消息，所以将当前task切换为运行状态
        -- 2、等待定向目标消息超时定时器超时后，在waitTo函数中，也会publish一条名称为taskName的全局消息
        --    在sys.run()下次调度时，会分发处理这条全局消息，发现当前task订阅了这条全局消息，所以将当前task切换为运行状态
        message = coroutine.yield()

        -- 如果定向消息队列中有消息
        if #taskList[taskName].msgQueue > 0 then
            -- 取出来队首的消息
            msg = table.remove(taskList[taskName].msgQueue, 1)
            -- sys.info("check target", msg[1], target)
            -- 如果没有指定期望接收的消息，则表示期望接收任何消息
            -- 退出while循环
            if target == nil then
                finish = true
            else
                -- 如果队首消息是期望处理的消息
                -- 退出while循环
                if (msg[1] == target) then
                    finish = true
                -- 如果队首消息不是期望处理的消息，并且也传入了非目标消息回调函数
                -- 则直接将队首消息丢给非目标消息回调函数去处理
                -- 不退出wbile循环，下次循环继续判断消息队列中的下一条消息
                elseif type(taskList[taskName].cb) == "function" then
                    taskList[taskName].cb(msg)
                end
            end
        -- 如果定向消息队列中没有消息，则表示此次恢复运行时定时器超时消息触发
        -- 退出此while循环
        elseif taskList[taskName].To then
            -- sys.info(taskName, "wait message timeout")
            finish = true
        end
    end

    -- 定时器超时消息触发，结束等待消息
    -- 这种情况下，表示没有等到目标消息
    if taskList[taskName].To then
        msg = nil
    end

    -- 复位定时器超时标志，关闭定时器，取消全局消息订阅
    taskList[taskName].To = false
    sys.timerStop(waitTo, taskName)
    sys.unsubscribe(taskName, coroutine.running())

    -- 接收到目标消息，返回table类型的定向消息{msg, para2, para3, para4}
    -- 超时返回nil
    return msg
end

--- 向目标任务发送一个消息
-- @param taskName 任务名称，用于唤醒任务的id
-- @param param1 消息中的参数1，同时也是waitMsg里的target
-- @param param2 消息中的参数2
-- @param param3 消息中的参数3
-- @param param4 消息中的参数4
-- @return true or false 成功返回true
-- @usage sys.sendMsg('a', 'b')
function sys.sendMsg(taskName, param1, param2, param3, param4)
    if taskList[taskName]~=nil then
        -- 向taskName所表示的高级task的定向消息队列中，插入一条定向消息
        table.insert(taskList[taskName].msgQueue, {param1, param2, param3, param4})

        -- 此处发布一条名称为taskName的全局消息，此消息的作用分为以下两种情况来描述：
        -- 1、如果taskName所表示的高级task正在sys.waitMsg接口阻塞等待接收消息，
        --    则可以控制task切换为运行状态，从定向消息队列中读消息进行后续处理
        -- 2、如果taskName所表示的高级task不在sys.waitMsg接口阻塞等待接收消息，
        --    则此处的publish消息接口没有任何作用，在下次sys.run()取出此消息后，会自动丢弃，不做任何处理
        sys.publish(taskName)
        return true
    end
    return false
end

-- 清空taskName所表示的高级task定向消息队列中的所有消息
function sys.cleanMsg(taskName)
    if taskList[taskName]~=nil then
        taskList[taskName].msgQueue = {}
        return true
    end
    return false
end

-- 这个函数目前没有直接开放给用户使用，忽略
function sys.taskCB(taskName, msg)
    if taskList[taskName]~=nil then
        if type(taskList[taskName].cb) == "function" then
            taskList[taskName].cb(msg)
            return
        end
    end
    log.error(taskName, "no cb fun")
end

-- _G是Lua的全局环境表
-- 这里给_G定义了两个全局函数sys_send和sys_wait
-- sys_send的作用是：内核固件的C代码中直接发送定向消息给Lua脚本中的高级task，例如socket.EVENT类型的消息
-- sys_wait的作用是：目前没有直接开放给用户使用，忽略
_G.sys_send = sys.sendMsg
_G.sys_wait = sys.waitMsg

return sys
----------------------------
