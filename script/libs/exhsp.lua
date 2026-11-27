--[[
@module  exhsp
@summary HSP v1 串口屏屏端协议扩展库
@version 1.0.0
@date    2026.11.27
@usage
通过 exhsp.create 创建屏端实例，每条连接使用自己的实例。
应用负责 UART 收发、发送队列及帧间隔，并用回调接入 AIRUI 或 PLCUI。
支持握手、变量读写、切页、触摸事件和滑块事件，其他命令可由项目注册处理函数。

local exhsp = require("exhsp")
local screen = exhsp.create({
    dictionary = {
        pages = {{index = 1}},
        variables = {{address = 0x0100, type = "I16", initial = 0}},
    },
    send = function(bytes)
        -- 真机接入时将 bytes 交给串口发送队列，保持顺序和至少 10 ms 帧间隔。
        log.info("exhsp", "TX", #bytes)
    end,
})
screen:ready()
-- UART 每次收到的数据传入 screen:feed(bytes)。
]]

local HSP = {}
local Screen = {}
Screen.__index = Screen

local HEADER = "\170\85"
local MAX_PAYLOAD = 1024
local COMMAND = {WRITE = 0x80, READ = 0x81, PAGE = 0x82, HANDSHAKE = 0x8F,
    TOUCH = 0xA0, REPORT = 0xA1, READY = 0xA2, SLIDER = 0xA3, ACK = 0xF0}
local ERR = {CRC = 1, LENGTH = 2, ADDRESS = 3, TYPE = 4, VERSION = 5,
    COMMAND = 6, RANGE = 7, BUSY = 8}
local TYPES = {
    U8 = {1, "I1", 1}, U16 = {2, "I2", 2}, U32 = {3, "I4", 4},
    I8 = {4, "i1", 1}, I16 = {5, "i2", 2}, I32 = {6, "i4", 4},
    F32 = {7, "f", 4}, STR = {16}, ICON = {17, "I2", 2}, COLOR = {18, "I2", 2}
}
local EVENT_FORMAT = {
    [1] = "", [2] = "", [3] = ">I2", [4] = ">I4", [5] = "STR",
    [6] = ">I2", [7] = ">I4", [8] = ">i4"
}

local function crc16(body)
    local crc = 0xFFFF
    for index = 1, #body do
        crc = crc ~ body:byte(index)
        for _ = 1, 8 do
            crc = (crc >> 1) ~ ((crc & 1) ~= 0 and 0xA001 or 0)
        end
    end
    return crc
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function word(value, minimum)
    return math.type(value) == "integer" and value >= minimum and value <= 0xFFFF
end

-- LuatOS builds may omit the standard Lua utf8 library.
local function valid_utf8(value)
    local position = 1
    while position <= #value do
        local lead, next_byte = value:byte(position, position + 1)
        if lead < 0x80 then
            position = position + 1
        else
            local size
            if lead >= 0xC2 and lead <= 0xDF then size = 2
            elseif lead >= 0xE0 and lead <= 0xEF then size = 3
            elseif lead >= 0xF0 and lead <= 0xF4 then size = 4
            else return false end
            if position + size - 1 > #value then return false end
            if (lead == 0xE0 and next_byte < 0xA0) or (lead == 0xED and next_byte >= 0xA0)
                or (lead == 0xF0 and next_byte < 0x90) or (lead == 0xF4 and next_byte >= 0x90) then
                return false
            end
            for index = position + 1, position + size - 1 do
                local byte = value:byte(index)
                if byte < 0x80 or byte > 0xBF then return false end
            end
            position = position + size
        end
    end
    return true
end

local function encode_value(kind, value)
    if kind == TYPES.STR then
        assert(type(value) == "string" and #value <= MAX_PAYLOAD - 5 and valid_utf8(value),
            "invalid UTF-8 string or length")
        return value, value
    end
    assert(finite(value), "invalid numeric value")
    if kind == TYPES.U32 then
        assert(value >= 0 and value <= 4294967295.0 and value % 1 == 0, "U32 exceeds wire range")
        return string.pack(">I2I2", math.floor(value / 65536), value % 65536), value
    end
    local format = ">" .. kind[2]
    local wire = string.pack(format, value)
    local normalized = string.unpack(format, wire)
    assert(finite(normalized), "numeric value exceeds wire range")
    return wire, normalized
end

local function entry(address, kind, value)
    local wire = encode_value(kind, value)
    return string.pack(">I2BI2", address, kind[1], #wire) .. wire
end

local function frame(command, payload)
    assert(#payload <= MAX_PAYLOAD, "HSP payload exceeds 1024 bytes")
    local body = string.char(command) .. payload
    return HEADER .. string.pack(">BI2", 1, #body) .. body .. string.pack("<I2", crc16(body))
end

-- @api exhsp.page_frame(index) 生成主控切页帧，供联调使用。
function HSP.page_frame(index)
    return frame(COMMAND.PAGE, string.pack(">I2", index))
end

function Screen:_emit(command, payload)
    if self.closed then return false end
    return self.send(frame(command, payload)) ~= false
end

-- @api screen:remote_read(address) 返回该地址的上报帧，地址不存在时返回 nil。
function Screen:remote_read(address)
    local item = self.variables[address]
    if item then return frame(COMMAND.REPORT, entry(address, item.kind, item.value)) end
end

function Screen:_ack(command, error_code)
    self:_emit(COMMAND.ACK, string.char(error_code == 0 and 0 or 1, command, error_code))
end

-- Send after the first UI page and UART are ready. Also used for MCU handshake.
-- @api screen:ready() 在界面和 UART 就绪后发送握手应答。
function Screen:ready()
    return self:_emit(COMMAND.READY, "\1" .. self.firmware .. "\0\0")
end

-- @api screen:get(address) 读取缓存中的变量，未声明地址返回 nil。
function Screen:get(address)
    local item = self.variables[address]
    return item and item.value
end

function Screen:_report(addresses)
    local batch, size = {}, 0
    for _, address in ipairs(addresses) do
        local item = self.variables[address]
        local data = entry(address, item.kind, item.value)
        if #batch == 32 or size + #data > MAX_PAYLOAD then
            self:_emit(COMMAND.REPORT, table.concat(batch))
            batch, size = {}, 0
        end
        batch[#batch + 1], size = data, size + #data
    end
    if #batch > 0 then self:_emit(COMMAND.REPORT, table.concat(batch)) end
end

-- Pass {source = "user"} to report a screen interaction. true is accepted for legacy callers.
-- @api screen:set(address, value, user_change) 更新项目变量，可选择触发上报。
function Screen:set(address, value, user_change)
    if self.closed then return false end
    local item = assert(address >= 0x0100 and self.variables[address], "unknown project variable")
    local _, normalized = encode_value(item.kind, value)
    if item.value == normalized then return false end
    item.value = normalized
    local from_user = user_change == true or (type(user_change) == "table" and user_change.source == "user")
    if from_user and item.report then
        self.pending[address] = true
        if not self.report_scheduled then
            self.report_scheduled = true
            self.schedule(50, function()
                if self.closed then return end
                local addresses = {}
                for key in pairs(self.pending) do addresses[#addresses + 1] = key end
                self.pending, self.report_scheduled = {}, false
                table.sort(addresses)
                self:_report(addresses)
            end)
        end
    elseif self.pending[address] then
        self.pending[address] = nil
    end
    return true
end

-- @api screen:touch(control, event, value) 上报当前页的控件事件。
function Screen:touch(control, event, value)
    local format = assert(EVENT_FORMAT[event], "unknown touch event")
    local data
    if format == "STR" then
        data = encode_value(TYPES.STR, value)
    else
        if event == 4 or event == 7 then
            data = encode_value(TYPES.U32, value)
        else
            data = format == "" and "" or string.pack(format, value)
        end
    end
    return self:_emit(COMMAND.TOUCH, string.pack(">I2BI2", self.page, event, control) .. data)
end

-- The UI calls this for each reportable slider step while dragging.
-- Use touch(control, 8, value) for the final value.
-- @api screen:slider(control, value, step) 上报滑块拖动，默认步长 5。
function Screen:slider(control, value, step)
    return self:_emit(COMMAND.SLIDER, string.pack(">I2i4B", control, value, step or 5))
end

function Screen:_switch_page(index)
    if not self.pages[index] then return ERR.RANGE end
    if index == self.page then return 0 end
    if self.on_page and self.on_page(index) == false then return ERR.BUSY end
    self.page = index
    self.variables[0].value = index
    return 0
end

-- Update the active page for UI navigation without emitting a wire command.
-- @api screen:set_page(index) 同步屏内切页结果。
function Screen:set_page(index)
    assert(self.pages[index], "unknown page")
    self.page = index
    self.variables[0].value = index
end

function Screen:_write(payload)
    if #payload == 0 then return ERR.LENGTH end
    local changes, position, page = {}, 1
    while position <= #payload do
        if #changes == 32 then return ERR.RANGE end
        if position + 4 > #payload then return ERR.LENGTH end
        local address, type_id, size, start = string.unpack(">I2BI2", payload, position)
        if start + size - 1 > #payload then return ERR.LENGTH end
        local item = self.variables[address]
        if not item or item.readonly then return ERR.ADDRESS end
        local kind = item.kind
        if kind[1] ~= type_id or (kind[3] and kind[3] ~= size) then return ERR.TYPE end
        local value
        if kind == TYPES.STR then
            value = payload:sub(start, start + size - 1)
            if not valid_utf8(value) then return ERR.TYPE end
        elseif kind == TYPES.U32 then
            local high, low = string.unpack(">I2I2", payload, start)
            value = high * 65536.0 + low
        else
            value = string.unpack(">" .. kind[2], payload, start)
            if not finite(value) then return ERR.RANGE end
        end
        if address == 0 then
            if not self.pages[value] then return ERR.RANGE end
            page = value
        end
        changes[#changes + 1] = {address = address, type = item.type, value = value}
        position = start + size
    end
    if page then
        local error_code = self:_switch_page(page)
        if error_code ~= 0 then return error_code end
    end
    for _, change in ipairs(changes) do
        if change.address ~= 0 then
            self.variables[change.address].value = change.value
            self.pending[change.address] = nil
        end
    end
    if self.on_write then self.on_write(changes) end
    return 0
end

function Screen:_read(payload)
    if #payload == 0 or #payload % 2 ~= 0 then return ERR.LENGTH end
    if #payload > 32 then return ERR.RANGE end
    local result, size = {}, 0
    for position = 1, #payload, 2 do
        local address = string.unpack(">I2", payload, position)
        local item = self.variables[address]
        local data = item and entry(address, item.kind, item.value)
            or string.pack(">I2BI2", address, TYPES.U8[1], 0)
        size = size + #data
        if size > MAX_PAYLOAD then return ERR.RANGE end
        result[#result + 1] = data
    end
    self:_emit(COMMAND.REPORT, table.concat(result))
end

function Screen:_receive(version, command, payload)
    if command >= 0xA0 then return end -- Replies are not addressed to the screen.
    local error_code
    if version ~= 1 then
        error_code = ERR.VERSION
    elseif command == COMMAND.HANDSHAKE then
        if #payload == 0 then self:ready(); return end
        error_code = ERR.LENGTH
    elseif command == COMMAND.WRITE then
        error_code = self:_write(payload)
    elseif command == COMMAND.READ then
        error_code = self:_read(payload)
    elseif command == COMMAND.PAGE then
        if #payload ~= 2 and #payload ~= 4 then
            error_code = ERR.LENGTH
        elseif #payload == 4 and payload:byte(3) ~= 0 then
            error_code = ERR.RANGE
        else
            error_code = self:_switch_page(string.unpack(">I2", payload))
        end
    elseif self.handlers[command] then
        local code, value = self.handlers[command](payload)
        assert(word(code, 0) and code <= ERR.BUSY, "HSP handler must return a protocol error code")
        error_code = code
        if value ~= nil then
            assert(error_code == 0 and word(value, 0), "HSP query value must be a U16 on success")
            self:_emit(COMMAND.ACK, string.pack(">BBBI2", error_code == 0 and 0 or 1,
                command, error_code, value))
            return
        end
    else
        error_code = ERR.COMMAND
    end
    if error_code then self:_ack(command, error_code) end
end

function Screen:_parse()
    while not self.closed do
        local start = self.buffer:find(HEADER, 1, true)
        if not start then
            self.buffer = self.buffer:sub(-1) == HEADER:sub(1, 1) and HEADER:sub(1, 1) or ""
            return
        end
        if start > 1 then self.buffer = self.buffer:sub(start) end
        if #self.buffer < 6 then return end
        local version, length, command = string.unpack(">BI2B", self.buffer, 3)
        if length < 1 or length > MAX_PAYLOAD + 1 then
            self.buffer = self.buffer:sub(2)
            if command < 0xA0 then self:_ack(command, ERR.LENGTH) end
        else
            if #self.buffer < 7 + length then return end
            local body = self.buffer:sub(6, 5 + length)
            local expected = string.unpack("<I2", self.buffer, 6 + length)
            if crc16(body) == expected then
                self.buffer = self.buffer:sub(8 + length)
                self:_receive(version, command, body:sub(2))
            else
                self.buffer = self.buffer:sub(2)
                if self.diagnostic and command < 0xA0 then self:_ack(command, ERR.CRC) end
            end
        end
    end
end

-- Accept any chunks from the serial adapter. Retains incomplete frames only.
-- @api screen:feed(bytes) 接收任意分段的二进制串口数据。
function Screen:feed(bytes)
    if self.closed then return end
    for start = 1, #bytes, 256 do
        if self.closed then return end
        self.buffer = self.buffer .. bytes:sub(start, start + 255)
        self:_parse()
    end
end

-- Discard a partial frame after RX idle or when the transport reconnects.
-- @api screen:reset() 清理尚未解析完的串口数据。
function Screen:reset()
    self.buffer = ""
end

-- send(bytes) must preserve frame order and arrange the 10 ms inter-frame gap.
-- Optional schedule(ms, callback) must run later and is required with report-enabled variables.
-- on_page(index) applies immediate navigation. Return false when busy.
-- on_write(changes) refreshes the UI after the entire validated write commits.
-- handlers[0x83..0x86](payload) returns a protocol error code, with 0 for success,
-- optionally followed by a U16 query value. The handler validates the payload.
-- @api exhsp.create(options)
-- @return HSP screen instance
function HSP.create(options)
    assert(type(options.send) == "function", "HSP send callback is required")
    local firmware = options.firmware or "1.0"
    assert(type(firmware) == "string" and #firmware == 3 and not firmware:find("[^ -~]"),
        "firmware must be exactly three printable ASCII characters")
    local dictionary = options.dictionary or options
    local handlers = {}
    for command, handler in pairs(options.handlers or {}) do
        assert(math.type(command) == "integer" and command >= 0x83 and command <= 0x86
            and type(handler) == "function", "invalid optional HSP handler")
        handlers[command] = handler
    end
    local self = setmetatable({
        send = options.send, schedule = options.schedule, firmware = firmware,
        on_page = options.on_page, on_write = options.on_write, diagnostic = options.diagnostic,
        variables = {}, pages = {}, pending = {}, buffer = "", handlers = handlers
    }, Screen)
    for _, page in ipairs(dictionary.pages or {}) do
        assert(word(page.index, 1) and not self.pages[page.index], "invalid or duplicate page ID")
        self.pages[page.index] = true
        self.page = self.page or page.index
    end
    assert(self.page, "at least one page is required")
    local function register(address, type_name, initial, readonly, report)
        local kind = assert(TYPES[type_name], "unknown HSP variable type")
        local _, value = encode_value(kind, initial)
        self.variables[address] = {type = type_name, kind = kind, value = value,
            readonly = readonly, report = report}
    end
    register(0, "U16", self.page)
    register(0x0010, "STR", options.model or "Air8607", true)
    register(0x0011, "STR", firmware, true)
    register(0x0012, "STR", "1", true)
    local declared = {}
    local system_types = {[0]="U16", [1]="U8", [2]="U8", [3]="U32",
        [0x10]="STR", [0x11]="STR", [0x12]="STR"}
    for _, item in ipairs(dictionary.variables or {}) do
        assert(word(item.address, 0) and not declared[item.address], "invalid or duplicate HSP address")
        declared[item.address] = true
        assert(item.address >= 0x100 or system_types[item.address] == item.type,
            "invalid HSP system address or type")
        assert(not item.report or type(options.schedule) == "function",
            "HSP report-enabled variables require a schedule callback")
        local initial = item.initial
        if initial == nil then initial = item.type == "STR" and "" or 0 end
        if item.address ~= 0 and (item.address < 0x10 or item.address >= 0x100) then
            register(item.address, item.type, initial,
                item.address == 2 or item.address == 3 or item.readonly or item.readOnly, item.report)
        end
    end
    return self
end

-- @api screen:destroy() 停止当前实例接收和发送。
function Screen:destroy()
    self.closed = true
    self.buffer, self.pending = "", {}
end

-- @api exhsp.version() 返回扩展库版本字符串。
function HSP.version()
    return "1.0.0"
end

HSP.new = HSP.create

return HSP
