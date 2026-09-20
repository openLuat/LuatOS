--[[
@module  modbus_map
@summary 汇川变频器寄存器采集字段表（设备间协议单一数据源）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 inter-device-communication-protocol.md 第 5 节定义：
- 15 项保持寄存器采集字段（03 功能码），每项含：字段键、寄存器地址、换算系数、AirCloud 字段编号；
- 变频器控制寄存器（06 功能码写单寄存器）：0x2000，写 1=开机、6=关机。
本模块为纯数据模块，有对外接口，末尾 return M。
]]

local M = {}

-- 采集字段表（顺序即采集顺序）
-- key   : 运行数据表中的字段键
-- reg   : 保持寄存器地址
-- scale : 原始值换算系数（原始值 × scale = 实际值）
-- field : AirCloud 上报 TLV 字段编号（见 config_app.FIELD）
M.fields = {
    { key = "outHz",    reg = 0x7000, scale = 0.01, field = 1536 },
    { key = "setHz",    reg = 0x7001, scale = 0.01, field = 1537 },
    { key = "muV",      reg = 0x7002, scale = 0.1,  field = 1538 },
    { key = "outV",     reg = 0x7003, scale = 1,    field = 1539 },
    { key = "outA",     reg = 0x7004, scale = 0.1,  field = 1540 },
    { key = "outkw",    reg = 0x7005, scale = 0.1,  field = 1541 },
    { key = "nbTemp",   reg = 0xF707, scale = 1,    field = nil }, -- 映射到标准字段 TEMPERATURE
    { key = "H",        reg = 0xF709, scale = 1,    field = 1542 },
    { key = "devstate", reg = 0x3000, scale = 1,    field = nil }, -- 映射到标准字段 WORK_STATUS
    { key = "oneHz",    reg = 0xF925, scale = 0.01, field = 1543 },
    { key = "oneA",     reg = 0xF926, scale = 0.1,  field = 1544 },
    { key = "twoHz",    reg = 0xF91B, scale = 0.01, field = 1545 },
    { key = "twoA",     reg = 0xF91C, scale = 0.1,  field = 1546 },
    { key = "threeHz",  reg = 0xF911, scale = 0.01, field = 1547 },
    { key = "threeA",   reg = 0xF912, scale = 0.1,  field = 1548 },
}

-- 控制寄存器（06 写单寄存器）
M.ctrl_reg = 0x2000
M.ctrl_on  = 1 -- 开机
M.ctrl_off = 6 -- 关机

-- 设备运行状态取值映射（0x3000 devstate）
M.DEVSTATE_TEXT = {
    [1] = "正转运行",
    [2] = "反转运行",
    [3] = "停止",
    [4] = "调谐",
    [5] = "故障",
}

return M
