-- hostabi_proto.lua
-- Protocol definitions for NDK host ABI testing

local M = {}

-- Command opcodes
M.CMD_QUERY_META = 0x01
M.CMD_DELAY_US = 0x02
M.CMD_EVENT_STATE = 0x03
M.CMD_GPIO_CONFIG = 0x10
M.CMD_GPIO_WRITE = 0x11
M.CMD_GPIO_READ = 0x12
M.CMD_GPIO_IRQ_STATE = 0x13
M.CMD_GPIO_IRQ_CLEAR = 0x14

-- UART v1 command opcodes
M.CMD_UART_CONFIG    = 0x20
M.CMD_UART_TX        = 0x21
M.CMD_UART_RX_STATE  = 0x22
M.CMD_UART_RX_READ   = 0x23
M.CMD_UART_RX_CLEAR  = 0x24
M.CMD_CRYPTO_MD5     = 0x30
M.CMD_CRYPTO_CRC32   = 0x31

-- Status codes
M.STATUS_OK = 0
M.STATUS_BAD_PIN = 10
M.STATUS_BAD_MODE = 11
M.STATUS_BAD_PULL = 12
M.STATUS_BAD_IRQ_MODE = 13
M.STATUS_UNSUPPORTED = 14
M.STATUS_HOST_ERROR = 15

-- UART v1 status codes
M.STATUS_UART_BAD_PORT   = 20
M.STATUS_UART_BAD_CONFIG = 21
M.STATUS_UART_BAD_LENGTH = 22
M.STATUS_UART_BUSY       = 23
M.STATUS_UART_OVERFLOW   = 24
M.STATUS_CRYPTO_BAD_ARG  = 30
M.STATUS_CRYPTO_BAD_BOUNDS = 31
M.STATUS_CRYPTO_UNSUPPORTED = 32

-- Protocol constants
M.HOST_MAGIC = 0x4E444B31  -- "NDK1"
M.HOST_VERSION = 0x00010000  -- 1.0.0
M.FEATURE_META = 1 << 0
M.FEATURE_TIME = 1 << 1
M.FEATURE_EVENT = 1 << 2
M.FEATURE_GPIO = 1 << 3
M.FEATURE_UART = 1 << 4
M.FEATURE_CRYPTO = 1 << 5
M.RESULT_OFFSET = 16
M.RESULT_SIZE = 16

-- UART v1 buffer offsets and port constants
M.UART_CFG_OFFSET     = 128
M.UART_PAYLOAD_OFFSET = 256
M.UART_PORT_LOOPBACK  = 0x20
M.CRYPTO_INPUT_OFFSET = 384
M.CRYPTO_OUTPUT_OFFSET = 900

-- Event constants
M.EVENT_HEADER_OFFSET = 32  -- Event header starts at offset 32 (after command + result)
M.EVENT_HEADER_SIZE = 16    -- Event header is 4 uint32_t values
M.EVENT_SLOT_SIZE = 8       -- Each event slot is 8 bytes (uint16_t type, uint16_t source, uint32_t data)
M.EVENT_TYPE_TIMER = 1      -- Timer event type
M.EVENT_TYPE_GPIO_IRQ = 2   -- GPIO IRQ event type
M.EVENT_TYPE_UART_RX_READY = 3  -- UART RX ready event type

-- GPIO constants
M.GPIO_MODE_INPUT = 0
M.GPIO_MODE_OUTPUT = 1
M.GPIO_MODE_IRQ = 2
M.GPIO_PULL_DEFAULT = 0
M.GPIO_PULL_UP = 1
M.GPIO_PULL_DOWN = 2
M.GPIO_IRQ_RISING = 0
M.GPIO_IRQ_FALLING = 1
M.GPIO_IRQ_BOTH = 2
M.GPIO_IRQ_HIGH = 3
M.GPIO_IRQ_LOW = 4
M.GPIO_IRQ_STATE_PIN_MASK = 0x0000FFFF
M.GPIO_IRQ_STATE_PENDING_MASK = 0x00010000
M.GPIO_IRQ_STATE_REASON_MASK = 0xFF000000
M.GPIO_IRQ_STATE_PENDING_SHIFT = 16
M.GPIO_IRQ_STATE_REASON_SHIFT = 24
M.GPIO_CONFIG_TEST_HOST_FAIL = 1 << 16
M.GPIO_WRITE_TEST_HOST_FAIL = 1 << 16

-- Pack command structure (opcode, arg0, arg1, arg2)
function M.pack_cmd(opcode, a0, a1, a2)
    return string.pack("<I4I4I4I4", opcode, a0 or 0, a1 or 0, a2 or 0)
end

function M.pack_gpio_config_cmd(pin, mode, pull, irq_mode, extra_flags)
    local packed = ((extra_flags or 0) & 0xFFFF0000) | (((irq_mode or 0) & 0xFF) << 8) | ((pull or 0) & 0xFF)
    return M.pack_cmd(M.CMD_GPIO_CONFIG, pin, mode, packed)
end

-- Unpack result structure (status, value0, value1, value2)
function M.unpack_result(data)
    if not data or #data < M.RESULT_SIZE then
        return {status = 255, value0 = 0, value1 = 0, value2 = 0}
    end
    local status, v0, v1, v2 = string.unpack("<I4I4I4I4", data)
    return {status = status, value0 = v0, value1 = v1, value2 = v2}
end

-- Unpack event header (host_write, guest_read, slot_count, overflow)
-- Event header is 16 bytes: uint32_t host_write, uint32_t guest_read, uint32_t slot_count, uint32_t overflow
function M.unpack_event_header(data, offset)
    offset = offset or M.EVENT_HEADER_OFFSET
    if not data or #data < offset + M.EVENT_HEADER_SIZE then
        return {host_write = 0, guest_read = 0, slot_count = 0, overflow = 0}
    end
    local host_write, guest_read, slot_count, overflow = string.unpack("<I4I4I4I4", data, offset + 1)
    return {host_write = host_write, guest_read = guest_read, slot_count = slot_count, overflow = overflow}
end

-- Unpack event slot (type, source, data)
-- Each event slot is 8 bytes: uint16_t type, uint16_t source, uint32_t data
function M.unpack_event_slot(data, slot_index, header_offset)
    header_offset = header_offset or M.EVENT_HEADER_OFFSET
    local slot_offset = header_offset + M.EVENT_HEADER_SIZE + (slot_index * M.EVENT_SLOT_SIZE)
    if not data or #data < slot_offset + M.EVENT_SLOT_SIZE then
        return {type = 0, source = 0, data = 0}
    end
    local etype, source, edata = string.unpack("<I2I2I4", data, slot_offset + 1)
    return {type = etype, source = source, data = edata}
end

-- Decode packed GPIO IRQ state/event payload:
-- bits  0..15 = pin, bit 16 = pending, bits 24..31 = irq reason
function M.decode_gpio_irq_state(packed)
    packed = packed or 0
    return {
        raw = packed,
        pin = packed & M.GPIO_IRQ_STATE_PIN_MASK,
        pending = (packed & M.GPIO_IRQ_STATE_PENDING_MASK) >> M.GPIO_IRQ_STATE_PENDING_SHIFT,
        reason = (packed & M.GPIO_IRQ_STATE_REASON_MASK) >> M.GPIO_IRQ_STATE_REASON_SHIFT,
    }
end

-- UART v1 helpers

-- Build a CMD_UART_CONFIG command header plus config payload.
-- Returns: cmd_bytes, cfg_payload
function M.pack_uart_config_cmd(port, baud, data_bits, stop_bits, parity, rx_enable)
    local payload = string.pack("<I4BBBB", baud, data_bits, stop_bits, parity, rx_enable and 1 or 0)
    return M.pack_cmd(M.CMD_UART_CONFIG, port, M.UART_CFG_OFFSET, #payload), payload
end

-- Build a generic UART IO command (TX / RX_READ).
-- offset and length are packed into arg1 as (offset<<16)|length.
function M.pack_uart_io_cmd(opcode, port, offset, length)
    local arg1 = ((offset & 0xFFFF) << 16) | (length & 0xFFFF)
    return M.pack_cmd(opcode, port, arg1, 0)
end

-- Decode CMD_UART_RX_STATE result fields.
function M.decode_uart_rx_state_result(result)
    return {
        pending = result.value0,
        buffered_len = result.value1,
        reason = result.value2,
    }
end

-- Compatibility wrapper; delegates to decode_uart_rx_state_result.
function M.decode_uart_rx_state(result)
    return M.decode_uart_rx_state_result(result)
end

-- Decode an UART_RX_READY event payload.
-- event.source = port, event.data = LUAT_NDK_UART_RX_STATE_PACK(pending, rx_len, reason)
function M.decode_uart_rx_ready_event(event)
    return {
        port         = event.source,
        pending      = event.data & 0x1,
        reason       = (event.data >> 8) & 0xFF,
        buffered_len = (event.data >> 16) & 0xFFFF,
    }
end

function M.pack_crypto_md5_cmd(input_offset, input_len, output_offset)
    return M.pack_cmd(M.CMD_CRYPTO_MD5, input_offset or 0, input_len or 0, output_offset or 0)
end

function M.pack_crypto_crc32_cmd(input_offset, input_len, start)
    return M.pack_cmd(M.CMD_CRYPTO_CRC32, input_offset or 0, input_len or 0, start or 0xFFFFFFFF)
end

function M.hex_to_bin(hex)
    return (hex:gsub("..", function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

return M
