-- exwin.lua - 嵌入式窗口管理扩展库
--[[
@module  exwin
@summary UI窗口管理扩展库
@version 1.0.0
@date    2026.03.11
@author  江访
@usage
本文件为窗口管理扩展库，核心业务逻辑为：
1、基于栈的窗口管理，栈顶为当前活动窗口
2、支持窗口生命周期回调（创建、销毁、获得焦点、失去焦点）
3、全局事件自动路由到当前活动窗口的对应处理函数
4、提供页面打开、关闭、返回首页等导航功能

窗口定义通过 Lua 表描述，可包含以下回调：
- on_create(id)：窗口创建时调用
- on_destroy(id)：窗口销毁时调用
- on_get_focus(id)：窗口获得焦点时调用
- on_lose_focus(id)：窗口失去焦点时调用
- on_<event>(...)：自定义事件处理函数，通过 EXWIN_EVENT 通道触发

所有外部事件需通过 sys.publish("EXWIN_EVENT", event_name, ...) 发布

本文件的对外接口有4个：
1、exwin.open(config)：打开/切换到指定窗口
2、exwin.close(win_id)：关闭指定窗口
3、exwin.is_active(win_id)：查询窗口是否为当前活动窗口
4、exwin.return_idle()：一键返回首页（ID=1），销毁其他所有窗口
]]

local exwin = {}

-- 窗口栈（栈顶为当前活动窗口）
local win_stack = {}
-- 下一个可分配的窗口ID（从1开始）
local next_id = 1

-- 内部函数：根据ID查找窗口在栈中的索引和记录
-- @number id 窗口ID
-- @return number|nil 窗口在栈中的索引，若不存在返回nil
-- @return table|nil 窗口记录表，若不存在返回nil
local function find_by_id(id)
    for i, w in ipairs(win_stack) do
        if w.id == id then
            return i, w
        end
    end
    return nil, nil
end

-- 内部函数：获取当前活动窗口（栈顶）
-- @return table|nil 当前活动窗口记录，若栈空返回nil
local function get_current()
    return win_stack[#win_stack]
end

-- 安全调用回调函数（忽略nil）
-- @param fn 回调函数（可能为nil）
-- @param ... 传递给回调的参数
local function safe_call(fn, ...)
    if fn then
        fn(...)
    end
end

--[[
打开/切换到指定窗口
@api exwin.open(config)
@table config 配置表，包含：
    @number win_id 可选，指定窗口ID：
        - 若为nil，则创建新窗口，ID自动分配
        - 若指定ID且窗口已存在，则切换到该窗口（移至栈顶）
        - 若指定ID但窗口不存在，则忽略（不做任何操作）
    @function on_create 可选，窗口创建回调
    @function on_destroy 可选，窗口销毁回调
    @function on_lose_focus 可选，窗口失去焦点回调
    @function on_get_focus 可选，窗口获得焦点回调
@return nil
@usage
-- 新建窗口
exwin.open({
    on_create = function(id) print("窗口创建", id) end,
    on_touch = function(event, x, y) print("触摸", event, x, y) end
})

-- 切换到已存在的窗口（假设ID为2）
exwin.open({win_id = 2})
]]
function exwin.open(config)
    config = config or {}
    local target_id = config.win_id
    local current = get_current()

    if target_id == nil then
        -- 新建窗口
        target_id = next_id
        next_id = next_id + 1
        local new_win = {
            id = target_id,
            create = config.on_create,
            destroy = config.on_destroy,
            lose_focus = config.on_lose_focus,
            get_focus = config.on_get_focus
        }
        -- 让当前窗口失去焦点
        if current then
            safe_call(current.lose_focus, current.id)
        end
        -- 新窗口入栈
        table.insert(win_stack, new_win)
        -- 调用创建回调
        safe_call(new_win.create, new_win.id)
    else
        -- 目标窗口已存在
        local idx, win = find_by_id(target_id)
        if not win then
            -- 如果ID不存在（不应发生），可忽略或按新建处理
            return
        end
        -- 如果已经是当前窗口，无需操作
        if current and current.id == target_id then
            return
        end
        -- 让当前窗口失去焦点
        if current then
            safe_call(current.lose_focus, current.id)
        end
        -- 从原位置移除，再推入栈顶
        table.remove(win_stack, idx)
        table.insert(win_stack, win)
        -- 让目标窗口获得焦点：优先调用 on_get_focus，否则回退到 on_create
        if win.get_focus then
            safe_call(win.get_focus, win.id)
        else
            safe_call(win.create, win.id)
        end
    end
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
    local idx, win = find_by_id(win_id)
    if not win then return end

    -- 调用销毁回调
    safe_call(win.destroy, win.id)

    -- 从栈中移除
    table.remove(win_stack, idx)

    -- 如果关闭的是当前窗口（原栈顶），则让新栈顶获得焦点
    if idx == #win_stack + 1 then  -- 移除后长度减1，原索引等于原长度
        local new_current = get_current()
        if new_current then
            safe_call(new_current.get_focus, new_current.id)
        end
    end
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
    local current = get_current()
    return current and current.id == win_id
end

--[[
一键返回首页（win_id=1），销毁其他所有页面，并重新创建首页
@api exwin.return_idle()
@return nil
@usage
-- 在任何页面调用，都会回到首页并销毁中间页面
exwin.return_idle()
]]
function exwin.return_idle()
    -- 从栈顶向下遍历，销毁除首页外的所有窗口
    for i = #win_stack, 2, -1 do
        local win = win_stack[i]
        -- 优先调用 on_destroy，若无则调用 on_lose_focus（模拟清理）
        if win.destroy then
            safe_call(win.destroy, win.id)
        elseif win.lose_focus then
            safe_call(win.lose_focus, win.id)
        end
        table.remove(win_stack, i)
    end

    -- 现在栈中只剩首页（ID应为1），重新创建它
    if #win_stack >= 1 and win_stack[1].id == 1 then
        safe_call(win_stack[1].create, win_stack[1].id)
    else
        -- 异常情况：可在此重新创建首页
    end
end

-- ========== 事件分发机制 ==========
-- 订阅全局事件通道，将事件转发给当前活动窗口的对应回调
-- 事件格式：sys.publish("EXWIN_EVENT", event_name, ...)
-- 例如：sys.publish("EXWIN_EVENT", "touch", touch_data)
-- 当前窗口需实现 on_touch(touch_data) 函数
sys.subscribe("EXWIN_EVENT", function(event, ...)
    local cur = get_current()
    if cur then
        local handler = cur["on_"..event]
        if handler then
            handler(...)
        end
    end
end)

return exwin