--[[
@module  exs_tm1637
@summary TM1637 数码管驱动扩展库（8段×6位 + 16个按键）
@version 1.0
@date    2026.07.13
@author  江访
@usage
本文件为 TM1637 驱动芯片的 LuatOS 扩展库，核心功能为：
1、初始化 TM1637，配置 CLK/DIO 双线通信引脚
2、6 位 8 段数码管显示（支持共阴/共阳切换）
3、16 个按键扫描检测（轮询和回调两种方式）
4、8 级亮度调节

本文件的对外接口有 7 个：
1、exs_tm1637.setup(config)：初始化 TM1637
2、exs_tm1637.set_brightness(level)：设置亮度
3、exs_tm1637.clear()：清空显示
4、exs_tm1637.set_display(str, offset)：数码管显示字符串
5、exs_tm1637.get_key()：轮询读取按键
6、exs_tm1637.set_key_callback(cbfunc)：设置按键回调
7、exs_tm1637.version()：获取版本号

-- 版本更新说明
-- 版本号：202607131200
-- 1、更新时间：2026-07-13 12:00
-- 2、更新内容
  - 首次发布，实现 TM1637 基础驱动功能
  - 支持数码管显示（8 段 ×6 位）
  - 支持按键扫描（轮询 + 回调两种方式）
  - 支持 8 级亮度调节
  - 支持共阴/共阳数码管切换
]]

local exs_tm1637 = {}

-- ==================== 模块常量 ====================

-- TM1637 命令常量
local CMD_DATA_WRITE   = 0x40  -- 数据命令：写显示寄存器
local CMD_READ_KEY     = 0x42  -- 数据命令：读按键
local CMD_ADDR_BASE    = 0xC0  -- 地址命令基址（C0H~C5H共6个地址）
local CMD_DISPLAY_ON   = 0x88  -- 显示控制：开启显示基值（+亮度0~7）
local CMD_DISPLAY_OFF  = 0x80  -- 显示控制：关闭显示

-- 最大支持参数
local MAX_DIGITS = 6   -- 最大数码管位数
local MAX_KEYS   = 16  -- 最大按键数

-- ==================== 内部状态 ====================

-- GPIO 引脚编号
local g_clk_pin = nil  -- CLK 引脚
local g_dio_pin = nil  -- DIO 数据引脚（双向）

-- 配置参数
local g_common_anode = false  -- 是否共阳数码管
local g_current_bright = 3    -- 当前亮度 0~7
local g_grid_map = nil        -- GRID物理位置映射表，如{6,5,4,3,2,1}

-- 显示缓冲区（6字节，对应C0H~C5H地址）
local g_display_buf = {}

-- 按键相关
local g_key_callback = nil    -- 按键回调函数
local g_last_key_byte = 0     -- 上一次按键字节数据，用于检测变化
local g_key_timer_id = nil    -- 按键轮询定时器ID

-- ==================== GPIO 底层操作 ====================

-- CLK 时钟线控制
local function clk_low()
    gpio.set(g_clk_pin, 0)
end

local function clk_high()
    gpio.set(g_clk_pin, 1)
end

-- DIO 数据线控制（双向）
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

-- ==================== 通信协议层 ====================

-- TM1637 启动条件：CLK=H, DIO=H→L
local function start_signal()
    dio_set_output()
    clk_high()
    dio_high()
    clk_high()  -- 保持稳定
    dio_low()
    clk_low()
end

-- TM1637 结束条件：CLK=H, DIO=L→H
local function stop_signal()
    dio_set_output()
    clk_low()
    dio_low()
    clk_high()
    dio_high()
end

-- 发送 1 个字节（低位先发，LSB first）
-- TM1637 在 CLK 上升沿读取 DIO 数据
-- 无显式延时，靠 gpio.set() 自身执行时间满足 TM1637 时序
-- @number data 要发送的字节
local function send_byte(data)
    for i = 0, 7 do
        clk_low()
        if data & 0x01 ~= 0 then
            dio_high()
        else
            dio_low()
        end
        clk_high()
        data = data >> 1
    end
end

-- 等待 ACK（芯片拉低 DIO 作为应答）
-- TM1637 在第 9 个时钟周期将 DIO 拉低表示 ACK
-- @return boolean 收到 ACK 返回 true，否则 false
local function wait_ack()
    clk_low()
    dio_set_input()
    clk_high()
    local ack = (dio_read() == 0)
    clk_low()
    dio_set_output()
    return ack
end

-- 接收 1 个字节（低位先出，LSB first）
-- TM1637 在 CLK 上升沿输出数据到 DIO，我们在 CLK 上升沿读取
-- @return number 读到的字节
local function recv_byte()
    local data = 0
    dio_set_input()
    for i = 0, 7 do
        clk_low()
        clk_high()
        if dio_read() ~= 0 then
            data = data | (1 << i)
        end
    end
    return data
end

-- 发送 ACK 信号（在第 9 个时钟拉低 DIO）
-- TM1637 的读键操作中，主机需发送 ACK 给芯片表示还想要更多数据
local function send_ack()
    dio_set_output()
    clk_low()
    dio_low()
    clk_high()
    clk_low()
    dio_set_input()
end

-- 发送 NAK 信号（在第 9 个时钟保持 DIO 高阻/高电平）
-- 读键操作中最后一个字节后发 NAK 通知芯片停止发送
local function send_nak()
    dio_set_output()
    clk_low()
    dio_high()
    clk_high()
    clk_low()
    dio_set_input()
end

-- 写数据到 TM1637 显存（使用自动地址递增模式）
-- 命令序列：
--   1. start → 0x40 + ACK → stop （设置写显示寄存器模式）
--   2. start → C0|addr + ACK → data1+ACK → data2+ACK... → stop
-- @number start_addr 起始地址偏移（0~5）
-- @table data_array 数据数组
local function write_data(start_addr, data_array)
    -- 第一帧：设定写寄存器模式（自动地址递增）
    start_signal()
    send_byte(CMD_DATA_WRITE)
    wait_ack()
    stop_signal()

    -- 第二帧：设置起始地址并写入数据
    start_signal()
    send_byte(CMD_ADDR_BASE | (start_addr & 0x07))
    wait_ack()
    for i = 1, #data_array do
        send_byte(data_array[i])
        wait_ack()
    end
    stop_signal()
end

-- 写入显示控制命令（开关显示 + 亮度）
-- TM1637 独立帧：start → 0x88|bright + ACK → stop
-- @number bright 亮度 0~7
-- @boolean display_on 是否开启显示
local function write_display_control(bright, display_on)
    start_signal()
    if display_on then
        send_byte(CMD_DISPLAY_ON | (bright & 0x07))
    else
        send_byte(CMD_DISPLAY_OFF)
    end
    wait_ack()
    stop_signal()
end

-- ==================== 缓冲区管理 ====================

-- 刷新显示缓冲区到 TM1637 硬件
local function flush_display()
    local buf = {}
    for i = 0, MAX_DIGITS - 1 do
        buf[i + 1] = g_display_buf[i] or 0x00
    end
    write_data(0x00, buf)
end

-- GRID 物理位置映射，将逻辑位号转换为物理GRID地址
-- grid_map 中的值从 1 开始（用户视角），内部自动转 0-based 地址
local function map_grid(pos)
    if g_grid_map then
        local physical_pos = g_grid_map[pos + 1]
        if physical_pos ~= nil then
            return physical_pos - 1  -- 用户 1-based 转内部 0-based
        end
    end
    return pos
end

-- 获取段码（自动处理共阴/共阳）
-- @number seg 共阴极段码值
-- @return number 实际写入芯片的段码值
local function get_seg_value(seg)
    if g_common_anode then
        return (~seg) & 0xFF
    else
        return seg & 0xFF
    end
end

-- ==================== 按键数据处理 ====================

-- 读取按键数据，返回 16 位的按键掩码
-- TM1637 读键协议：
--   1. start → 0x42 + ACK → stop （发读键命令）
--   2. start → 0x42 + ACK → recv_byte0 + ACK → recv_byte1 + NAK → stop
-- Byte0: bits[3:0]=K1-K4(KS1-KS4), bits[7:4]=K5-K8(KS1-KS4)
-- Byte1: bits[3:0]=K1-K4(KS5-KS8), bits[7:4]=K5-K8(KS5-KS8)
-- 总共 16 个按键：每个 KS 列有 K1~K8 共 8 个键，共 2 组（KS1~KS4 和 KS5~KS8）
-- @return number 16位按键掩码（bit0=按键1 ... bit15=按键16）
local function read_key_mask()
    local mask = 0

    -- 第一帧：发送读键命令
    start_signal()
    send_byte(CMD_READ_KEY)
    wait_ack()
    stop_signal()

    -- 第二帧：发送 command code 后读 2 字节
    start_signal()
    send_byte(CMD_READ_KEY)
    wait_ack()

    -- Byte0: K1-K4 列 (KS1-KS4) 和 K5-K8 列 (KS1-KS4)
    -- bits[3:0] = K1 KS1, K2 KS1, K1 KS2, K2 KS2 ... K1 KS4, K2 KS4 (每组 2bits)
    -- bits[7:4] = K3 KS1, K4 KS1, K3 KS2, K4 KS2 ... K3 KS4, K4 KS4 (每组 2bits)
    local byte0 = recv_byte()
    send_ack()

    -- Byte1: K1-K4 列 (KS5-KS8) 和 K5-K8 列 (KS5-KS8)
    local byte1 = recv_byte()
    send_nak()
    stop_signal()

    -- Datasheet 按键矩阵：
    --         KS1 KS2 KS3 KS4 KS5 KS6 KS7 KS8
    -- K1      K1  K5  K9  K13 K?  K?  K?  K?   -- 按键编码
    -- K2      K2  K6  K10 K14 K?  K?  K?  K?

    -- 简化解析：每个 nibble 的 bit0 和 bit1 对应按键
    -- 共 8 个 KS 列，每个 KS 列有 2 个按键（K1、K2），总共 16 个按键
    -- byte0: KS1~KS4 的 K1+K2
    -- byte1: KS5~KS8 的 K1+K2

    -- KS1~KS4 (来自 byte0)
    for col = 0, 3 do
        -- 每列 2 bits: [7:6]=K2, [5:4]=K1  (nibble 高半字节)
        --               [3:2]=K2, [1:0]=K1  (nibble 低半字节)
        -- 按键按列编码：col*4 + offset
        local low_nibble = (byte0 >> (col * 2)) & 0x03
        if low_nibble & 0x01 ~= 0 then
            mask = mask | (1 << (col * 2 + 0))   -- K1 of this KS
        end
        if low_nibble & 0x02 ~= 0 then
            mask = mask | (1 << (col * 2 + 1))   -- K2 of this KS
        end
    end

    -- KS5~KS8 (来自 byte1)
    for col = 0, 3 do
        local low_nibble = (byte1 >> (col * 2)) & 0x03
        if low_nibble & 0x01 ~= 0 then
            mask = mask | (1 << (8 + col * 2 + 0))  -- K1 of this KS
        end
        if low_nibble & 0x02 ~= 0 then
            mask = mask | (1 << (8 + col * 2 + 1))  -- K2 of this KS
        end
    end

    return mask
end

-- 按键轮询处理函数（由定时器调用）
local function key_scan_timer_func()
    local current_mask = read_key_mask()

    -- 检测按键状态变化（从松开→按下）
    local pressed = current_mask & (~g_last_key_byte)

    if pressed ~= 0 and g_key_callback then
        -- 找到所有按下的按键，逐个通知回调
        local code = 1
        while pressed ~= 0 do
            if pressed & 0x01 ~= 0 then
                g_key_callback(code)
            end
            pressed = pressed >> 1
            code = code + 1
        end
    end

    g_last_key_byte = current_mask
end

-- ==================== 外部 API ====================

--[[
初始化 TM1637 驱动芯片，配置通信引脚和初始参数

@api exs_tm1637.setup(config)

@table config
初始化配置表，包含以下键：

clk
CLK 时钟引脚 GPIO 编号；
数据类型：number
是否必选：必选

dio
DIO 数据引脚 GPIO 编号（双向通信）；
需要外接 4.7kΩ~10kΩ 上拉电阻到 VCC；
数据类型：number
是否必选：必选

bright
初始亮度等级 0~7，默认 3；
0 最暗（脉冲宽度 1/16），7 最亮（脉冲宽度 14/16）；
数据类型：number
是否必选：可选

common_anode
是否使用共阳数码管，默认 false（共阴极）；
设为 true 时内部自动对段码取反；
数据类型：boolean
是否必选：可选

grid_map
GRID 物理位置映射表，6 个元素的数组；
默认 nil（不映射）。可通过 setup() 适配 PCB 走线。设置 "123456" 若显示为 "654321"，说明顺序完全相反，填入 {6,5,4,3,2,1} 即可修正
数据类型：table
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 基础初始化
local result = exs_tm1637.setup({
    clk    = 27,
    dio    = 26,
    bright = 3,
})

-- 共阳数码管初始化
local result = exs_tm1637.setup({
    clk          = 27,
    dio          = 26,
    bright       = 3,
    common_anode = true,
})
]]
function exs_tm1637.setup(config)
    -- 参数检查
    if type(config) ~= "table" then
        log.error("exs_tm1637.setup 参数错误：config 应为 table 类型")
        return false
    end
    if not config.clk or not config.dio then
        log.error("exs_tm1637.setup 参数错误：clk、dio 均为必填")
        return false
    end

    -- 保存引脚编号
    g_clk_pin = config.clk
    g_dio_pin = config.dio
    g_common_anode = config.common_anode or false
    g_current_bright = config.bright or 3
    if g_current_bright > 7 then g_current_bright = 7 end
    if g_current_bright < 0 then g_current_bright = 0 end
    g_grid_map = config.grid_map or nil

    -- 初始化 GPIO
    gpio.setup(g_clk_pin, 0)
    dio_set_output()
    clk_high()
    dio_high()

    -- 初始化内部缓冲区
    for i = 0, MAX_DIGITS - 1 do
        g_display_buf[i] = 0x00
    end
    g_last_key_byte = 0

    -- 初始化流程：
    -- 1) 显示控制：0x8B (开显示 + 亮度 3)
    -- 2) 清空 6 字节显存
    -- 3) 根据传入亮度重新设置
    write_display_control(g_current_bright, true)
    local zero_buf = {}
    for i = 1, MAX_DIGITS do zero_buf[i] = 0x00 end
    write_data(0x00, zero_buf)
    write_display_control(g_current_bright, true)

    log.info("exs_tm1637", string.format("初始化完成, clk=%d dio=%d 亮度=%d",
        g_clk_pin, g_dio_pin, g_current_bright))

    return true
end

--[[
设置显示亮度（8级辉度调节）

@api exs_tm1637.set_brightness(level)

参数含义：亮度等级
数据类型：number
取值范围：0~7，0最暗 7最亮
是否必选：必选
注意事项：调用此接口会自动开启显示

@return nil

@usage
-- 设置最亮
exs_tm1637.set_brightness(7)
-- 设置中等亮度
exs_tm1637.set_brightness(3)
]]
function exs_tm1637.set_brightness(level)
    level = level or 3
    if level < 0 then level = 0 end
    if level > 7 then level = 7 end
    g_current_bright = level
    write_display_control(g_current_bright, true)
end

--[[
清空所有显示

向 6 个显示地址（C0H~C5H）全部写入 0x00

@api exs_tm1637.clear()

@return nil

@usage
exs_tm1637.clear()
]]
function exs_tm1637.clear()
    -- 清空缓冲区
    for i = 0, MAX_DIGITS - 1 do
        g_display_buf[i] = 0x00
    end
    -- 刷新到芯片
    flush_display()
end

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
    ["_"]  = 0x08,  -- 下划线（仅点亮SEG4=d段）
    [" "] = 0x00,  -- 全灭/空格
}

-- 字符到段码的映射（用于 set_display）
-- TM1637 有 8 段（SEG1~SEG8：a~g+dp）
-- 此处定义常用字母、数字和特殊符号的 8 段映射
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
    -- 温度符号：用两个字符拼接表示 "°"
    -- 段码 0x63 = 8 的上半圈（0x7F 去掉 g 段 bit6），用于显示 °C/°F
    -- 扩展库内部对特殊符号的支持通过以下映射：
    ["\xB0"] = 0x63,  -- ° 的 Latin-1 单字节编码，段码=8的上半圈，用于 "25°C" 温度显示
}

--[[
从指定起始位置开始显示字符串，自动查段码表

@api exs_tm1637.set_display(str, offset)

str
参数含义：要显示的字符串
数据类型：string
是否必选：必选
注意事项：支持数字 0-9、大写字母 A-Z、小写字母部分（自动转大写）、点号、减号、等于号、空格、度符号（自动识别 UTF-8/Latin-1/GBK 编码）。
点号"."作为小数点附加在前一个字符上，不独立占位。温度显示可用 `"25°C"` 表示 25℃（° 段码 0x63 = 8 的上半圈）。
不支持的字符显示为空格。

offset
参数含义：起始位置
数据类型：number
取值范围：1~6（1 对应第 1 位数码管，6 对应第 6 位数码管）
是否必选：可选
注意事项：默认 1。超出范围时超出部分不显示。

@return nil

@usage
exs_tm1637.set_display("123456")
exs_tm1637.set_display("88.88")
exs_tm1637.set_display("123", 3)
]]
function exs_tm1637.set_display(str, offset)
    if type(str) ~= "string" or #str == 0 then
        log.error("exs_tm1637.set_display 参数错误：str 应为非空字符串")
        return
    end
    offset = offset or 1
    if offset < 1 then offset = 1 end
    -- 转换为内部 0-based 偏移
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
            -- 小数点附加到前一个数字上
            if seg_idx > 1 then
                seg_array[seg_idx - 1] = (seg_array[seg_idx - 1] or 0x00) | 0x80
            end
        elseif ch == "\xC2" then
            -- UTF-8 编码的 °（\xC2\xB0），跳过前导字节，取后续字节
            i = i + 1
            if i <= #str then
                local next_ch = str:sub(i, i)
                if next_ch == "\xB0" then
                    seg_array[seg_idx] = 0x63  -- ° 段码（8 的上半圈）
                    seg_idx = seg_idx + 1
                else
                    seg_array[seg_idx] = 0x00  -- 未知字符
                    seg_idx = seg_idx + 1
                end
            end
        elseif ch == "\xA1" then
            -- GB2312/GBK 编码的 °（\xA1\xE3），跳过前导字节
            i = i + 1
            if i <= #str then
                local next_ch = str:sub(i, i)
                if next_ch == "\xE3" then
                    seg_array[seg_idx] = 0x63  -- ° 段码（8 的上半圈）
                    seg_idx = seg_idx + 1
                else
                    seg_array[seg_idx] = 0x00  -- 未知字符
                    seg_idx = seg_idx + 1
                end
            end
        elseif ch == "\xB0" then
            -- Latin-1 编码的 °（单字节）
            seg_array[seg_idx] = 0x63  -- ° 段码（8 的上半圈）
            seg_idx = seg_idx + 1
        else
            -- 查找字符段码，找不到则显示空格
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

    -- 填充到缓冲区并刷新（使用 GRID 映射）
    for pos = offset0, offset0 + max_len - 1 do
        local arr_idx = pos - offset0 + 1
        local grid_pos = map_grid(pos)
        if seg_array[arr_idx] ~= nil then
            g_display_buf[grid_pos] = get_seg_value(seg_array[arr_idx])
        end
    end

    flush_display()
end

--[[
轮询读取当前按下的按键编码。无按键按下时返回 nil。

16 个按键的矩阵布局：
                 KS1 KS2 KS3 KS4 KS5 KS6 KS7 KS8
         K1:     1   3   5   7   9  11  13  15
         K2:     2   4   6   8  10  12  14  16

@api exs_tm1637.get_key()

@return number or nil
有按键按下时返回按键编码 1~16，无按键按下返回 nil。
多个按键同时按下时返回编码最小的那个。

@usage
local key = exs_tm1637.get_key()
if key then
    log.info("exs_tm1637", "检测到按键:", key)
end
]]
function exs_tm1637.get_key()
    local mask = read_key_mask()

    if mask == 0 then
        return nil
    end

    -- 找到最低位的 1（编码最小的按键）
    local code = 1
    while mask ~= 0 do
        if mask & 0x01 ~= 0 then
            return code
        end
        mask = mask >> 1
        code = code + 1
    end
    return nil
end

--[[
设置按键事件回调函数。注册后库内部会每隔 50ms 自动轮询按键
状态，检测到有按键按下时调用回调函数。

@api exs_tm1637.set_key_callback(cbfunc)

参数含义：按键事件回调函数
数据类型：function
是否必选：必选
注意事项：回调函数接收一个参数 key_code（number 类型 1~16）。
传入 nil 可取消回调。回调函数中应避免长时间阻塞操作。

@return nil

@usage
-- 注册按键回调
exs_tm1637.set_key_callback(on_key)

-- 取消回调
exs_tm1637.set_key_callback(nil)
]]
function exs_tm1637.set_key_callback(cbfunc)
    g_key_callback = cbfunc

    -- 取消已有的定时器
    if g_key_timer_id then
        sys.timerStop(g_key_timer_id)
        g_key_timer_id = nil
    end

    -- 如果有回调函数，启动定时轮询（每 50ms 检查一次）
    if cbfunc then
        g_last_key_byte = read_key_mask()  -- 清除初始状态
        g_key_timer_id = sys.timerLoopStart(key_scan_timer_func, 50)
    end
end

--[[
获取 exs_tm1637 库的版本号

@api exs_tm1637.version()

@return string
版本号字符串，格式为 "yyyymmddhhmm"

@usage
local ver = exs_tm1637.version()
log.info("exs_tm1637", "版本号:", ver)
]]
function exs_tm1637.version()
    return "202607131200"
end

log.debug("exs_tm1637", "version -> " .. exs_tm1637.version())

return exs_tm1637
