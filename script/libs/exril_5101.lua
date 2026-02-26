--[[
@summary exril_5101扩展库
@version 1.3
@date    2026.2.26
@author  王世豪
@usage
-- 应用场景：
本模块专为基于Air5101的蓝牙通信设备设计，提供完整的蓝牙连接管理、数据传输、参数配置和状态监控功能。
集成了ril AT命令处理模块，无需额外的ril.lua文件。

-- 实现的功能：
1. 蓝牙连接管理：自动检测连接状态，支持主动断开连接
2. 工作模式切换：支持AT指令模式和UART透传模式
3. 参数配置：设备名称、广播参数、连接参数等配置
4. 数据收发：支持在透传模式下双向数据通信
5. 状态查询：实时查询连接状态和设备信息
6. 系统控制：模块重启、恢复出厂设置、看门狗控制
7. 功耗管理：多级功耗模式配置

-- 用法实例：
本扩展库对外提供了以下接口：
1. 核心接口：
exril_5101.on(cbfunc)                              -- 注册事件回调
exril_5101.mode(mode, timeout)                     -- 切换工作模式
exril_5101.set(config, timeout)                    -- 配置参数
exril_5101.get(key, timeout)                       -- 获取设备信息
exril_5101.send(data, wakeup_option, timeout)      -- 向已连接的蓝牙主设备发送数据
exril_5101.disconnect(timeout)                     -- 断开连接
exril_5101.status(timeout)                         -- 查询连接状态
exril_5101.wakeup(source, level, width, timeout)   -- 配置唤醒主控功能

2. 系统控制接口：
exril_5101.restart(timeout)                        -- 软重启模块
exril_5101.restore(timeout)                        -- 恢复出厂设置
exril_5101.save(timeout)                           -- 保存配置到Flash

3. 功耗管理接口：
exril_5101.power(mode, timeout)                    -- 设置功耗模式

4. 看门狗接口：
exril_5101.wdcfg(enable, timeout, level, width, sync_timeout)   -- 配置看门狗
exril_5101.wdfed(timeout)                          -- 喂狗操作

同步/异步调用说明：
1. 同步调用(默认)：若不提供callback参数，则视为同步，由函数返回结果；
2. 异步调用(可选)：若提供了callback参数，则视为异步，函数立即返回，结果通过callback回调。

同步调用示例：
local success, message = exril_5101.mode(exril_5101.MODE_AT)
if success then
    log.info("main", "切换到AT指令模式成功")
else
    log.error("main", "切换到AT指令模式失败:", message)
end

异步调用示例：
local function mode_switch_callback(success, message)
    if success then
        log.info("main", "切换到AT指令模式成功")
    else
        log.error("main", "切换到AT指令模式失败:", message)
    end
end
exril_5101.mode(exril_5101.MODE_AT, mode_switch_callback)
]]

local exril_5101 = {}
local ril = {}

-- =============== 常量定义 ===============
-- 功耗模式常量
exril_5101.P0 = "exril_5101.P0"  -- 常规模式0
exril_5101.P1 = "exril_5101.P1"  -- 低功耗模式1，蓝牙可连接，唤醒后保持低功耗模式1
exril_5101.P3 = "exril_5101.P3"  -- 低功耗模式3，唤醒后自动恢复常规模式

-- 蓝牙工作模式
exril_5101.MODE_UA = "exril_5101.MODE_UA"  -- uart透传模式
exril_5101.MODE_AT = "exril_5101.MODE_AT"    -- AT指令模式

-- 广播类型
exril_5101.ADV_N = "0x02"       -- 不可连接广播
exril_5101.ADV_C = "0x03"       -- 可连接广播

-- 超时设置
local DEFAULT_TIMEOUT = 200    -- 默认同步超时时间（毫秒）
local MAX_TIMEOUT = 10000      -- 最大同步超时时间（毫秒）

-- =============== 内部状态变量 ===============
local exril_5101_current_mode = exril_5101.MODE_UA  -- 当前模式，默认透传模式
local exril_5101_connected = false             -- 连接状态
local user_callback = nil                 -- 用户回调函数
local urc_registered = false              -- 是否已注册URC处理器
local exril_5101_power_mode = exril_5101.P0         -- 当前功耗模式，默认P0


-- =============== ril部分 ===============
local UART_ID = 1
local UART_BAUDRATE = 9600

-- 加载常用的全局函数至本地
local vwrite = uart.write
local vread = uart.read
local TIMEOUT = 10000

-- 前向声明urc_handler
local urc_handler

-- AT命令的应答类型
-- NORESULT：收到的应答数据当做urc通知处理，如果发送的AT命令不处理应答或者没有设置类型，默认为此类型
-- NUMBERIC：纯数字类型；例如发送AT+CGSN命令，应答的内容为：862991527986589\r\nOK，此类型指的是862991527986589这一部分为纯数字类型
-- SLINE：有前缀的单行字符串类型；例如发送AT+CSQ命令，应答的内容为：+CSQ: 23,99\r\nOK，此类型指的是+CSQ: 23,99这一部分为单行字符串类型
-- MLINE：有前缀的多行字符串类型；例如发送AT+CMGR=5命令，应答的内容为：+CMGR: 0,,84\r\n0891683108200105F76409A001560889F800087120315123842342050003590404590D003A59\r\nOK，此类型指的是OK之前为多行字符串类型
-- STRING：无前缀的字符串类型，例如发送AT+ATWMFT=99命令，应答的内容为：SUCC\r\nOK，此类型指的是SUCC
-- SPECIAL：特殊类型，需要针对AT命令做特殊处理，例如CIPSEND、CIPCLOSE、CIFSR
-- ATRESP: 特殊类型，针对响应格式为AT:data做的特殊处理，典型应用：Air5101
-- UA_TRANSPARENT：透传数据模式，专门处理UA模式下的原始数据透传，典型应用：Air5101
local NORESULT, NUMBERIC, SLINE, MLINE, STRING, SPECIAL, ATRESP, UA_TRANSPARENT = 0, 1, 2, 3, 4, 10, 11, 12

-- AT命令的应答类型表，预置了如下几项
local RILCMD = {}

-- radioready：AT命令通道是否准备就绪
-- delaying：执行完某些AT命令前，需要延时一段时间，才允许执行这些AT命令；此标志表示是否在延时状态
local radioready, isupdate, delaying = true
local updateRcvFun
-- AT命令队列
local cmdqueue = {}
-- 当前正在执行的AT命令,参数,反馈回调,延迟执行时间,命令头,类型,反馈格式
local currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt, cmdRspParam
-- 反馈结果,中间信息,结果信息
local result, interdata, respdata

-- ril会出现三种情况:
-- 发送AT命令，收到应答
-- 发送AT命令，命令超时没有应答
-- 底层软件主动上报的通知，下文我们简称为urc
--[[
函数名：atimeout
功能  ：发送AT命令，命令超时没有应答的处理
参数  ：无
返回值：无
]]
local function atimeout()
    -- sys.restart("ril.atimeout_" .. (currcmd or ""))
    currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt = nil, nil, nil, nil, nil, nil, nil
    result, interdata, respdata = nil, nil, nil
    sys.publish("RIL_AT_TIMEOUT")
end

local function defrsp(cmd, success, response, intermediate)
    log.info("ril.defrsp", cmd, success, response, intermediate)
end

local rsptable = {}
setmetatable(rsptable, {
    __index = function()
        return defrsp
    end
})
local formtab = {}

---注册某个AT命令应答的处理函数
-- @param head  此应答对应的AT命令头，去掉了最前面的AT两个字符
-- @param fnc   AT命令应答的处理函数
-- @param typ   AT命令的应答类型，取值范围NORESULT,NUMBERIC,SLINE,MLINE,STRING,SPECIAL
-- @param formt typ为STRING时，进一步定义STRING中的详细格式
-- @return bool ,成功返回true，失败false
-- @usage ril.regRsp("+CSQ", rsp)
function ril.regRsp(head, fnc, typ, formt)
    -- 没有定义应答类型
    if typ == nil then
        rsptable[head] = fnc
        return true
    end
    -- 定义了合法应答类型
    if typ == 0 or typ == 1 or typ == 2 or typ == 3 or typ == 4 or typ == 10 then
        -- 如果AT命令的应答类型已存在，并且与新设置的不一致
        if RILCMD[head] and RILCMD[head] ~= typ then
            return false
        end
        -- 保存
        RILCMD[head] = typ
        rsptable[head] = fnc
        formtab[head] = formt
        return true
    else
        return false
    end
end

--[[
函数名：rsp
功能  ：AT命令的应答处理
参数  ：无
返回值：无
]]
local function rsp()
    -- 停止应答超时定时器
    sys.timerStopAll(atimeout)

    -- 如果发送AT命令时已经同步指定了应答处理函数
    if currsp then
        currsp(currcmd, result, respdata, interdata)
        -- 用户注册的应答处理函数表中找到处理函数
    else
        rsptable[cmdhead](currcmd, result, respdata, interdata, cmdRspParam)
    end
    -- 重置全局变量
    -- if cmdhead == "+CIPSEND" and cipsendflag then
    --     return
    -- end
    currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt = nil, nil, nil, nil, nil, nil, nil
    result, interdata, respdata = nil, nil, nil
end

--[[
函数名：defurc
功能  ：urc的默认处理。如果没有定义某个urc的应答处理函数，则会走到本函数
参数  ：
data：urc内容
返回值：无
]]
local function defurc(data)
    log.info("ril.defurc", data)
end

-- urc的处理表
local urctable = {}
setmetatable(urctable, {
    __index = function()
        return defurc
    end
})

--- 注册某个urc的处理函数
-- @param prefix    urc前缀，最前面的连续字符串，包含+、大写字符、数字的组合
-- @param handler   urc的处理函数
-- @return 无
-- @usage ril.regUrc("+CREG", neturc)
function ril.regUrc(prefix, handler)
    urctable[prefix] = handler
end

--- 解注册某个urc的处理函数
-- @param prefix    urc前缀，最前面的连续字符串，包含+、大写字符、数字的组合
-- @return 无
-- @usage deRegUrc("+CREG")
function ril.deRegUrc(prefix)
    urctable[prefix] = nil
end

-- “数据过滤器”，虚拟串口收到的数据时，首先需要调用此函数过滤处理一下
local urcfilter

--[[
函数名：urc
功能  ：urc处理
参数  ：
data：urc数据
返回值：无
]]
local function urc(data)
    local prefix = string.match(data, "([%+%*]*[%a%d& ]+)")
    -- log.info("URC调试", "原始数据:", data, "匹配到的前缀:", prefix)
    -- 执行prefix的urc处理函数，返回数据过滤器
    urcfilter = urctable[prefix](data, prefix)
end

--[[
函数名：procatc
功能  ：处理虚拟串口收到的数据
参数  ：
data：收到的数据
返回值：无
]]
local function procatc(data)
    -- log.info("ril.proatc", data)
    log.info("ril.proatc", data, "cmdtype:", cmdtype, "cmdhead:", cmdhead)
    -- 如果命令的应答是多行字符串格式
    if interdata and cmdtype == MLINE then
        -- 不出现OK\r\n，则认为应答还未结束
        if data ~= "OK\r\n" then
            -- 去掉最后的\r\n
            if string.find(data, "\r\n", -2) then
                data = string.sub(data, 1, -3)
            end
            -- 拼接到中间数据
            interdata = interdata .. "\r\n" .. data
            return
        end
    end
    -- 如果存在“数据过滤器”
    if urcfilter then
        data, urcfilter = urcfilter(data)
    end
    -- 数据为空
    if data == "" then
        return
    end
    -- 当前无命令在执行则判定为urc
    if currcmd == nil then
        -- 检查是否是透传模式下的数据
        if exril_5101_current_mode == exril_5101.MODE_UA then
            -- 透传模式下，直接调用urc_handler处理
            urc_handler(data, nil)
        else
            -- AT模式下，按正常URC处理
            urc(data)
        end
        return
    end

    local isurc = false

    -- 一些特殊的错误信息，转化为ERROR统一处理
    if string.find(data, "ERROR") then
        data = "ERROR"
    end
        -- 执行成功的应答
    if data == "OK" or data == "AT:OK" or data == "UT:OK" then
        result = true
        respdata = data
        -- 执行失败的应答
    elseif data == "ERROR" or data == "AE" or data == "UE" then
        result = false
        respdata = data
    else
        -- 无类型
        if cmdtype == NORESULT then
            isurc = true
            -- 全数字类型
        elseif cmdtype == NUMBERIC then
            local numstr = string.match(data, "(%x+)")
            if numstr == data then
                interdata = data
            else
                isurc = true
            end
            -- 字符串类型
        elseif cmdtype == STRING then
            if string.match(data, rspformt or "^.+$") then
                interdata = data
            else
                isurc = true
            end
        elseif cmdtype == SLINE or cmdtype == MLINE then
            if interdata == nil and string.find(data, cmdhead) == 1 then
                interdata = data
            else
                isurc = true
            end
        elseif cmdtype == ATRESP then
            if string.match(data, rspformt or "^AT:.+$") then
                interdata = data
                -- 直接完成，不需要等待OK
                result = true
                respdata = data
            else
                isurc = true
                -- log.warn("ril.proatc", "ATRESP类型格式不匹配:", data, "期望格式:", rspformt)
            end
        else
            isurc = true
        end
    end

    -- log.info("ril.proatc判断", "isurc:", isurc, "result:", result, "interdata:", interdata)

    -- urc处理
    if isurc then
        -- log.info("ril.proatc", "当作URC处理")
        urc(data)
    -- 应答处理
    elseif result ~= nil then
        -- log.info("ril.proatc", "调用rsp()")
        rsp()
    end
end

-- 是否在读取虚拟串口数据
local readat = false

--[[
函数名：getcmd
功能  ：解析一条AT命令
参数  ：
item：AT命令
返回值：当前AT命令的内容
]]
local function getcmd(item)
    local cmd, arg, rsp, delay, rspParam, typ, formt

    -- 命令是string类型
    if type(item) == "string" then
        -- 命令内容
        cmd = item
    -- 命令是table类型
    elseif type(item) == "table" then
        -- 命令内容
        cmd = item.cmd
        -- 命令参数
        arg = item.arg
        -- 命令应答处理函数
        rsp = item.rsp
        -- 命令延时执行时间
        delay = item.delay
        -- 命令携带的参数，执行回调时传入此参数
        rspParam = item.rspParam
        -- 从item中获取类型
        typ = item.typ     
        -- 从item中获取格式
        formt = item.formt  
    else
        log.info("ril.getcmd", "getpack unknown item")
        return
    end

    -- 如果是透传数据，跳过AT命令头解析
    if typ == UA_TRANSPARENT then
        -- 透传数据直接设置，不需要解析AT命令头
        currcmd = cmd
        currarg = arg
        currsp = rsp
        curdelay = delay
        cmdhead = nil  -- 透传数据没有AT命令头，设为nil
        cmdRspParam = rspParam
        cmdtype = typ  -- UA_TRANSPARENT类型
        rspformt = formt
        return currcmd
    end
    
    -- log.info("ril.getcmd", "解析结果:", "cmd:", cmd, "arg:", arg, "rsp:", rsp, "delay:", delay, "typ:", typ, "formt:", formt)

    -- 原有的AT命令解析逻辑
    local head = string.match(cmd, "AT([%+%*]*%u+)")

    if head == nil then
        log.error("ril.getcmd", "request error cmd:", cmd)
        return
    end

    -- 赋值全局变量
    currcmd = cmd
    currarg = arg
    currsp = rsp
    curdelay = delay
    cmdhead = head
    cmdRspParam = rspParam
    
    -- 优先使用传入的类型，如果没有则使用注册的类型
    if typ then
        cmdtype = typ
    else
        cmdtype = RILCMD[head] or NORESULT
    end
    
    -- 优先使用传入的格式，如果没有则使用注册的格式
    if formt then
        rspformt = formt
    else
        rspformt = formtab[head]
    end

    return currcmd
end

--[[
函数名：sendat
功能  ：发送AT命令
参数  ：无
返回值：无
]]
local function sendat()
    -- AT通道未准备就绪、正在读取串口数据、有AT命令在执行或者队列无命令、正延时发送某条AT
    if not radioready or readat or currcmd ~= nil or delaying  or isupdate then
        return
    end
    local item
    while true do
        -- 队列无AT命令
        if #cmdqueue == 0 then
            return
        end
        -- 读取第一条命令
        item = table.remove(cmdqueue, 1)
        -- 解析命令
        getcmd(item)
        -- 需要延迟发送
        if curdelay then
            -- 启动延迟发送定时器
            sys.timerStart(ril.delayfunc, curdelay)
            -- 清除全局变量
            currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt, cmdRspParam = nil, nil, nil, nil, nil, nil, nil, nil
            item.delay = nil
            -- 设置延迟发送标志
            delaying = true
            -- 把命令重新插入命令队列的队首
            table.insert(cmdqueue, 1, item)
            return
        end
        if currcmd ~= nil then
            break
        end
    end
    -- 启动AT命令应答超时定时器
    sys.timerStart(atimeout, TIMEOUT)
    -- log.info("ril.sendat", currcmd)

    -- 根据类型发送数据
    if cmdtype == UA_TRANSPARENT then
        -- 透传数据：向虚拟串口直接发送原始数据，不加\r\n
        vwrite(UART_ID, currcmd)
        
        -- 透传数据发送后立即完成处理，不需要等待响应
        sys.timerStopAll(atimeout)  -- 停止超时定时器
        
        -- 触发回调
        if currsp then
            currsp(currcmd, true, "UA_TRANSPARENT_SENT", nil, cmdRspParam)
        end
        
        -- 重置状态
        currcmd, currarg, currsp, curdelay, cmdhead, cmdtype, rspformt, cmdRspParam = 
            nil, nil, nil, nil, nil, nil, nil, nil
        result, interdata, respdata = nil, nil, nil
        
        -- 处理队列中的下一条命令
        sendat()
    else
        -- AT命令：向虚拟串口发送AT命令，加\r\n
        vwrite(UART_ID, currcmd .. "\r\n")
    end
end

-- 延时执行某条AT命令的定时器回调
-- @return 无
-- @usage ril.delayfunc()
function ril.delayfunc()
    delaying = nil
    sendat()
end

local function atcreader(id, len)
    local alls = vread(UART_ID, len):split("\r\n")
    if isupdate then
        for i = 1, #alls do
            local s = alls[i]
            -- log.debug("uart.log", s)
            if string.len(s) ~= 0 then
                updateRcvFun(s)
            else
                break
            end
        end
    else
        readat = true
        for i = 1, #alls do
            local s = alls[i]
            -- log.debug("uart.log", s)
            if string.len(s) ~= 0 then
                procatc(s)
            else
                break
            end
        end
        readat = false
        sendat()
    end
end

--- 发送AT命令到底层软件
-- @param cmd   AT命令内容
-- @param arg   AT命令参数，例如AT+CMGS=12命令执行后，接下来会发送此参数；AT+CIPSEND=14命令执行后，接下来会发送此参数
-- @param onrsp AT命令应答的处理函数，只是当前发送的AT命令应答有效，处理之后就失效了
-- @param delay 延时delay毫秒后，才发送此AT命令
-- @param typ   命令应答类型，可以是NORESULT,NUMBERIC,SLINE,MLINE,STRING,SPECIAL
-- @param formt 应答格式（正则表达式）
-- @return 无
-- @usage ril.request("AT+CENG=1,1")
-- @usage ril.request("AT+CRSM=214,28539,0,0,12,\"64f01064f03064f002fffff\"", nil, crsmResponse)
function ril.request(cmd, arg, onrsp, delay, typ, formt, rspParam)
    -- log.info("ril.request被调用", 
    --         "cmd:", cmd,
    --         "arg:", arg,
    --         "onrsp:", onrsp and "有回调" or "无回调",
    --         "delay:", delay,
    --         "typ:", typ,
    --         "formt:", formt,
    --         "rspParam:", rspParam)
    -- -- 检查参数类型
    -- log.info("参数类型检查:", 
    --         "typ类型:", type(typ), "值:", typ,
    --         "formt类型:", type(formt), "值:", formt)

    -- 插入缓冲队列
    local queue_item = {
        cmd = cmd,
        arg = arg,
        rsp = onrsp,
        delay = delay,
        rspParam = rspParam,
        typ = typ,      -- 新增：命令类型
        formt = formt   -- 新增：响应格式
    }
    
    table.insert(cmdqueue, queue_item)
    -- 执行AT命令发送
    sendat()
    return true
end

-- 导出常量到ril表
ril.NORESULT = NORESULT
ril.NUMBERIC = NUMBERIC
ril.SLINE = SLINE
ril.MLINE = MLINE
ril.STRING = STRING
ril.SPECIAL = SPECIAL
ril.ATRESP = ATRESP
ril.UA_TRANSPARENT = UA_TRANSPARENT

-- 同步模式支持
local sync_response = nil
local sync_msg_id = "EXRIL_SYNC_RESP"

-- 同步响应处理函数
local function sync_rsp_handler(cmd, success, response, intermediate)
    sync_response = {
        cmd = cmd,
        success = success,
        response = response,
        intermediate = intermediate
    }
    sys.publish(sync_msg_id, sync_response)
end

-- 同步发送AT命令
function ril.requestSync(cmd, arg, delay, typ, formt, timeout)
    -- 透传数据直接处理，不需要等待响应
    if typ == UA_TRANSPARENT then
        -- 创建队列项，确保命令队列管理正常
        local queue_item = {
            cmd = cmd,
            arg = arg,
            rsp = nil,  -- 透传数据不需要回调
            delay = delay,
            typ = typ,
            formt = formt
        }
        
        -- 入队
        table.insert(cmdqueue, queue_item)
        
        -- 触发发送
        sendat()
        
        -- 透传数据发送后立即返回成功，不需要等待响应
        return true, "UA_TRANSPARENT_SENT"
    end
    -- 普通AT命令的处理逻辑
    sync_response = nil
    
    local queue_item = {
        cmd = cmd,
        arg = arg,
        rsp = sync_rsp_handler,
        delay = delay,
        typ = typ,
        formt = formt
    }
    
    table.insert(cmdqueue, queue_item)
    sendat()
    
    -- 等待响应
    local success, resp = sys.waitUntil(sync_msg_id, timeout or DEFAULT_TIMEOUT)
    if not success then
        return false, "timeout"
    end
    
    return resp.success, resp.response, resp.intermediate
end

uart.setup(UART_ID, UART_BAUDRATE)
-- 注册"AT命令的虚拟串口数据接收消息"的处理函数
uart.on(UART_ID, "receive", atcreader)

-- =============== 内部辅助函数 ===============
-- URC处理器：处理蓝牙事件
urc_handler = function(data, prefix)
    local event, payload
    
    if data == "AT:CONNECTED" or data == "UT:CONNECTED" then
        exril_5101_connected = true
        event = "connected"
        payload = {connected = true}
        
    elseif data == "AT:DISCONNECT" or data == "UT:DISCONNECT" then
        exril_5101_connected = false
        event = "disconnected"
        payload = {connected = false}
        
    else
        event = "data"
        if exril_5101_current_mode == exril_5101.MODE_AT then
            -- AT模式下，去掉AT:前缀
            local processed_data = data
            if processed_data:sub(1, 3) == "AT:" then
                processed_data = processed_data:sub(4)
            end
            payload = {
                data = processed_data,   -- 不带AT:前缀的数据
                raw = data,              -- 原始完整数据
                prefix = prefix,
                mode = exril_5101_current_mode
            }
        else
            -- 透传模式下，直接接收原始数据（无前缀）
            payload = {
                data = data,    -- 原始数据
                prefix = nil,
                mode = exril_5101_current_mode
            }
        end
    end
    
    if user_callback then
        pcall(user_callback, event, payload)
    end
end

-- 注册URC处理器
local function register_ble_urc()
    ril.regUrc("AT", urc_handler)
    ril.regUrc("UT", urc_handler)
end

-- AT指令模式发送数据
function send_at(data, callback, timeout)
    -- log.info("exril_5101._send_at", "AT模式发送数据，长度:", #data)
    
    -- 数据长度检查（最大80字节）
    local MAX_AT_LENGTH = 80
    if #data > 80 then
        local error_msg = string.format("数据长度%d超过最大值%d，无法发送", #data, MAX_AT_LENGTH)
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end
    
    -- 构建AT命令
    local at_cmd = "AT+BS=" .. data
    
    -- 异步调用
    if callback then
        local function handle_send_response(cmd, success, response)
            local send_success = success and response and response == "AT:OK"
            if callback then
                callback(send_success, send_success and "发送成功" or "发送失败")
            end
        end
        
        -- 发送AT命令
        local sent = ril.request(at_cmd, nil, handle_send_response, nil, ril.ATRESP, "^AT:.+$")
        if not sent then
            log.error("send_at", "AT命令发送失败")
            if callback then callback(false, "AT命令发送失败") end
        end
        
        return sent
    else
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        -- 同步调用
        local success, response = ril.requestSync(at_cmd, nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success and response and response == "AT:OK" then
            return true, "发送成功"
        else
            return false, "发送失败"
        end
    end
end

-- 透传模式透传数据，适合大数据透传
local function send_ua(data, callback, timeout)
    if type(data) ~= "string" or #data == 0 then
        local error_msg = "数据不能为空"
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end
    
    if not exril_5101_connected then
        local error_msg = "蓝牙未连接"
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end
    
    if exril_5101_current_mode ~= exril_5101.MODE_UA then
        local error_msg = "必须在透传模式下发送"
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end
    
    -- 数据长度检查（MTU-3字节限制）
    local MAX_MTU_LENGTH = 512 - 3  -- MTU最大512，减去3字节协议头
    if #data > MAX_MTU_LENGTH then
        local error_msg = string.format("数据长度%d超过最大值%d，无法发送", #data, MAX_MTU_LENGTH)
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end

    -- 异步调用
    if callback then
        -- 定义透传数据响应处理函数
        local function ua_response_handler(cmd, success, response, intermediate, param)
            if success then
                callback(true, "数据已发送")
            else
                callback(false, "发送失败")
            end
        end
        
        -- 构建透传数据项
        local sent = ril.request(data, nil, ua_response_handler, nil, ril.UA_TRANSPARENT, nil)
        
        if not sent then
            callback(false, "加入队列失败")
        end
        
        return sent
        
    else
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        -- 同步调用
        local success = ril.requestSync(data, nil, nil, ril.UA_TRANSPARENT, nil, sync_timeout)
        
        if success then
            return true, "发送成功"
        else
            return false, "发送失败"
        end
    end
end

-- 唤醒Air5101模块
local function wakeup_module(data)
    if type(data) ~= "string" or #data == 0 then
        return false
    end
    -- 发送唤醒数据
    local sent = uart.write(UART_ID, data)
    local success = sent ~= false and sent ~= nil
    
    return success
end

-- =============== 公共API函数 ===============
--[[
切换蓝牙工作模式
@api exril_5101.mode(mode, timeout)
@param mode string 工作模式，nil表示获取当前模式
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和模式，失败返回false和错误信息
@usage
-- 同步获取当前模式
local success, mode = exril_5101.mode()
if success then
    log.info("当前模式:", mode)
else
    log.error("获取失败:", mode)
end

-- 同步切换到AT指令模式
local success, mode = exril_5101.mode(exril_5101.MODE_AT)
if success then
    log.info("已切换到", mode, "模式")
end
--]]
function exril_5101.mode(mode, callback, timeout)
    -- 参数重载处理：
    -- 1. 如果第一个参数是函数，说明是异步获取模式
    -- 2. 如果第二个参数是数字，说明是同步调用并指定超时
    if type(mode) == "function" then
        callback = mode
        mode = nil
        timeout = nil
    elseif type(callback) == "number" then
        timeout = callback
        callback = nil
    end

    -- 异步调用
    if callback then
        if mode == nil then
            -- 获取当前模式
            callback(true, exril_5101_current_mode, "获取成功")
            return true
        end

        -- 处理 AT+AU 响应
        local function handle_au_response(cmd, success, response) 
            if success then
                exril_5101_current_mode = exril_5101.MODE_UA
                if callback then
                    callback(true, exril_5101.MODE_UA, "已切换到透传模式")
                end
            else
                if callback then
                    callback(false, nil, "切换到透传模式失败")
                end
            end
        end

        -- 处理 AT+UA 响应
        local function handle_ua_response(cmd, success, response)    
            if success then
                exril_5101_current_mode = exril_5101.MODE_AT
                if callback then
                    callback(true, exril_5101.MODE_AT, "已切换到AT指令模式")
                end
            else
                if callback then
                    callback(false, nil, "切换到AT指令模式失败")
                end
            end
        end

        -- 设置模式
        if mode == exril_5101.MODE_UA then
            -- 切换到透传模式
            ril.request("AT+AU", nil, handle_au_response, nil, ril.ATRESP, "^AT:.+$")
            return true
        elseif mode == exril_5101.MODE_AT then
            -- 切换到AT指令模式
            ril.request("AT+UA", nil, handle_ua_response, nil, ril.ATRESP, "^AT:.+$")
            return true
        else
            if callback then
                callback(false, nil, "无效的模式参数")
            end
            return false
        end
    else
        -- 同步调用
        if mode == nil then
            -- 获取当前模式
            return true, exril_5101_current_mode
        end

        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒

        if mode == exril_5101.MODE_UA then
            -- 切换到透传模式
            local success, response = ril.requestSync("AT+AU", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
            if success then
                exril_5101_current_mode = exril_5101.MODE_UA
                return true, exril_5101.MODE_UA
            else
                return false, "切换到透传模式失败"
            end
        elseif mode == exril_5101.MODE_AT then
            -- 切换到AT指令模式
            local success, response = ril.requestSync("AT+UA", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
            if success then
                exril_5101_current_mode = exril_5101.MODE_AT
                return true, exril_5101.MODE_AT
            else
                return false, "切换到AT指令模式失败"
            end
        else
            return false, "无效的模式参数"
        end
    end
end

--[[
设置蓝牙参数
@api exril_5101.set(config, timeout)
@param config table 配置表，可包含以下字段：
  name: 设备名称
  adv_type: 广播类型
  adv_data: 广播数据（十六进制字符串）
  scan_rsp_data: 扫描响应数据（十六进制字符串）
  adv_interval: 广播间隔（毫秒）
  conn_interval: 连接间隔（毫秒）
  mtu_len: MTU长度
  baud: 波特率
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, table 成功返回true和结果，失败返回false和错误信息
@usage
-- 设置设备参数
local config = {
    name = "MyDevice",
    adv_type = exril_5101.ADV_C,
    adv_interval = 1000
}
local success, results = exril_5101.set(config)
if success then
    log.info("参数设置成功")
else
    log.error("参数设置失败:", results)
end
--]]
function exril_5101.set(config, callback, timeout)
    -- 参数重载处理：
    -- 如果第二个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end

    -- 同步调用
    if not callback then
        if type(config) ~= "table" then
            return false, "config必须是table类型"
        end
        
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下设置参数"
        end
        
        local save = true  -- 默认将设置保存到flash,掉电不消失
        local setting_sequence = {}
        
        -- 构建设置命令序列
        local cmd_map = {
            name = function(value) 
                return "AT+SN=" .. tostring(value)
            end,
            adv_type = function(value) 
                return "AT+SAT=" .. tostring(value)
            end,
            adv_data = function(value)
                -- 自动添加0x前缀
                if type(value) == "string" and not string.find(value, "^0x") then
                    value = "0x" .. value
                end
                return "AT+SA=" .. tostring(value)
            end,
            scan_rsp_data = function(value)
                -- 自动添加0x前缀
                if type(value) == "string" and not string.find(value, "^0x") then
                    value = "0x" .. value
                end
                return "AT+SSR=" .. tostring(value)
            end,
            adv_interval = function(value)
                return "AT+SAI=" .. tostring(value)
            end,
            conn_interval = function(value)
                return "AT+SCI=" .. tostring(value)
            end,
            mtu_len = function(value)
                return "AT+SMT=" .. tostring(value)
            end,
            baud = function(value)
                return "AT+SD=" .. tostring(value)
            end
        }
        
        -- 验证配置项的有效性
        for key, value in pairs(config) do
            if cmd_map[key] then
                -- 设备名称长度验证
                if key == "name" then
                    log.info("exril_5101.set", "设备名称:", value)
                    if #value > 20 then
                        return false, "设备名称不能超过20字符"
                    end
                elseif key == "adv_type" then
                    -- 验证广播类型
                    if value ~= exril_5101.ADV_N and value ~= exril_5101.ADV_C then
                        return false, "无效的广播类型"
                    end
                    -- 广播数据长度验证
                elseif key == "adv_data" then
                    if #value > 31 then
                        return false, "广播数据不能超过31字节"
                    end
                    -- 扫描响应数据长度验证
                elseif key == "scan_rsp_data" then
                    if #value > 31 then
                        return false, "扫描响应数据不能超过31字节"
                    end
                    -- 广播间隔验证
                elseif key == "adv_interval" then
                    if type(value) ~= "number" then
                        return false, "广播间隔必须是数字"
                    end
                    if value < 20 or value > 10000 then
                        return false, "广播间隔范围20-10000ms"
                    end
                    
                    -- 转换为十六进制
                    local ticks = math.floor(value / 0.625 + 0.5)
                    local hex_value = string.format("0x%04X", ticks)
                    value = hex_value
                    -- 连接间隔验证
                elseif key == "conn_interval" then
                    if type(value) ~= "number" then
                        return false, "连接间隔必须是数字"
                    end
                    if value < 7.5 or value > 2000 then
                        return false, "连接间隔范围7.5-2000ms"
                    end
                    -- 转换为十六进制
                    local ticks = math.floor(value / 0.625 + 0.5)
                    local hex_value = string.format("0x%04X", ticks)
                    value = hex_value
                    -- MTU长度验证
                elseif key == "mtu_len" then
                    if value < 23 or value > 512 then
                        return false, "MTU长度范围23-512"
                    end
                end
                
                -- 生成AT命令
                local cmd = cmd_map[key](value)
                if cmd == nil then
                    -- 命令生成失败（如无效的广播类型）
                    return false, "生成AT命令失败: " .. key
                end

                table.insert(setting_sequence, {
                    key = key,
                    cmd = cmd_map[key](value),
                    value = value
                })
            else
                log.warn("exril_5101.set", "忽略未知配置项:", key)
            end
        end
        
        if #setting_sequence == 0 then
            log.warn("exril_5101.set", "没有有效的配置项需要设置")
            return true, {}
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        -- 执行设置命令
        local results = {}
        local has_error = false
        local error_msg = ""

        for i, item in ipairs(setting_sequence) do
            local success, response = ril.requestSync(item.cmd, nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
            
            results[item.key] = {
                success = success,
                value = item.value,
                message = success and "设置成功" or "设置失败"
            }
            
            if not success then
                has_error = true
                error_msg = error_msg .. item.key .. "设置失败; "
            end
        end
        
        -- 保存配置
        if not has_error and save then
            -- 处理超时参数
            local sync_timeout = timeout or DEFAULT_TIMEOUT
            sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
            
            local success, response = ril.requestSync("AT+SAVE", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
            if success then
                log.info("exril_5101.set", "配置保存到Flash成功")
            else
                log.warn("exril_5101.set", "配置保存到Flash失败")
            end
        end
        
        if has_error then
            return false, error_msg
        else
            return true, results
        end
    else
        -- 异步调用
        if type(config) ~= "table" then
            if type(callback) == "function" then callback(false, nil, "config必须是table类型") end
            return false
        end
        
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if type(callback) == "function" then callback(false, nil, "必须在AT模式下设置参数") end
            return false
        end
        
        local save = true  -- 默认将设置保存到flash,掉电不消失
        local setting_sequence = {}
        
        -- 构建设置命令序列
        local cmd_map = {
            name = function(value) 
                return "AT+SN=" .. tostring(value)
            end,
            adv_type = function(value) 
                return "AT+SAT=" .. tostring(value)
            end,
            adv_data = function(value)
                -- 自动添加0x前缀
                if type(value) == "string" and not string.find(value, "^0x") then
                    value = "0x" .. value
                end
                return "AT+SA=" .. tostring(value)
            end,
            scan_rsp_data = function(value)
                -- 自动添加0x前缀
                if type(value) == "string" and not string.find(value, "^0x") then
                    value = "0x" .. value
                end
                return "AT+SSR=" .. tostring(value)
            end,
            adv_interval = function(value)
                return "AT+SAI=" .. tostring(value)
            end,
            conn_interval = function(value)
                return "AT+SCI=" .. tostring(value)
            end,
            mtu_len = function(value)
                return "AT+SMT=" .. tostring(value)
            end,
            baud = function(value)
                return "AT+SD=" .. tostring(value)
            end
        }
        
        -- 验证配置项的有效性
        for key, value in pairs(config) do
            if cmd_map[key] then
                -- 设备名称长度验证
                if key == "name" then
                    log.info("exril_5101.set", "设备名称:", value)
                    if #value > 20 then
                        if callback then callback(false, nil, "设备名称不能超过20字符") end
                        return false
                    end
                elseif key == "adv_type" then
                    -- 验证广播类型
                    if value ~= exril_5101.ADV_N and value ~= exril_5101.ADV_C then
                        if callback then callback(false, nil, "无效的广播类型") end
                        return false
                    end
                    -- 广播数据长度验证
                elseif key == "adv_data" then
                    if #value > 31 then
                        if callback then callback(false, nil, "广播数据不能超过31字节") end
                        return false
                    end
                    -- 扫描响应数据长度验证
                elseif key == "scan_rsp_data" then
                    if #value > 31 then
                        if callback then callback(false, nil, "扫描响应数据不能超过31字节") end
                        return false
                    end
                    -- 广播间隔验证
                elseif key == "adv_interval" then
                    if type(value) ~= "number" then
                        if callback then callback(false, nil, "广播间隔必须是数字") end
                        return false
                    end
                    if value < 20 or value > 10000 then
                        if callback then callback(false, nil, "广播间隔范围20-10000ms") end
                        return false
                    end
                    
                    -- 转换为十六进制
                    local ticks = math.floor(value / 0.625 + 0.5)
                    local hex_value = string.format("0x%04X", ticks)
                    value = hex_value
                    -- 连接间隔验证
                elseif key == "conn_interval" then
                    if type(value) ~= "number" then
                        if callback then callback(false, nil, "连接间隔必须是数字") end
                        return false
                    end
                    if value < 7.5 or value > 2000 then
                        if callback then callback(false, nil, "连接间隔范围7.5-2000ms") end
                        return false
                    end
                    -- 转换为十六进制
                    local ticks = math.floor(value / 0.625 + 0.5)
                    local hex_value = string.format("0x%04X", ticks)
                    value = hex_value
                    -- MTU长度验证
                elseif key == "mtu_len" then
                    if value < 23 or value > 512 then
                        if callback then callback(false, nil, "MTU长度范围23-512") end
                        return false
                    end
                end
                
                -- 生成AT命令
                local cmd = cmd_map[key](value)
                if cmd == nil then
                    -- 命令生成失败（如无效的广播类型）
                    if callback then callback(false, nil, "生成AT命令失败: " .. key) end
                    return false
                end

                table.insert(setting_sequence, {
                    key = key,
                    cmd = cmd_map[key](value),
                    value = value
                })
            else
                log.warn("exril_5101.set", "忽略未知配置项:", key)
            end
        end
        
        if #setting_sequence == 0 then
            log.warn("exril_5101.set", "没有有效的配置项需要设置")
            if callback then callback(true, {}, "没有需要设置的配置项") end
            return true
        end
        
        -- 执行设置命令
        local results = {}
        local pending_count = #setting_sequence
        local has_error = false
        local error_msg = ""

        local function handle_save_response(cmd, success, response)
            log.info("exril_5101.handle_save_response", "命令:", cmd, "成功:", success, "响应:", response)
            if success then
                if callback then callback(true, results, "配置保存成功") end
            else
                if callback then callback(false, results, "配置保存失败") end
            end
        end
        
        local function check_complete()        
            if pending_count == 0 then
                -- 所有设置命令完成
                if not has_error then
                    -- 所有设置成功，保存配置
                    if save then
                        ril.request("AT+SAVE", nil, handle_save_response, nil, ril.ATRESP, "^AT:.+$")
                    else
                        -- 不保存，直接回调
                        if callback then callback(true, results, "设置成功") end
                    end
                else
                    -- 有设置失败
                    if callback then callback(false, results, error_msg) end
                end
            end
        end

        for i, item in ipairs(setting_sequence) do
            -- 创建局部变量捕获当前item
            local current_item = item
            
            local function handle_set_response(cmd, success, response)
                log.info("exril_5101.set.response", 
                    "key:", current_item.key,
                    "cmd:", cmd,
                    "success:", success,
                    "response:", response)
                
                -- 存储结果
                results[current_item.key] = {
                    success = success,
                    value = current_item.value,
                    message = success and "设置成功" or "设置失败"
                }
                
                if not success then
                    has_error = true
                    error_msg = error_msg .. current_item.key .. "设置失败; "
                end
                
                -- 计数器减一
                pending_count = pending_count - 1
                if pending_count == 0 then
                    log.info("exril_5101.set", "所有设置命令完成")
                    check_complete()
                end
            end
            
            ril.request(current_item.cmd, nil, handle_set_response, nil, ril.ATRESP, "^AT:.+$")
        end
        
        return true
    end
end


-- =============== exril_5101.get()内部辅助函数 ===============
-- 解析固件版本号
-- 格式: AT:1.5.2-2601162021
-- 返回: 版本字符串
local function parse_ver(response)
    return string.match(response, "^AT:(.+)$")
end

-- 解析设备名称
-- 格式: AT:Air5101S
-- 返回: 设备名称字符串
local function parse_name(response)
    return string.match(response, "^AT:(.+)$")
end

-- 解析串口波特率
-- 格式: AT:9600
-- 返回: 波特率数值
local function parse_baud(response)
    local value = string.match(response, "^AT:(%d+)$")
    return value and tonumber(value)
end

-- 解析MAC地址（小端模式）
-- 格式: AT:0x443322116AED (14字符，0x+12位十六进制)
-- 返回: 反序后的十六进制字符串（无0x前缀）
local function parse_mac(response)
    local hex_str = string.match(response, "^AT:(0x%x+)$")
    if not hex_str or #hex_str ~= 14 then
        return nil
    end
    
    -- 去掉"0x"前缀
    local hex_only = hex_str:sub(3)
    
    -- 按字节反序（每2个字符为一组）
    local reversed = ""
    for i = #hex_only, 1, -2 do
        reversed = reversed .. hex_only:sub(i-1, i)
    end
    
    return reversed
end

-- 解析广播类型
-- 格式: AT:0x02 (不可连接) 或 AT:0x03 (可连接)
-- 返回: exril_5101.ADV_N 或 exril_5101.ADV_C 常量
local function parse_adv_type(response)
    local value = string.match(response, "^AT:(0x%x+)$")
    if value then
        if value == "0x02" then 
            return exril_5101.ADV_N
        elseif value == "0x03" then 
            return exril_5101.ADV_C
        else 
            return value 
        end
    end
    return nil
end

-- 解析广播数据
-- 格式: AT:0x02010603031218 (十六进制字符串)
-- 返回: 十六进制字符串（可能为空）
local function parse_adv_data(response)
    return string.match(response, "^AT:(0x%x*)$")
end

-- 解析扫描响应数据
-- 格式: AT:0x... (十六进制字符串)
-- 返回: 十六进制字符串（可能为空）
local function parse_scan_rsp_data(response)
    return string.match(response, "^AT:(0x%x*)$")
end

-- 解析广播间隔（毫秒）
-- 格式: AT:0x0140 (十六进制，单位0.625ms)
-- 返回: 整数毫秒值（向下取整）
local function parse_adv_interval(response)
    local hex_str = string.match(response, "^AT:(0x%x+)$")
    if hex_str then
        local ticks = tonumber(hex_str:gsub("0x", ""), 16)
        if ticks then 
            local raw_ms = ticks * 0.625
            local int_ms = math.floor(raw_ms)
            return int_ms
        end
    end
    return nil
end

-- 解析连接间隔（毫秒）
-- 格式: AT:0x... (十六进制，单位1.25ms)
-- 返回: 整数毫秒值（向下取整）
local function parse_conn_interval(response)
    local hex_str = string.match(response, "^AT:(0x%x+)$")
    if hex_str then
        local ticks = tonumber(hex_str:gsub("0x", ""), 16)
        if ticks then 
            local raw_ms = ticks * 1.25
            local int_ms = math.floor(raw_ms)
            return int_ms
        end
    end
    return nil
end

-- 解析MTU长度
-- 格式: AT:512
-- 返回: MTU数值
local function parse_mtu_len(response)
    local value = string.match(response, "^AT:(%d+)$")
    return value and tonumber(value)
end

-- 解析功耗模式
-- 格式: AT:LOWPOWER=0
-- 返回: 功耗模式数值
local function parse_power_mode(response)
    local value = string.match(response, "^AT:LOWPOWER=(%d+)$")
    if value then return tonumber(value) end
    value = string.match(response, "^AT:(%d+)$")
    return value and tonumber(value)
end

-- 统一的配置表
local config = {
    ver = {
        cmd = "AT+VER",
        type = ril.ATRESP,
        format = "^AT:.+$",
        parser = parse_ver
    },
    name = {
        cmd = "AT+GN", 
        type = ril.ATRESP,
        format = "^AT:.+$",
        parser = parse_name
    },
    baud = {
        cmd = "AT+GD",
        type = ril.ATRESP,
        format = "^AT:.+$",
        parser = parse_baud
    },
    mac = {
        cmd = "AT+GM",
        type = ril.ATRESP,
        format = "^AT:0x%x+$",
        parser = parse_mac
    },
    adv_type = {
        cmd = "AT+GAT",
        type = ril.ATRESP,
        format = "^AT:0x%x+$",
        parser = parse_adv_type
    },
    adv_data = {
        cmd = "AT+GA",
        type = ril.ATRESP,
        format = "^AT:0x%x*$",
        parser = parse_adv_data
    },
    scan_rsp_data = {
        cmd = "AT+GSR",
        type = ril.ATRESP,
        format = "^AT:0x%x*$",
        parser = parse_scan_rsp_data
    },
    adv_interval = {
        cmd = "AT+GAI",
        type = ril.ATRESP,
        format = "^AT:0x%x+$",
        parser = parse_adv_interval
    },
    conn_interval = {
        cmd = "AT+GCI",
        type = ril.ATRESP,
        format = "^AT:0x%x+$",
        parser = parse_conn_interval
    },
    mtu_len = {
        cmd = "AT+GMT",
        type = ril.ATRESP,
        format = "^AT:.+$",
        parser = parse_mtu_len
    },
    power_mode = {
        cmd = "AT+GLP",
        type = ril.ATRESP,
        format = "^AT:.+$",
        parser = parse_power_mode
    }
}

-- =============== exril_5101.get(key) ===============
--[[
获取设备信息
@api exril_5101.get(key, timeout)
@param key string|table 单个键名或键名数组
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return table, string 成功返回结果表，失败返回nil和错误信息
@usage
-- 获取单个信息
local value, error = exril_5101.get("name")
if value then
    log.info("设备名称:", value)
else
    log.error("获取失败:", error)
end

-- 获取多个信息
local results, error = exril_5101.get({"name", "mac", "ver"})
if results then
    log.info("设备名称:", results.name)
    log.info("设备MAC:", results.mac)
    log.info("设备版本:", results.ver)
else
    log.error("获取失败:", error)
end
--]]
function exril_5101.get(key, callback, timeout)
    -- 参数重载处理：
    -- 如果第二个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return nil, "必须在AT模式下获取参数"
        end

        -- 单个键获取
        if type(key) == "string" then
            local cfg = config[key]
            if not cfg then
                return nil, "未知的键: " .. key
            end

            -- 处理超时参数
            local sync_timeout = timeout or DEFAULT_TIMEOUT
            sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
            
            log.info("exril_5101.get", "获取单个参数:", key, "命令:", cfg.cmd)
            
            local success, response = ril.requestSync(cfg.cmd, nil, nil, cfg.type, cfg.format, sync_timeout)
            
            if success and response then
                local value = cfg.parser(response)
                if not value then
                    log.warn("exril_5101.get", key, "解析失败:", response)
                    return nil, "解析响应失败: " .. response
                end
                return value, nil
            else
                return nil, "AT命令执行失败: " .. (response or "无响应")
            end

        -- 批量获取
        elseif type(key) == "table" then
            if #key == 0 then
                log.warn("exril_5101.get", "空的键列表")
                return {}, nil
            end

            -- 处理超时参数
            local sync_timeout = timeout or DEFAULT_TIMEOUT
            sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
            
            log.info("exril_5101.get", "批量获取参数:", table.concat(key, ","))
            
            local results = {}
            local errors = {}
            
            -- 处理每个键
            for _, k in ipairs(key) do
                local cfg = config[k]
                if not cfg then
                    log.warn("exril_5101.get", "忽略未知键:", k)
                    results[k] = nil
                    table.insert(errors, k .. ":未知的键")
                else
                    local success, response = ril.requestSync(cfg.cmd, nil, nil, cfg.type, cfg.format, sync_timeout)
                    
                    if success and response then
                        local value = cfg.parser(response)
                        if value then
                            results[k] = value
                            log.info("exril_5101.get", k, "获取成功:", value)
                        else
                            results[k] = nil
                            table.insert(errors, k .. ":解析响应失败")
                            log.warn("exril_5101.get", k, "解析失败:", response)
                        end
                    else
                        results[k] = nil
                        table.insert(errors, k .. ":发送命令失败")
                    end
                end
            end
            
            if #errors > 0 then
                return results, table.concat(errors, "; ")
            else
                return results, nil
            end
        else
            return nil, "参数必须是string或table类型"
        end
    -- 异步调用
    else
        -- 参数验证
        if not callback or type(callback) ~= "function" then
            log.error("exril_5101.get", "必须提供回调函数")
            return false
        end
        
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            callback(nil, "必须在AT模式下获取参数")
            return false
        end

        -- 单个键获取
        if type(key) == "string" then
            local cfg = config[key]
            if not cfg then
                callback(nil, "未知的键: " .. key)
                return false
            end

            log.info("exril_5101.get", "获取单个参数:", key, "命令:", cfg.cmd)
            
            local function single_callback(cmd_sent, success, response, intermediate)
                local value = nil
                local error_msg = nil
                
                if success and response then
                    value = cfg.parser(response)
                    if not value then
                        error_msg = "解析响应失败: " .. response
                        log.warn("exril_5101.get", key, "解析失败:", response)
                    end
                else
                    error_msg = "AT命令执行失败"
                    if response then
                        error_msg = error_msg .. ": " .. response
                    end
                end
                
                callback(value, error_msg)
            end
            
            local success = ril.request(cfg.cmd, nil, single_callback, nil, cfg.type, cfg.format)
            
            return success ~= false and success ~= nil

        -- 批量获取
        elseif type(key) == "table" then
            if #key == 0 then
                callback({}, nil, {})
                return true
            end

            log.info("exril_5101.get", "批量获取参数:", table.concat(key, ","))
            
            local results = {}
            local pending_count = {value = 0}
            local errors = {}
            local has_error = {value = false}
            
            local function batch_complete()
                -- 整理结果：只包含成功获取的值
                local values = {}
                for k, result in pairs(results) do
                    if result.success then
                        values[k] = result.value
                    end
                end
                
                local error_msg = nil
                if #errors > 0 then
                    error_msg = table.concat(errors, "; ")
                    has_error.value = true
                end
                
                if not has_error.value or next(values) ~= nil then
                    -- 至少部分成功
                    callback(values, error_msg, results)
                else
                    -- 全部失败
                    callback(nil, error_msg, results)
                end
            end

            -- 处理每个键
            for _, k in ipairs(key) do
                local cfg = config[k]
                if not cfg then
                    log.warn("exril_5101.get", "忽略未知键:", k)
                    results[k] = {
                        success = false,
                        key = k,
                        value = nil,
                        error = "未知的键"
                    }
                    table.insert(errors, k .. ":未知的键")
                else
                    pending_count.value = pending_count.value + 1
                    
                    local function item_callback(cmd_sent, success, response, intermediate)
                        local value = nil
                        local error_msg = nil
                        
                        if success and response then
                            value = cfg.parser(response)
                            if not value then
                                error_msg = "解析响应失败: " .. response
                                log.warn("exril_5101.get", k, "解析失败:", response)
                            end
                        else
                            error_msg = "AT命令执行失败"
                            if response then
                                error_msg = error_msg .. ": " .. response
                            end
                        end
                        
                        -- 存储结果
                        results[k] = {
                            success = value ~= nil,
                            key = k,
                            value = value,
                            error = error_msg,
                            response = response,
                            intermediate = intermediate
                        }
                        
                        if error_msg then
                            table.insert(errors, k .. ":" .. error_msg)
                            log.error("exril_5101.get.batch", k, "获取失败:", error_msg)
                        else
                            log.info("exril_5101.get.batch", k, "获取成功:", value)
                        end
                        
                        -- 计数器减一
                        pending_count.value = pending_count.value - 1
                        if pending_count.value == 0 then
                            batch_complete()
                        end
                    end
                    
                    -- 发送请求
                    local success = ril.request(cfg.cmd, nil, item_callback, nil, cfg.type, cfg.format)
                    
                    if not success then
                        -- 立即失败的情况
                        results[k] = {
                            success = false,
                            key = k,
                            value = nil,
                            error = "发送命令失败"
                        }
                        table.insert(errors, k .. ":发送命令失败")
                        pending_count.value = pending_count.value - 1
                    end
                end
            end
            
            -- 如果所有键都是未知的或立即失败的
            if pending_count.value == 0 then
                batch_complete()
            end
            
            return true
        else
            callback(nil, "参数必须是string或table类型")
            return false
        end
    end
end

--[[
恢复出厂设置
@api exril_5101.restore(timeout)
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和"恢复出厂设置成功"，失败返回false和错误信息
@usage
-- 恢复出厂设置
local success, message = exril_5101.restore()
if success then
    log.info("恢复出厂设置成功")
else
    log.error("恢复失败:", message)
end
--]]
function exril_5101.restore(callback, timeout)
    -- 参数重载处理：
    -- 如果第一个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync("AT+DEFAULT", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success then
            return true
        else
            return false
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end
        
        local function handle_reset_response(cmd, success, response)
            local executed = success and response and string.find(response, "^AT:") == 1
            if executed then
                log.warn("exril_5101.reset", "模块将重启恢复出厂设置")
            else
                log.error("exril_5101.reset", "恢复出厂设置失败:", response or "无响应")
            end
            if callback then
                callback(executed, executed and "恢复出厂设置成功" or "恢复出厂设置失败")
            end 
        end
        
        local sent = ril.request("AT+DEFAULT", nil, handle_reset_response, nil, ril.ATRESP, "^AT:.+$")
        if not sent then
            if callback then callback(false, "命令发送失败") end
        end
        
        return sent
    end
end

--[[
软重启模块
@api exril_5101.restart(timeout)
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和"重启成功"，失败返回false和错误信息
@usage
-- 重启模块
local success, message = exril_5101.restart()
if success then
    log.info("模块重启成功")
else
    log.error("重启失败:", message)
end
--]]
function exril_5101.restart(callback, timeout)
    -- 参数重载处理：
    -- 如果第一个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync("AT+RESET", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success then
            return true, "重启成功"
        else
            return false, "重启失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end
        
        local function handle_restart_response(cmd, success, response)
            local executed = success and response and string.find(response, "^AT:") == 1
            if executed then
                log.warn("exril_5101.restart", "模块正在重启...")
            else
                log.error("exril_5101.restart", "重启失败:", response or "无响应")
            end
            if callback then
                callback(executed, executed and "重启成功" or "重启失败")
            end 
        end
        
        local sent = ril.request("AT+RESTART", nil, handle_restart_response, nil, ril.ATRESP, "^AT:.+$")
        if not sent then
            if callback then callback(false, "命令发送失败") end
        end
        
        return sent
    end
end

--[[
断开蓝牙连接
@api exril_5101.disconnect(timeout)
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和"断开连接成功"，失败返回false和错误信息
@usage
-- 断开连接
local success, message = exril_5101.disconnect()
if success then
    log.info("连接已断开")
else
    log.error("断开失败:", message)
end
--]]
function exril_5101.disconnect(callback, timeout)
    -- 参数重载处理：
    -- 如果第一个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync("AT+DISCONN", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success then
            exril_5101_connected = false
            return true, "断开连接成功"
        else
            return false, "断开连接失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end

        local function handle_dn_response(cmd_sent, success, response)
            local disconnected = success and response and (response == "AT:OK")
            
            if disconnected then
                exril_5101_connected = false
            end
            
            if callback then
                callback(disconnected, disconnected and "断开成功" or "断开失败")
            end
        end

        local sent = ril.request("AT+DN", nil, handle_dn_response, nil, ril.ATRESP, "^AT:.+$")
        
        if not sent then
            if callback then callback(false, "命令发送失败") end
        end
        
        return sent
    end
end

--[[
查询蓝牙连接状态
@api exril_5101.status(timeout)
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, table 成功返回true和状态信息，失败返回false和错误信息
@usage
local success, status = exril_5101.status()
if success then
    log.info("连接状态:", status.connected)
else
    log.error("查询失败:", status)
end
--]]
function exril_5101.status(callback, timeout)
    -- 参数重载处理：
    -- 如果第一个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync("AT+STATUS", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success and response then
            local status = {
                connected = exril_5101_connected,
                mode = exril_5101_current_mode,
                raw_response = response
            }
            return true, status
        else
            return false, "查询连接状态失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end
        
        local function handle_status_response(cmd_sent, success, response)
            local connected = false
            
            if success and response then
                if response == "AT:CONNECTED" then
                    connected = true
                elseif response == "AT:DISCONNECT" then
                    connected = false
                end
            end

            -- 更新内部连接状态
            exril_5101_connected = connected
            
            if callback then
                callback(connected, connected and "已连接" or "未连接")
            end
        end
        
        local sent = ril.request("AT+SU", nil, handle_status_response, nil, ril.ATRESP, "^AT:.+$")
        if not sent then
            if callback then callback(false, "命令发送失败") end
        end
        
        return sent
    end
end

--[[
功耗模式控制
@api exril_5101.power(mode, wakeup_option, timeout)
@param mode number|nil 要设置的功耗模式，nil表示获取当前模式
@param wakeup_option nil|boolean|number|table 唤醒配置（可选）
    - nil/false: 不唤醒
    - true: 唤醒（使用默认参数：data="wakeup", delay=25ms）
    - number: 唤醒并指定延时（毫秒），如：50
    - table: 完整唤醒配置，支持字段：
        enable: boolean 是否唤醒
        data:   string 唤醒数据（默认"wakeup"）
        delay:  number 唤醒后延时（默认25ms）
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和模式/"设置成功"，失败返回false和错误信息
@usage
-- 获取当前功耗模式
local success, mode = exril_5101.power()
if success then
    log.info("当前功耗模式:", mode)
else
    log.error("获取功耗模式失败:", mode)
end

-- 设置低功耗模式(不唤醒)
local success, message = exril_5101.power(exril_5101.P1)
if success then
    log.info("功耗模式设置成功:", message)
else
    log.error("功耗模式设置失败:", message)
end

-- 设置低功耗模式(使用默认配置唤醒)
local success, message = exril_5101.power(exril_5101.P1, true)
if success then
    log.info("功耗模式设置成功:", message)
else
    log.error("功耗模式设置失败:", message)
end
--]]
function exril_5101.power(mode, wakeup_option, callback, timeout)
    -- 参数重载：
    -- 1. 第二个参数是函数时当作回调
    -- 2. 第三个参数是数字时当作超时
    if type(wakeup_option) == "function" then
        callback = wakeup_option
        wakeup_option, timeout = nil, nil
    elseif type(callback) == "number" then
        timeout = callback
        callback = nil
    end

    -- 解析唤醒配置（只支持 enable/data/delay）
    local wakeup_config = {
        enable = false,
        data = "wakeup",    -- 默认唤醒数据
        delay = 25       -- 默认延时25ms
    }
    
    if wakeup_option == true then
        -- 简单唤醒（使用默认参数）
        wakeup_config.enable = true
    elseif type(wakeup_option) == "number" then
        -- 唤醒并指定延时
        wakeup_config.enable = true
        wakeup_config.delay = wakeup_option
    elseif type(wakeup_option) == "table" then
        -- table配置
        wakeup_config.enable = wakeup_option.enable == true
        if wakeup_option.data ~= nil then
            wakeup_config.data = wakeup_option.data
        end
        if wakeup_option.delay ~= nil then
            wakeup_config.delay = wakeup_option.delay
        end
    end
    
    -- 执行唤醒
    if wakeup_config.enable then
        local wakeup_success = wakeup_module(wakeup_config.data)
        if not wakeup_success then
            local error_msg = "唤醒模块失败"
            if callback then 
                callback(false, nil, error_msg) 
            end
            return false, error_msg
        end
        if wakeup_config.delay > 0 then
            sys.wait(wakeup_config.delay)
        end
    end

    -- 同步调用
    if not callback then
        -- 获取当前模式
        if mode == nil then
            return true, exril_5101_power_mode
        end
        
        -- 设置模式
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 处理字符串类型的模式参数
        if type(mode) == "string" then
            if mode == exril_5101.P0 then
                mode = 0
            elseif mode == exril_5101.P1 then
                mode = 1
            elseif mode == exril_5101.P3 then
                mode = 3
            else
                return false, "无效的功耗模式"
            end
        elseif type(mode) ~= "number" or mode < 0 or mode > 4 then
            return false, "无效的功耗模式"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local at_cmd = "AT+LP=" .. mode
        -- log.info("exril_5101.power", "发送AT命令:", at_cmd, "超时:", sync_timeout)
        local success, response = ril.requestSync(at_cmd, nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        -- log.info("exril_5101.power", "命令响应:", success, response)
        if success then
            -- 保持exril_5101_power_mode为字符串类型
            if mode == 0 then
                exril_5101_power_mode = exril_5101.P0
            elseif mode == 1 then
                exril_5101_power_mode = exril_5101.P1
            elseif mode == 3 then
                exril_5101_power_mode = exril_5101.P3
            else
                exril_5101_power_mode = tostring(mode)
            end
            log.info("exril_5101.power", "设置成功，当前模式:", exril_5101_power_mode)
            return true, "设置成功"
        else
            return false, "设置失败"
        end
    else
        -- 异步调用
        -- 获取当前模式
        if mode == nil then
            if callback then
                callback(true, exril_5101_power_mode, "获取成功")
            end
            return exril_5101_power_mode
        end
        
        -- 设置模式
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, nil, "必须在AT模式下执行") end
            return false
        end
        
        -- 处理字符串类型的模式参数
        if type(mode) == "string" then
            if mode == exril_5101.P0 then
                mode = 0
            elseif mode == exril_5101.P1 then
                mode = 1
            elseif mode == exril_5101.P3 then
                mode = 3
            else
                if callback then callback(false, nil, "无效的功耗模式") end
                return false
            end
        elseif type(mode) ~= "number" or mode < 0 or mode > 4 then
            if callback then callback(false, nil, "无效的功耗模式") end
            return false
        end
        
        local at_cmd = (mode == 0) and "AT+LP=0" or ("AT+LP=" .. tostring(mode))
        
        local function handle_response(cmd_sent, success, response)
            local ok = success and response and response == "OK"
            
            if ok then
                -- 保持exril_5101_power_mode为字符串类型
                if mode == 0 then
                    exril_5101_power_mode = exril_5101.P0
                elseif mode == 1 then
                    exril_5101_power_mode = exril_5101.P1
                elseif mode == 3 then
                    exril_5101_power_mode = exril_5101.P3
                else
                    exril_5101_power_mode = tostring(mode)
                end
                local mode_names = {"常规", "低功耗(保持)", "休眠(保持)", "低功耗(自动)", "休眠(自动)"}
                log.info("exril_5101.power", "功耗模式已设置为:" .. mode_names[mode + 1])
            end
            
            if callback then
                callback(ok, ok and mode or nil, ok and "设置成功" or "设置失败")
            end
        end
        
        local sent = ril.request(at_cmd, nil, handle_response)
        
        if not sent and callback then
            callback(false, nil, "命令发送失败")
        end
        
        return sent
    end
end

--[[
配置或查询看门狗功能
@api exril_5101.wdcfg(en, timeout, level, width, sync_timeout)
@param en boolean|nil 如果为nil表示查询，true/false表示设置使能
@param timeout number|nil 可选，喂狗超时时长（秒），默认60，范围1-99999999
@param level number|nil 可选，超时动作电平，默认0
    0：超时后拉低SWITCH
    1：超时后拉高SWITCH
@param width number|nil 可选，复位脉冲宽度（毫秒），默认100, 范围10-10000
@param sync_timeout number|nil 可选，同步调用超时时间（毫秒），默认DEFAULT_TIMEOUT
@return boolean|table 设置时返回发送状态，查询时返回当前看门狗配置信息
@usage
-- 查询看门狗配置
local success, config = exril_5101.wdcfg()
if success then
    log.info("看门狗配置:", config)
end

-- 开启看门狗，60秒超时，超时后拉低100ms
local success, message = exril_5101.wdcfg(true, 60, 0, 100)
if success then
    log.info("看门狗已开启")
end
--]]
function exril_5101.wdcfg(en, timeout, level, width, callback, sync_timeout)
    -- 参数重载处理：
    -- 如果第五个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        sync_timeout = callback
        callback = nil
    end
    -- 参数重载处理
    if type(en) == "function" then
        callback = en
        en = nil
    elseif type(en) == "boolean" and type(timeout) == "function" then
        callback = timeout
        timeout, level, width = nil, nil, nil
    end
    
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下配置看门狗"
        end
        
        -- 查询功能
        if en == nil then
            -- 处理超时参数
            local st = sync_timeout or DEFAULT_TIMEOUT
            st = math.min(st, MAX_TIMEOUT) -- 最大10秒
            
            local success, response = ril.requestSync("AT+WDCFG?", nil, nil, ril.ATRESP, "^AT:.+$", st)
            if success and response then
                local en_val, timeout_val, level_val, width_val = 
                    string.match(response, "^AT:(%d+),(%d+),(%d+),(%d+)$")
                
                if en_val then
                    local config = {
                        en = tonumber(en_val) == 1,
                        timeout = tonumber(timeout_val),
                        level = tonumber(level_val),
                        width = tonumber(width_val)
                    }
                    return true, config
                else
                    return false, "查询响应格式错误"
                end
            else
                return false, "查询失败"
            end
        end
        
        -- 设置功能
        if type(en) ~= "boolean" then
            return false, "en必须是true/false"
        end

        -- 构建命令
        local parts = {en and "1" or "0"}
        
        if timeout ~= nil then
            if type(timeout) ~= "number" or timeout < 1 or timeout > 99999999 then
                return false, "timeout范围1-99999999秒"
            end
            table.insert(parts, tostring(math.floor(timeout)))
            
            if level ~= nil then
                if level ~= 0 and level ~= 1 then
                    return false, "level只能是0或1"
                end
                table.insert(parts, tostring(level))
                
                if width ~= nil then
                    if type(width) ~= "number" or width < 10 or width > 10000 then
                        return false, "width范围10-10000ms"
                    end
                    table.insert(parts, tostring(math.floor(width)))
                end
            end
        end
        
        local at_cmd = "AT+WDCFG=" .. table.concat(parts, ",")
        log.debug("exril_5101.wdcfg", "设置命令:", at_cmd)

        -- 处理超时参数
        local st = sync_timeout or DEFAULT_TIMEOUT
        st = math.min(st, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync(at_cmd, nil, nil, ril.ATRESP, "^AT:.+$", st)
        if success then
            -- 配置成功，保存配置
            local save_success = exril_5101.save()
            return save_success, save_success and "配置保存成功" or "配置保存失败"
        else
            return false, "配置失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, nil, "必须在AT模式下执行") end
            return false
        end
        
        -- 查询功能
        if en == nil then
            local function handle_query_response(cmd_sent, success, response)
                local result = {success = false, config = {}}
                
                if success and response then
                    local en_val, timeout_val, level_val, width_val = 
                        string.match(response, "^AT:(%d+),(%d+),(%d+),(%d+)$")
                    
                    if en_val then
                        result.success = true
                        result.config = {
                            en = tonumber(en_val) == 1,
                            timeout = tonumber(timeout_val),
                            level = tonumber(level_val),
                            width = tonumber(width_val)
                        }
                    end
                end
                
                if callback then
                    callback(result.success, result.config, 
                            result.success and "查询成功" or "查询失败")
                end
            end
            
            local sent = ril.request("AT+WDCFG?", nil, handle_query_response, nil, ril.ATRESP, "^AT:.+$")
            
            if not sent and callback then
                callback(false, nil, "查询命令发送失败")
            end
            
            return sent
        end
        
        -- 设置功能
        if type(en) ~= "boolean" then
            if callback then callback(false, nil, "en必须是true/false") end
            return false
        end

        -- 构建命令
        local parts = {en and "1" or "0"}
        
        if timeout ~= nil then
            if type(timeout) ~= "number" or timeout < 1 or timeout > 99999999 then
                if callback then callback(false, nil, "timeout范围1-99999999秒") end
                return false
            end
            table.insert(parts, tostring(math.floor(timeout)))
            
            if level ~= nil then
                if level ~= 0 and level ~= 1 then
                    if callback then callback(false, nil, "level只能是0或1") end
                    return false
                end
                table.insert(parts, tostring(level))
                
                if width ~= nil then
                    if type(width) ~= "number" or width < 10 or width > 10000 then
                        if callback then callback(false, nil, "width范围10-10000ms") end
                        return false
                    end
                    table.insert(parts, tostring(math.floor(width)))
                end
            end
        end
        
        local at_cmd = "AT+WDCFG=" .. table.concat(parts, ",")
        log.debug("exril_5101.wdcfg", "设置命令:", at_cmd)

        local function on_save_complete(save_success, save_msg)
            local success = save_success
            local msg = save_success and "配置保存成功" or "配置保存失败"
            
            log.info("exril_5101.wdcfg", msg)
            
            if callback then
                callback(success, nil, msg)
            end
        end

        local function handle_set_response(cmd_sent, success, response)
            local sent_ok = success and response and response == "AT:OK"

            if not sent_ok then
                if callback then
                    callback(false, nil, "配置失败")
                end
                return
            end
            
            -- 配置成功，调用保存函数
            exril_5101.save(on_save_complete)
        end
        
        local sent = ril.request(at_cmd, nil, handle_set_response, nil, ril.ATRESP, "^AT:.+$")
        if not sent and callback then
            callback(false, nil, "命令发送失败")
        end
        
        return sent
    end
end

--[[
看门狗喂狗
@api exril_5101.wdfed(timeout)
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean 命令是否发送成功
@usage
-- 定期喂狗
local function wdfed()
    while true do
        exril_5101.wdfed()
        sys.wait(30000)  -- 30秒喂一次
    end
end
sys.taskInit(wdfed)
--]]
function exril_5101.wdfed(callback, timeout)
    -- 参数重载处理：
    -- 如果第一个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行喂狗操作"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync("AT+WDFED", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success then
            return true, "喂狗成功"
        else
            return false, "喂狗失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end
        
        -- 定义喂狗响应处理函数
        local function handle_feed_response(cmd_sent, success, response)
            local fed_ok = success and response and response == "AT:OK"
            
            if callback then
                callback(fed_ok, fed_ok and "喂狗成功" or "喂狗失败")
            end
        end
        
        local sent = ril.request("AT+WDFED", nil, handle_feed_response, nil, ril.ATRESP, "^AT:.+$")
        
        if not sent and callback then
            callback(false, "喂狗命令发送失败")
        end
        
        return sent
    end
end

--[[
配置蓝牙唤醒功能
@api exril_5101.wakeup(source, level, width, timeout)
@param source number 唤醒源配置，0-3
    0：禁用所有唤醒源
    1：使能蓝牙连接断开作为唤醒源
    2：使能蓝牙接收到数据作为唤醒源
    3：同时使能蓝牙连接断开和蓝牙接收到数据作为唤醒源
@param level number 唤醒电平，0/1，默认0
    0：当唤醒事件发生时，拉低 WAKEUP脚
    1：当唤醒事件发生时，拉高 WAKEUP脚
@param width number 脉冲宽度，单位：ms，默认100，范围：10-10000ms
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean 唤醒配置是否成功
@usage
-- 查询唤醒配置
local success, config = exril_5101.wakeup()
if success then
    log.info("唤醒配置:", config)
end

-- 配置唤醒功能，唤醒源1，唤醒后拉低 WAKEUP 脚100ms
local success, message = exril_5101.wakeup(1, 0, 100)
if success then
    log.info("唤醒配置成功")
end
--]]
function exril_5101.wakeup(source, level, width, callback, timeout)
    -- 参数重载处理：
    -- 如果第四个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 参数重载处理
    if type(source) == "function" then
        callback = source
        source = nil
    elseif type(source) == "number" and type(level) == "function" then
        callback = level
        level, width = nil, nil
    end
    
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 查询功能
        if source == nil then
            -- 处理超时参数
            local sync_timeout = timeout or DEFAULT_TIMEOUT
            sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
            
            local success, response = ril.requestSync("AT+WAKEUP?", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
            if success and response then
                local source_val, level_val, width_val = 
                    string.match(response, "^AT:(%d+),(%d+),(%d+)$")
                
                if source_val then
                    local config = {
                        source = tonumber(source_val),
                        level = tonumber(level_val),
                        width = tonumber(width_val)
                    }
                    return true, config
                else
                    return false, "查询响应格式错误"
                end
            else
                return false, "查询失败"
            end
        end
        
        -- 设置功能
        if type(source) ~= "number" or source < 0 or source > 3 then
            return false, "无效的唤醒源"
        end
        
        if type(level) ~= "number" or level < 0 or level > 1 then
            return false, "无效的唤醒电平"
        end
        
        if type(width) ~= "number" or width < 10 or width > 10000 then
            return false, "无效的唤醒脉宽"
        end
        
        local at_cmd = string.format("AT+WAKEUP=%d,%d,%d", source, level, width)
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync(at_cmd, nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success then
            -- 配置成功，保存配置
            local save_success, save_msg = exril_5101.save()
            return save_success, save_success and "配置保存成功" or save_msg
        else
            return false, "唤醒配置失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            log.error("exril_5101.wakeup", "必须在AT模式下配置唤醒功能")
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end

        -- 查询功能
        if source == nil then
            local function handle_query_response(cmd_sent, success, response)
                local config = {}
                
                if success and response then
                    local source_val, level_val, width_val = 
                        string.match(response, "^AT:(%d+),(%d+),(%d+)$")
                    
                    if source_val then
                        config = {
                            source = tonumber(source_val),
                            level = tonumber(level_val),
                            width = tonumber(width_val)
                        }
                    end
                end
                
                if callback then
                    local ok = (config.source ~= nil)
                    callback(ok, config, ok and "查询成功" or "查询失败")
                end
            end
            
            log.debug("exril_5101.wakeup", "查询唤醒配置")
            local sent = ril.request("AT+WAKEUP?", nil, handle_query_response, nil, ril.ATRESP, "^AT:.+$")
            if not sent and callback then
                callback(false, nil, "查询命令发送失败")
            end
            
            return sent
        end

        -- 设置功能
        if type(source) ~= "number" or source < 0 or source > 3 then
            if callback then callback(false, "source必须为0-3的数值") end
            return false
        end
        
        if type(level) ~= "number" or level < 0 or level > 1 then
            if callback then callback(false, "level必须为0或1") end
            return false
        end
        
        if type(width) ~= "number" or width < 10 or width > 10000 then
            if callback then callback(false, "width范围10-10000ms") end
            return false
        end
        
        local at_cmd = string.format("AT+WAKEUP=%d,%d,%d", source, level, width)
        log.debug("exril_5101.wakeup", "配置唤醒:", at_cmd)
        
        local function on_save_complete(save_success, save_msg)
            local success = save_success
            local msg = save_success and "配置保存成功" or save_msg or "配置保存失败"
                        
            if callback then
                callback(success, nil, msg)
            end
        end

        local function handle_wakeup_response(cmd_sent, success, response)
            local config_ok = success and response and response == "AT:OK"
            
            if not config_ok then
                if callback then
                    callback(false, nil, "唤醒配置失败")
                end
                return
            end
                        
            -- 配置成功，调用保存函数
            exril_5101.save(on_save_complete)
        end
        
        local sent = ril.request(at_cmd, nil, handle_wakeup_response, nil, ril.ATRESP, "^AT:.+$")
        if not sent and callback then
            callback(false, "唤醒配置命令发送失败")
        end
        
        return sent
    end
end

--[[
保存当前配置到Flash
@api exril_5101.save(timeout)
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和"保存成功"，失败返回false和错误信息
@usage
-- 保存配置到Flash
local success, message = exril_5101.save()
if success then
    log.info("配置保存成功")
else
    log.error("保存失败:", message)
end
--]]
function exril_5101.save(callback, timeout)
    -- 参数重载处理：
    -- 如果第一个参数是数字，说明是同步调用并指定超时
    if type(callback) == "number" then
        timeout = callback
        callback = nil
    end
    -- 同步调用
    if not callback then
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            return false, "必须在AT模式下执行"
        end
        
        -- 处理超时参数
        local sync_timeout = timeout or DEFAULT_TIMEOUT
        sync_timeout = math.min(sync_timeout, MAX_TIMEOUT) -- 最大10秒
        
        local success, response = ril.requestSync("AT+SAVE", nil, nil, ril.ATRESP, "^AT:.+$", sync_timeout)
        if success then
            return true, "保存成功"
        else
            return false, "保存失败"
        end
    else
        -- 异步调用
        if exril_5101_current_mode ~= exril_5101.MODE_AT then
            if callback then callback(false, "必须在AT模式下执行") end
            return false
        end
        
        local function handle_save_response(cmd_sent, success, response)
            local saved = success and response and response == "AT:OK"
            
            if callback then
                callback(saved, saved and "保存成功" or "保存失败")
            end
        end
        
        local sent = ril.request("AT+SAVE", nil, handle_save_response, nil, ril.ATRESP, "^AT:.+$")
        
        if not sent and callback then
            callback(false, "命令发送失败")
        end
        
        return sent
    end
end

--[[
向已连接的蓝牙主设备发送数据
@api exril_5101.send(data, wakeup_option, timeout)
@param data string 要发送的数据
@param wakeup_option nil|boolean|number|table 唤醒配置（可选）
    - nil/false: 不唤醒
    - true: 唤醒（使用默认参数：data="wakeup", delay=25ms）
    - number: 唤醒并指定延时（毫秒），如：50
    - table: 完整唤醒配置，支持字段：
        enable: boolean 是否唤醒
        data:   string 唤醒数据（默认"wakeup"）
        delay:  number 唤醒后延时（默认25ms）
@param timeout number|nil 可选，超时时间，单位毫秒，默认DEFAULT_TIMEOUT
@return boolean, string 成功返回true和"发送成功"，失败返回false和错误信息
@usage
-- 1. 发送数据给已连接的蓝牙设备，不唤醒
local success, message = exril_5101.send("Hello, Bluetooth!")
if success then
    log.info("数据发送成功")
else
    log.error("发送失败:", message)
end

-- 2. 简单唤醒（使用默认参数） 
exril_5101.send("Hello", true)

-- 3. 唤醒并指定延时20ms
exril_5101.send("Hello", 20)

-- 4. 完整唤醒配置
exril_5101.send("Hello", {
    enable = true,
    data = "0x00",     -- 唤醒数据
    delay = 30        -- 延时30ms
})

@note
1. 根据当前工作模式自动选择发送方式：
    - 透传模式：直接发送原始数据，最大MTU-3字节（MTU最大是512，所以data最大是509字节）；
    - AT指令模式：使用AT+BS命令，最大80字节；
2. 需要蓝牙已连接才能发送成功
--]]
function exril_5101.send(data, wakeup_option, callback, timeout)
    -- 参数重载：
    -- 1. 第二个参数是函数时当作回调
    -- 2. 第三个参数是数字时当作超时
    if type(data) == "string" and type(wakeup_option) == "function" then
        callback = wakeup_option
        wakeup_option = nil
        timeout = nil
    elseif type(callback) == "number" then
        timeout = callback
        callback = nil
    end

    -- 基本参数检查
    if type(data) ~= "string" or #data == 0 then
        local error_msg = "数据不能为空"
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end

    -- 解析唤醒配置（只支持 enable/data/delay）
    local wakeup_config = {
        enable = false,
        data = "wakeup",    -- 默认唤醒数据
        delay = 25       -- 默认延时100ms
    }
    
    if wakeup_option == true then
        -- 简单唤醒（使用默认参数）
        wakeup_config.enable = true
    elseif type(wakeup_option) == "number" then
        -- 唤醒并指定延时
        wakeup_config.enable = true
        wakeup_config.delay = wakeup_option
    elseif type(wakeup_option) == "table" then
        -- table配置
        wakeup_config.enable = wakeup_option.enable == true
        if wakeup_option.data ~= nil then
            wakeup_config.data = wakeup_option.data
        end
        if wakeup_option.delay ~= nil then
            wakeup_config.delay = wakeup_option.delay
        end
    end
    
    -- 执行唤醒
    if wakeup_config.enable then
        local wakeup_success = wakeup_module(wakeup_config.data)
        if not wakeup_success then
            local error_msg = "唤醒模块失败"
            if callback then 
                callback(false, error_msg) 
            end
            return false, error_msg
        end
        if wakeup_config.delay > 0 then
            sys.wait(wakeup_config.delay)
        end
    end
    
    -- 检查蓝牙连接
    if not exril_5101_connected then
        local error_msg = "蓝牙未连接"
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end
    
    -- 根据模式调用相应的发送函数
    if exril_5101_current_mode == exril_5101.MODE_UA then
        -- 异步调用
        if callback then
            return send_ua(data, callback)
        else
            -- 同步调用 - 需要接收两个返回值
            local success, message = send_ua(data, nil, timeout)
            return success, message
        end
    elseif exril_5101_current_mode == exril_5101.MODE_AT then
        -- 异步调用
        if callback then
            return send_at(data, callback)
        else
            -- 同步调用 - 需要接收两个返回值
            local success, message = send_at(data, nil, timeout)
            return success, message
        end
    else
        local error_msg = "未知的工作模式"
        if callback then 
            callback(false, error_msg) 
        end
        return false, error_msg
    end
end

--[[
注册蓝牙事件回调函数
@api exril_5101.on(cbfunc)
@function cbfunc 回调函数，格式: function(event, payload)
@return boolean, string|nil 成功返回true，失败返回false和错误信息
@usage
local function ble_callback(event, payload)
    if event == "connected" then
        log.info("蓝牙已连接")
    elseif event == "disconnected" then
        log.info("蓝牙已断开")
    elseif event == "data" then
        log.info("收到数据:", payload.data)
    end
end
exril_5101.on(ble_callback)
--]]
function exril_5101.on(cbfunc)
    if type(cbfunc) ~= "function" then
        return false, "回调必须是函数"
    end
    
    user_callback = cbfunc
    
    -- 首次注册时，注册URC处理器
    if not urc_registered then
        register_ble_urc()
        urc_registered = true
    end
    return true
end

return exril_5101