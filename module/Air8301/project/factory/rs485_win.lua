--[[
@module  rs485_win
@summary RS485-1 从站请求监视页（8301出厂固件·业务模式）
@version 5.0
@date    2026.10.13
@author  江访

@usage
业务模式下 RS485-1（UART1，隔离口）是 **Modbus RTU 从站**（rtu_slave_regmap.lua），
本页只读监视：订阅 MODBUS_RTU_REQ，把主站（PC 串口板）的请求**解析成中文可读数据**后
按时间倒序显示，不再显示原始 HEX 帧，也不显示从站地址/波特率等参数信息。

=== v5.0（2026.10.13）解析化 + 精简版式 ===
  1) 移除页内的标题行与"从站地址 1 | 9600 8N1 | ..."参数行，整屏只显示数据；
     （窗口身份由导航栏右侧的 "RS485-1" 表达，无需页内重复）
  2) 把 rtu_slave_regmap 发布的原始帧解析可读文本：
     读操作   请求:01 03 00 00 00 05  应答:01 03 0A 0003 0001 0001 0000 0000
              → "读 5 个 @0x0000" + "掩码=3 通道0=1 通道1=1 通道2=0 通道3=0"
     写控制字 写控制字:0x0101        → "断开通道0"
     写通道   写通道开关:0x0001=0x0001 → "接通通道0"
     多寄存器 多寄存器写入，起始:0x0001 数量:4 → "写 4 个 @0x0001"
  3) 连续地址按寄存器语义分组解析：FLOAT（CPU温度 / VBAT / 温湿度）、
     INT32（时间戳）、STRING（纬度 / 经度 / IMEI / ICCID，每寄存器 2 字节大端）。

=== v4.0 沿革（2026.10.13）由"终端页"改为"从站请求监视页" ===
旧版发送走 sys.publish("RS485_SEND_REQUEST", ...)，该消息在业务模式下没有任何订阅者
（唯一接收方 prod_rs485_app 仅产测模式加载），点击"发送"被静默丢弃；接收侧订阅的
RS485_DATA_RECEIVED 同样没有任何发布方，接收区永远"暂无数据"。
且不可退回 uart.write 直发：UART1 已被 exmodbus 的 RTU 从站占用
（uart.setup + uart.on("receive")），再注册接收回调会覆盖从站的回调；
半双工 485 的方向脚由 uart 内置 RS485 模式控制，两边抢总线会打乱帧。

@note 消息接口：
  订阅 MODBUS_RTU_REQ(text)    由 rtu_slave_regmap.lua 发布
  订阅 OPEN_RS485_WIN          由 comm_win.lua 磁贴点击发布（本页入口，未变更）
@note 字库约束：hzfont 不含 "·" "…" 等字形，行内分隔一律用 "|"（见 ui_theme.lua）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container
local history = {}                 -- 已解析条目缓存（最新置顶）
local history_label

local HISTORY_MAX  = 6             -- 缓存条数
local HISTORY_SHOW = 3             -- 显示条数
local ENTRY_MAX_LINES = 2          -- 每条最多 2 行数据行（另加 1 行标题行）
local LINE_UNITS   = 50            -- 单行宽度上限（半角单位；464px 内容区约 55）

-- 内容区 464×210
local BLOCK_H = 210

local ui_alive = false

-- ==================== 寄存器语义（与 rtu_slave_regmap.lua 的 REG_ADDR 保持一致） ====================

-- FLOAT 组（占 2 个寄存器，低 16 位在前）
local FLOAT_GROUPS = {
    [0x0005] = { name = "CPU温度", unit = "℃" },
    [0x0007] = { name = "VBAT",   unit = "V"  },
    [0x003A] = { name = "温度",   unit = "℃" },
    [0x003C] = { name = "湿度",   unit = "%RH" },
}

-- STRING 组（每寄存器 2 字节，大端）
local STR_GROUPS = {
    [0x0009] = { name = "纬度",  regs = 10 },
    [0x0013] = { name = "经度",  regs = 10 },
    [0x001E] = { name = "IMEI",  regs = 12 },
    [0x002A] = { name = "ICCID", regs = 14 },
}

-- INT32（时间戳，低 16 位在前）
local TS_ADDR = 0x0038

-- ==================== 基础工具 ====================

--[[
取当前时间字符串（RTC 未同步时降级为空串）

@local
@function now_str
@return string "HH:MM:SS " 或 ""
]]
local function now_str()
    local ok, t = pcall(os.date, "%H:%M:%S")
    if ok and type(t) == "string" then return t .. " " end
    return ""
end

--[[
估算字符串显示宽度（半角单位）：ASCII=1，汉字/全角=2

@local
@function text_units
@param s string 文本
@return number 半角单位数
]]
local function text_units(s)
    local u, i, n = 0, 1, #s
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then
            u = u + 1
            i = i + 1
        elseif b < 0xE0 then
            u = u + 2
            i = i + 2
        elseif b < 0xF0 then
            u = u + 2
            i = i + 3
        else
            u = u + 2
            i = i + 4
        end
    end
    return u
end

--[[
HEX 字符串转字节数组（忽略空格等分隔符）

@local
@function hex_to_bytes
@param s string 形如 "01 03 00 00 00 05"
@return table 字节数组（1-based）
]]
local function hex_to_bytes(s)
    local t = {}
    if type(s) ~= "string" then return t end
    for h in s:gmatch("%x%x") do
        t[#t + 1] = tonumber(h, 16)
    end
    return t
end

--[[
两个 16 位寄存器还原为 FLOAT

与 rtu_slave_regmap.lua:144 的 float_to_bits 严格对称：
  编码：bits(u32) = string.unpack("I4", string.pack("f", f))，低 16 位写低地址寄存器
  解码：f = string.unpack("f", string.pack("I4", lo16 | (hi16 << 16)))
（两端都用本地字节序，不写 "<" 格式符，避免依赖格式串解析差异）

@local
@function regs_to_float
@param lo16 number 低 16 位（低地址寄存器）
@param hi16 number 高 16 位
@return number 浮点值
]]
local function regs_to_float(lo16, hi16)
    local u32 = (lo16 or 0) | ((hi16 or 0) << 16)
    local ok, f = pcall(function()
        return string.unpack("f", string.pack("I4", u32))
    end)
    if ok and type(f) == "number" then return f end
    return 0
end

--[[
寄存器数组还原为 ASCII 字符串（每寄存器 2 字节，大端；遇 0 截断）

@local
@function regs_to_string
@param regs table 寄存器值数组
@return string 字符串
]]
local function regs_to_string(regs)
    local t = {}
    for _, v in ipairs(regs) do
        local b1, b2 = (v >> 8) & 0xFF, v & 0xFF
        if b1 == 0 then break end
        t[#t + 1] = string.char(b1)
        if b2 == 0 then break end
        t[#t + 1] = string.char(b2)
    end
    return table.concat(t)
end

--[[
单寄存器短名

@local
@function single_name
@param addr number 寄存器地址
@return string 短名
]]
local function single_name(addr)
    if addr == 0x0000 then return "掩码" end
    if addr >= 0x0001 and addr <= 0x0004 then return "通道" .. (addr - 0x0001) end
    if addr == 0x001D then return "信号" end
    if addr == 0x0050 then return "控制字" end
    return string.format("0x%04X", addr)
end

--[[
把若干短句按显示宽度折行

@local
@function wrap_items
@param items table 短句数组
@return table 行数组
]]
local function wrap_items(items)
    local lines, cur = {}, ""
    for _, it in ipairs(items) do
        local sep = (#cur > 0) and " " or ""
        if #cur > 0 and text_units(cur .. sep .. it) > LINE_UNITS then
            lines[#lines + 1] = cur
            cur = it
        else
            cur = cur .. sep .. it
        end
    end
    if #cur > 0 then lines[#lines + 1] = cur end
    return lines
end

-- ==================== 帧解析 ====================

--[[
解析读保持/输入寄存器（0x03 / 0x04）的请求与应答帧

@local
@function parse_read
@param req_hex string 请求帧 HEX（slave func addrH addrL cntH cntL）
@param resp_hex string 应答帧 HEX（slave func bytes data...）
@return table|nil 短句数组（失败返回 nil）
]]
local function parse_read(req_hex, resp_hex)
    local rb = hex_to_bytes(req_hex)
    if #rb < 6 then return nil end
    local start_addr = rb[3] * 256 + rb[4]
    local reg_count  = rb[5] * 256 + rb[6]

    -- 应答：跳过 slave / func / 字节数，其余按 2 字节大端还原成寄存器值
    local vb = hex_to_bytes(resp_hex)
    local regvals = {}
    for i = 4, #vb - 1, 2 do
        regvals[#regvals + 1] = vb[i] * 256 + vb[i + 1]
    end

    local items = {}
    local idx = 1
    local guard = 0
    while idx <= reg_count and guard < 128 do
        guard = guard + 1
        local addr = start_addr + idx - 1
        local fg = FLOAT_GROUPS[addr]
        local sg = STR_GROUPS[addr]
        if fg and idx + 1 <= reg_count then
            items[#items + 1] = string.format("%s=%.1f%s", fg.name,
                regs_to_float(regvals[idx], regvals[idx + 1]), fg.unit)
            idx = idx + 2
        elseif addr == TS_ADDR and idx + 1 <= reg_count then
            local ts = (regvals[idx] or 0) + (regvals[idx + 1] or 0) * 65536
            local ok, t = pcall(os.date, "%m-%d %H:%M", ts)
            items[#items + 1] = "时间=" .. ((ok and t and ts > 0) and t or "未同步")
            idx = idx + 2
        elseif sg and (idx + sg.regs - 1) <= reg_count then
            local parts = {}
            for k = 0, sg.regs - 1 do parts[#parts + 1] = regvals[idx + k] or 0 end
            local str = regs_to_string(parts)
            if #str > 0 then
                items[#items + 1] = sg.name .. "=" .. str
            end
            idx = idx + sg.regs
        else
            items[#items + 1] = string.format("%s=%d", single_name(addr), regvals[idx] or 0)
            idx = idx + 1
        end
    end

    return items, start_addr, reg_count
end

--[[
继电器控制字（0x0050）转中文

@local
@function ctrl_text
@param ctrl number 控制字
@return string 中文描述
]]
local function ctrl_text(ctrl)
    if ctrl == 0x0000 then return "全部断开" end
    if ctrl == 0xFFFF then return "全部接通" end
    local op = (ctrl >> 8) & 0xFF
    local ch = (ctrl & 0xFF) - 1
    if ch < 0 or ch > 3 then return string.format("控制字=0x%04X", ctrl) end
    if op == 0x00 then return "接通通道" .. ch end
    if op == 0x01 then return "断开通道" .. ch end
    if op == 0x02 then return "翻转通道" .. ch end
    return string.format("控制字=0x%04X", ctrl)
end

--[[
把 MODBUS_RTU_REQ 文本解析成可读条目

支持 rtu_slave_regmap.lua 的全部 5 种发布形态：
  1) [RTU] 请求:<hex>  应答:<hex>         → 读操作，逐寄存器解析
  2) [RTU] 写控制字:0xXXXX               → 接通/断开/翻转通道N
  3) [RTU] 写通道开关:0xXXXX=0xXXXX      → 接通/断开通道N
  4) [RTU] 多寄存器写入，起始:0xXXXX 数量:N
  5) [RTU] 不支持的功能码:0xXX

@local
@function format_entry
@param text string 原始消息
@return string|nil 可显示条目（含换行；非字符串返回 nil）
]]
local function format_entry(text)
    if type(text) ~= "string" or #text == 0 then return nil end
    local body = text:gsub("^%[RTU%]%s*", "")
    local head, items

    local req_hex, resp_hex = body:match("^请求:(.-)%s+应答:(.*)$")
    if req_hex then
        local parsed, start_addr, reg_count = parse_read(req_hex, resp_hex)
        if parsed then
            head = string.format("读 %d 个 @0x%04X", reg_count or 0, start_addr or 0)
            items = parsed
        else
            head = "读寄存器"
        end
    else
        local ctrl_hex = body:match("^写控制字:0x(%x+)$")
        local ch_addr, ch_val = body:match("^写通道开关:0x(%x+)=0x(%x+)$")
        local m_addr, m_cnt = body:match("^多寄存器写入，起始:0x(%x+) 数量:(%d+)$")
        local bad_fc = body:match("^不支持的功能码:0x(%x+)$")
        if ctrl_hex then
            head = ctrl_text(tonumber(ctrl_hex, 16) or 0)
        elseif ch_addr and ch_val then
            local ch = (tonumber(ch_addr, 16) or 1) - 1
            head = ((tonumber(ch_val, 16) or 0) ~= 0) and ("接通通道" .. ch) or ("断开通道" .. ch)
        elseif m_addr and m_cnt then
            head = string.format("写 %s 个 @0x%04X", m_cnt, tonumber(m_addr, 16) or 0)
        elseif bad_fc then
            head = string.format("不支持的功能码 0x%02X", tonumber(bad_fc, 16) or 0)
        else
            head = body
        end
    end

    local lines = { now_str() .. head }
    if items then
        local wrapped = wrap_items(items)
        local shown = 0
        for _, l in ipairs(wrapped) do
            if shown >= ENTRY_MAX_LINES then
                -- 超出行数上限：末行尾部标注省略（"..." 为 ASCII，字库安全）
                lines[#lines] = lines[#lines] .. " ..."
                break
            end
            lines[#lines + 1] = "  " .. l
            shown = shown + 1
        end
    end
    return table.concat(lines, "\n")
end

-- ==================== 历史与显示 ====================

--[[
把历史缓存拼成显示文本（只取最新 HISTORY_SHOW 条）

@local
@function build_history_text
@return string 显示文本
]]
local function build_history_text()
    local n = #history
    if n == 0 then return "等待主站请求" end
    local lines = {}
    local show = n < HISTORY_SHOW and n or HISTORY_SHOW
    for i = 1, show do
        lines[i] = history[i]
    end
    return table.concat(lines, "\n")
end

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not ui_alive then return end
    exwin.close(win_id)
end

--[[
从站请求/应答消息（rtu_slave_regmap 发布）

解析后入历史缓存（即使窗口未激活也缓存），窗口存在时立即刷新。

@local
@function on_rtu_req
@param text string "[RTU] ..."
]]
local function on_rtu_req(text)
    local entry = format_entry(text)
    if not entry then return end
    table.insert(history, 1, entry)          -- 最新置顶
    if #history > HISTORY_MAX then
        table.remove(history)
    end
    if history_label then
        history_label:set_text(build_history_text())
    end
end

--[[
创建 UI 界面（整屏只显示数据：无标题行、无参数行）

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "RS485-1", on_back = on_back_click })
    main_container = ctx.base

    local card = theme.card(ctx.base, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = BLOCK_H,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
    })

    -- 数据区：占满整块卡片
    history_label = theme.label(card, {
        x = 12, y = 10, w = ctx.w - 24, h = BLOCK_H - 20,
        text = build_history_text(), px_size = 16, color = theme.C.t1,
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    log.info("rs485_win", "[UI-MARK] RS485-1 从站监视页 v5.0 已加载（只显示解析后的数据）")
    ui_alive = true
    create_ui()
    sys.subscribe("MODBUS_RTU_REQ", on_rtu_req)
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    ui_alive = false
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    history_label = nil
    sys.unsubscribe("MODBUS_RTU_REQ", on_rtu_req)
    win_id = nil
end

--[[
窗口获得焦点回调：刷新数据区

@local
@function on_get_focus
]]
local function on_get_focus()
    if history_label then
        history_label:set_text(build_history_text())
    end
end

--[[
OPEN_RS485_WIN 消息处理器

单实例保护：避免同页多实例并存时互相覆盖 win_id

@local
@function open_handler
]]
local function open_handler()
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RS485_WIN", open_handler)
