--[[
@module  json_app
@summary json 序列化与反序列化功能模块
@version 1.0
@date    2025.11.05
@author  马梦阳
@usage
本功能模块演示的内容为：
1.将 Lua 对象 转为 JSON 字符串：
    示例一：Lua string 转为 JSON string；
    示例二：Lua number 转为 JSON string；
    示例三：Lua boolean 转为 JSON string；
    示例四：Lua table 转为 JSON string；
    示例五：Lua nil 转为 JSON string；
    序列化失败示例和指定浮点数示例；
2.将 JSON 字符串 转为 Lua 对象：
    示例一：JSON string 转为 Lua string；
    示例二：JSON number 转为 Lua number；
    示例三：JSON boolean 转为 Lua boolean；
    示例四：JSON table 转为 Lua table；
    示例五：JSON nil 转为 Lua nil；
    反序列化失败示例；
    空表（empty table）转换为 JSON 时的说明；
    字符串中包含控制字符（如 \r\n）的 JSON 序列化与反序列化说明；
    json.null 的语义与比较行为说明：

本文件没有对外接口,直接在 main.lua 中 require "json_app" 就可以加载运行；
]]


-- json库支持将 Lua 对象 转为 JSON 字符串, 或者反过来, JSON 字符串 转 Lua 对象
-- 若转换失败, 会返回nil值, 强烈建议在使用时添加额外的判断，如下列演示代码中所示
local function main_task()
    while true do
        sys.wait(1000)
        -- 序列化成功示例：
        -- 示例一：Lua string 转为 JSON string；
        local data = "test"
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("string_string_test1","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("string_string_test1","序列化成功：", json_str)
        end

        -- 示例二：Lua number 转为 JSON string；
        local data = 123456789
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("number_string_test1","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("number_string_test1","序列化成功：", json_str)
        end

        -- 示例三：Lua boolean 转为 JSON string；
        local data = true
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("boolean_string_test1","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("boolean_string_test1","序列化成功：", json_str)
        end

        -- 示例四：Lua table 转为 JSON string；
        local data = {abc = 123, def = "123", ttt = true}
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("table_string_test1","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            -- 由于 Lua 表在遍历时键的顺序是不确定的（尤其是字符串键）
            -- 而 JSON 对象本身也是无序的
            -- 因此序列化后的 JSON 字符串中键的顺序可能与 Lua 源码中的书写顺序不同，属于正常情况
            log.info("table_string_test1","序列化成功：", json_str)
        end

        -- 示例五：Lua nil 转为 JSON string；
        local data = nil
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("nil_string_test1","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            -- 注意：此时返回值是一个空字符串 ""
            log.info("nil_string_test1","序列化成功：", json_str)
        end


        -- 序列化失败示例：
        -- Lua table 中包含 function；
        local data = {abc = 123, def = "123", ttt = true, err = function() end}
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("table_string_test2","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("table_string_test2","序列化成功：", json_str)
        end


        -- 指定浮点数示例：
        -- 指定保留三位小数，不足时补零，超出时四舍五入；
        local data = {abc = 1234.56789}
        local json_str, err_msg = json.encode(data, "3f")
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("table_string_test3","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("table_string_test3","序列化成功：", json_str)
        end


        -- 反序列化成功示例：
        -- 示例一：JSON string 转为 Lua string
        local str = '"test"'
        -- local str = "\"test\""
        local obj, result, err = json.decode(str)
        if result == false then
            -- 反序列化失败时, 会返回 nil 值, 并通过 err 参数返回错误信息
            log.info("string_string_test1","反序列化失败：", err)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 反序列化成功时, 会返回 Lua string
            log.info("string_string_test1","反序列化成功：", obj)
        end

        -- 示例二：JSON string 转为 Lua number；
        local str = "123456789"
        local obj, result, err = json.decode(str)
        if result == false then
            -- 反序列化失败时, 会返回 nil 值, 并通过 err 参数返回错误信息
            log.info("string_number_test1","反序列化失败：", err)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 反序列化成功时, 会返回 Lua number
            log.info("string_number_test1","反序列化成功：", obj)
        end

        -- 示例三：JSON string 转为 Lua boolean；
        local str = "true"
        local obj, result, err = json.decode(str)
        if result == false then
            -- 反序列化失败时, 会返回 nil 值, 并通过 err 参数返回错误信息
            log.info("string_boolean_test1","反序列化失败：", err)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 反序列化成功时, 会返回 Lua boolean
            log.info("string_boolean_test1","反序列化成功：", obj)
        end

        -- 示例四：JSON string 转为 Lua table；
        local str = "{\"abc\":1234545}"
        local obj, result, err = json.decode(str)
        if result == false then
            -- 反序列化失败时, 会返回 nil 值, 并通过 err 参数返回错误信息
            log.info("string_table_test1.2","反序列化失败：", err)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 反序列化成功时, 会返回 Lua table
            -- 注意：此时 obj 是一个 Lua table
            -- 若直接打印 obj，会输出 table: 01C9A490 类似的内存地址
            log.info("string_table_test1.2","反序列化成功：", obj)
            -- 需要添加具体的字段名称，才能正确输出
            log.info("string_table_test1.2","反序列化成功：", obj.abc)
        end


        -- 反序列化失败示例：
        -- JSON string 不是合法的 JSON 格式；
        local str = "{\"def\":}"
        local obj, result, err = json.decode(str)
        if result == false then
            -- 反序列化失败时, 会返回 nil 值, 并通过 err 参数返回错误信息
            log.info("string_table_test2","反序列化失败：", err)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 反序列化成功时, 会返回 Lua table
            log.info("string_table_test2","反序列化成功：", obj)
        end


        -- empty table（空表） 转换为 JSON 时的说明：
        -- 原生 Lua 中的 table 是数组（sequence）和哈希表（map）的统一数据结构；
        -- 空表 {} 在转换为 JSON 时存在歧义：无法确定应输出为空数组 [] 还是空对象 {}；
        -- 由于 Lua 中只有包含连续正整数索引（从 1 开始）的表才被视为数组，而空表不满足这一条件；
        -- 因此 JSON 库默认将其序列化为 {}（空对象）；
        local data = {abc = {}}
        local json_str, err_msg = json.encode(data)
        if json_str == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("table_string_test3","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("table_string_test3","序列化成功：", json_str)
        end


        -- 字符串中包含控制字符（如 \r\n）的 JSON 序列化与反序列化说明：
        -- 在 Lua 中，字符串可以包含任意字符，包括回车（\r）、换行（\n）等控制字符；
        -- 当使用 json.encode() 对包含此类字符的字符串进行序列化时；
        -- JSON 库会自动将其转义为标准的 JSON 字符串字面量形式（例如 \r 转为 "\r"，\n 转为 "\n"）；
        -- 以确保生成的 JSON 符合规范且可安全传输；
        -- 反序列化时（json.decode()），这些转义序列会被正确还原为原始的控制字符；
        -- 因此解码后的字符串与原始字符串在内容上完全一致（逐字节相等）；
        -- 需要注意的是：日志输出函数（如 log.info）在打印包含 \r\n 的字符串时；
        -- 会实际执行回车换行操作，导致日志在终端上分行显示；
        -- 这可能造成“输出格式混乱”或“多出缩进/空格”的视觉错觉（例如 true 前有一个空格长度）；
        -- 但这只是日志显示效果，并非字符串内容本身发生变化；
        -- 实际比较（tmp3.str == tmp）结果为 true，证明序列化与反序列化过程是无损且正确的；
        local tmp = "ABC\r\nDEF\r\n"
        local tmp2, err_msg = json.encode({str=tmp})
        if tmp2 == nil then
            -- 序列化失败时, 会返回 nil 值, 并通过 err_msg 参数返回错误信息
            log.info("json","序列化失败：", err_msg)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 序列化成功时, 会返回 JSON 字符串
            log.info("json","序列化成功：", tmp2)
        end
        local tmp3, result, err = json.decode(tmp2)
        if result == false then
            -- 反序列化失败时, 会返回 nil 值, 并通过 err 参数返回错误信息
            log.info("json","反序列化失败：", err)
            -- 执行错误处理逻辑，如使用默认值、重试或中止操作
        else
            -- 反序列化成功时, 会返回 Lua table
            -- 注意：此时 tmp3 是一个 Lua table
            -- 直接打印 tmp3 显示的是内存地址，需要添加对应字段
            -- true前存在一个空格长度，这是日志输出格式导致的，与字符串内容本身无实际差异
            log.info("json","反序列化成功：", tmp3.str, tmp3.str == tmp)
        end


        -- json.null 的语义与比较行为说明：
        -- 在标准 JSON 中，null 是一个合法的字面量，表示“空值”或“无值”；
        -- 然而，Lua 语言本身没有 null 类型，只有 nil 用于表示未定义或空值；
        -- 为在 Lua 中准确表示 JSON 的 null，json 库提供了一个特殊占位符：json.null；
        -- json.null 通常是一个轻量级的 userdata 或 table，具体实现依赖库版本；
        -- 当使用 json.encode() 序列化包含 json.null 的字段时，该字段会被正确转换为 JSON 中的 null；
        -- 反之，json.decode() 在解析 JSON 中的 null 时，会将其还原为 json.null，而非 Lua 的 nil；
        -- 这是因为：若将 JSON 的 null 直接转为 nil，会导致 table 中对应键被删除；
        -- 从而丢失原始 JSON 的结构信息；
        -- 因此，json.decode('{"abc":null}').abc 的结果是 json.null，而不是 nil；
        -- 由于 json.null 是一个具体的值（非 nil），它与 nil 比较结果为 false；
        -- 只有与 json.null 自身比较时，结果才为 true；
        -- 开发者应始终使用 == json.null 来判断某个字段是否为 JSON 的 null；
        -- 而不要用 == nil，否则逻辑将出错；
        log.info("json.null", json.encode({name=json.null}))
        -- 日志输出：{"name":null}
        log.info("json.null", json.decode("{\"abc\":null}").abc == json.null)
        -- 日志输出：true
        log.info("json.null", json.decode("{\"abc\":null}").abc == nil)
        -- 日志输出：false
    end
end

-- 启动主任务
sys.taskInit(main_task)
