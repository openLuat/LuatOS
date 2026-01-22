--[[
@module libnet
@summary libnet 在socket库基础上的同步阻塞api，socket库本身是异步非阻塞api
@version 1.0
@date    2023.03.16
@author  lisiqi
]]

local libnet = {}

--[[
阻塞等待网卡的网络连接上，只能用于sysplus.taskInitEx创建的任务函数中
@api libnet.waitLink(taskName,timeout,...)
@string 任务标志
@int 超时时间，如果==0或者空，则没有超时一致等待
@... 其他参数和socket.linkup一致
@return boolean 失败或者超时返回false 成功返回true
]]
function libnet.waitLink(taskName, timeout, ...)
	local succ, result = socket.linkup(...)
	if not succ then
		return false
	end
	if not result then
		result = sysplus.waitMsg(taskName, socket.LINK, timeout)
	else
		return true
	end
	if type(result) == 'table' and result[2] == 0 then
		return true
	else
		return false
	end
end


--[[
阻塞等待IP或者域名连接上，如果加密连接还要等握手完成，只能用于sysplus.taskInitEx创建的任务函数中
@api libnet.connect(taskName,timeout,...)
@string 任务标志
@int 超时时间，如果==0或者空，则没有超时一致等待
@... 其他参数和socket.connect一致
@return boolean 失败或者超时返回false 成功返回true
]]
function libnet.connect(taskName,timeout, ... )
	local succ, result = socket.connect(...)
	if not succ then
		return false
	end
	if not result then
		result = sysplus.waitMsg(taskName, socket.ON_LINE, timeout)
	else
		return true
	end
	if type(result) == 'table' and result[2] == 0 then
		return true
	else
		return false
	end
end

--[[
阻塞等待客户端连接上，只能用于sysplus.taskInitEx创建的任务函数中
@api libnet.listen(taskName,timeout,...)
@string 任务标志
@int 超时时间，如果==0或者空，则没有超时一致等待
@... 其他参数和socket.listen一致
@return boolean 失败或者超时返回false 成功返回true
]]
function libnet.listen(taskName,timeout, ... )
	local succ, result = socket.listen(...)
	if not succ then
		return false
	end
	if not result then
		result = sysplus.waitMsg(taskName, socket.ON_LINE, timeout)
	else
		return true
	end
	if type(result) == 'table' and result[2] == 0 then
		return true
	else
		return false
	end
end

--[[
阻塞等待数据发送完成，只能用于sysplus.taskInitEx创建的任务函数中
@api libnet.tx(taskName,timeout,...)
@string 任务标志
@int 超时时间，如果==0或者空，则没有超时一直等待
@... 其他参数和socket.tx一致
@return boolean 失败或者超时返回false，缓冲区满了或者成功返回true
@return boolean 缓存区是否满了
]]
function libnet.tx(taskName,timeout, ...)
	local succ, is_full, result = socket.tx(...)
	if not succ then
		return false, is_full
	end
	if is_full then
		return true, true
	end
	if not result then
		result = sysplus.waitMsg(taskName, socket.TX_OK, timeout)
	else
		return true, is_full
	end
	if type(result) == 'table' and result[2] == 0 then
		return true, false
	else
		return false, is_full
	end
end

--[[
阻塞等待新的网络事件，只能用于sysplus.taskInitEx创建的任务函数中，可以通过sysplus.sendMsg(taskName,socket.EVENT,0)或者sys_send(taskName,socket.EVENT,0)强制退出
@api libnet.wait(taskName,timeout, netc)
@string 任务标志
@int 超时时间，如果==0或者空，则没有超时一致等待
@userdata socket.create返回的netc
@return boolean 网络异常返回false，其他返回true
@return boolean 超时返回false，有新的网络事件到返回true
]]
function libnet.wait(taskName,timeout, netc)
	local succ, result = socket.wait(netc)
	if not succ then
		return false,false
	end
	if not result then
		result = sysplus.waitMsg(taskName, socket.EVENT, timeout)
	else
		return true,true
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

--[[
阻塞等待网络断开连接，只能用于sysplus.taskInitEx创建的任务函数中
@api libnet.close(taskName,timeout, netc)
@string 任务标志
@int 超时时间，如果==0或者空，则没有超时一致等待
@userdata socket.create返回的netc
]]
function libnet.close(taskName,timeout, netc)
	local succ, result = socket.discon(netc)
	if not succ then
		socket.close(netc)
		return
	end
	if not result then
		result = sysplus.waitMsg(taskName, socket.CLOSED, timeout)
	else
		socket.close(netc)
		return
	end
	socket.close(netc)
end

--[[
阻塞发起PING请求，可在sys.taskInit创建的任务中使用
@api libnet.ping(id, ip, timeout, len)
@number 网络适配器编号，例如socket.LWIP_ETH，必需
@string 要ping的目标ip地址，必需
@int 超时时间，可选，单位毫秒，默认5000ms
@number ping包大小，可选，默认128字节
@return boolean ping成功返回true，失败或超时返回false
]]
function libnet.ping(id, ip, timeout, len)
	-- 检查必需参数
	if not id then
		log.error("libnet.ping", "参数错误：缺少网络适配器编号(id)")
		return false
	end
	
	if not ip then
		log.error("libnet.ping", "参数错误：缺少目标IP地址(ip)")
		return false
	end
	
	-- 处理参数
	local wait_timeout = timeout or 5000 -- 默认超时5秒
	local packet_len = len or 128 -- 默认包大小128字节
	
	
	-- 发送ping请求（返回值仅表示发送成功与否）
	local send_ok = netdrv.ping(id, ip, packet_len)
	if not send_ok then
		log.warn("libnet.ping", "ping请求发送失败", "目标:", ip)
		return false
	end
	
	-- 等待PING_RESULT事件获取ping结果
	local event, ping_id, ping_time, ping_dst = sys.waitUntil("PING_RESULT", wait_timeout)
	
	-- 根据事件结果判断ping是否成功
	if event and ping_time and ping_time > 0 then
		log.info("libnet.ping", "ping成功", "目标:", ping_dst, "耗时:", ping_time, "ms")
		return true
	else
		log.warn("libnet.ping", "ping失败", "目标:", ip)
		return false
	end
end

return libnet