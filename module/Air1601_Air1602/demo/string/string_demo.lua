--[[
@summary 字符串操作功能演示脚本
@version 1.0
@date 2025.07.16
@author 陈媛媛
@usage
本demo通过多个示例演示string核心库的主要功能：
1、十六进制编码/解码：演示字符串与十六进制格式的互相转换
2、字符串分割处理：演示使用不同分隔符进行字符串分割
3、数值转换操作：演示字符串到二进制数据的转换
4、Base64编码解码：演示Base64编码和解码功能
5、Base32编码解码：演示Base32编码和解码功能
6、字符串前后缀判断：演示字符串前缀和后缀判断功能
7、字符串裁剪处理：演示去除字符串前后空白字符的功能
]]

-- 初始化函数
local function init()
    log.info("string_demo", "字符串操作演示脚本初始化")
end

-- ====================== 十六进制转换示例 ======================
local function hex_examples()
    log.info("=== 十六进制转换示例 ===")
    
    -- 字符串转十六进制
    local original_str = "123abc"
    local hex_result, hex_length = string.toHex(original_str)
    log.info("toHex", "原始字符串:", original_str, "HEX结果:", hex_result, "长度:", hex_length)
    
    -- 带分隔符的十六进制转换
    local hex_with_space = string.toHex(original_str, " ")
    log.info("toHex", "带空格分隔:", hex_with_space)
    
    -- 十六进制转字符串
    local decoded_str = string.fromHex("313233616263")
    log.info("fromHex", "HEX字符串解码:", decoded_str)
    
    -- 二进制数据转换
    local binary_data = string.char(0x01, 0x02, 0x03, 0x04, 0x05)
    local binary_hex = string.toHex(binary_data)
    log.info("toHex", "二进制数据转HEX:", binary_hex)
end

-- ====================== 字符串分割示例 ======================
local function split_examples()
    log.info("=== 字符串分割示例 ===")
    
    -- 基本分割
    local csv_str = "123,456,789"
    local parts1 = string.split(csv_str, ",")
    log.info("split", "CSV分割结果:", #parts1, json.encode(parts1))
    
    -- 使用小数点作为分隔符
    local ip_str = "192.168.1.1"
    local ip_parts = string.split(ip_str, "%.")
    log.info("split", "IP地址分割:", #ip_parts, json.encode(ip_parts))
    
    -- 多字符分隔符
    local multi_sep = "a||b||c||d"
    local multi_parts = string.split(multi_sep, "||")
    log.info("split", "多字符分隔符:", #multi_parts, json.encode(multi_parts))
end

-- ====================== 数值转换示例 ======================
local function value_conversion_examples()
    log.info("=== 数值转换示例 ===")
    
    -- 字符串转数值编码
    local num_str = "123456"
    local binary_result, converted_chars = string.toValue(num_str)
    log.info("toValue", "原始字符串:", num_str, "转换字符数:", converted_chars)
    log.info("toValue", "二进制结果HEX:", string.toHex(binary_result))
    
    -- 包含字母的转换
    local mixed_str = "123abc"
    local mixed_result, mixed_count = string.toValue(mixed_str)
    log.info("toValue", "混合字符串转换:", mixed_str, "字符数:", mixed_count)
    log.info("toValue", "混合结果HEX:", string.toHex(mixed_result))
end

-- ====================== Base64编码示例 ======================
local function base64_examples()
    log.info("=== Base64编码示例 ===")
    
    -- Base64编码
    local plain_text = "Hello LuaOS!"
    local encoded_b64 = string.toBase64(plain_text)
    log.info("toBase64", "原文:", plain_text, "编码后:", encoded_b64)
    
    -- Base64解码
    local decoded_b64 = string.fromBase64(encoded_b64)
    log.info("fromBase64", "解码结果:", decoded_b64)
    
    -- 中文编码
    local chinese_text = "你好世界"
    local chinese_b64 = string.toBase64(chinese_text)
    log.info("toBase64", "中文原文:", chinese_text, "编码后:", chinese_b64)
end

-- ====================== Base32编码解码示例 ======================
local function base32_examples()
    log.info("=== Base32编码解码示例 ===")
    
    -- 检查Base32功能是否可用
    if string.toBase32 and string.fromBase32 then
        -- 基本编码
        local plain_text = "Hello World"
        local encoded_b32 = string.toBase32(plain_text)
        log.info("toBase32", "原文:", plain_text, "编码后:", encoded_b32)
        
        -- 解码验证
        local decoded_b32 = string.fromBase32(encoded_b32)
        log.info("fromBase32", "解码结果:", decoded_b32)
        
        -- 短字符串编码
        local short_text = "test"
        local short_b32 = string.toBase32(short_text)
        log.info("toBase32", "短字符串编码:", short_text, "=>", short_b32)
        log.info("fromBase32", "短字符串解码:", string.fromBase32(short_b32))
        
        -- 中文编码
        local chinese_text = "你好世界"
        local chinese_b32 = string.toBase32(chinese_text)
        log.info("toBase32", "中文原文:", chinese_text, "编码后:", chinese_b32)
        log.info("fromBase32", "中文解码:", string.fromBase32(chinese_b32))
        
        -- 二进制数据编码
        local binary_data = string.char(0x01, 0x02, 0x03, 0x04, 0x05)
        local binary_b32 = string.toBase32(binary_data)
        log.info("toBase32", "二进制数据HEX:", string.toHex(binary_data), "Base32:", binary_b32)
        
        -- 空字符串处理
        local empty_b32 = string.toBase32("")
        log.info("toBase32", "空字符串编码:", "''", "=>", empty_b32)
        log.info("fromBase32", "空字符串解码:", "'" .. string.fromBase32(empty_b32) .. "'")
        
    else
        log.warn("Base32", "当前固件不支持Base32编码解码功能")
        log.info("Base32", "请确保使用支持Base32的LuatOS固件版本")
    end
end

-- ====================== 字符串判断示例 ======================
local function string_check_examples()
    log.info("=== 字符串判断示例 ===")
    
    local test_str = "hello world"
    
    -- 判断前缀
    local starts_with_hello = string.startsWith(test_str, "hello")
    local starts_with_world = string.startsWith(test_str, "world")
    log.info("startsWith", "字符串:", test_str)
    log.info("startsWith", "以'hello'开头:", starts_with_hello)
    log.info("startsWith", "以'world'开头:", starts_with_world)
    
    -- 判断后缀
    local ends_with_world = string.endsWith(test_str, "world")
    local ends_with_hello = string.endsWith(test_str, "hello")
    log.info("endsWith", "以'world'结尾:", ends_with_world)
    log.info("endsWith", "以'hello'结尾:", ends_with_hello)
end

-- ====================== 字符串裁剪示例 ======================
local function trim_examples()
    log.info("=== 字符串裁剪示例 ===")
    
    -- 包含空白字符的字符串
    local dirty_str = "  \r\n  hello world  \t\n  "
    
    -- 默认裁剪（前后都裁剪）
    local trimmed = string.trim(dirty_str)
    log.info("trim", "原始字符串长度:", #dirty_str)
    log.info("trim", "裁剪后字符串:", "'" .. trimmed .. "'", "长度:", #trimmed)
    
    -- 用户输入清理示例
    local user_input = "   admin   "
    local clean_input = string.trim(user_input)
    log.info("trim", "用户输入清理:", "'" .. user_input .. "'", "=>", "'" .. clean_input .. "'")
end

-- ====================== 主演示函数 ======================
local function run_all_demos()
    log.info("string_demo", "开始执行所有字符串操作演示")
    
    init()
    hex_examples()
    split_examples()
    value_conversion_examples()
    base64_examples()
    base32_examples()
    string_check_examples()
    trim_examples()
    
    log.info("string_demo", "所有演示执行完成")
end

-- 主任务函数
local function main()
    log.info("string_demo", "开始运行字符串操作演示")
    run_all_demos()
    log.info("string_demo", "演示运行完毕")
end

-- 启动演示任务
sys.taskInit(main)