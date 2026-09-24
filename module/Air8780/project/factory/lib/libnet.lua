local libnet = {}
local tag = "libnet"
--- 阻塞等待网卡的网络连接上，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.linkup一致
-- @return 失败或者超时返回false 成功返回true
function libnet.waitLink(taskName, timeout, ...)
    local succ, result = socket.linkup(...)
    if not succ then return false end
    if not result then
        result = sys_wait(taskName, socket.LINK, timeout)
    else
        return true
    end
    if type(result) == 'table' and result[2] == 0 then
        return true
    else
        return false
    end
end

--- 阻塞等待IP或者域名连接上，如果加密连接还要等握手完成，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.connect一致
-- @return 失败或者超时返回false 成功返回true
function libnet.connect(taskName, timeout, ...)
    sysplus.cleanMsg(taskName)
    local succ, result = socket.connect(...)
    if not succ then return false end
    if not result then
        result = sys_wait(taskName, socket.ON_LINE, timeout)
    else
        return true
    end
    if type(result) == 'table' and result[2] == 0 then
        return true
    else
        return false
    end
end

--- 阻塞等待客户端连接上，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.listen一致
-- @return 失败或者超时返回false 成功返回true
function libnet.listen(taskName, timeout, ...)
    local succ, result = socket.listen(...)
    if not succ then return false end
    if not result then
        result = sys_wait(taskName, socket.ON_LINE, timeout)
    else
        return true
    end
    if type(result) == 'table' and result[2] == 0 then
        return true
    else
        return false
    end
end

--- 阻塞等待数据发送完成，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.tx一致
-- @return 
-- @boolean 失败或者超时返回false，缓冲区满了或者成功返回true
-- @boolean 缓存区是否满了
function libnet.tx(taskName, timeout, ...)
    local succ, is_full, result = socket.tx(...)
    if not succ then return false, is_full end
    if is_full then return true, true end
    if not result then
        result = sys_wait(taskName, socket.TX_OK, timeout)
    else
        return true, is_full
    end
    if type(result) == 'table' and result[2] == 0 then
        return true, false
    else
        return false, is_full
    end
end

--- 阻塞等待新的网络事件或者特定事件，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.wait一致
-- @return 
-- @boolean 网络异常返回false，其他返回true
-- @table or boolean 超时返回false，有新的数据到返回true，被其他事件退出的，返回接收到的事件
function libnet.wait(taskName, timeout, netc)
    local succ, result = socket.wait(netc)
    if not succ then return false, false end
    if not result then
        result = sys_wait(taskName, socket.EVENT, timeout)
    else
        return true, true
    end
    if type(result) == 'table' then
        if result[2] == 0 then
            return true, true
        else
            return false, false
        end
    else
        return true, false
    end
end

--- 阻塞等待网络断开连接，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和socket.close一致
-- @return 无
function libnet.close(taskName, timeout, netc)
    local succ, result = socket.discon(netc)
    if not succ then
        socket.close(netc)
        return
    end
    if not result then
        result = sys_wait(taskName, socket.CLOSED, timeout)
    else
        socket.close(netc)
        return
    end
    socket.close(netc)
end

--- 一个简单模仿8910 net.lua的逻辑
-- 打印CSQ值
local function getcsq(time)
    if time and tonumber(time) ~= 0 then
        log.info(tag,"+ csq", mobile.csq(), mobile.rssi(), mobile.rsrp(),
                 mobile.rsrq())
        sys.timerLoopStart(function()
            log.info(tag,"+ csq", mobile.csq(), mobile.rssi(), mobile.rsrp(),
                     mobile.rsrq())
        end, time)
    else
        log.info(tag,"+ csq", mobile.csq(), mobile.rssi(), mobile.rsrp(),
                 mobile.rsrq())
        sys.timerLoopStart(function()
            log.info(tag,"+ csq", mobile.csq(), mobile.rssi(), mobile.rsrp(),
                     mobile.rsrq())
        end, 30 * 1000)
    end
end
-- 打印iccid
-- 逻辑：先去找卡，找到就打印卡号，找不到就打印sim卡不识别
local function geticcid(id)
    if id then
        log.info(tag,"iccid"..id, mobile.iccid(tonumber(id)))
        return mobile.iccid(tonumber(id))
    else
        log.info(tag,"iccid", mobile.iccid())
        return mobile.iccid()
    end
end

sys.subscribe("SIM_IND", function(status)
    -- status的取值有:
    -- RDY SIM卡就绪
    -- NORDY 无SIM卡
    -- SIM_PIN 需要输入PIN
    -- GET_NUMBER 获取到电话号码(不一定有值)
    log.info("sim status", status)
    if status == "GET_NUMBER" then log.info(tag,"GET_NUMBER iccid ", mobile.iccid())
    elseif status == "RDY" then log.info(tag,"识别到了SIM卡状态：RDY iccid： ", mobile.iccid())
    elseif status == "NORDY" then log.info(tag,"识别不到您的SIM卡,请重新插入并且重启模块")
    elseif status == "SIM_PIN" then log.info(tag,"SIM卡锁pin,请解锁后使用")
	else log.info(tag,"sim status", status) end
end)
sys.timerStart(geticcid, 5000)

sys.timerStart(getcsq, 5000)

return libnet
