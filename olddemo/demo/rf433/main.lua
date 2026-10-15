
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "my_test"
VERSION = "1.2"
PRODUCT_KEY = "123" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)
local gpio_pin = 2

local function on_data_ready(handle)
    while true do
        local result, err = rf433.read(handle)
        if not result then
            if err then log.error("rf433", "read failed", err) end
            break
        end
        log.info("rf433", string.format("code=0x%06X", result.code), "bits", result.bits,
            "protocol", result.protocol, "time_us", result.timestamp_us)
        -- Latest tested remote codes: 0x80E5FD, 0x80E5FB, 0x80E5F7.
        -- Keep draining until nil so a later reception can notify again.
    end
end

local receiver, err = rf433.open({
    pin = gpio_pin,
    sync_level = rf433.LOW,
    sync_min_us = 6000,
    sync_max_us = 18000,
    glitch_us = 150,
}, on_data_ready)
log.info("rf433", "opened", receiver)
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!