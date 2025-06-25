
local air101 = {}
local xmodem = require "xmodem"
local sys = require "sys"

local boot
local rst
local led

local led_state = 1
air101.download_state = false

local information = {} --firm model app_version wifi_mac_str unique_id_str 

local function led_loop()
    led(led_state%2)
    led_state = led_state+1
end

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

function air101.download(pin_boot,pin_rst,uart_id,file_path,app_version,led_func)
    if led_func then
        led = led_func
    end
    boot= gpio.setup(pin_boot, 0,gpio.PULLUP)
    rst= gpio.setup(pin_rst, 0,gpio.PULLUP)
    boot(1)
    rst(1)


    sys.wait(100)
    air101_rst()
    sys.wait(100)

    uart.setup(uart_id,9600)
    uart.on(uart_id, "receive", uart_cb)
    local timeid = sys.timerLoopStart(uart.write,100,uart_id,"ATI+\r\n")
    local result, data = sys.waitUntil("download", 500)
    sys.timerStop(timeid)
    if result then print(information[3]) end

    if result and information[3]~=app_version then
        air101_boot()
        local ledid
        air101.download_state = true
        if led then ledid = sys.timerLoopStart(led_loop,200) end
        local ret = xmodem.send(uart_id,115200,file_path)
        if led then sys.timerStop(ledid) end
        air101.download_state = false
        if ret then
            air101_rst()

            uart.setup(uart_id,9600)
            uart.on(uart_id, "receive", uart_cb)
            local timeid = sys.timerLoopStart(uart.write,100,uart_id,"ATI+\r\n")
            local result, data = sys.waitUntil("download", 500)
            sys.timerStop(timeid)
            if result then print(information[3]) end
            if result and information[3]==app_version then
                if led then led(0) end
                return true
            else
                if led then led(1) end
                return false
            end
        else
            if led then led(1) end
            return false
        end
    elseif result and information[3]==app_version then
        if led then led(0) end
        return true
    else
        if led then led(1) end
        return false
    end
end

function air101.download_force(pin_boot,pin_rst,uart_id,file_path,app_version,led_func)

    air101_boot()
    local ledid
    air101.download_state = true
    if led then ledid = sys.timerLoopStart(led_loop,200) end
    local ret = xmodem.send(uart_id,115200,file_path)
    if led then sys.timerStop(ledid) end
    air101.download_state = false
    if ret then
        air101_rst()

        uart.setup(uart_id,9600)
        uart.on(uart_id, "receive", uart_cb)
        local timeid = sys.timerLoopStart(uart.write,100,uart_id,"ATI+\r\n")
        local result, data = sys.waitUntil("download", 1000)
        sys.timerStop(timeid)
        if result then print(information[3]) end
        if result and information[3]==app_version then
            if led then led(0) end
            return true
        else
            if led then led(1) end
            return false
        end
    else
        if led then led(1) end
        return false
    end
end

return air101
