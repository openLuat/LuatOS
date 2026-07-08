--[[
@module  exs_tm1638
@summary TM1638 数码管驱动扩展库（10段×8位 + 24个按键 + 8颗LED）
@version 1.0
@date    2026.07.07
@author  江访
@usage
本文件为 TM1638 驱动芯片的 LuatOS 扩展库，核心功能为：
1、初始化 TM1638，配置 CLK/DIO/STB 三线通信引脚
2、8 位 10 段数码管显示（支持共阴/共阳切换）
3、8 颗独立 LED 指示灯控制
4、24 个按键扫描检测（轮询和回调两种方式）
5、8 级亮度调节

本文件的对外接口有 9 个：
1、exs_tm1638.init(config)：初始化 TM1638
2、exs_tm1638.set_brightness(level)：设置亮度
3、exs_tm1638.clear()：清空显示和LED
4、exs_tm1638.set_display(str, offset)：数码管显示字符串
5、exs_tm1638.set_led(state, pos)：控制LED指示灯（单个或批量）
6、exs_tm1638.get_key()：轮询读取按键
7、exs_tm1638.set_key_callback(cbfunc)：设置按键回调
8、exs_tm1638.version()：获取版本号

-- 版本更新说明
-- 版本号：202607071200
-- 1、更新时间：2026-07-07 12:00
-- 2、更新内容
  - 首次发布，实现 TM1638 基础驱动功能
  - 支持数码管显示（10 段 ×8 位）
  - 支持 LED 指示灯独立控制
  - 支持按键扫描（轮询 + 回调两种方式）
  - 支持 8 级亮度调节
  - 支持共阴/共阳数码管切换
]]

local exs_tm1638 = {}

-- ==================== 模块常量 ====================

-- TM1638 命令常量
local CMD_DATA_AUTO    = 0x40  -- 数据命令：自动地址增加，写显示
local CMD_DATA_FIXED   = 0x44  -- 数据命令：固定地址，写显示
local CMD_READ_KEY     = 0x42  -- 数据命令：读按键
local CMD_ADDR_BASE    = 0xC0  -- 地址命令基址（C0H~CFH共16个地址）
local CMD_DISPLAY_OFF  = 0x80  -- 显示控制：关闭显示
local CMD_DISPLAY_ON   = 0x88  -- 显示控制：开启显示基值（+亮度0~7）

-- 最大支持参数
local MAX_DIGITS = 8   -- 最大数码管位数
local MAX_LEDS   = 8   -- 最大LED数
local MAX_KEYS   = 24  -- 最大按键数

-- ==================== 内部状态 ====================

-- GPIO 引脚编号
local g_clk_pin = nil  -- CLK 引脚
local g_dio_pin = nil  -- DIO 数据引脚
local g_stb_pin = nil  -- STB 片选引脚

-- 配置参数
local g_common_anode = false  -- 是否共阳数码管
local g_current_bright = 3    -- 当前亮度 0~7
local g_grid_map = nil        -- GRID物理位置映射表，如{6,5,8,7,2,1,4,3}
local g_write_mode = "fixed"  -- 显存写入模式："fixed"(固定地址) 或 "auto"(自动递增)

-- 显示缓冲区（16字节，对应C0H~CFH地址）
-- 偶数下标 = SEG1~SEG8段数据，奇数下标 = SEG9~SEG10数据
local g_display_buf = {}

-- LED状态表（8个LED，true=亮 false=灭）
local g_led_state = {}

-- 按键相关
local g_key_callback = nil    -- 按键回调函数
local g_last_key_mask = 0     -- 上一次按键掩码，用于检测变化
local g_key_timer_id = nil    -- 按键轮询定时器ID

-- ==================== GPIO 底层操作 ====================

-- CLK 时钟线控制
local function clk_low()
    gpio.set(g_clk_pin, 0)
end

local function clk_high()
    gpio.set(g_clk_pin, 1)
end

-- STB 片选线控制
local function stb_low()
    gpio.set(g_stb_pin, 0)
end

local function stb_high()
    gpio.set(g_stb_pin, 1)
end

-- DIO 数据线控制
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

-- 发送 1 个字节（低位先发）
-- TM1638 在 CLK 上升沿读取 DIO 数据
-- 无显式延时，靠 gpio.set() 自身执行时间满足 TM1638 时序（≥1MHz 可工作）
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

-- 接收 1 个字节（低位先出）
-- TM1638 在 CLK 下降沿输出数据到 DIO，我们在 CLK 上升沿读取
-- @return number 读到的字节
local function recv_byte()
    local data = 0
    for i = 0, 7 do
        clk_low()
        clk_high()
        if dio_read() ~= 0 then
            data = data | (1 << i)
        end
    end
    return data
end

-- 发送命令（STB↓ → 1字节 → STB↑）
-- @number cmd 命令字节
local function write_command(cmd)
    dio_set_output()
    stb_low()
    send_byte(cmd)
    stb_high()
end

-- 使用自动递增模式批量写入显存数据
-- 帧1: STB↓→40H→STB↑  (设置数据命令为自动递增)
-- 帧2: STB↓→C0|start_addr→data[1]~data[n]→STB↑ (批量写入)
-- 注意：该方法最多传输 14 字节（手册第 10.1 节），用于全量刷新时需配合固定地址补写后 2 字节
-- @number start_addr 起始地址（0x00~0x0F）
-- @table data_array 要写入的数据数组
-- @number count 写入字节数
local function write_data_auto(start_addr, data_array, count)
    local n = count or #data_array
    write_command(CMD_DATA_AUTO)
    dio_set_output()
    stb_low()
    send_byte(CMD_ADDR_BASE | (start_addr & 0x0F))
    for i = 1, n do
        send_byte(data_array[i])
    end
    stb_high()
end

-- 注意：0x44 命令必须单独一帧，不能与地址数据放在同一 STB 帧内
-- 帧1: STB↓ → 44H → STB↑   (设置数据命令为固定地址)
-- 帧2: STB↓ → C0|addr → data → STB↑  (写入数据)
-- @number addr 目标地址（0x00~0x0F）
-- @number data 要写入的字节
local function write_byte_fixed_addr(addr, data)
    write_command(CMD_DATA_FIXED)
    dio_set_output()
    stb_low()
    send_byte(CMD_ADDR_BASE | (addr & 0x0F))     -- 目标地址
    send_byte(data)
    stb_high()
end

-- 向 TM1638 写入显示控制命令（开关显示 + 亮度）
-- @number bright 亮度 0~7
-- @boolean display_on 是否开启显示
local function write_display_control(bright, display_on)
    dio_set_output()
    stb_low()
    if display_on then
        send_byte(CMD_DISPLAY_ON | (bright & 0x07))
    else
        send_byte(CMD_DISPLAY_OFF)
    end
    stb_high()
end

-- ==================== 缓冲区管理 ====================

-- 固定地址模式全量刷新（逐个写入 16 字节）
local function fixed_flush_display()
    for addr = 0x00, 0x0F do
        local data = g_display_buf[addr] or 0x00
        write_byte_fixed_addr(addr, data)
    end
end

-- 自动递增模式全量刷新（14 字节批量 + 2 字节补写）
local function auto_flush_display()
    local buf14 = {}
    for i = 0, 13 do
        buf14[i + 1] = g_display_buf[i] or 0x00
    end
    write_data_auto(0x00, buf14, 14)
    write_byte_fixed_addr(0x0E, g_display_buf[14] or 0x00)
    write_byte_fixed_addr(0x0F, g_display_buf[15] or 0x00)
end

-- 刷新显示缓冲区到 TM1638 硬件
-- 根据 g_write_mode 选择写入模式：
--   "fixed" - 固定地址模式：逐个写入全部 16 字节 × 2 帧/字节，可靠但慢
--   "auto"  - 自动递增 + 固定地址补写：40H→C0H→[14字节] + 44H→0EH→[1] + 44H→0FH→[1]
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

-- 更新 LED 状态到显示缓冲区
-- LED 使用 GRID 高字节的 bit0（对应 SEG9）
-- 即地址 C0+pos*2+1 的 bit0。注意：使用 grid_map 映射物理 GRID 顺序
local function update_led_buf()
    for pos = 0, MAX_LEDS - 1 do
        local grid_pos = map_grid(pos)
        local high_addr_idx = grid_pos * 2 + 1  -- 奇数为高字节
        local val = g_display_buf[high_addr_idx] or 0x00
        if g_led_state[pos] then
            g_display_buf[high_addr_idx] = val | 0x01  -- 点亮LED
        else
            g_display_buf[high_addr_idx] = val & 0xFE  -- 熄灭LED
        end
    end
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

-- 读取按键数据，返回 24 位的按键掩码
-- bit0=按键1, bit1=按键2, ..., bit23=按键24
-- @return number 24位按键掩码
local function read_key_mask()
    local key_bytes = {}

    -- 发送读键命令 0x42
    dio_set_output()
    stb_low()
    send_byte(CMD_READ_KEY)

    -- 切换 DIO 为输入模式
    dio_set_input()

    -- 读取 4 个字节的按键数据
    for i = 1, 4 do
        key_bytes[i] = recv_byte()
    end
    stb_high()

    -- 解析按键数据为 24 位掩码
    -- 每字节包含 2 个 KS 列的低/高半字节
    -- 低半字节（bit0~2）：K3,K2,K1 用于奇数KS列
    -- 高半字节（bit4~6）：K3,K2,K1 用于偶数KS列
    local mask = 0
    for col = 0, 7 do
        local byte_idx = math.floor(col / 2) + 1  -- 1~4
        local nibble_shift = (col % 2) * 4         -- 0 或 4
        local byte_val = key_bytes[byte_idx]
        local nibble = (byte_val >> nibble_shift) & 0x07  -- 取出低3位

        -- nibble bit0=K3, bit1=K2, bit2=K1
        if nibble & 0x04 ~= 0 then  -- K1 (bit2)
            mask = mask | (1 << (col + 0))   -- 按键编码 1~8
        end
        if nibble & 0x02 ~= 0 then  -- K2 (bit1)
            mask = mask | (1 << (col + 8))   -- 按键编码 9~16
        end
        if nibble & 0x01 ~= 0 then  -- K3 (bit0)
            mask = mask | (1 << (col + 16))  -- 按键编码 17~24
        end
    end

    return mask
end

-- 按键轮询处理函数（由定时器调用）
local function key_scan_timer_func()
    local current_mask = read_key_mask()

    -- 检测按键状态变化（从松开→按下）
    local pressed = current_mask & (~g_last_key_mask)

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

    g_last_key_mask = current_mask
end

-- ==================== 外部 API ====================

--[[
初始化 TM1638 驱动芯片，配置通信引脚和初始参数

@api exs_tm1638.init(config)

@table config
初始化配置表，包含以下键：

clk
CLK 时钟引脚 GPIO 编号，接 TM1638 第 27 脚；
数据类型：number
是否必选：必选

dio
DIO 数据引脚 GPIO 编号，接 TM1638 第 26 脚；
需要外接 4.7kΩ~10kΩ 上拉电阻到 VCC；
数据类型：number
是否必选：必选

stb
STB 片选引脚 GPIO 编号，接 TM1638 第 28 脚；
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
GRID 物理位置映射表，8 个元素的数组；
默认 nil（不映射）。可通过 init() 适配 PCB 走线。设置 "12345678" 若显示为 "87654321"，说明顺序完全相反，填入 {8,7,6,5,4,3,2,1} 即可修正
数据类型：table
是否必选：可选

write_mode
显存写入模式，可选 "fixed"（固定地址）或 "auto"（自动递增）；
默认 "fixed"。
- "fixed"：固定地址模式，每字节独立 STB 帧，共 32 帧/次刷新，兼容性最好，调试阶段推荐
- "auto"：自动递增批量写 14 字节 + 固定地址补写 2 字节，共 4 帧/次刷新，效率更高，稳定后推荐
数据类型：string
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 基础初始化
local result = exs_tm1638.init({
    clk    = 27,
    dio    = 26,
    stb    = 28,
    bright = 3,
})

-- 共阳数码管初始化
local result = exs_tm1638.init({
    clk          = 27,
    dio          = 26,
    stb          = 28,
    bright       = 3,
    common_anode = true,
})
]]
function exs_tm1638.init(config)
    -- 参数检查
    if type(config) ~= "table" then
        log.error("exs_tm1638.init 参数错误：config 应为 table 类型")
        return false
    end
    if not config.clk or not config.dio or not config.stb then
        log.error("exs_tm1638.init 参数错误：clk、dio、stb 均为必填")
        return false
    end

    -- 保存引脚编号
    g_clk_pin = config.clk
    g_dio_pin = config.dio
    g_stb_pin = config.stb
    g_common_anode = config.common_anode or false
    g_current_bright = config.bright or 3
    if g_current_bright > 7 then g_current_bright = 7 end
    if g_current_bright < 0 then g_current_bright = 0 end
    g_grid_map = config.grid_map or nil
    g_write_mode = config.write_mode or "fixed"

    -- 初始化 GPIO
    gpio.setup(g_clk_pin, 0)
    gpio.setup(g_stb_pin, 1)
    dio_set_output()
    clk_high()
    stb_high()

    -- 初始化内部缓冲区
    for i = 0, 15 do
        g_display_buf[i] = 0x00
    end
    for i = 0, MAX_LEDS - 1 do
        g_led_state[i] = false
    end
    g_last_key_mask = 0

    -- 与 C51 参考代码一致的初始化流程：
    -- 1) 显示控制：0x8B (开显示 + 亮度 3)
    -- 2) 清空 16 字节显存
    -- 3) 根据传入亮度重新设置
    write_display_control(g_current_bright, true)
    if g_write_mode == "auto" then
        local zero14 = {}
        for i = 1, 14 do zero14[i] = 0x00 end
        write_data_auto(0x00, zero14, 14)
        write_byte_fixed_addr(0x0E, 0x00)
        write_byte_fixed_addr(0x0F, 0x00)
    else
        for addr = 0x00, 0x0F do
            write_byte_fixed_addr(addr, 0x00)
        end
    end
    write_display_control(g_current_bright, true)

    log.info("exs_tm1638", string.format("初始化完成, clk=%d dio=%d stb=%d 亮度=%d",
        g_clk_pin, g_dio_pin, g_stb_pin, g_current_bright))

    return true
end

--[[
设置显示亮度（8级辉度调节）

@api exs_tm1638.set_brightness(level)

参数含义：亮度等级
数据类型：number
取值范围：0~7，0最暗 7最亮
是否必选：必选
注意事项：调用此接口会自动开启显示

@return nil

@usage
-- 设置最亮
exs_tm1638.set_brightness(7)
-- 设置中等亮度
exs_tm1638.set_brightness(3)
]]
function exs_tm1638.set_brightness(level)
    level = level or 3
    if level < 0 then level = 0 end
    if level > 7 then level = 7 end
    g_current_bright = level
    write_display_control(g_current_bright, true)
end

--[[
清空所有显示和 LED 指示灯

向 16 个显示地址（C0H~CFH）全部写入 0x00，同时熄灭所有 LED

@api exs_tm1638.clear()

@return nil

@usage
exs_tm1638.clear()
]]
function exs_tm1638.clear()
    -- 清空缓冲区
    for i = 0, 15 do
        g_display_buf[i] = 0x00
    end
    for i = 0, MAX_LEDS - 1 do
        g_led_state[i] = false
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
-- TM1638 有 10 段（SEG1~SEG10），标准段码只用到 SEG1~SEG8（a~g+dp）
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
    ["o"] = 0x5C,  -- 小写o（与0区分）
    -- 温度符号：用两个字符拼接表示 "°"
    -- 段码 0x63 = 8 的上半圈（0x7F 去掉 g 段 bit6），用于显示 °C/°F
    -- 注意：set_display 中用户直接传 ASCII 字符，° 是双字节 UTF-8
    -- 简便方法：用 "o" 替代 °，或直接用 "." 小数点附加在前一个数字上
    -- 扩展库内部对特殊符号的支持通过以下映射：
    ["\xB0"] = 0x63,  -- ° 的 Latin-1 单字节编码，段码=8的上半圈，用于 "25°C" 温度显示
}

--[[
从指定起始位置开始显示字符串，自动查段码表

@api exs_tm1638.set_display(str, offset)

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
取值范围：1~8（1 对应第 1 位数码管，8 对应第 8 位数码管）
是否必选：可选
注意事项：默认 1。超出范围时超出部分不显示。

@return nil

@usage
exs_tm1638.set_display("12345678")
exs_tm1638.set_display("88.88")
exs_tm1638.set_display("1234", 3)
]]
function exs_tm1638.set_display(str, offset)
    if type(str) ~= "string" or #str == 0 then
        log.error("exs_tm1638.set_display 参数错误：str 应为非空字符串")
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
        local idx = grid_pos * 2
        if seg_array[arr_idx] ~= nil then
            g_display_buf[idx] = get_seg_value(seg_array[arr_idx])
        end
    end

    flush_display()
end

--[[
控制 LED 指示灯的亮灭。支持单个控制和批量设置两种模式。

单个控制：传入 LED 状态（boolean）和位置（number）。
批量设置：传入 8 个 LED 状态的数组（table）。

@api exs_tm1638.set_led(state, pos)

state
参数含义：LED 状态（单个控制模式），或 8 颗 LED 的状态数组（批量设置模式）
数据类型：boolean | table
取值范围：
  单个控制模式：true（亮）, false（灭）
  批量设置模式：包含 8 个 boolean 值的数组，true=亮，false=灭，nil 值表示该位保持不变
是否必选：是
参数示例（单个）：true
参数示例（批量）：{true, false, true, false, true, false, true, false}

pos
参数含义：LED 指示灯位置（仅单个控制模式使用）
数据类型：number
取值范围：1~8（1 对应第 1 颗 LED 指示灯，8 对应第 8 颗 LED 指示灯）
是否必选：单个控制模式为是，批量设置模式无此参数
参数示例：3

@return nil

@usage
-- 单个控制
exs_tm1638.set_led(true, 1)   -- 点亮第 1 颗 LED 指示灯
exs_tm1638.set_led(false, 5)  -- 熄灭第 5 颗 LED 指示灯

-- 批量设置（全部 8 颗 LED）
exs_tm1638.set_led({true, false, true, false, true, false, true, false})
]]
function exs_tm1638.set_led(state, pos)
    -- 批量设置模式：state 为数组
    if type(state) == "table" then
        local led_array = state
        for p = 0, MAX_LEDS - 1 do
            if led_array[p + 1] ~= nil then
                g_led_state[p] = led_array[p + 1] == true
            end
        end
        update_led_buf()
        flush_display()
        return
    end

    -- 单个控制模式：pos 为 1~8，转换为 0-based 内部索引
    local idx = pos - 1
    if idx < 0 or idx >= MAX_LEDS then
        log.error("exs_tm1638.set_led 参数错误：pos 超出范围 1~8")
        return
    end

    g_led_state[idx] = state == true
    update_led_buf()

    -- 刷新该 LED 对应的高字节（使用 GRID 物理映射）
    local grid_pos = map_grid(idx)
    local high_idx = grid_pos * 2 + 1
    write_command(CMD_DATA_FIXED)
    dio_set_output()
    stb_low()
    send_byte(CMD_ADDR_BASE + high_idx)       -- 目标地址
    send_byte(g_display_buf[high_idx])
    stb_high()
end

--[[
轮询读取当前按下的按键编码。无按键按下时返回 nil。

24 个按键的排列就像电影院座位：
                 KS1 KS2 KS3 KS4 KS5 KS6 KS7 KS8
        第1排K1:  1   2   3   4   5   6   7   8
        第2排K2:  9  10  11  12  13  14  15  16
        第3排K3: 17  18  19  20  21  22  23  24

@api exs_tm1638.get_key()

@return number or nil
有按键按下时返回按键编码 1~24，无按键按下返回 nil。
多个按键同时按下时返回编码最小的那个。

@usage
local key = exs_tm1638.get_key()
if key then
    log.info("exs_tm1638", "检测到按键:", key)
end
]]
function exs_tm1638.get_key()
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

@api exs_tm1638.set_key_callback(cbfunc)

参数含义：按键事件回调函数
数据类型：function
是否必选：必选
注意事项：回调函数接收一个参数 key_code（number 类型 1~24）。
传入 nil 可取消回调。回调函数中应避免长时间阻塞操作。

@return nil

@usage
-- 注册按键回调
exs_tm1638.set_key_callback(on_key)

-- 取消回调
exs_tm1638.set_key_callback(nil)
]]
function exs_tm1638.set_key_callback(cbfunc)
    g_key_callback = cbfunc

    -- 取消已有的定时器
    if g_key_timer_id then
        sys.timerStop(g_key_timer_id)
        g_key_timer_id = nil
    end

    -- 如果有回调函数，启动定时轮询（每 50ms 检查一次）
    if cbfunc then
        g_last_key_mask = read_key_mask()  -- 清除初始状态
        g_key_timer_id = sys.timerLoopStart(key_scan_timer_func, 50)
    end
end

--[[
获取 exs_tm1638 库的版本号

@api exs_tm1638.version()

@return string
版本号字符串，格式为 "yyyymmddhhmm"

@usage
local ver = exs_tm1638.version()
log.info("exs_tm1638", "版本号:", ver)
]]
function exs_tm1638.version()
    return "202607071200"
end

return exs_tm1638
