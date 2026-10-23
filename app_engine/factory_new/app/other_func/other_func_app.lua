--[[
@module  other_func_app
@summary 功能测试业务层：UVC / RS485 / UART 外设的开关、状态与 485 收发（config.peripherals 驱动）
@version 1.1
@date    2026.10.23
@author  江访
@usage
订阅: OTHER_FUNC_GET / OTHER_FUNC_SET(id, enabled)
发布: OTHER_FUNC_STATUS(list) / OTHER_FUNC_CHANGED(list) / OTHER_FUNC_SET_RESULT(id, ok, err)

订阅: RS485_TEST_SEND(id, data)      -- 485 收发测试页发起发送
发布: RS485_TEST_RESULT(id, ok, err) -- 发送结果回执（接收数据由 periph_rs485 直接广播 PERIPH_RX）

list 为按 config.peripherals 声明顺序排列的实例数组：
    { { id=, type=, name=, enabled=bool, info=string }, ... }

实例来源 config.peripherals，同一 type 可配多条（UART1 / UART2 / 多路 485），
靠 id 区分，互不覆盖。开关只控制外设上下电与串口打开；
数据收发只走 485 测试页这条路径，列表页本身不做收发。
]]

local M = {}

-- 编译清单：DRIVER_OF 的值经变量传给 require，编译系统文本扫描不到，
-- 此处补字面量 require 兜底（运行时永不调用）
local function _compile_manifest()
    require("periph_uvc")
    require("periph_rs485")
    require("periph_uart")
end

-- 外设 type → 驱动模块名
local DRIVER_OF = {
    uvc   = "periph_uvc",
    rs485 = "periph_rs485",
    uart  = "periph_uart",
}

-- 已挂 handle 的实例列表，顺序与 config.peripherals 一致
local items = {}
-- 实例 id → items 下标
local index_of = {}

--[[
@function status_of
@summary 取 handle 的运行状态，失败时返回未启用占位状态
@param h 外设 handle
@return table { enabled=bool, info=string }
]]
local function status_of(h)
    if type(h) ~= "table" or type(h.status) ~= "function" then
        return { enabled = false, info = "驱动未就绪" }
    end
    local ok, st = pcall(h.status, h)
    if ok and type(st) == "table" then return st end
    return { enabled = false, info = "状态读取失败" }
end

--[[
@function ensure_handle
@summary 取配置条目对应的外设 handle，缺失时按 type 补登记
@param p config.peripherals 条目
@return table|nil handle
]]
local function ensure_handle(p)
    if type(p) ~= "table" then return nil end
    local h = p.handle
    if type(h) == "table" and type(h.status) == "function" then return h end

    local mod_name = DRIVER_OF[p.type]
    if not mod_name then return nil end
    local ok, mod = pcall(require, mod_name)
    if not ok or type(mod) ~= "table" then return nil end

    if p.id and type(mod.get) == "function" then
        local ok_get, old = pcall(mod.get, p.id)
        if ok_get and type(old) == "table" and type(old.status) == "function" then
            p.handle = old
            return old
        end
    end

    if type(mod.init) ~= "function" then return nil end
    local ok_init, nh = pcall(mod.init, p)
    if ok_init and type(nh) == "table" and type(nh.status) == "function" then
        p.handle = nh
        return nh
    end
    return nil
end

--[[
@function build_items
@summary 按 config.peripherals 收集可管理实例
]]
local function build_items()
    items = {}
    index_of = {}
    local cfg = _G.project_config or {}
    local list = cfg.peripherals
    if type(list) ~= "table" then return end

    for i, p in ipairs(list) do
        if DRIVER_OF[p and p.type] then
            if not p.id then
                log.warn("other_func_app", "外设缺 id，跳过", p.type, "#" .. i)
            elseif index_of[p.id] then
                log.warn("other_func_app", "外设 id 重复，跳过", p.id)
            else
                local h = ensure_handle(p)
                if h then
                    local item = {
                        id = p.id,
                        type = p.type,
                        name = p.name or p.id or p.type,
                        params = p,
                        handle = h,
                        enabled = false,
                        info = "",
                    }
                    items[#items + 1] = item
                    index_of[item.id] = #items
                end
            end
        end
    end
end

--[[
@function refresh
@summary 刷新全部实例的开关状态与状态描述
]]
local function refresh()
    for i = 1, #items do
        local it = items[i]
        local st = status_of(it.handle)
        it.enabled = st.enabled and true or false
        it.info = tostring(st.info or "")
    end
end

--[[
@function snapshot
@summary 生成对外的实例状态列表（不含 handle）
@return table
]]
local function snapshot()
    local out = {}
    for i = 1, #items do
        local it = items[i]
        out[i] = {
            id = it.id,
            type = it.type,
            name = it.name,
            enabled = it.enabled,
            info = it.info,
        }
    end
    return out
end

--[[
@function push
@summary 把最新实例状态列表发布到指定事件
@param event 事件名
]]
local function push(event)
    refresh()
    sys.publish(event, snapshot())
end

--[[
@function on_get
@summary 回应实例状态查询
]]
local function on_get()
    push("OTHER_FUNC_STATUS")
end

--[[
@function apply
@summary 开启/关闭指定实例
@param id 实例 id
@param enabled true 打开 / false 关闭
@return boolean, string|nil
]]
local function apply(id, enabled)
    if #items == 0 then build_items() end
    local idx = index_of[id]
    if not idx then return false, "未找到外设: " .. tostring(id) end
    local it = items[idx]
    local h = ensure_handle(it.params) or it.handle
    if not h then return false, "驱动未就绪" end
    it.handle = h

    local fn = enabled and h.start or h.stop
    if type(fn) ~= "function" then return false, "驱动不支持该操作" end
    local ok, ret, err = pcall(fn, h)
    if not ok then return false, tostring(ret) end
    if ret ~= true then return false, tostring(err or (enabled and "打开失败" or "关闭失败")) end
    return true
end

--[[
@function on_set
@summary 开启/关闭指定实例并回执结果
@param id 实例 id
@param enabled true 打开 / false 关闭

放在 sys.taskInit 里跑：驱动 start/stop 内部会 sys.wait（UVC 上电稳定、485 DE 切换），
sys.subscribe 的派发上下文不是协程，直接跑会把等待整段跳过；camera.init / uart.setup
也会把消息派发卡住。
]]
local function on_set(id, enabled)
    sys.taskInit(function()
        local ok, err = apply(id, enabled)
        sys.publish("OTHER_FUNC_SET_RESULT", id, ok, err)
        push("OTHER_FUNC_CHANGED")
    end)
end

--[[
@function on_rs485_send
@summary 收发测试页的发送请求，转给对应 handle:send
@param id 实例 id
@param data 原始字节串

与 on_set 同理放在 sys.taskInit 里跑：rs485_send 内部要等 DE 方向切换的 tx_delay。
]]
local function on_rs485_send(id, data)
    sys.taskInit(function()
        if #items == 0 then build_items() end
        local idx = index_of[id]
        if not idx then
            sys.publish("RS485_TEST_RESULT", id, false, "未找到外设: " .. tostring(id))
            return
        end
        local it = items[idx]
        local h = ensure_handle(it.params) or it.handle
        if not h or type(h.send) ~= "function" then
            sys.publish("RS485_TEST_RESULT", id, false, "该外设不支持发送")
            return
        end
        it.handle = h
        local ok, ret, err = pcall(h.send, h, data)
        if not ok then
            sys.publish("RS485_TEST_RESULT", id, false, tostring(ret))
            return
        end
        if ret ~= true then
            sys.publish("RS485_TEST_RESULT", id, false, tostring(err or "发送失败"))
            return
        end
        sys.publish("RS485_TEST_RESULT", id, true)
    end)
end

--[[
@function M.get_list
@summary 同步取实例状态列表（供启动自检等非窗口路径使用）
@return table
]]
function M.get_list()
    if #items == 0 then build_items() end
    refresh()
    return snapshot()
end

--[[
@function M.set_enabled
@summary 同步开启/关闭指定实例
@param id 实例 id
@param enabled true 打开 / false 关闭
@return boolean, string|nil
]]
function M.set_enabled(id, enabled)
    return apply(id, enabled)
end

build_items()
sys.subscribe("OTHER_FUNC_GET", on_get)
sys.subscribe("OTHER_FUNC_SET", on_set)
sys.subscribe("RS485_TEST_SEND", on_rs485_send)

return M
