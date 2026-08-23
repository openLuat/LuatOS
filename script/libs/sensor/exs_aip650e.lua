--[[
@module  exs_aip650e
@summary AiP650E 数码管驱动扩展库（8段×4位 + 28键扫描 + 4个组合按键）
@version 1.0
@date    2026.07.13
@author  江访
@usage
本文件为 AiP650E 驱动芯片的 LuatOS 扩展库，核心功能为：
1、初始化 AiP650E，配置 CLK/DIO 两线通信引脚
2、4 位 8 段数码管显示（支持共阴/共阳切换、7段/8段模式切换）
3、28 个按键+4 个组合按键扫描检测（轮询和回调两种方式）
4、8 级亮度调节
5、睡眠模式控制

本文件的对外接口有 12 个：
1、exs_aip650e.setup(config)：初始化
2、exs_aip650e.set_brightness(level)：设置亮度
3、exs_aip650e.set_display(str, offset)：数码管显示字符串
4、exs_aip650e.set_mode(mode)：设置 7段/8段模式
5、exs_aip650e.display_on()：开启显示
6、exs_aip650e.display_off()：关闭显示
7、exs_aip650e.sleep()：进入睡眠模式
8、exs_aip650e.wakeup()：唤醒
9、exs_aip650e.clear()：清空显示
10、exs_aip650e.get_key()：轮询读取按键
11、exs_aip650e.set_key_callback(cbfunc)：设置按键回调
12、exs_aip650e.version()：获取版本号

-- 版本更新说明
-- 版本号：202607131200
-- 1、更新时间：2026-07-13 12:00
-- 2、更新内容
  - 首次发布，实现 AiP650E 基础驱动功能
  - 支持数码管显示（8 段 ×4 位）
  - 支持按键扫描（轮询 + 回调两种方式）
  - 支持 8 级亮度调节
  - 支持共阴/共阳数码管切换
  - 支持 7 段/8 段显示模式切换
  - 支持睡眠模式和唤醒
]]--

local exs_aip650e = {}

-- ==================== 模块常量 ====================

-- AiP650E 系统指令
local CMD_SYSTEM      = 0x48  -- 系统指令（固定值）

-- AiP650E 显示寄存器地址（DIG1~DIG4）
local DISP_ADDR_DIG1  = 0x68  -- DIG1 显示地址
local DISP_ADDR_DIG2  = 0x6A  -- DIG2 显示地址
local DISP_ADDR_DIG3  = 0x6C  -- DIG3 显示地址
local DISP_ADDR_DIG4  = 0x6E  -- DIG4 显示地址

-- 读按键指令
local CMD_READ_KEY    = 0x49  -- 读按键数据指令

-- 最大支持参数
local MAX_DIGITS = 4   -- 最大数码管位数
local MAX_KEYS   = 28  -- 最大单一按键数（不含组合键）
local MAX_COMBO_KEYS = 4  -- 最大组合按键数（KI1+KI2，每个DIG一组）

-- ==================== 内部状态 ====================

-- GPIO 引脚编号
local g_clk_pin = nil  -- CLK 时钟引脚
local g_dio_pin = nil  -- DIO 数据引脚

-- 配置参数
local g_common_anode = false    -- 是否共阳数码管
local g_current_bright = 3      -- 当前亮度 0~7
local g_display_on = true       -- 当前显示状态
local g_segment_7seg = false    -- 是否 7 段模式（true=7段，false=8段）
local g_sleep_mode = false      -- 是否睡眠模式
local g_grid_map = nil          -- GRID 物理位置映射表，如 {3,4,1,2}
local g_kp_pin = nil            -- KP 中断引脚（可选）

-- 显示缓冲区（4个地址，对应 68H/6AH/6CH/6EH）
local g_display_buf = {}

-- 按键相关
local g_key_callback = nil      -- 按键回调函数
local g_last_key_byte = 0x2E    -- 上一次按键数据字节（0x2E = NO KEY）
local g_key_timer_id = nil      -- 按键轮询定时器 ID
local g_kp_int_pin = nil        -- KP 中断 GPIO 编号

-- ==================== GPIO 底层操作 ====================

local function clk_low()
    gpio.set(g_clk_pin, 0)
end

local function clk_high()
    gpio.set(g_clk_pin, 1)
end

local function dio_set_output()
    gpio.setup(g_dio_pin, 0, gpio.PULLUP)
end

local function dio_set_input()
    gpio.setup(g_dio_pin, nil)
end

local function dio_high()
    gpio.set(g_dio_pin, 1)
end

local function dio_low()
    gpio.set(g_dio_pin, 0)
end

local function dio_read()
    return gpio.get(g_dio_pin)
end

-- ==================== I²C 类通信协议层 ====================

-- AiP650E 使用 I²C 类两线协议：
-- CLK=H 时 DIO 下降沿 = START
-- CLK=H 时 DIO 上升沿 = STOP
-- CLK 上升沿锁存数据
-- DIO 在 CLK=低电平时改变数据
-- 每 8 位数据后第 9 个时钟为 ACK（设备拉低 DIO）

-- 发送 1 个字节（高位先发），返回是否收到 ACK
local function send_byte(data)
    for i = 7, 0, -1 do
        clk_low()
        if (data >> i) & 0x01 ~= 0 then
            dio_high()
        else
            dio_low()
        end
        clk_high()  -- 设备在 CLK 上升沿锁存数据
    end
    -- 第 9 个时钟：等待设备 ACK
    clk_low()
    dio_set_input()  -- 释放 DIO，让设备驱动
    clk_high()
    local ack = dio_read()  -- 设备拉低 DIO 表示 ACK
    clk_low()
    dio_set_output()  -- 恢复输出
    return ack == 0  -- 低电平 = ACK
end

-- 接收 1 个字节（高位先收）
-- 调用前 DIO 必须处于输入模式
-- 返回接收到的字节
local function recv_byte()
    local data = 0
    dio_set_input()
    for i = 7, 0, -1 do
        clk_low()
        clk_high()
        if dio_read() ~= 0 then
            data = data | (1 << i)
        end
    end
    -- 第 9 个时钟：主机发送 ACK（拉低 DIO）
    clk_low()
    dio_set_output()
    dio_low()   -- ACK
    clk_high()
    clk_low()
    return data
end

-- I²C 起始条件：CLK=H 时 DIO 下降沿
local function i2c_start()
    dio_set_output()
    clk_high()
    dio_high()
    dio_low()   -- CLK=H, DIO 下降沿
end

-- I²C 停止条件：CLK=H 时 DIO 上升沿
local function i2c_stop()
    dio_set_output()
    dio_low()
    clk_high()
    dio_high()  -- CLK=H, DIO 上升沿
end

-- ==================== AiP650E 协议层 ====================

-- 发送 16 位显示控制指令（系统指令 + 显示指令）
-- 格式：START → 0x48 + ACK → display_ctrl + ACK → STOP
local function write_display_command(display_ctrl_byte)
    i2c_start()
    send_byte(CMD_SYSTEM)
    send_byte(display_ctrl_byte)
    i2c_stop()
end

-- 生成显示控制字节
-- 位定义：X BR2 BR1 BR0 S X W D
--   BR[2:0] = 亮度编码（bits[6:4]）
--   S = 段模式（bit[3]，1=7段，0=8段）
--   W = 睡眠（bit[1]，1=睡眠，0=工作）
--   D = 显示开/关（bit[0]，1=开，0=关）
local function make_display_ctrl(bright, segment_7seg, sleep, display_on)
    -- 亮度映射：用户 0~7 → 芯片 BR[2:0]
    -- 用户 0(暗) → BR=1, 用户 7(亮) → BR=0
    local br_code = (bright + 1) % 8
    local s_bit = 0
    if segment_7seg then s_bit = 1 end
    local w_bit = 0
    if sleep then w_bit = 1 end
    local d_bit = 0
    if display_on then d_bit = 1 end
    return (br_code << 4) | (s_bit << 3) | (w_bit << 1) | d_bit
end

-- 更新显示控制（刷新到芯片）
local function update_display_control()
    local ctrl = make_display_ctrl(g_current_bright, g_segment_7seg, g_sleep_mode, g_display_on)
    write_display_command(ctrl)
end

-- 获取显示地址（基于 DIG 索引 0~3）
-- 地址：DIG1=0x68, DIG2=0x6A, DIG3=0x6C, DIG4=0x6E
local function get_disp_addr(dig_idx)
    return 0x68 + (dig_idx * 2)
end

-- GRID 物理位置映射
-- grid_map 中的值从 1 开始（用户视角），内部转 0-based
local function map_grid(pos)
    if g_grid_map then
        local physical_pos = g_grid_map[pos + 1]
        if physical_pos ~= nil then
            return physical_pos - 1
        end
    end
    return pos
end

-- 获取段码值（自动处理共阴/共阳）
local function get_seg_value(seg)
    if g_common_anode then
        return (~seg) & 0xFF
    else
        return seg & 0xFF
    end
end

-- 写入一个 DIG 的显示数据
-- START → addr + ACK → data + ACK → STOP
local function write_disp_digit(dig_idx, data_byte)
    local addr = get_disp_addr(dig_idx)
    i2c_start()
    send_byte(addr)
    send_byte(data_byte)
    i2c_stop()
end

-- 全量刷新显示缓冲区到芯片
local function flush_display()
    for pos = 0, MAX_DIGITS - 1 do
        local grid_pos = map_grid(pos)
        local data = g_display_buf[grid_pos] or 0x00
        write_disp_digit(pos, data)
    end
end

-- ==================== 按键数据处理 ====================

-- 读取按键数据字节
-- 返回值：
--   0x2E = 无按键
--   0x48~0x4F 范围 = 按键编码数据
-- 返回：number 按键数据字节
local function read_key_byte()
    i2c_start()
    send_byte(CMD_READ_KEY)
    local key_data = recv_byte()
    i2c_stop()
    return key_data
end

-- 解析按键数据字节为按键编码 1~28 或 29~32（组合键）
-- 按键数据格式：01_KI2_KI1_KI0_DI2_DI1_DI0
--   KI[2:0] = 000(KI1)~110(KI7), 111=KI1+KI2 组合键
--   DI[2:0] = 100(DIG1)~111(DIG4)
-- NO KEY = 00_101_110 = 0x2E
local function key_byte_to_code(key_byte)
    if key_byte == 0x2E then
        return nil  -- NO KEY
    end

    -- 检查是否为有效按键按下（高位为 01）
    if (key_byte & 0xC0) ~= 0x40 then
        return nil  -- 不是有效按键数据
    end

    local ki_code = (key_byte >> 3) & 0x07  -- bits[5:3]
    local dig_code = key_byte & 0x07        -- bits[2:0]

    -- DIG 编码从 4(100) 开始
    if dig_code < 4 then
        return nil
    end
    local dig_idx = dig_code - 4  -- 0~3

    -- 组合键（KI1+KI2）：ki_code == 7
    if ki_code == 7 then
        -- 返回组合键编码 29~32
        return 29 + dig_idx
    end

    -- 普通按键：ki_code 0~6（对应 KI1~KI7）
    -- 按键编码 = ki_code * 4 + dig_idx + 1
    return ki_code * 4 + dig_idx + 1
end

-- 按键轮询处理函数（由定时器调用）
local function key_scan_timer_func()
    local current_byte = read_key_byte()
    if current_byte == g_last_key_byte then
        return  -- 状态无变化
    end

    local current_code = key_byte_to_code(current_byte)
    local prev_code = key_byte_to_code(g_last_key_byte)

    -- 检测从无按键→有按键的上升沿
    if current_code ~= nil and g_key_callback then
        g_key_callback(current_code)
    end

    g_last_key_byte = current_byte
end

-- KP 中断处理函数
local function kp_int_func()
    -- 简单消抖后读取按键
    local key_byte = read_key_byte()
    local code = key_byte_to_code(key_byte)
    if code ~= nil and g_key_callback then
        g_key_callback(code)
    end
    g_last_key_byte = key_byte
end

-- ==================== 外部 API ====================

--[[
初始化 AiP650E 驱动芯片，配置通信引脚和初始参数

@api exs_aip650e.setup(config)

@table config
初始化配置表，包含以下键：

clk
CLK 时钟引脚 GPIO 编号，接 AiP650E 第 2 脚（CLK）；
数据类型：number
是否必选：必选

dio
DIO 数据引脚 GPIO 编号，接 AiP650E 第 3 脚（DIO）；
注意：DIO 为开漏模式，需外接 4.7kΩ~10kΩ 上拉电阻到 VCC；
数据类型：number
是否必选：必选

kp
KP 中断引脚 GPIO 编号（可选），接 AiP650E 第 16 脚（DP/KP）；
注册回调后按键按下时 KP 引脚产生电平变化触发中断读取，替代轮询方式；
数据类型：number
是否必选：可选

bright
初始亮度等级 0~7，默认 3；
0 最暗，7 最亮；
数据类型：number
是否必选：可选

common_anode
是否使用共阳数码管，默认 false（共阴极）；
设为 true 时内部自动对段码取反；
数据类型：boolean
是否必选：可选

grid_map
GRID 物理位置映射表，4 个元素的数组；
默认 nil（不映射）。当物理走线导致显示顺序与预期不符时使用。
例如设置 "1234" 显示为 "4321"，则填入 {4,3,2,1}；
数据类型：table
是否必选：可选

segment_7seg
是否启用 7 段模式，默认 false（8 段模式）；
7 段模式下 DP 段不可用，仅显示 a~g 七个段；
数据类型：boolean
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 基础初始化
local result = exs_aip650e.setup({
    clk    = 27,
    dio    = 26,
    bright = 3,
})

-- 共阳数码管 + KP 中断
local result = exs_aip650e.setup({
    clk          = 27,
    dio          = 26,
    kp           = 25,
    bright       = 3,
    common_anode = true,
})
]]
function exs_aip650e.setup(config)
    -- 参数检查
    if type(config) ~= "table" then
        log.error("exs_aip650e.setup 参数错误：config 应为 table 类型")
        return false
    end
    if not config.clk or not config.dio then
        log.error("exs_aip650e.setup 参数错误：clk、dio 均为必填")
        return false
    end

    -- 保存引脚编号
    g_clk_pin = config.clk
    g_dio_pin = config.dio
    g_kp_pin = config.kp or nil
    g_common_anode = config.common_anode or false
    g_current_bright = config.bright or 3
    if g_current_bright > 7 then g_current_bright = 7 end
    if g_current_bright < 0 then g_current_bright = 0 end
    g_grid_map = config.grid_map or nil
    g_segment_7seg = config.segment_7seg or false
    g_display_on = true
    g_sleep_mode = false

    -- 初始化 GPIO
    gpio.setup(g_clk_pin, 0)
    dio_set_output()
    clk_high()
    dio_high()

    -- 初始化内部缓冲区（清空 4 个显示地址）
    for i = 0, MAX_DIGITS - 1 do
        g_display_buf[i] = 0x00
    end

    -- 初始化：先清空显存，再设置显示控制
    flush_display()
    update_display_control()

    -- 初始化按键状态
    g_last_key_byte = read_key_byte()
    g_key_callback = nil

    log.info("exs_aip650e", string.format("初始化完成, clk=%d dio=%d 亮度=%d",
        g_clk_pin, g_dio_pin, g_current_bright))

    return true
end

--[[
设置显示亮度（8 级辉度调节）

@api exs_aip650e.set_brightness(level)

@param number level
亮度等级 0~7，0 最暗，7 最亮；
调用此接口会自动开启显示。

@return nil

@usage
exs_aip650e.set_brightness(7)  -- 最亮
exs_aip650e.set_brightness(0)  -- 最暗
]]
function exs_aip650e.set_brightness(level)
    if level == nil then level = 3 end
    if level < 0 then level = 0 end
    if level > 7 then level = 7 end
    g_current_bright = level
    g_display_on = true
    g_sleep_mode = false
    update_display_control()
end

--[[
开启显示：恢复数码管显示

@api exs_aip650e.display_on()

@return nil

@usage
exs_aip650e.display_on()
]]
function exs_aip650e.display_on()
    g_display_on = true
    g_sleep_mode = false
    update_display_control()
end

--[[
关闭显示：熄灭数码管（保留显存数据）

@api exs_aip650e.display_off()

@return nil

@usage
exs_aip650e.display_off()
]]
function exs_aip650e.display_off()
    g_display_on = false
    update_display_control()
end

--[[
进入睡眠模式：低功耗，显存数据保留

@api exs_aip650e.sleep()

注意事项：睡眠前需先停止按键回调定时器（set_key_callback(nil)），
否则定时器会阻止系统进入低功耗模式。

@return nil

@usage
exs_aip650e.sleep()
]]
function exs_aip650e.sleep()
    -- 进入睡眠时关闭显示并进入休眠模式
    g_sleep_mode = true
    g_display_on = true  -- 睡眠模式相关位可保留显示
    update_display_control()
end

--[[
从睡眠模式唤醒

@api exs_aip650e.wakeup()

@return nil

@usage
exs_aip650e.wakeup()
]]
function exs_aip650e.wakeup()
    g_sleep_mode = false
    g_display_on = true
    update_display_control()
end

--[[
清空所有显示（熄灭所有数码管段）

@api exs_aip650e.clear()

@return nil

@usage
exs_aip650e.clear()
]]
function exs_aip650e.clear()
    for i = 0, MAX_DIGITS - 1 do
        g_display_buf[i] = 0x00
    end
    flush_display()
end

--[[
设置 7 段/8 段显示模式

@api exs_aip650e.set_mode(mode)

@param number mode
0 = 8 段模式（默认，含 DP 段）；
1 = 7 段模式（无 DP 段，适合纯数字显示）。

@return nil

@usage
exs_aip650e.set_mode(0)  -- 8 段模式
exs_aip650e.set_mode(1)  -- 7 段模式
]]
function exs_aip650e.set_mode(mode)
    g_segment_7seg = (mode == 1)
    update_display_control()
end

-- ==================== 段码表 ====================

-- 共阴极段码表（0~F + 特殊符号）
local SEG_TABLE = {
    [0]    = 0x3F,  -- 0
    [1]    = 0x06,  -- 1
    [2]    = 0x5B,  -- 2
    [3]    = 0x4F,  -- 3
    [4]    = 0x66,  -- 4
    [5]    = 0x6D,  -- 5
    [6]    = 0x7D,  -- 6
    [7]    = 0x07,  -- 7
    [8]    = 0x7F,  -- 8
    [9]    = 0x6F,  -- 9
    [10]   = 0x77,  -- A
    [11]   = 0x7C,  -- b
    [12]   = 0x39,  -- C
    [13]   = 0x5E,  -- d
    [14]   = 0x79,  -- E
    [15]   = 0x71,  -- F
    ["-"] = 0x40,  -- 减号/横线
    ["_"]  = 0x08,  -- 下划线（仅点亮 SEG4=D 段）
    [" "] = 0x00,  -- 全灭/空格
}

-- 字符到段码的映射
local CHAR_TO_SEG = {
    ["0"] = 0x3F, ["1"] = 0x06, ["2"] = 0x5B, ["3"] = 0x4F,
    ["4"] = 0x66, ["5"] = 0x6D, ["6"] = 0x7D, ["7"] = 0x07,
    ["8"] = 0x7F, ["9"] = 0x6F,
    ["A"] = 0x77, ["B"] = 0x7C, ["C"] = 0x39, ["D"] = 0x5E,
    ["E"] = 0x79, ["F"] = 0x71, ["G"] = 0x3D, ["H"] = 0x76,
    ["I"] = 0x30, ["J"] = 0x1E, ["K"] = 0x76, ["L"] = 0x38,
    ["M"] = 0x37, ["N"] = 0x37, ["O"] = 0x3F, ["P"] = 0x73,
    ["Q"] = 0x67, ["R"] = 0x31, ["S"] = 0x6D, ["T"] = 0x31,
    ["U"] = 0x3E, ["V"] = 0x3E, ["W"] = 0x7E, ["X"] = 0x76,
    ["Y"] = 0x6E, ["Z"] = 0x5B,
    ["a"] = 0x77, ["b"] = 0x7C, ["c"] = 0x58, ["d"] = 0x5E,
    ["e"] = 0x79, ["f"] = 0x71, ["g"] = 0x6F, ["h"] = 0x74,
    ["i"] = 0x04, ["j"] = 0x0E, ["k"] = 0x75, ["l"] = 0x30,
    ["m"] = 0x54, ["n"] = 0x54, ["o"] = 0x5C, ["p"] = 0x73,
    ["q"] = 0x67, ["r"] = 0x50, ["s"] = 0x6D, ["t"] = 0x78,
    ["u"] = 0x1C, ["v"] = 0x1C, ["w"] = 0x3E, ["x"] = 0x76,
    ["y"] = 0x6E, ["z"] = 0x5B,
    ["-"] = 0x40, ["_"] = 0x08, ["="] = 0x48, [" "] = 0x00,
    ["."] = 0x80,
    ["\xB0"] = 0x63,  -- ° 的 Latin-1 编码，段码 = 8 的上半圈
}

--[[
从指定起始位置开始显示字符串，自动查段码表

@api exs_aip650e.set_display(str, offset)

str
参数含义：要显示的字符串
数据类型：string
是否必选：必选
注意事项：支持数字 0-9、大小写字母、点号、减号、空格、度符号。
点号"."作为小数点附加在前一个字符上，不独立占位。
温度显示可用 "25°C" 表示 25℃（° 段码 0x63 = 8 的上半圈）。
不支持的字符显示为空格。

offset
参数含义：起始位置
数据类型：number
取值范围：1~4（1 对应第 1 位数码管，4 对应第 4 位数码管）
是否必选：可选
注意事项：默认 1。超出范围时超出部分不显示。

@return nil

@usage
exs_aip650e.set_display("1234")
exs_aip650e.set_display("88.8")
exs_aip650e.set_display("12", 3)
exs_aip650e.set_display("25°C")
]]
function exs_aip650e.set_display(str, offset)
    if type(str) ~= "string" or #str == 0 then
        log.error("exs_aip650e.set_display 参数错误：str 应为非空字符串")
        return
    end
    offset = offset or 1
    if offset < 1 then offset = 1 end
    local offset0 = offset - 1
    if offset0 >= MAX_DIGITS then return end

    local max_len = MAX_DIGITS - offset0

    -- 构建段码数组
    local seg_array = {}
    local seg_idx = 1
    local i = 1

    while i <= #str and seg_idx <= max_len do
        local ch = str:sub(i, i)

        if ch == "." then
            -- 小数点附加到前一个字符上
            if seg_idx > 1 then
                seg_array[seg_idx - 1] = (seg_array[seg_idx - 1] or 0x00) | 0x80
            end
        elseif ch == "\xC2" then
            -- UTF-8 编码的 °（\xC2\xB0）
            i = i + 1
            if i <= #str then
                local next_ch = str:sub(i, i)
                if next_ch == "\xB0" then
                    seg_array[seg_idx] = 0x63  -- ° 段码
                    seg_idx = seg_idx + 1
                else
                    seg_array[seg_idx] = 0x00
                    seg_idx = seg_idx + 1
                end
            end
        elseif ch == "\xA1" then
            -- GB2312/GBK 编码的 °（\xA1\xE3）
            i = i + 1
            if i <= #str then
                local next_ch = str:sub(i, i)
                if next_ch == "\xE3" then
                    seg_array[seg_idx] = 0x63  -- ° 段码
                    seg_idx = seg_idx + 1
                else
                    seg_array[seg_idx] = 0x00
                    seg_idx = seg_idx + 1
                end
            end
        elseif ch == "\xB0" then
            -- Latin-1 编码的 °（单字节）
            seg_array[seg_idx] = 0x63  -- ° 段码
            seg_idx = seg_idx + 1
        else
            -- 查找字符段码
            local seg = CHAR_TO_SEG[ch]
            if seg == nil then
                local upper = string.upper(ch)
                seg = CHAR_TO_SEG[upper] or 0x00
            end
            seg_array[seg_idx] = seg
            seg_idx = seg_idx + 1
        end
        i = i + 1
    end

    -- 填充到缓冲区并刷新
    for pos = offset0, offset0 + max_len - 1 do
        local arr_idx = pos - offset0 + 1
        local val = get_seg_value(seg_array[arr_idx] or 0x00)
        g_display_buf[pos] = val
    end

    flush_display()
end

-- 按键编码说明
-- 28 个按键排列（K1~K7 × DIG1~DIG4）：
--
--             DIG1  DIG2  DIG3  DIG4
--         KI1:  1     2     3     4
--         KI2:  5     6     7     8
--         KI3:  9    10    11    12
--         KI4: 13    14    15    16
--         KI5: 17    18    19    20
--         KI6: 21    22    23    24
--         KI7: 25    26    27    28
--
-- 组合键（KI1+KI2）：29(DIG1)~32(DIG4)

--[[
轮询读取当前按下的按键编码。无按键按下时返回 nil。

AiP650E 内置 7×4 按键扫描矩阵，最多支持 28 个独立的按键
以及 4 个组合按键（KI1+KI2 × 4 个 DIG）。

按键扫描由芯片自动完成，结果存储在内部寄存器，
主控通过两线总线读取即可。

@api exs_aip650e.get_key()

@return number or nil
有按键按下时返回按键编码 1~28（普通按键）或 29~32（组合键），
无按键按下返回 nil。
多个键同时按下时返回编码最小的那个。

@usage
local key = exs_aip650e.get_key()
if key then
    log.info("exs_aip650e", "检测到按键:", key)
end
]]
function exs_aip650e.get_key()
    local key_byte = read_key_byte()
    local code = key_byte_to_code(key_byte)
    g_last_key_byte = key_byte
    return code
end

--[[
设置按键事件回调函数。注册后库内部会每隔 50ms 自动轮询按键
状态，检测到有按键按下时调用回调函数。

设备进入低功耗休眠前，必须先调用 exs_aip650e.set_key_callback(nil)
停止内部轮询定时器，否则定时器会阻止系统进入低功耗模式。
唤醒后重新注册回调即可。

如果 setup() 时配置了 kp 引脚，且未注册回调时 kp 引脚将
配置为中断模式替代轮询，降低 CPU 占用。

@api exs_aip650e.set_key_callback(cbfunc)

@param function cbfunc
按键事件回调函数，接收一个参数 key_code（number 类型 1~32）。
传入 nil 可取消回调。回调函数中应避免长时间阻塞操作。

@return nil

@usage
-- 注册按键回调
local function on_key(key_code)
    log.info("exs_aip650e", "按键:", key_code)
end
exs_aip650e.set_key_callback(on_key)

-- 取消回调
exs_aip650e.set_key_callback(nil)
]]
function exs_aip650e.set_key_callback(cbfunc)
    g_key_callback = cbfunc

    -- 取消已有的定时器
    if g_key_timer_id then
        sys.timerStop(g_key_timer_id)
        g_key_timer_id = nil
    end

    -- 取消已有的 KP 中断
    if g_kp_int_pin then
        gpio.setup(g_kp_int_pin, nil)
        g_kp_int_pin = nil
    end

    if cbfunc then
        if g_kp_pin then
            -- 使用 KP 引脚中断方式
            g_kp_int_pin = g_kp_pin
            gpio.setup(g_kp_int_pin, function()
                kp_int_func()
            end, gpio.PULLUP, gpio.FALLING)
            -- 初始化时读取一次清除初始状态
            g_last_key_byte = read_key_byte()
        else
            -- 使用定时器轮询方式（每 50ms 检查一次）
            g_last_key_byte = read_key_byte()
            g_key_timer_id = sys.timerLoopStart(key_scan_timer_func, 50)
        end
    end
end

--[[
获取 exs_aip650e 库的版本号

@api exs_aip650e.version()

@return string
版本号字符串，格式为 "yyyymmddhhmm"

@usage
local ver = exs_aip650e.version()
log.info("exs_aip650e", "版本号:", ver)
]]
function exs_aip650e.version()
    return "202607131200"
end

log.debug("exs_aip650e", "version -> " .. exs_aip650e.version())

return exs_aip650e
