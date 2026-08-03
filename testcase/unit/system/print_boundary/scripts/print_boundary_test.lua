-- print缓冲区边界测试
-- 验证P0-1: lbaselib.c中print缓冲区offset接近512时不会栈溢出
local print_boundary_test = {}

-- 测试: 多个参数print, 总长度接近512字节边界
-- 当offset=511时, 写入空格分隔符会导致offset变为512, 随后写'\0'越界
function print_boundary_test.test_print_multi_args_near_boundary()
    log.info("print_boundary", "测试多参数print接近512字节边界")
    -- 构造多个字符串, 使得累计offset接近511
    -- 每个参数之间会插入一个空格, 所以n个参数有n-1个空格
    -- 使用10个50字节的字符串 + 9个空格 = 509字节, 再加一个参数触发边界
    local s50 = string.rep("A", 50)
    -- 10 * 50 + 9 spaces = 509, 第11个参数的空格在offset=509, 写入后offset=510
    -- 再加2个字符到达511, 然后下一个空格在511写入后offset=512 -> 触发溢出
    local ok, err = pcall(function()
        print(s50, s50, s50, s50, s50, s50, s50, s50, s50, s50, "BB", "C")
    end)
    assert(ok, "print多参数接近边界不应崩溃: " .. tostring(err))
    log.info("print_boundary", "多参数print边界测试通过")
end

-- 测试: 单个超长字符串print
function print_boundary_test.test_print_single_long_string()
    log.info("print_boundary", "测试单个超长字符串print")
    local ok, err = pcall(function()
        -- 超过512字节的单个字符串
        print(string.rep("X", 600))
    end)
    assert(ok, "print超长字符串不应崩溃: " .. tostring(err))
    log.info("print_boundary", "超长字符串print测试通过")
end

-- 测试: 精确触发offset=511时写空格的路径
function print_boundary_test.test_print_exact_offset_511_space()
    log.info("print_boundary", "测试精确offset=511时写空格")
    -- 构造: 第一个参数511字节, 第二个参数触发空格写入
    -- offset=0 + 511字节 = offset=511, 然后第二个参数前写空格在buff[511], offset变512
    local ok, err = pcall(function()
        print(string.rep("A", 511), "B")
    end)
    assert(ok, "offset=511时写空格不应崩溃: " .. tostring(err))
    log.info("print_boundary", "offset=511空格测试通过")
end

-- 测试: 精确触发offset=511时写换行的路径
function print_boundary_test.test_print_exact_offset_511_newline()
    log.info("print_boundary", "测试精确offset=511时写换行")
    -- 构造: 单个参数511字节, print结束时写'\n'在buff[511], offset变512
    local ok, err = pcall(function()
        print(string.rep("A", 511))
    end)
    assert(ok, "offset=511时写换行不应崩溃: " .. tostring(err))
    log.info("print_boundary", "offset=511换行测试通过")
end

-- 测试: 多次print连续调用
function print_boundary_test.test_print_repeated_calls()
    log.info("print_boundary", "测试多次连续print调用")
    local ok, err = pcall(function()
        for i = 1, 100 do
            print(string.rep("Z", 200), string.rep("Y", 200), string.rep("X", 200))
        end
    end)
    assert(ok, "多次print不应崩溃: " .. tostring(err))
    log.info("print_boundary", "多次连续print测试通过")
end

-- 测试: 512字节精确边界
function print_boundary_test.test_print_exact_512()
    log.info("print_boundary", "测试精确512字节")
    local ok, err = pcall(function()
        print(string.rep("A", 512))
    end)
    assert(ok, "精确512字节print不应崩溃: " .. tostring(err))
    log.info("print_boundary", "精确512字节测试通过")
end

return print_boundary_test
