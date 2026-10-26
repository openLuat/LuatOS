--[[
@module  settings_can_app
@summary CAN 总线测试业务层（设置页入口 · Air1601 CAN2 复用 UART2）
@version 1.0
@date    2026.10.26
@author  江访
@usage
本模块是 CAN 测试页的业务层，只做「打开总线 / 发一帧 / 收一帧 / 切模式」，不保存历史。

消息协议:
订阅: CAN_OPEN_REQ                 → 打开总线（init + 回调 + 时序 + 工作模式）
订阅: CAN_CLOSE_REQ                → 关闭总线（退出页面时注销回调并 deinit）
订阅: CAN_SEND_REQ(data)           → 发送一帧（不带参数时发配置里的 test_data，≤8 字节，纯字符串不转 HEX）
订阅: CAN_MODE_REQ(mode)           → 切换工作模式："normal" 正常 / "test" 自收自发 / "listen" 只听
发布: CAN_OPEN_RESULT(ok, err, info)  info = { name,can_id,uart_id,bitrate,mode,tx_id,ext,need_ack,
                                              test_data,running,state,state_text,rx,tx }
发布: CAN_SEND_RESULT(ok, err, body)  body = 实际写进总线的那一帧数据
发布: CAN_MODE_RESULT(ok, err, info)  切模式结果（info 同 CAN_OPEN_RESULT）
发布: CAN_RX(msg_id, id_type, rtr, data)  收到的一帧（id_type: 1=扩展帧 0=标准帧）
发布: CAN_STATE(state, text)          总线状态变化（STATE_XXX 原始值 + 中文说明）
发布: CAN_NOTE(text)                  附加提示（错误码 / 发送异常 / 未打开）

=== can 是内置核心库，不需要 require ===
固件编译时带 CAN 时，全局就有 can；没带时 can 为 nil（PC 模拟器等）。所以本模块
统一写 `if can then` / `if not can then`，其余地方直接用 can.xxx，不做 type() 包装。

=== 参数来源 ===
config.can（顶层字段，不是 peripherals）：CAN 不需要开机初始化，也不归 periph_loader 管，
所以只声明参数。老配置若仍写在 peripherals 里 type="can" 的条目，本模块也兼容读。

本板 CAN2 复用 UART2，
与 RS485 测试页是**同一个串口、同一组引脚**，由底板拨码开关切换（S3 选 CAN2 通路、
U17 把 UART2 切到 CAN），两者不能同时使用。所以打开前会先 uart.close 把口抢回来。

=== 现有固件的两个坑（务必先看）===
1. can 库编号是 **1-based**：Lua 写 1 = CAN1（复用 UART1），写 2 = CAN2（本板复用 UART2）。
   所以 config 里 can_id 直接填 2，不要按文档的 0-based 思维填 1。
2. 同一版固件 can.node 的过滤有 bug（非 FIFO 模式），**不要调用 can.node / can.filter**。
   默认就是收全部帧，调了反而一帧都收不到。

=== 自测模式 vs 正常模式 ===
mode = "test"（can.MODE_TEST）自收自发：不需要对端、不需要终端电阻，点「发送」就能在
日志里看到自己那帧回来，适合单板验证收发通路（示例 demo 用的就是它）。
mode = "normal"（can.MODE_NORMAL）真总线：必须接对端（另一台 CAN 设备）且两端各 120Ω
终端电阻，否则发送会因无应答反复重试、错误计数上涨，状态从「主动错误」掉到「被动错误」
甚至「离线」。页面上的模式按钮可随时切换，先自测通路、再接对端切正常模式。
]]

-- 缺省测试内容（config 里写了 test_data 以配置为准）
local DEFAULT_TEST_DATA = "CAN test"
-- 缺省发送帧 ID（与官方 demo 一致）
local DEFAULT_TX_ID = 0x12345677
-- CAN 单帧数据上限
local CAN_MAX_DATA = 8
-- 一次回调里最多取多少帧（防止固件 bug 导致 rx 永远返回 true 时卡死）
local RX_DRAIN_MAX = 64

-- 未配置 config.can 时的兜底硬件参数（本板 CAN2 复用 UART2）
local FALLBACK_PARAMS = {
    id = "can_1", name = "CAN",
    can_id = 2, uart_id = 2,
    mode = "normal",
    bitrate = 1000000, pts = 6, pbs1 = 6, pbs2 = 4, sjw = 2,
    tx_id = DEFAULT_TX_ID, ext = true, need_ack = true,
    cache = 128, test_data = DEFAULT_TEST_DATA,
}

-- 模式名 → can.MODE_XXX 常量名 / 常量缺失时的兜底值（luat_can.h 枚举顺序）
local MODE_CONST = { normal = "MODE_NORMAL", listen = "MODE_LISTEN", test = "MODE_TEST", sleep = "MODE_SLEEP" }
local MODE_FALLBACK = { normal = 0, listen = 1, test = 2, sleep = 3 }
-- 模式中文名（页面显示）
local MODE_TEXT = { normal = "正常", test = "自收自发", listen = "只听", sleep = "休眠" }

local params = nil
local running = false      -- 总线是否已打开
local cur_mode = "normal"  -- 当前工作模式（normal / test / listen）
local bus_state = nil      -- 最近一次总线状态（can.state 原始值）
local rx_count, tx_count = 0, 0

-- ==================== 参数 ====================

--[[取本机型的 can 参数：优先 config.can，兼容写在 peripherals 里 type="can" 的旧配置]]
local function find_params()
    local cfg = _G.project_config
    if type(cfg) ~= "table" then return nil end
    if type(cfg.can) == "table" then return cfg.can end
    local list = cfg.peripherals
    if type(list) ~= "table" then return nil end
    for _, p in ipairs(list) do
        if p and p.type == "can" then return p end
    end
    return nil
end

local function get_params()
    if params then return params end
    params = find_params() or FALLBACK_PARAMS
    return params
end

local function can_id()
    return get_params().can_id or 0
end

local function test_data()
    return tostring(get_params().test_data or DEFAULT_TEST_DATA)
end

--[[模式名 → 数值；未知模式返回 nil + 错误串]]
local function mode_value(name)
    name = tostring(name or "normal"):lower()
    local key = MODE_CONST[name]
    if not key then return nil, nil, "未知模式：" .. name end
    local v = can and can[key] or nil
    if type(v) ~= "number" then v = MODE_FALLBACK[name] end
    return v, name
end

--[[总线状态值 → 中文；常量缺失时按枚举顺序兜底]]
local function state_text(v)
    if type(v) ~= "number" then return "--" end
    local c = can or {}
    if c.STATE_ACTIVE and v == c.STATE_ACTIVE then return "主动错误(正常)" end
    if c.STATE_PASSIVE and v == c.STATE_PASSIVE then return "被动错误" end
    if c.STATE_BUSOFF and v == c.STATE_BUSOFF then return "离线(BusOff)" end
    if c.STATE_LISTEN and v == c.STATE_LISTEN then return "监听" end
    if c.STATE_TEST and v == c.STATE_TEST then return "自收自发" end
    if c.STATE_SLEEP and v == c.STATE_SLEEP then return "休眠" end
    if c.STATE_STOP and v == c.STATE_STOP then return "停止" end
    -- luat_can.h: 0 停止 / 1 主动 / 2 被动 / 3 离线 / 4 监听 / 5 自测 / 6 休眠
    local fallback = { "停止", "主动错误(正常)", "被动错误", "离线(BusOff)", "监听", "自收自发", "休眠" }
    return fallback[v + 1] or ("状态" .. tostring(v))
end

--[[端口描述，给 UI 显示]]
local function port_info()
    local p = get_params()
    return {
        name       = p.name or "CAN",
        can_id     = p.can_id or 0,
        uart_id    = p.uart_id,
        bitrate    = p.bitrate or 1000000,
        pts        = p.pts or 6,
        pbs1       = p.pbs1 or 6,
        pbs2       = p.pbs2 or 4,
        sjw        = p.sjw or 2,
        mode       = cur_mode,
        mode_text  = MODE_TEXT[cur_mode] or cur_mode,
        tx_id      = p.tx_id or DEFAULT_TX_ID,
        ext        = p.ext ~= false,
        need_ack   = p.need_ack ~= false,
        cache      = p.cache or 128,
        test_data  = test_data(),
        running    = running,
        state      = bus_state,
        state_text = state_text(bus_state),
        rx         = rx_count,
        tx         = tx_count,
    }
end

--[[刷新总线状态（打开后 / 状态变化回调里调用）]]
local function refresh_state()
    if not can or not running then return bus_state end
    local ok, v = pcall(can.state, can_id())
    if ok and type(v) == "number" then bus_state = v end
    return bus_state
end

-- ==================== 事件回调 ====================

--[[can 回调在 msgbus 上下文里执行（不是协程），只做「取空缓存 + publish」这两件事，
--不要在这里 sys.wait，也不要直接碰 UI 控件。]]
local function can_event_cb(id, cb_type, param)
    if not can then return end

    if cb_type == can.CB_MSG then
        local succ, msg_id, id_type, rtr, data
        for _ = 1, RX_DRAIN_MAX do
            succ, msg_id, id_type, rtr, data = can.rx(id)
            if not succ then break end
            rx_count = rx_count + 1
            sys.publish("CAN_RX", msg_id, id_type, rtr, data)
        end

    elseif cb_type == can.CB_TX then
        -- param 为 true = 发送成功，false = 总线层面失败（无应答 / 错误帧）
        if param ~= true then
            sys.publish("CAN_NOTE", "发送未被确认（总线无应答或出错，检查对端与终端电阻）")
        end

    elseif cb_type == can.CB_ERR then
        sys.publish("CAN_NOTE", string.format("总线错误 0x%08X", tonumber(param) or 0))

    elseif cb_type == can.CB_STATE then
        -- param 不可信：C 层有的实现把状态值放 ptr，有的传 NULL(0)，
        -- 直接把 0 当状态会误显示「停止」。一律以 can.state() 为准。
        log.info("settings_can", "状态回调 param=", tostring(param))
        bus_state = refresh_state()
        sys.publish("CAN_STATE", bus_state, state_text(bus_state))
    end
end

-- ==================== 打开 / 关闭 ====================

--[[切换工作模式（供打开流程与 CAN_MODE_REQ 共用）]]
local function apply_mode(cid, name)
    if not can then return false, "固件未提供 can 库（需带 CAN 功能的固件）" end
    local val, norm, err = mode_value(name)
    if not val then return false, err end
    local ok, ret = pcall(can.mode, cid, val)
    if not ok then return false, "can.mode 调用失败：" .. tostring(ret) end
    if ret == false then return false, "can.mode 返回失败（该模式固件可能不支持）" end
    cur_mode = norm
    return true, nil
end

--[[打开失败时的回滚：注销回调 + 关总线]]
local function rollback(cid)
    if not can then return end
    pcall(can.on, cid, nil)
    pcall(can.deinit, cid)
end

--[[进页面时把 0~2 号总线都探一遍，写进串口日志：
     capacity=true 表示本固件认识这个总线号；
     state=0(STOP) 表示该路没有真正启动（can1/can2 编号对不上时就是这个现象）。
     用于核对 config.can.can_id 到底该填几]]
local function log_probe(cid)
    if not can then return end
    for id = 0, 2 do
        local ok_c, cap, clk = pcall(can.capacity, id)
        local ok_s, st = pcall(can.state, id)
        log.info("settings_can", "probe id=" .. tostring(id),
            "可用=" .. tostring(ok_c and cap),
            "clk=" .. tostring(clk),
            "state=" .. tostring(ok_s and st),
            (id == cid) and "<<当前配置" or "")
    end
end

local function do_open()
    if running then
        sys.publish("CAN_OPEN_RESULT", true, nil, port_info())
        return
    end
    if not can then
        sys.publish("CAN_OPEN_RESULT", false, "固件未提供 can 库（需带 CAN 功能的固件）", port_info())
        return
    end

    local p = get_params()
    local cid = p.can_id or 0

    -- CAN2 复用 UART2：与 RS485 测试页同一个串口。RS485 正常退出会 close，
    -- 但异常退出或别的模块占用时口可能还开着 —— 不 close 就 init，收不到任何帧。
    if p.uart_id and p.uart_id > 0 then pcall(uart.close, p.uart_id) end

    -- 1. 初始化总线（rx_message_cache_max = cache）
    local ok_init, ret_init = pcall(can.init, cid, p.cache or 128)
    if not ok_init or ret_init == false or ret_init == nil then
        log.error("settings_can", "CAN 初始化失败", tostring(ret_init))
        sys.publish("CAN_OPEN_RESULT", false,
            "初始化失败：" .. tostring(ret_init) .. "（CAN 收发器未切到该路或串口被占用）", port_info())
        return
    end

    -- 2. 接管事件（后续 init/timing 过程中的回调也能收到）
    pcall(can.on, cid, can_event_cb)

    -- 3. 时序：实际波特率 = 基础时钟 / 分频 / (1+PTS+PBS1+PBS2)，各平台基础时钟不同
    local ok_tm, ret_tm = pcall(can.timing, cid, p.bitrate or 1000000,
        p.pts or 6, p.pbs1 or 6, p.pbs2 or 4, p.sjw or 2)
    if not ok_tm or ret_tm == false then
        log.error("settings_can", "CAN 时序配置失败", tostring(ret_tm))
        rollback(cid)
        sys.publish("CAN_OPEN_RESULT", false,
            "时序配置失败：" .. tostring(ret_tm) .. "（检查波特率是否可被本平台分频出来）", port_info())
        return
    end

    -- 注意：这里**不调用 can.node / can.filter**，现有固件的过滤有 bug，默认全收即可

    -- 4. 工作模式：失败不致命，保持固件缺省（正常模式）
    local want = tostring(p.mode or "normal"):lower()
    local ok_mode, mode_err = apply_mode(cid, want)
    if not ok_mode then
        log.warn("settings_can", "切换工作模式失败", want, tostring(mode_err))
        cur_mode = "normal"
    end

    running = true
    rx_count, tx_count = 0, 0
    bus_state = refresh_state()
    log.info("settings_can", "CAN 已打开", "CAN" .. tostring(cid),
             "UART" .. tostring(p.uart_id or "-"), tostring(p.bitrate or 1000000),
             "模式=" .. tostring(cur_mode), "state=" .. tostring(bus_state))
    log_probe(cid)
    sys.publish("CAN_OPEN_RESULT", true, nil, port_info())
end

local function do_close()
    local cid = can_id()
    if can then
        pcall(can.on, cid, nil)
        pcall(can.deinit, cid)
    end
    running = false
    bus_state = nil
    -- CAN2 复用 UART2：deinit 之后再 close 一次，把口彻底还给 RS485 页。
    -- 不 close 的话 RS485 页打开时 uart.setup 会被 C 层跳过（日志 uart2 is opened!），
    -- 表现是 485 一个字节都收不到。close 一个本来就没打开的口是 no-op，不必先判断。
    local p = get_params()
    if p.uart_id and p.uart_id > 0 then pcall(uart.close, p.uart_id) end
    log.info("settings_can", "CAN 已关闭", "CAN" .. tostring(cid))
    sys.publish("CAN_OPEN_RESULT", false, "已关闭", port_info())
end

sys.subscribe("CAN_OPEN_REQ", function()
    -- 打开流程里有 uart/can 的同步调用，放进协程里跑，避免阻塞事件派发
    sys.taskInit(do_open)
end)

sys.subscribe("CAN_CLOSE_REQ", function()
    if not can then
        running = false
        return
    end
    do_close()
end)

-- ==================== 发送 ====================

sys.subscribe("CAN_SEND_REQ", function(data)
    sys.taskInit(function()
        if not can then
            sys.publish("CAN_SEND_RESULT", false, "固件未提供 can 库")
            return
        end
        if not running then
            sys.publish("CAN_SEND_RESULT", false, "CAN 未打开")
            return
        end

        local p = get_params()
        local body = (type(data) == "string" and #data > 0) and data or test_data()
        -- 单帧最多 8 字节，超了截断（C 层也会截，这里先截是为了日志里显示的就是实发内容）
        if #body > CAN_MAX_DATA then body = string.sub(body, 1, CAN_MAX_DATA) end

        local ext = (p.ext ~= false) and 1 or 0
        local ack = (p.need_ack ~= false)
        local ok_tx, ret = pcall(can.tx, p.can_id or 0, p.tx_id or DEFAULT_TX_ID, ext, false, ack, body)
        -- can.tx 返回 0 表示已提交发送（真正的结果由 CB_TX 回调给）
        local ok = ok_tx and (ret == 0)
        if ok then tx_count = tx_count + 1 end
        log.info("settings_can", "发送", string.format("0x%08X", p.tx_id or DEFAULT_TX_ID),
                 #body, "字节", tostring(ok), tostring(ret))
        sys.publish("CAN_SEND_RESULT", ok and true or false,
                    ok and nil or ("can.tx 返回 " .. tostring(ret)), body)
    end)
end)

-- ==================== 模式切换 ====================

sys.subscribe("CAN_MODE_REQ", function(mode)
    sys.taskInit(function()
        if not can then
            sys.publish("CAN_MODE_RESULT", false, "固件未提供 can 库", port_info())
            return
        end
        if not running then
            sys.publish("CAN_NOTE", "CAN 未打开，无法切换模式")
            return
        end
        local ok, err = apply_mode(can_id(), mode)
        log.info("settings_can", "切换模式", tostring(mode), tostring(ok), tostring(err))
        if ok then
            bus_state = refresh_state()
            -- 控制器从 STOP 切到工作态不是同步生效的，刚切完读到的还是 0(停止)，
            -- 稍等一下再读一次，避免页面显示「停止」误导
            if bus_state == 0 or (can.STATE_STOP ~= nil and bus_state == can.STATE_STOP) then
                sys.wait(50)
                bus_state = refresh_state()
            end
            sys.publish("CAN_STATE", bus_state, state_text(bus_state))
        end
        sys.publish("CAN_MODE_RESULT", ok and true or false, err, port_info())
    end)
end)
