--[[
    @module  zbuff_advanced
    @summary zbuff的高级操作模块
    @version 1.0.0
    @date    2025.08.08
    @author  王棚嶙
    @usage
    本文件为本部分为zbuff高级操作模块，包含zbuff的复杂数据处理功能,包括：
    1. 数据打包/解包
    2. 类型化读写
    3. 浮点数操作
    本文件没有对外接口，直接在main.lua中require "zbuff_advanced"就可以加载运行
    ]]

local function zbuff_advanced_task_func()
    log.info("zbuff_advanced", "启动高级功能演示")
    
    -- 创建1024字节的缓冲区
    local buff = zbuff.create(1024)
    
    -- === 数据打包与解包演示 ===
    log.info("zbuff_advanced", "=== 数据打包与解包演示 ===")
    
    -- 清空缓冲区
    buff:clear()
    -- 重置指针到开头
    buff:seek(0)
    
    -- 打包数据：大端序，2个32位整数，1个16位整数，1个字符串
    buff:pack(">IIHA", 0x1234, 0x4567, 0x12, "abcdefg")
    log.info("zbuff_advanced", "数据打包", "格式: >IIHA", "值: 0x1234, 0x4567, 0x12, 'abcdefg'")
    -- 显示打包后的二进制内容
    local packed = buff:toStr(0, buff:used())--按照起始位置和长度，取出数据，并转换为字符串
    log.info("zbuff_advanced", "打包后数据", packed:toHex())
    
    
    -- 重置指针到开头
    buff:seek(0)
    
    -- 解包数据：大端序，2个32位整数，1个16位整数，1个10字节字符串
    local cnt, a, b, c, s = buff:unpack(">IIHA10")
    log.info("zbuff_advanced", "数据解包", "数量:", cnt, "值:", a, b, c, s)
     -- 显示解包后的输出内容
     -- string.forma是Lua的格式化字符串函数，按照格式化参数formatstring，返回后面...内容的格式化版本。string.format("0x%X", a)表示将整数a转换为十六进制字符串。
    log.info("zbuff_advanced", "解包输出内容", 
        "cnt:", cnt, 
        "a(32位):", string.format("0x%X", a),
        "b(32位):", string.format("0x%X", b),
        "c(16位):", string.format("0x%X", c),
        "s(字符串):", s)
    -- === 类型化读写演示 ===
    --[[
    类型化读写演示
    展示I8和U32两种类型操作
    @param buff zbuff对象
    --]]
    log.info("zbuff_advanced", "=== 类型化读写演示 ===")

    -- 重置指针到开头
    buff:seek(0)
    
    -- 写入8位有符号整数
    buff:writeI8(10)
    log.info("zbuff_advanced", "类型化写入", "I8:", 10)
    
    -- 写入32位无符号整数
    buff:writeU32(1024)
    log.info("zbuff_advanced", "类型化写入", "U32:", 1024)
    
    -- 重置指针到开头
    buff:seek(0)
    
    -- 读取8位有符号整数
    local i8data = buff:readI8()
    log.info("zbuff_advanced", "类型化读取", "I8:", i8data)
    
    -- 读取32位无符号整数
    local u32data = buff:readU32()
    log.info("zbuff_advanced", "类型化读取", "U32:", u32data)



    --[[
    浮点数操作演示
    @param buff zbuff对象
    --]]
    log.info("zbuff_advanced", "=== 浮点数操作演示 ===")
    -- 重置指针到开头
    buff:seek(0)
    
    -- 写入32位浮点数
    buff:writeF32(1.2)
    log.info("zbuff_advanced", "浮点数操作", "写入F32:", 1.2)
    
    -- 重置指针到开头
    buff:seek(0)
    
    -- 读取32位浮点数
    local f32data = buff:readF32()
    log.info("zbuff_advanced", "浮点数操作", "读取F32:", f32data)

    -- 清空缓冲区
    buff:clear()
    -- 重置指针到开头
    buff:seek(0)
    log.info("zbuff_advanced", "高级功能演示完成")
end
sys.taskInit(zbuff_advanced_task_func)