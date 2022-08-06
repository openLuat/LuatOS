local libnet = {}

--- 阻塞等待网卡的网络连接上，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和network.linkup一致
-- @return 失败或者超时返回false 成功返回true
function libnet.waitLink(taskName, timeout, ...)
	local is_err, result = network.linkup(...)
	if is_err then
		return false
	end
	if not result then
		result = sys_wait(taskName, network.LINK, timeout)
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
-- @... 其他参数和network.connect一致
-- @return 失败或者超时返回false 成功返回true
function libnet.connect(taskName,timeout, ... )
	local is_err, result = network.connect(...)
	if is_err then
		return false
	end
	if not result then
		result = sys_wait(taskName, network.ON_LINE, timeout)
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
-- @... 其他参数和network.listen一致
-- @return 失败或者超时返回false 成功返回true
function libnet.listen(taskName,timeout, ... )
	local is_err, result = network.listen(...)
	if is_err then
		return false
	end
	if not result then
		result = sys_wait(taskName, network.ON_LINE, timeout)
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
-- @... 其他参数和network.tx一致
-- @return 
-- @boolean 失败或者超时返回false，缓冲区满了或者成功返回true
-- @boolean 缓存区是否满了
function libnet.tx(taskName,timeout, ...)
	local is_err, is_full, result = network.tx(...)
	if is_err then
		return false, is_full
	end
	if is_full then
		return true, true
	end
	if not result then
		result = sys_wait(taskName, network.TX_OK, timeout)
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
-- @... 其他参数和network.wait一致
-- @return 
-- @boolean 网络异常返回false，其他返回true
-- @table or boolean 超时返回false，有新的数据到返回true，被其他事件退出的，返回接收到的事件
function libnet.wait(taskName,timeout, netc)
	local is_err, result = network.wait(netc)
	if is_err then
		return false,false
	end
	if not result then
		result = sys_wait(taskName, network.EVENT, timeout)
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

--- 阻塞等待网络断开连接，只能用于任务函数中
-- @string 任务标志
-- @int 超时时间，如果==0或者空，则没有超时一致等待
-- @... 其他参数和network.close一致
-- @return 无
function libnet.close(taskName,timeout, netc)
	local is_err, result = network.discon(netc)
	if is_err then
		network.close(netc)
		return
	end
	if not result then
		result = sys_wait(taskName, network.CLOSED, timeout)
	else
		network.close(netc)
		return
	end
	network.close(netc)
end

return libnet