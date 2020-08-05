
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2cdemo"
VERSION = "1.0.0"

-- sys库是标配
local sys = require "sys"

-- 当前仅支持i2c0哦
i2c.setup(0)

-- 读取 OPT3001 光亮度传感器的数据

-- OPT3001 device addr
local OPT3001_DEVICE_ADDR           = 0x44

-- OPT3001 register addr
local OPT3001_REG_RESULT            = 0x00
local OPT3001_REG_CONFIGURATION     = 0x01
local OPT3001_REG_LOW_LIMIT         = 0x02
local OPT3001_REG_HIGH_LIMIT        = 0x03
local OPT3001_REG_MANUFACTURE_ID    = 0x7E
local OPT3001_REG_DEVICE_ID         = 0x7F

--OPT3001 CONFIG resister bit map
local CONFIG_RN_Pos         = (12)
local CONFIG_RN_Msk         = (0xF << CONFIG_RN_Pos) -- Lua 5.3支持各种位运算符, 这在Lua 5.1是没有的

local CONFIG_CT_Pos         = (11)
local CONFIG_CT_Msk         = (0x1 << CONFIG_CT_Pos)

local CONFIG_M_Pos          = (9)
local CONFIG_M_Msk          = (0x3 << CONFIG_M_Pos)

local CONFIG_OVF_Pos        = (8)
local CONFIG_OVF_Msk        = (0x1 << CONFIG_OVF_Pos)

local CONFIG_CRF_Pos        = (7)
local CONFIG_CRF_Msk        = (0x1 << CONFIG_CRF_Pos)

local CONFIG_FH_Pos         = (6)
local CONFIG_FH_Msk         = (0x1 << CONFIG_FH_Pos)

local CONFIG_FL_Pos         = (5)
local CONFIG_FL_Msk         = (0x1 << CONFIG_FL_Pos)

local CONFIG_L_Pos          = (4)
local CONFIG_L_Msk          = (0x1 << CONFIG_L_Pos)

local CONFIG_POL_Pos        = (3)
local CONFIG_POL_Msk        = (0x1 << CONFIG_POL_Pos)

local CONFIG_ME_Pos         = (2)
local CONFIG_ME_Msk         = (0x1 << CONFIG_ME_Pos)

local CONFIG_FC_Pos         = (0)
local CONFIG_FC_Msk         = (0x3 << CONFIG_L_Pos)


-- OPT3001 CONFIG setting macro
local CONFIG_CT_100         = 0x0000                           -- conversion time set to 100ms
local CONFIG_CT_800         = CONFIG_CT_Msk                    -- conversion time set to 800ms

local CONFIG_M_CONTI        = (0x2 << CONFIG_M_Pos)            -- continuous conversions
local CONFIG_M_SINGLE       = (0x1 << CONFIG_M_Pos)            -- single-shot
local CONFIG_M_SHUTDOWN     = 0x0000                           -- shutdown


local CONFIG_RN_RESET       = (0xC << CONFIG_RN_Pos)
local CONFIG_CT_RESET       = CONFIG_CT_800
local CONFIG_L_RESET        = CONFIG_L_Msk
local CONFIG_DEFAULTS       = (CONFIG_RN_RESET | CONFIG_CT_RESET | CONFIG_L_RESET)

local CONFIG_ENABLE_CONTINUOUS     = (CONFIG_M_CONTI | CONFIG_DEFAULTS)
local CONFIG_ENABLE_SINGLE_SHOT    = (CONFIG_M_SINGLE | CONFIG_DEFAULTS)
local CONFIG_DISABLE    =  CONFIG_DEFAULTS

sys.taskInit(function()
    -- 读取device id, 应该是0x3001 = 12289
    local devid = i2c.readReg(0, OPT3001_DEVICE_ADDR, OPT3001_REG_DEVICE_ID)
    log.info("i2c", "opt3001", "device id", devid)
    -- 设置为持续转换
    i2c.writeReg(0, OPT3001_DEVICE_ADDR, OPT3001_REG_CONFIGURATION, CONFIG_ENABLE_CONTINUOUS)
    local regVal = 0
    while 1 do
        while 1 do
            log.info("i2c", "check sensor data ready")
            regVal = i2c.readReg(0, OPT3001_DEVICE_ADDR, OPT3001_REG_CONFIGURATION)
            if (regVal & CONFIG_CRF_Msk) then
                log.info("i2c", "sensor data ready")
                break
            end
            sys.wait(3000)
        end
        regVal = i2c.readReg(0, OPT3001_DEVICE_ADDR, OPT3001_REG_RESULT)
        local fraction = regVal & 0xFFF
        local exponent = 1 << (regVal >> 12)
        log.info("i2c", "read lux=", fraction * exponent, "/100")
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
