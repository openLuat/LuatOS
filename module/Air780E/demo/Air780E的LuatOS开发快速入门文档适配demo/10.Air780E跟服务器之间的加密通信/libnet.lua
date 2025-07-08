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
		result = sys_wait(taskName, socket.EVENT, timeout)
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
		result = sys_wait(taskName, socket.CLOSED, timeout)
	else
		socket.close(netc)
		return
	end
	socket.close(netc)
end

return libnet