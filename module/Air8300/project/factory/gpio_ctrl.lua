--[[
@module  gpio_ctrl
@summary GPIO 控制模块
@version 1.0 / 2026.06.12
]]

local M = {}

-- 可用引脚列表
local PINS = {
    do_pins = {146, 147, 153, 140, 141, 1},
    di_pins = {2, 3, 160, 162},
}

-- 初始化：DO 设为输出下拉，DI 设为输入上拉
for _, p in ipairs(PINS.do_pins) do
    gpio.setup(p, 0, gpio.PULLDOWN)
end
for _, p in ipairs(PINS.di_pins) do
    gpio.setup(p, nil, gpio.PULLUP)
end

function M.set(pin, state)
    gpio.setup(pin, state and 1 or 0, gpio.PULLDOWN)
    log.info("gpio", "GPIO" .. pin, state and "HIGH" or "LOW")
    return true
end

function M.get(pin)
    return gpio.get(pin) == 1
end

function M.list()
    local function read_pins(pins)
        local r = {}
        for _, p in ipairs(pins) do
            r[p] = M.get(p)
        end
        return r
    end
    return {
        do_pins = read_pins(PINS.do_pins),
        di_pins = read_pins(PINS.di_pins),
    }
end

log.info("gpio", "GPIO控制模块就绪, DO:", table.concat(PINS.do_pins, ","), "DI:", table.concat(PINS.di_pins, ","))
return M
