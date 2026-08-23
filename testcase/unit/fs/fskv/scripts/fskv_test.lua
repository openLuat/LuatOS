local fskv_tests = {}

-- 重新初始化并清空KV存储，确保每个测试独立
local function reset_db()
    assert(fskv, "fskv不可用")
    assert(fskv.init(), "fskv初始化失败")
    if fskv.clear then
        assert(fskv.clear(), "fskv清空失败")
    elseif fskv.clr then
        assert(fskv.clr(), "fskv清空失败")
    end
end

-- 浮点数比较辅助函数
local function is_close(a, b, eps)
    eps = eps or 1e-3
    return math.abs(a - b) <= eps
end

function fskv_tests.test_init_and_clear()
    log.info("fskv_tests", "初始化和清空测试")
    reset_db()
    local used, total, count = fskv.stat()
    assert(type(used) == "number", "已用空间类型应为number")
    assert(type(total) == "number", "总空间类型应为number")
    assert(type(count) == "number", "键值对数量类型应为number")
    assert(total > 0, "总容量应为正数")
end

-- 验证所有支持的基本类型的存储和读取
function fskv_tests.test_set_get_basic()
    log.info("fskv_tests", "基本类型存取测试")
    reset_db()
    assert(fskv.set("ut_bool", true), "设置布尔值失败")
    assert(fskv.set("ut_int", 123), "设置整数失败")
    assert(fskv.set("ut_number", 1.23), "设置浮点数失败")
    assert(fskv.set("ut_str", "luatos"), "设置字符串失败")
    assert(fskv.set("ut_table", {name="wendal", age=18}), "设置table失败")
    assert(fskv.set("ut_str_int", "123"), "设置数字字符串失败")
    assert(fskv.set("1", "123"), "设置单字节键失败")

    assert(fskv.get("ut_bool") == true, "布尔值读取不匹配")
    assert(fskv.get("ut_int") == 123, "整数读取不匹配")
    local num = fskv.get("ut_number")
    assert(is_close(num, 1.23, 1e-3), "浮点数读取不匹配")
    assert(fskv.get("ut_str") == "luatos", "字符串读取不匹配")
    local t = fskv.get("ut_table")
    assert(type(t) == "table" and t.name == "wendal" and t.age == 18, "table读取不匹配")
    assert(fskv.get("ut_str_int") == "123", "数字字符串读取不匹配")
    assert(fskv.get("1") == "123", "单字节键读取不匹配")
end

function fskv_tests.test_delete()
    log.info("fskv_tests", "删除键测试")
    reset_db()
    assert(fskv.set("ut_del", "to-delete"), "设置待删除键失败")
    assert(fskv.del("ut_del"), "删除操作失败")
    assert(fskv.get("ut_del") == nil, "删除后键应该为nil")
end

-- 验证sett可以更新嵌套字段，以及值为nil时删除字段
function fskv_tests.test_sett_and_subkey()
    log.info("fskv_tests", "嵌套字段操作测试")
    reset_db()

    assert(fskv.set("ut_table", {name="wendal"}), "设置初始table失败")
    assert(fskv.sett("ut_table", "age", 18), "设置age字段失败")
    assert(fskv.sett("ut_table", "flag", true), "设置flag字段失败")
    local full = fskv.get("ut_table")
    assert(type(full) == "table" and full.age == 18 and full.flag == true, "sett更新失败")
    local age = fskv.get("ut_table", "age")
    assert(age == 18, "子键读取失败")

    assert(fskv.set("ut_mykv", "123"), "设置字符串失败")
    assert(fskv.sett("ut_mykv", "age", "123"), "字符串转table失败")
    local kv = fskv.get("ut_mykv")
    assert(type(kv) == "table" and kv.age == "123", "字符串转table转换失败")

    assert(fskv.set("ut_remove", {age=18, name="wendal"}), "设置待删除table失败")
    assert(fskv.sett("ut_remove", "name", nil), "删除name字段失败")
    local rm = fskv.get("ut_remove")
    assert(type(rm) == "table" and rm.name == nil and rm.age == 18, "字段删除失败")
end

-- 确保iter/next能遍历所有键，stat返回合理值
function fskv_tests.test_iteration()
    log.info("fskv_tests", "迭代器遍历测试")
    reset_db()
    local keys = {"ut_iter1", "ut_iter2", "ut_iter3"}
    for i, k in ipairs(keys) do
        assert(fskv.set(k, i), string.format("写入%s失败", k))
    end

    local iter = fskv.iter()
    assert(iter ~= nil, "迭代器创建失败")
    local seen = {}
    while true do
        local k = fskv.next(iter)
        if not k then break end
        seen[k] = true
    end

    for _, k in ipairs(keys) do
        assert(seen[k], string.format("迭代器未找到键: %s", k))
    end

    local used, total, count = fskv.stat()
    assert(type(count) == "number" and count >= #keys, "键值对数量不匹配")
    assert(type(used) == "number" and type(total) == "number", "空间统计类型错误")
end

-- 测试set/get/del函数传参为nil的情况
function fskv_tests.test_nil_params()
    log.info("fskv_tests", "nil参数测试")
    reset_db()
    
    -- 测试set函数传入nil键 - 应该报错（因为参数类型错误）
    local ok, err = pcall(fskv.set, nil, "value")
    assert(not ok, "set函数传入nil键应该报错")
    
    -- 测试set函数传入nil值 - 根据文档value不能为nil，应返回false
    assert(fskv.set("test_key", "valid_value"), "初始设置应该成功")
    local set_result = fskv.set("test_key", nil)
    -- 根据文档和警告信息，传入nil值应返回false
    assert(set_result == false or set_result == nil, "set函数传入nil值应返回false或nil")
    
    -- 验证原始值保持不变
    assert(fskv.get("test_key") == "valid_value", "nil值设置失败后原值应保持不变")
    
    -- 测试get函数传入nil键 - 应该报错
    ok, err = pcall(fskv.get, nil)
    assert(not ok, "get函数传入nil键应该报错")
    
    -- 测试get函数传入有效键但nil子键（这是允许的，应返回完整table）
    assert(fskv.set("ut_table", {name="test", age=99}), "设置table失败")
    local full_table = fskv.get("ut_table")
    assert(type(full_table) == "table" and full_table.name == "test", 
           "不传子键应返回完整table")
    
    -- 测试del函数传入nil键 - 应该报错
    ok, err = pcall(fskv.del, nil)
    assert(not ok, "del函数传入nil键应该报错")
    
    -- 验证现有键未受影响
    assert(fskv.get("test_key") == "valid_value", "现有键应保持不变")
    
    log.info("fskv_tests", "nil参数测试通过")
end

-- 测试status/stat函数
function fskv_tests.test_status()
    log.info("fskv_tests", "状态函数测试")
    reset_db()
    
    -- 初始状态，已用空间可能有一些开销，键值对数量应为0
    local used1, total1, count1 = fskv.stat()
    assert(type(used1) == "number", "已用空间应为number类型")
    assert(type(total1) == "number", "总空间应为number类型")
    assert(type(count1) == "number", "键值对数量应为number类型")
    assert(total1 > 0, "总容量应为正数")
    assert(count1 == 0, "初始键值对数量应为0")
    
    -- 添加一些数据，验证数量增加
    local test_data = {
        {"key1", "value1"},
        {"key2", 12345},
        {"key3", {a=1, b=2}},
        {"key4", true},
        {"key5", "a" .. string.rep("b", 100)}  -- 102字节字符串
    }
    
    for _, item in ipairs(test_data) do
        assert(fskv.set(item[1], item[2]), string.format("设置%s失败", item[1]))
    end
    
    local used2, total2, count2 = fskv.stat()
    -- 验证键值对数量增加
    assert(count2 == #test_data, string.format("键值对数量应为%d，实际为%d", #test_data, count2))
    -- 验证总容量不变
    assert(total1 == total2, "总容量应保持不变")
    
    -- 再添加一条数据，验证数量再次增加
    assert(fskv.set("extra_key", "extra_value"), "设置额外键失败")
    local used3, total3, count3 = fskv.stat()
    assert(count3 == count2 + 1, "键值对数量应增加1")
    
    -- 验证总容量保持不变
    assert(total2 == total3, "总容量应保持不变")
    
    log.info("fskv_tests", string.format("状态信息: 已用=%d, 总容量=%d, 键值对数量=%d", used3, total3, count3))
end

-- 最终清理测试
function fskv_tests.test_final_cleanup()
    log.info("fskv_tests", "最终清理 - 清空所有数据")
    
    -- 首先添加一些测试数据验证clear功能
    assert(fskv.set("cleanup_test1", "data1"), "设置cleanup_test1失败")
    assert(fskv.set("cleanup_test2", "data2"), "设置cleanup_test2失败")
    assert(fskv.set("cleanup_test3", {nested=true}), "设置cleanup_test3失败")
    
    -- 验证数据存在
    assert(fskv.get("cleanup_test1") == "data1", "cleanup_test1应该存在")
    assert(fskv.get("cleanup_test2") == "data2", "cleanup_test2应该存在")
    assert(fskv.get("cleanup_test3") ~= nil, "cleanup_test3应该存在")
    
    -- 清空前获取统计信息
    local used_before, total_before, count_before = fskv.stat()
    assert(count_before >= 3, "清空前至少应有3个键值对")
    
    -- 执行清空操作
    local clear_result = fskv.clear()
    assert(clear_result == true, "fskv.clear()应返回true")
    
    -- 验证所有数据被清空
    assert(fskv.get("cleanup_test1") == nil, "cleanup_test1清空后应为nil")
    assert(fskv.get("cleanup_test2") == nil, "cleanup_test2清空后应为nil")
    assert(fskv.get("cleanup_test3") == nil, "cleanup_test3清空后应为nil")
    
    -- 验证清空后键值对数量为0
    local used_after, total_after, count_after = fskv.stat()
    assert(count_after == 0, string.format("清空后键值对数量应为0，实际为%d", count_after))
    assert(total_after == total_before, "总容量应保持不变")
    
    log.info("fskv_tests", "最终清理完成")
end

return fskv_tests