--[[
@module joystick
@summary joystick 驱动
@version 1.0
@date    2023.04.10
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例

local joystick = require "joystick"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    joystick.init(i2cid)--初始化,传入i2c_id
    -- while 1 do
        local button_a = joystick.get_button_status(joystick.BUTOON_A)
        local button_b = joystick.get_button_status(joystick.BUTOON_B)
        local button_select = joystick.get_button_status(joystick.BUTOON_D)
        local button_start = joystick.get_button_status(joystick.BUTOON_C)
        local joystick_x = joystick.get_joystick_status(joystick.JOYSTICK_X)
        local joystick_y = joystick.get_joystick_status(joystick.JOYSTICK_Y)
        log.info("joystick", button_a,button_b,button_select,button_start,joystick_x,joystick_y)
        sys.wait(1000)
    -- end
end)
]]
local joystick = {}
local sys = require "sys"
local i2cid

local JOYSTICK_ADDRESS_ADDR     =   0x5A

---器件所用地址
local JOYSTICK_BASE_REG         =   0x10
local JOYSTICK_LEFT_X_REG       =   0x10
local JOYSTICK_LEFT_Y_REG       =   0x11
local JOYSTICK_RIGHT_X_REG      =   0x12
local JOYSTICK_RIGHT_Y_REG      =   0x13

local BUTOON_BASE               =   0x20
local BUTOON_LEFT_REG           =   0x24
local BUTOON_RIGHT_REG          =   0x23
local BUTOON_UP_REG             =   0x22
local BUTOON_DOWN_REG           =   0x21
local JOYSTICK_BUTTON_REG       =   0x20

joystick.PRESS_DOWN             =   0
joystick.PRESS_UP               =   1
joystick.PRESS_REPEAT           =   2
joystick.SINGLE_CLICK           =   3
joystick.DOUBLE_CLICK           =   4 
joystick.LONG_PRESS_START       =   5
joystick.LONG_PRESS_HOLD        =   6
joystick.number_of_event        =   7
joystick.NONE_PRESS             =   8

joystick.BUTOON_D               =   0 
joystick.BUTOON_B               =   1 
joystick.BUTOON_A               =   2 
joystick.BUTOON_C               =   3 
joystick.BUTTON_J               =   4 
joystick.JOYSTICK_X             =   5
joystick.JOYSTICK_Y             =   6

local function joystick_recv(...)
    i2c.send(i2cid, JOYSTICK_ADDRESS_ADDR, {...})
    local _, read_data = pack.unpack(i2c.recv(0, JOYSTICK_ADDRESS_ADDR, 1), "b")
    return read_data
end

function joystick.init(joystick_i2c)
    -- i2c.setup(joystick_i2c, i2c.FAST)
    i2cid = joystick_i2c
end

function joystick.get_button_status(button)
    local status = 0
    if button == joystick.BUTOON_D then
        status = joystick_recv(BUTOON_LEFT_REG)
    elseif button == joystick.BUTOON_B then
        status = joystick_recv(BUTOON_RIGHT_REG)
    elseif button == joystick.BUTOON_A then
        status = joystick_recv(BUTOON_UP_REG)
    elseif button == joystick.BUTOON_C then
        status = joystick_recv(BUTOON_DOWN_REG)
    elseif button == joystick.BUTTON_J then
        status = joystick_recv(JOYSTICK_BUTTON_REG)
    end
    return status
end

function joystick.get_joystick_status(joystick_xy)
    local status = 0
    if joystick_xy == joystick.JOYSTICK_X then
        status = joystick_recv(JOYSTICK_LEFT_X_REG)
    elseif joystick_xy == joystick.JOYSTICK_Y then
        status = joystick_recv(JOYSTICK_LEFT_Y_REG)
    end
    return status
end

return joystick
