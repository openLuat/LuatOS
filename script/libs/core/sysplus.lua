
--[[
@module sysplus
@summary LuaTask核心增强逻辑
@version 1.0
@date    2022.04.27
@author  晨旭/刘清宇/李思琦
@usage

]]

local sys = require "sys"
local sysplus = {}

----------------------------------------------
-- 提供给异步c接口使用, by 晨旭
sysplus.cwaitMt = {
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
sysplus.cwaitMt.__index = function(t,i)
    if sysplus.cwaitMt[i] then
        return sysplus.cwaitMt[i](rawget(t,"w"),rawget(t,"r"))
    else
        rawget(t,i)
    end
end
_G.sys_cw = function (w,...)
    local r = {...}
    local t = {w=w,r=(#r > 0 and r or nil)}
    setmetatable(t,sysplus.cwaitMt)
    return t
end

-------------------------------------------------------------------
------------- 基于任务的task扩展 by 李思琦---------------------------

--任务列表
local taskList = {}

--- 创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可
-- @param fun 任务函数名，用于resume唤醒时调用
-- @param taskName 任务名称，用于唤醒任务的id
-- @param cbFun 接收到非目标消息时的回调函数
-- @param ... 任务函数fun的可变参数
-- @return co  返回该任务的线程号
-- @usage sysplus.taskInitEx(task1,'a',callback)
function sysplus.taskInitEx(fun, taskName, cbFun, ...)
    taskList[taskName]={msgQueue={}, To=false, cb=cbFun}
    return sys.taskInit(fun, ...)
end

--- 删除由taskInitEx创建的任务线程
-- @param taskName 任务名称，用于唤醒任务的id
-- @return 无
-- @usage sysplus.taskDel('a')
function sysplus.taskDel(taskName)
    taskList[taskName]=nil
end

local function waitTo(taskName)
    taskList[taskName].To = true
    sys.publish(taskName)
end

--- 等待接收一个目标消息
-- @param taskName 任务名称，用于唤醒任务的id
-- @param target 目标消息，如果为nil，则表示接收到任意消息都会退出
-- @param ms 超时时间，如果为nil，则表示无超时，永远等待
-- @return msg or false 成功返回table型的msg，超时返回false
-- @usage sysplus.waitMsg('a', 'b', 1000)
function sysplus.waitMsg(taskName, target, ms)
    local msg = false
    local message = nil
    if #taskList[taskName].msgQueue > 0 then
        msg = table.remove(taskList[taskName].msgQueue, 1)
        if target == nil then
            return msg
        end
        if (msg[1] == target) then
            return msg
        elseif type(taskList[taskName].cb) == "function" then
            taskList[taskName].cb(msg)
        end
    end
    sys.subscribe(taskName, coroutine.running())
    sys.timerStop(waitTo, taskName)
    if ms and ms ~= 0 then
        sys.timerStart(waitTo, ms, taskName)
    end
    taskList[taskName].To = false
    local finish=false
    while not finish do
        message = coroutine.yield()
        if #taskList[taskName].msgQueue > 0 then
            msg = table.remove(taskList[taskName].msgQueue, 1)
            -- sys.info("check target", msg[1], target)
            if target == nil then
                finish = true
            else
                if (msg[1] == target) then
                    finish = true
                elseif type(taskList[taskName].cb) == "function" then
                    taskList[taskName].cb(msg)
                end
            end
        elseif taskList[taskName].To then
            -- sys.info(taskName, "wait message timeout")
            finish = true
        end
    end
    if taskList[taskName].To then
        msg = nil
    end
    taskList[taskName].To = false
    sys.timerStop(waitTo, taskName)
    sys.unsubscribe(taskName, coroutine.running())
    return msg
end

--- 向目标任务发送一个消息
-- @param taskName 任务名称，用于唤醒任务的id
-- @param param1 消息中的参数1，同时也是waitMsg里的target
-- @param param2 消息中的参数2
-- @param param3 消息中的参数3
-- @param param4 消息中的参数4
-- @return true or false 成功返回true
-- @usage sysplus.sendMsg('a', 'b')
function sysplus.sendMsg(taskName, param1, param2, param3, param4)
    if taskList[taskName]~=nil then
        table.insert(taskList[taskName].msgQueue, {param1, param2, param3, param4})
        sys.publish(taskName)
        return true
    end
    return false
end

function sysplus.cleanMsg(taskName)
    if taskList[taskName]~=nil then
        taskList[taskName].msgQueue = {}
        return true
    end
    return false
end

function sysplus.taskCB(taskName, msg)
    if taskList[taskName]~=nil then
        if type(taskList[taskName].cb) == "function" then
            taskList[taskName].cb(msg)
            return
        end
    end
    log.error(taskName, "no cb fun")
end

_G.sys_send = sysplus.sendMsg
_G.sys_wait = sysplus.waitMsg

return sysplus
----------------------------
