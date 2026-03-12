-- exwin.lua - 嵌入式窗口管理扩展库
--[[
@module  exwin
@summary UI窗口管理扩展库
@version 1.0.0
@date    2026.03.12
@author  江访
@usage
本文件为窗口管理扩展库，核心业务逻辑为：
1、基于栈的窗口管理，栈顶为当前活动窗口
2、支持窗口生命周期回调（创建、销毁、获得焦点、失去焦点）
3、提供页面打开、关闭、查询活动、返回首页等导航功能

窗口定义通过 Lua 表描述，需包含以下回调：
- on_create()：窗口创建时调用(必须有)
- on_destroy()：窗口销毁时调用
- on_get_focus()：窗口获得焦点时调用
- on_lose_focus()：窗口失去焦点时调用

本文件的对外接口有4个：
1、exwin.open(config)：打开一个新窗口，自动分配ID并执行创建回调
2、exwin.close(win_id)：关闭指定窗口（通常用于关闭自己）
3、exwin.is_active(win_id)：查询窗口是否为当前活动窗口
4、exwin.return_idle()：一键返回首页（ID=1），销毁其他所有窗口
]]

local exwin = {}

-- 窗口栈，栈顶为当前活动窗口
local win_stack = {}
-- 下一个可分配的窗口ID（从1开始）
local next_id = 0

-- 内部函数：根据ID查找窗口在栈中的索引
-- @number id 窗口ID
-- @return number|nil 窗口在栈中的索引，若不存在返回nil
local function find_index_by_id(id)
    for i, w in ipairs(win_stack) do
        if w.id == id then
            return i
        end
    end
    return nil
end

--[[
打开一个新窗口
@api exwin.open(config)
@table config 配置表，可包含：
    @function on_create 可选，窗口创建回调
    @function on_destroy 可选，窗口销毁回调
    @function on_lose_focus 可选，窗口失去焦点回调
    @function on_get_focus 可选，窗口获得焦点回调
@return number 新窗口的ID
@usage
local win_id = exwin.open({
    on_create = function(id) print("窗口创建", id) end,
    on_get_focus = function(id) print("窗口获得焦点", id) end,
    on_lose_focus = function(id) print("窗口失去焦点", id) end,
    on_destroy = function(id) print("窗口销毁", id) end
})
]]
function exwin.open(config)

    -- 如果参数不是表则报错重启
    assert(type(config) == "table" and type(config.on_create) == "function", "exwin.open()参数必须是table，并且包含on_create函数")

    -- 获取当前活动窗口（栈顶）
    local current = win_stack[#win_stack]

    -- 分配新ID
    next_id = next_id + 1
    local new_id = next_id

    -- 构造窗口记录
    local new_win = {
        id = new_id,
        create = config.on_create,
        destroy = config.on_destroy,
        lose_focus = config.on_lose_focus,
        get_focus = config.on_get_focus
    }

    -- 如果存在当前窗口，先让其失去焦点
    if current and current.lose_focus then
        pcall(current.lose_focus)
    end

    -- 新窗口入栈
    table.insert(win_stack, new_win)

    -- 调用新窗口的创建回调
    pcall(new_win.create)

    return new_id
end

--[[
关闭指定窗口（通常由页面自己调用）
@api exwin.close(win_id)
@number win_id 要关闭的窗口ID
@return nil
@usage
-- 在窗口内部关闭自己
exwin.close(win_id)
]]
function exwin.close(win_id)
    local idx = find_index_by_id(win_id)
    if not idx then return end

    local win = win_stack[idx]
    local is_top = (idx == #win_stack) -- 是否是栈顶窗口

    -- 调用销毁回调
    if win.destroy then
        pcall(win.destroy)
    end

    -- 从栈中移除
    table.remove(win_stack, idx)

    -- 如果关闭的是栈顶窗口，则让新的栈顶获得焦点
    if is_top then
        local new_current = win_stack[#win_stack]
        if new_current and new_current.get_focus then
            pcall(new_current.get_focus)
        end
    end
    -- 若关闭的不是栈顶，焦点窗口不变，无需额外操作
end

--[[
查询窗口是否为当前活动页面
@api exwin.is_active(win_id)
@number win_id 窗口ID
@return boolean true表示是活动窗口，false表示不是或窗口不存在
@usage
if exwin.is_active(1) then
    log.info("首页是活动窗口")
end
]]
function exwin.is_active(win_id)
    if win_id == nil then return false end
    local current = win_stack[#win_stack]
    return current and current.id == win_id
end

--[[
一键返回首页（win_id=1），销毁其他所有窗口，并保留第一个窗口
@api exwin.return_idle()
@return nil
@usage
-- 在任何页面调用，都会回到首页并销毁中间页面
exwin.return_idle()
]]
function exwin.return_idle()
    -- 从栈顶向下遍历，销毁除栈底（第一个窗口）外的所有窗口
    -- 栈底窗口的ID应为1（假设第一个打开的窗口是首页）
    for i = #win_stack, 2, -1 do
        local win = win_stack[i]
        log.info("return_idle", i, win.id)
        if win.destroy then
            pcall(win.destroy)
        end
        table.remove(win_stack, i)
    end

    -- 现在栈中只剩首页（索引1），调用其获得焦点回调
    local home = win_stack[1]
    if home and home.get_focus then
        pcall(home.get_focus)
    end
end

return exwin