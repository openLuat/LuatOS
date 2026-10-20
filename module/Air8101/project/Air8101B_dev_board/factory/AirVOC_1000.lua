--[[
@module  AirVOC_1000
@summary AirVOC_1000 空气质量（TVOC）传感器配件板驱动（官方驱动，改造接入本工程 I2C 总线）
@version 1.0
@date    2026.10.16
@usage
    AirVOC_1000.open()      -- 用工程总线（与 GT911 触摸共用排针）★本工程默认
    AirVOC_1000.open(0)     -- 硬件 I2C0（官方 demo 的接法：SDA=38/R5、SCL=45/R6）
    AirVOC_1000.read()      -- 成功返回 ppb, ppm, 等级, 等级描述；失败返回 false
    AirVOC_1000.probe()     -- 器件是否在线（读一次数据并校验 CRC）
    AirVOC_1000.last_error()-- 最近一次读失败的原因：nil/"no-ack"/"no-data"/"crc"（排查用）
    AirVOC_1000.close()

来源：LuatOS 官方 demo
    module/Air8101/demo/accessory_board/AirVOC_1000/AirVOC_1000.lua
    （@author 沈园园  @date 2025.10.21）

器件：AGS02MA，I2C 从机地址 0x1A；TVOC 数据在寄存器 0x00，读 5 字节
      （3 字节大端 ppb + 1 字节保留 + 1 字节 CRC8）

本工程改动（与 AirSHT30_1000.lua 同一套做法）
1. open() 不传参数时复用工程 I2C 总线（drv_i2c 软 I2C，GPIO38/39 排针，与 GT911 触摸同一条）；
   open(0/1) 与原版一致走硬件 I2C；
2. close() 只在用硬件 I2C 时才 i2c.close（共用总线关掉会连触摸一起弄没）；
3. 新增 read() / probe()，业务层不用自己拼三条取值接口。

AGS02MA 特性（接线和调参要看这几条）
- 数据约 1.5 秒更新一次，读取间隔不要小于 1.5 秒；
- 数据手册规定 I2C 时钟 ≤ 30kHz。本工程软 I2C 默认约 100kHz，
  若日志反复出现 crc error，把 config 的 hw.tp.i2c_delay 调到 20（≈25kHz）；
- 上电需要预热，前一两分钟读数会漂移，属正常现象。
]]

local AirVOC_1000 = {}

-- AGS02MA 从机地址固定 0x1A
local slave_addr = 0x1A

-- TVOC 数据寄存器 0x00，长度 5 字节
local DATA_REG_ADDR = 0x00
local DATA_REG_LEN  = 0x05

-- 当前使用的总线：I2C 编号（number）/ 软件 I2C 对象（userdata）
local bus = nil

local last_err = nil

function AirVOC_1000.last_error()
    return last_err
end

-- CRC8（AGS02MA 数据手册，初值 0xFF，多项式 0x31）
local function crc8(data)
    local crc = 0xFF
    for i = 1, #data do
        crc = bit.bxor(crc, data[i])
        for _ = 1, 8 do
            crc = crc * 2
            if crc >= 0x100 then
                crc = bit.band(bit.bxor(crc, 0x31), 0xff)
            end
        end
    end
    return crc
end

-- 读寄存器：先写寄存器地址，再读 len 字节
local function read_register(reg, len)
    if not bus then
        log.error("AirVOC_1000.read_register", "请先调用 open()")
        last_err = "no-bus"
        return false
    end

    if not i2c.send(bus, slave_addr, reg) then
        last_err = "no-ack"
        log.warn("AirVOC_1000.read_register", "写寄存器地址无应答（器件不在线，或总线速率超规格）")
        return false
    end

    local data = i2c.recv(bus, slave_addr, len)
    if type(data) == "string" and data:len() == len then
        last_err = nil
        return data
    end

    last_err = "no-data"
    log.warn("AirVOC_1000.read_register", "地址有应答但数据读不回:", type(data))
    return false
end

function AirVOC_1000.open(i2c_id)
    -- ===== 本工程默认：复用工程 I2C 总线（与 GT911 触摸同一排针），软件 I2C =====
    if i2c_id == nil then
        bus = require("drv_i2c").get()
        AirVOC_1000.i2c_id = nil
        log.info("AirVOC_1000", "使用工程 I2C 总线（软件 I2C）")
        return true
    end

    -- ===== 以下为官方原版逻辑（硬件 I2C）=====
    if not (i2c_id == 0 or i2c_id == 1) then
        log.error("AirVOC_1000.open", "invalid i2c_id", i2c_id)
        return false
    end

    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("AirVOC_1000.open", "i2c.setup error", i2c_id)
        return false
    end

    bus = i2c_id
    AirVOC_1000.i2c_id = i2c_id
    log.info("AirVOC_1000", "使用硬件 I2C" .. i2c_id)
    return true
end

function AirVOC_1000.get_ppb()
    local raw = read_register(DATA_REG_ADDR, DATA_REG_LEN)
    if not raw then return false end

    -- 前 4 字节参与 CRC，第 5 字节是校验值
    if crc8({ raw:byte(1), raw:byte(2), raw:byte(3), raw:byte(4) }) ~= raw:byte(5) then
        last_err = "crc"
        log.warn("AirVOC_1000.get_ppb", "crc error，原始数据:", raw:toHex())
        return false
    end

    -- 大端 3 字节
    return (raw:byte(2) << 16) | (raw:byte(3) << 8) | raw:byte(4)
end

function AirVOC_1000.get_ppm()
    local ppb = AirVOC_1000.get_ppb()
    if not ppb then return false end
    return ppb / 1000
end

function AirVOC_1000.get_quality_level()
    local ppb = AirVOC_1000.get_ppb()
    if not ppb then return false end

    if ppb < 200 then
        return 1, "优"
    elseif ppb < 1000 then
        return 2, "良好"
    elseif ppb < 3000 then
        return 3, "轻度污染"
    elseif ppb < 5000 then
        return 4, "中度污染"
    else
        return 5, "重度污染"
    end
end

function AirVOC_1000.read()
    local raw = read_register(DATA_REG_ADDR, DATA_REG_LEN)
    if not raw then return false end

    if crc8({ raw:byte(1), raw:byte(2), raw:byte(3), raw:byte(4) }) ~= raw:byte(5) then
        last_err = "crc"
        log.warn("AirVOC_1000.read", "crc error，原始数据:", raw:toHex())
        return false
    end

    local ppb = (raw:byte(2) << 16) | (raw:byte(3) << 8) | raw:byte(4)
    local ppm = ppb / 1000

    local level, desc
    if ppb < 200 then
        level, desc = 1, "优"
    elseif ppb < 1000 then
        level, desc = 2, "良好"
    elseif ppb < 3000 then
        level, desc = 3, "轻度污染"
    elseif ppb < 5000 then
        level, desc = 4, "中度污染"
    else
        level, desc = 5, "重度污染"
    end

    return ppb, ppm, level, desc
end

function AirVOC_1000.probe()
    if not bus then
        bus = require("drv_i2c").get()
    end
    local raw = read_register(DATA_REG_ADDR, DATA_REG_LEN)
    if not raw then return false end
    return crc8({ raw:byte(1), raw:byte(2), raw:byte(3), raw:byte(4) }) == raw:byte(5)
end

function AirVOC_1000.close()
    if AirVOC_1000.i2c_id then
        i2c.close(AirVOC_1000.i2c_id)
        AirVOC_1000.i2c_id = nil
    end
    bus = nil
    return true
end

return AirVOC_1000
