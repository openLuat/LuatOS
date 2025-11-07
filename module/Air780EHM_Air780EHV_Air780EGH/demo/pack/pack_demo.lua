--[[
@summary pack API演示脚本
@version 1.0
@date    2025.10.27
@author  陈媛媛
@usage
本脚本演示pack.pack和pack.unpack API的各种用法：
1、大小端编码演示：使用'<'和'>'格式符进行小端和大端编码
2、多种数据类型打包：打包short、int、float等多种数据类型
3、字符串格式演示：'a'格式（带长度前缀）和'z'格式（以null结尾）的字符串打包和解包
4、An格式演示：An格式（如A2、A5）的打包行为，即打包前n个字符串参数
5、指定位置解包：从指定位置开始解包数据
6、复杂数据组合：打包和解包复杂的数据结构，包括整数、字符串和短整数
7、边界情况测试：空数据打包和解包，以及数值边界测试
]]

-- 初始化函数
local function init()
    log.info("pack_demo", "脚本初始化完成")
end

-- 大小端编码演示
local function demo_endian()
    log.info("\n--- 实验1：大小端编码 ---")
    
    -- 小端编码
    local data_le = pack.pack("<I", 0xAABBCCDD)
    log.info("小端编码:", data_le:toHex())
    
    -- 大端编码  
    local data_be = pack.pack(">I", 0xAABBCCDD)
    log.info("大端编码:", data_be:toHex())
    
    -- 解包验证
    local _, val_le = pack.unpack(data_le, "<I")
    local _, val_be = pack.unpack(data_be, ">I")
    log.info("解包验证 - 小端:", string.format("0x%08X", val_le))
    log.info("解包验证 - 大端:", string.format("0x%08X", val_be))
end

-- 多种数据类型打包演示
local function demo_mixed_types()
    log.info("\n--- 实验2：多种数据类型打包 ---")
    
    -- 打包多个不同类型数据
    local mixed_data = pack.pack("<hIf", 123, 456789, 3.14)
    log.info("混合数据打包:", mixed_data:toHex())
    
    -- 解包混合数据
    local _, short_val, int_val, float_val = pack.unpack(mixed_data, "<hIf")
    log.info("解包混合数据:", short_val, int_val, float_val)
end

-- 字符串格式演示
local function demo_string_formats()
    log.info("\n--- 实验3：字符串格式演示 ---")
    
    -- 'a' 格式 - 带长度前缀的字符串
    local str_data_a = pack.pack('a', "LuatOS")
    log.info("'a'格式字符串:", str_data_a:toHex())
    
    -- 解包a格式
    local _, str_a = pack.unpack(str_data_a, 'a')
    log.info("'a'格式解包:", str_a)
    
    -- 'z' 格式 - 以null结尾的字符串
    local str_data_z = pack.pack('z', "LuatOS")
    log.info("'z'格式字符串:", str_data_z:toHex())
    
    -- 解包z格式
    local _, str_z = pack.unpack(str_data_z, 'z')
    log.info("'z'格式解包:", str_z)
end

-- An格式演示
local function demo_An_format()
    log.info("\n--- 实验4：'An'格式演示 ---")
    
    -- 'A' 格式 - 打包第一个参数的整个字符串
    local str_data_A = pack.pack('A', "hezhou", "LuatOS")
    log.info("'A'格式打包:", str_data_A:toHex())
    log.info("'A'格式结果:", str_data_A)
    
    -- 'A5' 格式 - 打包前5个字符串参数
    local str_data_A5 = pack.pack('A5', "he", "zhou", "LuatOS", "!", "!")
    log.info("'A5'格式打包:", str_data_A5:toHex())
    log.info("'A5'格式结果:", str_data_A5)
end

-- 指定位置解包演示
local function demo_position_unpack()
    log.info("\n--- 实验5：指定位置解包 ---")
    
    -- 打包多个数据
    local multi_data = pack.pack("<hIh", 100, 200, 300)
    log.info("多数据打包:", multi_data:toHex())
    
    -- 从指定位置开始解包
    local pos, val1 = pack.unpack(multi_data, "<h", 1)  -- 从位置1开始解包
    local pos, val2 = pack.unpack(multi_data, "<I", pos) -- 从上次结束位置开始
    local pos, val3 = pack.unpack(multi_data, "<h", pos) -- 继续解包
    log.info("分步解包结果:", val1, val2, val3)
end

-- 复杂数据组合演示
local function demo_complex_data()
    log.info("\n--- 实验6：复杂数据组合 ---")
    
    -- 打包复杂数据结构
    local complex_data = pack.pack(">H a h", 0x1234, "Test", -50)
    log.info("复杂数据打包:", complex_data:toHex())
    
    -- 解包复杂数据
    local _, header, text, value = pack.unpack(complex_data, ">H a h")
    log.info("复杂数据解包:", string.format("0x%04X", header), text, value)
end

-- 边界情况演示
local function demo_edge_cases()
    log.info("\n--- 实验7：边界情况 ---")
    
    -- 打包空数据
    local empty_data = pack.pack("")
    log.info("空格式打包:", empty_data:toHex())
    
    -- 解包空数据
    local pos_empty = pack.unpack("", "")
    log.info("空格式解包位置:", pos_empty)
    
    -- 数值边界测试
    local max_short = pack.pack("<h", 32767)
    local min_short = pack.pack("<h", -32768)
    log.info("短整型边界 - 最大值:", max_short:toHex())
    log.info("短整型边界 - 最小值:", min_short:toHex())
    
    local _, max_val = pack.unpack(max_short, "<h")
    local _, min_val = pack.unpack(min_short, "<h")
    log.info("边界值验证:", max_val, min_val)
end

-- 运行所有演示
local function run_all_demos()
    log.info("=== pack.pack 和 pack.unpack API 演示开始 ===")
    
    init()
    demo_endian()
    demo_mixed_types()
    demo_string_formats()
    demo_An_format()
    demo_position_unpack()
    demo_complex_data()
    demo_edge_cases()
    
    log.info("=== pack API 演示完成 ===")
end

-- 主任务函数
local function main()
    log.info("pack_demo", "开始运行pack API演示")
    run_all_demos()
    log.info("pack_demo", "演示运行完毕")
end

-- 启动演示任务
sys.taskInit(main)