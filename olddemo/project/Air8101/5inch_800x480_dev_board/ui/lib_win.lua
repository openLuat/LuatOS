local lib_win = {}

--窗口管理栈
local stack = {}
--当前分配的窗口ID
local win_id = 0

local function alloc_id()
	win_id = win_id + 1
	return win_id
end

local function lose_focus()
	if stack[#stack] and stack[#stack]["on_lose_focus"] then
		stack[#stack]["on_lose_focus"]()
	end	
end

local function on_add(wnd)
	table.insert(stack,wnd)
	stack[#stack].on_refresh()
end

local function on_remove(win_id)
	local is_top,k,v
	for k,v in ipairs(stack) do
		if v.id == win_id then
			is_top = (k==#stack)
			table.remove(stack,k)
			if #stack~=0 and is_top then
				stack[#stack].on_refresh()
			end
			return
		end
	end
end

local function on_remove_all()
	local k,v
	for k,v in ipairs(stack) do
		table.remove(stack,k)
	end
end

local function on_refresh()
    if stack[#stack] and stack[#stack].on_refresh then
        stack[#stack].on_refresh()
    end
end

local function on_touch(tp_data)
	-- log.info("lib_win on_touch", stack[#stack], stack[#stack].on_touch)
    if stack[#stack] and stack[#stack].on_touch then
        stack[#stack].on_touch(tp_data)
    end
end

--- 新增一个窗口
-- @table wnd，窗口的元素以及消息处理函数表
-- @return number，窗口ID
-- @usage lib_win.add({on_refresh = refresh})
function lib_win.add(wnd)
	---必须注册更新接口
	assert(wnd.on_refresh)
	if type(wnd) ~= "table" then
		assert("unknown wnd type "..type(wnd))
	end
	--上一个窗口执行失去焦点的处理函数
	lose_focus()
	--为新窗口分配窗口ID
	wnd.id = alloc_id()
	--新窗口请求入栈
	sys.publish("LIBWIN_ADD",wnd)
	return wnd.id
end

--- 移除一个窗口
-- @number win_id，窗口ID
-- @return nil
-- @usage uiWin.remove(win_id)
function lib_win.remove(win_id)
	sys.publish("LIBWIN_REMOVE",win_id)
end

function lib_win.remove_all()
    sys.publish("LIBWIN_REMOVEALL")
end

function lib_win.refresh()
    sys.publish("LIBWIN_REFRESH")
end

--- 判断一个窗口是否处于最前显示
-- @number win_id，窗口ID
-- @return bool，true表示最前显示，其余表示非最前显示
-- @usage lib_win.is_active(win_id)
function lib_win.is_active(win_id)
    if stack[#stack] and stack[#stack].id then
        return stack[#stack].id==win_id
    end	
end

sys.subscribe("LIBWIN_ADD",on_add)
sys.subscribe("LIBWIN_REMOVE",on_remove)
sys.subscribe("LIBWIN_REMOVEALL",on_remove_all)
sys.subscribe("LIBWIN_REFRESH",on_refresh)
sys.subscribe("LIBWIN_TOUCH",on_touch)

return lib_win
