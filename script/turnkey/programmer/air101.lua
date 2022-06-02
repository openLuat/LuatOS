
local air101 = {}
local xmodem = require "xmodem"
local sys = require "sys"

local boot
local rst

local information = {} --firm model app_version wifi_mac_str unique_id_str 

local function uart_cb(id, len)
    local data = uart.read(id, len)
    if #data>60 then
        local i = 1
        for s in string.gmatch(data, '(%g+)\r\n') do 
            information[i]=s
            i = i+1
        end
        sys.publish("download", information)
    else
        print(data)
    end
end

local function air101_rst()
    rst(0)
    sys.wait(50)
    rst(1)
end

local function air101_boot()
    boot(0)
    sys.wait(50)
    air101_rst()
    sys.wait(50)
    boot(1)
end

function air101.download(pin_boot,pin_rst,uart_id,file_path,app_version)
    print(pin_boot,pin_rst,uart_id,file_path)
    boot= gpio.setup(pin_boot, 0,gpio.PULLUP)
    rst= gpio.setup(pin_rst, 0,gpio.PULLUP)
    boot(1)
    rst(1)
    sys.wait(100)
    air101_rst()
    sys.wait(100)
    uart.setup(uart_id,9600)
    uart.on(uart_id, "receive", uart_cb)
    uart.write(uart_id,"ATI+\r\n")
    local timeid = sys.timerLoopStart(uart.write,100,uart_id,"ATI+\r\n")
    local result, data = sys.waitUntil("download", 120000)
    if result then print(information[3]) end
    sys.timerStop(timeid)
    if information[3]~=app_version then
        air101_boot()
        xmodem.send(uart_id,115200,file_path)
        air101_rst()
        uart.setup(uart_id,9600)
        uart.on(uart_id, "receive", uart_cb)
        local timeid = sys.timerLoopStart(uart.write,100,uart_id,"ATI+\r\n")
        local result, data = sys.waitUntil("download", 120000)
        if result then print(information[3]) end
        sys.timerStop(timeid)
    end
end

return air101
