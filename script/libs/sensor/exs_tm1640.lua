--[[
@module  exs_tm1640
@summary TM1640 LED 驱动扩展库（8段×16位，无按键）
@version 1.0
@date    2026.07.13
@author  江访
@usage
本文件为 TM1640 LED 驱动芯片的 LuatOS 扩展库，核心功能为：
1、初始化 TM1640，配置 CLK/DIN 二线通信引脚
2、16 位 8 段数码管显示（支持共阴/共阳切换）
3、8 级亮度调节

注意：TM1640 仅支持输出模式（DIN 为单向数据输出引脚），
不支持按键扫描功能，与 TM1638/TM1639 不同。

本文件的对外接口有 5 个：
1、exs_tm1640.setup(config)：初始化 TM1640
2、exs_tm1640.set_brightness(level)：设置亮度
3、exs_tm1640.clear()：清空显示
4、exs_tm1640.set_display(str, offset)：数码管显示字符串
5、exs_tm1640.version()：获取版本号

-- 版本更新说明
-- 版本号：202607131200
-- 1、更新时间：2026-07-13 12:00
-- 2、更新内容
  - 首次发布，实现 TM1640 基础驱动功能
  - 支持数码管显示（8 段 ×16 位）
  - 支持 8 级亮度调节
  - 支持共阴/共阳数码管切换
]]

local exs_tm1640 = {}

-- ==================== 模块常量 ====================

-- TM1640 命令常量
-- 数据命令：设置数据传输模式
local CMD_DATA_AUTO    = 0x40  -- 数据命令：自动地址增加，写显示
local CMD_DATA_FIXED   = 0x44  -- 数据命令：固定地址，写显示
local CMD_ADDR_BASE    = 0xC0  -- 地址命令基址（C0H~CFH共16个地址）
local CMD_DISPLAY_OFF  = 0x80  -- 显示控制：关闭显示
local CMD_DISPLAY_ON   = 0x88  -- 显示控制：开启显示基值（+亮度0~7）

-- 最大支持参数
local MAX_DIGITS = 16  -- 最大数码管位数

-- ==================== 内部状态 ====================

-- GPIO 引脚编号
local g_clk_pin = nil  -- CLK 时钟引脚
local g_din_pin = nil  -- DIN 数据引脚（输出模式，无输入功能）

-- 配置参数
local g_common_anode = false  -- 是否共阳数码管
local g_current_bright = 3    -- 当前亮度 0~7
local g_grid_map = nil        -- GRID物理位置映射表，16 个元素的数组
local g_write_mode = "fixed"  -- 显存写入模式："fixed"(固定地址) 或 "auto"(自动递增)

-- 显示缓冲区（16字节，对应C0H~CFH地址）
-- 每个地址存储一个 GRID 的 SEG1~SEG8 段数据
local g_display_buf = {}

-- ==================== GPIO 底层操作 ====================

-- CLK 时钟线控制
local function clk_low()
    gpio.set(g_clk_pin, 0)
end

local function clk_high()
    gpio.set(g_clk_pin, 1)
end

-- DIN 数据线控制（仅输出模式）
local function din_high()
    gpio.set(g_din_pin, 1)
end

local function din_low()
    gpio.set(g_din_pin, 0)
end

-- ==================== 通信协议层 ====================

-- TM1640 起始条件：CLK=H, DIN=H→L
local function send_start()
    clk_high()
    din_high()
    din_low()
    clk_low()
end

-- TM1640 结束条件：CLK=H, DIN=L→H
local function send_stop()
    clk_low()
    din_low()
    clk_high()
    din_high()
end

-- 发送 1 个字节（低位先发，LSB first）
-- TM1640 在 CLK 上升沿读取 DIN 数据，数据输入总是低位在前
-- 无显式延时，靠 gpio.set() 自身执行时间满足 TM1640 时序
-- @number data 要发送的字节
local function send_byte(data)
    for i = 0, 7 do
        clk_low()
        if data & 0x01 ~= 0 then
            din_high()
        else
            din_low()
        end
        clk_high()
        data = data >> 1
    end
end

-- 发送命令（起始→命令→停止）
-- @number cmd 命令字节
local function write_command(cmd)
    send_start()
    send_byte(cmd)
    send_stop()
end

-- 使用自动递增模式批量写入显存数据
-- 帧1: start → 40H → stop  (设置数据命令为自动递增)
-- 帧2: start → C0|start_addr → data[1]~data[n] → stop (批量写入)
-- TM1640 共 16 个地址（0xC0~0xCF），自动模式无需分段写
-- @number start_addr 起始地址（0x00~0x0F）
-- @table data_array 要写入的数据数组
-- @number count 写入字节数
local function write_data_auto(start_addr, data_array, count)
    local n = count or #data_array
    write_command(CMD_DATA_AUTO)
    send_start()
    send_byte(CMD_ADDR_BASE | (start_addr & 0x0F))
    for i = 1, n do
        send_byte(data_array[i])
    end
    send_stop()
end

-- 固定地址模式：写入单个字节到指定地址
-- 帧1: start → 44H → stop  (设置数据命令为固定地址)
-- 帧2: start → C0|addr → data → stop (写入数据)
-- @number addr 目标地址（0x00~0x0F）
-- @number data 要写入的字节
local function write_byte_fixed_addr(addr, data)
    write_command(CMD_DATA_FIXED)
    send_start()
    send_byte(CMD_ADDR_BASE | (addr & 0x0F))     -- 目标地址
    send_byte(data)
    send_stop()
end

-- 向 TM1640 写入显示控制命令（开关显示 + 亮度）
-- @number bright 亮度 0~7
-- @boolean display_on 是否开启显示
local function write_display_control(bright, display_on)
    send_start()
    if display_on then
        send_byte(CMD_DISPLAY_ON | (bright & 0x07))
    else
        send_byte(CMD_DISPLAY_OFF)
    end
    send_stop()
end

-- ==================== 缓冲区管理 ====================

-- 固定地址模式全量刷新（逐个写入 16 字节）
local function fixed_flush_display()
    for addr = 0x00, 0x0F do
        local data = g_display_buf[addr] or 0x00
        write_byte_fixed_addr(addr, data)
    end
end

-- 自动递增模式全量刷新（一次批量写入全部 16 字节）
local function auto_flush_display()
    local buf = {}
    for i = 0, 15 do
        buf[i + 1] = g_display_buf[i] or 0x00
    end
    write_data_auto(0x00, buf, 16)
end

-- 刷新显示缓冲区到 TM1640 硬件
-- 根据 g_write_mode 选择写入模式：
--   "fixed" - 固定地址模式：逐个写入全部 16 字节 × 2 帧/字节，可靠但慢
--   "auto"  - 自动递增：40H→C0H→[16字节]，共 2 帧
local function flush_display()
    if g_write_mode == "auto" then
        auto_flush_display()
    else
        fixed_flush_display()
    end
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

-- ==================== 外部 API ====================

--[[
初始化 TM1640 LED 驱动芯片，配置通信引脚和初始参数

@api exs_tm1640.setup(config)

@table config
初始化配置表，包含以下键：

clk
CLK 时钟引脚 GPIO 编号，接 TM1640 CLK 引脚；
数据类型：number
是否必选：必选

din
DIN 数据引脚 GPIO 编号，接 TM1640 DIN 引脚；
TM1640 的 DIN 为单向输出引脚，无需上拉电阻；
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
GRID 物理位置映射表，16 个元素的数组；
默认 nil（不映射）。可通过 setup() 适配 PCB 走线。设置 "123456789ABCDEF0" 若显示为
"0FEDCBA987654321"，说明顺序完全相反，填入 {16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1}
即可修正
数据类型：table
是否必选：可选

write_mode
显存写入模式，可选 "fixed"（固定地址）或 "auto"（自动递增）；
默认 "fixed"。
- "fixed"：固定地址模式，每字节独立帧，共 32 帧/次刷新，兼容性最好，调试阶段推荐
- "auto"：自动递增批量写 16 字节，共 2 帧/次刷新，效率更高，稳定后推荐
数据类型：string
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 基础初始化
local result = exs_tm1640.setup({
    clk    = 27,
    din    = 26,
    bright = 3,
})

-- 共阳数码管初始化
local result = exs_tm1640.setup({
    clk          = 27,
    din          = 26,
    bright       = 3,
    common_anode = true,
})
]]
function exs_tm1640.setup(config)
    -- 参数检查
    if type(config) ~= "table" then
        log.error("exs_tm1640.setup 参数错误：config 应为 table 类型")
        return false
    end
    if not config.clk or not config.din then
        log.error("exs_tm1640.setup 参数错误：clk、din 均为必填")
        return false
    end

    -- 保存引脚编号
    g_clk_pin = config.clk
    g_din_pin = config.din
    g_common_anode = config.common_anode or false
    g_current_bright = config.bright or 3
    if g_current_bright > 7 then g_current_bright = 7 end
    if g_current_bright < 0 then g_current_bright = 0 end
    g_grid_map = config.grid_map or nil
    g_write_mode = config.write_mode or "fixed"

    -- 初始化 GPIO（均为输出模式）
    gpio.setup(g_clk_pin, 0)
    gpio.setup(g_din_pin, 0)
    clk_high()
    din_high()

    -- 初始化内部缓冲区
    for i = 0, 15 do
        g_display_buf[i] = 0x00
    end

    -- 初始化流程：
    -- 1) 显示控制：0x8B (开显示 + 亮度 3)
    -- 2) 清空 16 字节显存
    -- 3) 根据传入亮度重新设置
    write_display_control(g_current_bright, true)
    if g_write_mode == "auto" then
        local zero = {}
        for i = 1, 16 do zero[i] = 0x00 end
        write_data_auto(0x00, zero, 16)
    else
        for addr = 0x00, 0x0F do
            write_byte_fixed_addr(addr, 0x00)
        end
    end
    write_display_control(g_current_bright, true)

    log.info("exs_tm1640", string.format("初始化完成, clk=%d din=%d 亮度=%d",
        g_clk_pin, g_din_pin, g_current_bright))

    return true
end

--[[
设置显示亮度（8级辉度调节）

@api exs_tm1640.set_brightness(level)

参数含义：亮度等级
数据类型：number
取值范围：0~7，0最暗 7最亮
是否必选：必选
注意事项：调用此接口会自动开启显示

@return nil

@usage
-- 设置最亮
exs_tm1640.set_brightness(7)
-- 设置中等亮度
exs_tm1640.set_brightness(3)
]]
function exs_tm1640.set_brightness(level)
    level = level or 3
    if level < 0 then level = 0 end
    if level > 7 then level = 7 end
    g_current_bright = level
    write_display_control(g_current_bright, true)
end

--[[
清空所有显示

向 16 个显示地址（C0H~CFH）全部写入 0x00

@api exs_tm1640.clear()

@return nil

@usage
exs_tm1640.clear()
]]
function exs_tm1640.clear()
    -- 清空缓冲区
    for i = 0, 15 do
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
-- 定义常用字母、数字和特殊符号的 8 段映射（a~g+dp）
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
    ["\xB0"] = 0x63,  -- ° 的 Latin-1 单字节编码，段码=8的上半圈，用于 "25°C" 温度显示
}

--[[
从指定起始位置开始显示字符串，自动查段码表

@api exs_tm1640.set_display(str, offset)

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
取值范围：1~16（1 对应第 1 位数码管，16 对应第 16 位数码管）
是否必选：可选
注意事项：默认 1。超出范围时超出部分不显示。

@return nil

@usage
exs_tm1640.set_display("12345678")
exs_tm1640.set_display("88.88")
exs_tm1640.set_display("1234", 3)
]]
function exs_tm1640.set_display(str, offset)
    if type(str) ~= "string" or #str == 0 then
        log.error("exs_tm1640.set_display 参数错误：str 应为非空字符串")
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
    -- TM1640 每个地址对应一个 GRID，地址连续存放
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
获取 exs_tm1640 库的版本号

@api exs_tm1640.version()

@return string
版本号字符串，格式为 "yyyymmddhhmm"

@usage
local ver = exs_tm1640.version()
log.info("exs_tm1640", "版本号:", ver)
]]
function exs_tm1640.version()
    return "202607131200"
end

log.debug("exs_tm1640", "version -> " .. exs_tm1640.version())

return exs_tm1640
