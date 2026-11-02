--[[
@module  other_func_app
@summary 功能测试业务层：UVC / RS485 / UART / 录音播放 外设的开关、状态与测试动作（config.peripherals 驱动）
@version 1.3
@date    2026.10.26
@author  江访
@usage
订阅: OTHER_FUNC_GET / OTHER_FUNC_SET(id, enabled)
发布: OTHER_FUNC_STATUS(list) / OTHER_FUNC_CHANGED(list) / OTHER_FUNC_SET_RESULT(id, ok, err)

订阅: RS485_TEST_SEND(id, data)      -- 485 收发测试页发起发送
发布: RS485_TEST_RESULT(id, ok, err) -- 发送结果回执（接收数据由 periph_rs485 直接广播 PERIPH_RX）

订阅: RS485_DE_HOLD(ms)              -- 方向脚自检：把 DE 拉高 ms 毫秒再回接收态
发布: RS485_DE_HOLD_RESULT(ok, used, pins, bad)
                                     -- 自检结果，used 为实际保持的毫秒数，
                                     -- pins 为拉高的方向脚，bad 为拉高期间回读不是高电平的脚

订阅: AUDIO_REC_START(id, seconds)   -- 录音播放测试页发起录音
订阅: AUDIO_REC_STOP(id)             -- 提前结束录音
订阅: AUDIO_PLAY_START(id)           -- 回放最近一次录音
订阅: AUDIO_PLAY_STOP(id)            -- 停止回放
发布: AUDIO_ACTION_RESULT(id, action, ok, err) -- 上述动作的回执，action 是动作名
（录音/播放的状态迁移由 periph_audio 直接广播 AUDIO_TEST_STATE）

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
    require("periph_audio")
end

-- 外设 type → 驱动模块名
local DRIVER_OF = {
    uvc   = "periph_uvc",
    rs485 = "periph_rs485",
    uart  = "periph_uart",
    audio = "periph_audio",
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
@function on_de_hold
@summary 方向脚自检：把 DE 脚拉高一段时间再回接收态，供现场用万用表量
@param ms 保持高电平的毫秒数

与 on_set 同理放在 sys.taskInit 里跑：de_hold 内部要 sys.wait 撑满保持时长。
]]
local function on_de_hold(ms)
    sys.taskInit(function()
        local ok_req, mod = pcall(require, "periph_rs485")
        if not ok_req or type(mod) ~= "table" or type(mod.de_hold) ~= "function" then
            sys.publish("RS485_DE_HOLD_RESULT", false, "驱动不支持方向脚自检")
            return
        end
        local ok, hold_ok, hold_ms, hold_pins, hold_bad = pcall(mod.de_hold, ms)
        if not ok then
            sys.publish("RS485_DE_HOLD_RESULT", false, tostring(hold_ok))
            return
        end
        if not hold_ok then
            sys.publish("RS485_DE_HOLD_RESULT", false, "没有登记到 DE 方向脚")
            return
        end
        sys.publish("RS485_DE_HOLD_RESULT", true, hold_ms, hold_pins, hold_bad)
    end)
end

--[[
@function on_audio_action
@summary 录音播放测试页的动作请求，转给对应 handle 的同名方法
@param action 动作名：record_start / record_stop / play_start / play_stop
@param id 实例 id
@param arg 透传给动作的可选参数（目前只有 record_start 用它传录音秒数）

与 on_set 同理放在 sys.taskInit 里跑：exaudio.record_start / play_start 是阻塞调用，
直接在消息派发上下文跑会把整段派发卡住。回执一律走 AUDIO_ACTION_RESULT，
成功与否都在里面，测试页只认这一个事件。
]]
local function on_audio_action(action, id, arg)
    sys.taskInit(function()
        if #items == 0 then build_items() end
        local idx = index_of[id]
        if not idx then
            sys.publish("AUDIO_ACTION_RESULT", id, action, false, "未找到外设: " .. tostring(id))
            return
        end
        local it = items[idx]
        local h = ensure_handle(it.params) or it.handle
        if not h then
            sys.publish("AUDIO_ACTION_RESULT", id, action, false, "驱动未就绪")
            return
        end
        it.handle = h

        local fn = h[action]
        if type(fn) ~= "function" then
            sys.publish("AUDIO_ACTION_RESULT", id, action, false, "驱动不支持该操作")
            return
        end
        local ok, ret, err = pcall(fn, h, arg)
        if not ok then
            sys.publish("AUDIO_ACTION_RESULT", id, action, false, tostring(ret))
            return
        end
        if ret ~= true then
            sys.publish("AUDIO_ACTION_RESULT", id, action, false, tostring(err or "操作失败"))
            return
        end
        sys.publish("AUDIO_ACTION_RESULT", id, action, true)
    end)
end

-- 录音播放测试页的四个动作入口，参数折成 on_audio_action 的 action 名
local function on_rec_start(id, seconds) on_audio_action("record_start", id, seconds) end
local function on_rec_stop(id)          on_audio_action("record_stop",  id) end
local function on_play_start(id)        on_audio_action("play_start",   id) end
local function on_play_stop(id)         on_audio_action("play_stop",    id) end

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
sys.subscribe("RS485_DE_HOLD", on_de_hold)
sys.subscribe("AUDIO_REC_START", on_rec_start)
sys.subscribe("AUDIO_REC_STOP", on_rec_stop)
sys.subscribe("AUDIO_PLAY_START", on_play_start)
sys.subscribe("AUDIO_PLAY_STOP", on_play_stop)

return M
