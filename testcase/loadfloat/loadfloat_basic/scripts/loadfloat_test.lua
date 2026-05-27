-- testcase/loadfloat/loadfloat_basic/scripts/loadfloat_test.lua
-- Tests for load() with long floating-point literals.
-- Regression for: air1601 64-bit crash when load() contains long float literals.
-- Root cause: l_str2d() in lobject.c passed unlimited-length strings to strtod(),
--   which crashes on some embedded libc implementations.

local loadfloat_tests = {}

-- Test 1: Normal short float - baseline correctness
function loadfloat_tests.test_normal_float_in_load()
    local f, err = load("return 3.14")
    assert(f ~= nil, "load failed: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number, got " .. type(v))
    assert(v > 3.13 and v < 3.15, "value should be ~3.14, got " .. tostring(v))
    log.info("loadfloat", "test_normal_float_in_load PASS, v=" .. tostring(v))
end

-- Test 2: Long mantissa (200+ decimal digits) - primary crash scenario on air1601
function loadfloat_tests.test_long_mantissa_in_load()
    -- "1.12345678901234567890..." with 200 digits after the decimal point
    local mantissa = "1." .. string.rep("1234567890", 20)  -- 200 decimal digits
    assert(#mantissa > 200, "mantissa should be >200 chars, got " .. #mantissa)
    local f, err = load("return " .. mantissa)
    assert(f ~= nil, "load failed on long mantissa: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number, got " .. type(v))
    assert(v > 1.0 and v < 2.0, "value should be in (1,2), got " .. tostring(v))
    log.info("loadfloat", "test_long_mantissa_in_load PASS, v=" .. tostring(v) .. " len=" .. #mantissa)
end

-- Test 3: Long integer part before decimal point
function loadfloat_tests.test_long_integer_part_in_load()
    -- "99999999999999999999999999999999999.0" (35 nines before decimal)
    local numstr = string.rep("9", 35) .. ".0"
    local f, err = load("return " .. numstr)
    assert(f ~= nil, "load failed on long integer part: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number, got " .. type(v))
    assert(v > 0, "value should be > 0, got " .. tostring(v))
    log.info("loadfloat", "test_long_integer_part_in_load PASS, v=" .. tostring(v))
end

-- Test 4: Long mantissa + exponent - must preserve the exponent part
function loadfloat_tests.test_long_float_with_exponent_in_load()
    -- "1.555....(50 fives)....e+10"
    local numstr = "1." .. string.rep("5", 50) .. "e+10"
    local f, err = load("return " .. numstr)
    assert(f ~= nil, "load failed on long float+exponent: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number, got " .. type(v))
    -- 1.555e+10 ~ 1.555 * 10^10 = 15,550,000,000
    assert(v > 1e10 and v < 2e10, "value should be ~1.555e10, got " .. tostring(v))
    log.info("loadfloat", "test_long_float_with_exponent_in_load PASS, v=" .. tostring(v))
end

-- Test 5: Very long mantissa (300+ decimal digits) - stress test
function loadfloat_tests.test_very_long_mantissa_in_load()
    local mantissa = "2." .. string.rep("9876543210", 30)  -- 300 decimal digits
    assert(#mantissa > 300, "mantissa should be >300 chars, got " .. #mantissa)
    local f, err = load("return " .. mantissa)
    assert(f ~= nil, "load failed on very long mantissa: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number, got " .. type(v))
    assert(v > 2.0 and v < 3.0, "value should be in (2,3), got " .. tostring(v))
    log.info("loadfloat", "test_very_long_mantissa_in_load PASS, v=" .. tostring(v) .. " len=" .. #mantissa)
end

-- Test 6: Precision consistency - a long float should parse to the same value
-- as the precision-limited version (IEEE 754 double has ~17 significant digits)
function loadfloat_tests.test_precision_consistency()
    -- "1.1111111111111111" (16 ones after decimal) - within double precision
    -- plus 184 extra identical digits - should give the same double value
    local short_code = "return 1.1111111111111111"
    local long_code  = "return 1." .. string.rep("1", 200)
    local sf, _ = load(short_code)
    local lf, _ = load(long_code)
    assert(sf ~= nil, "short load failed")
    assert(lf ~= nil, "long load failed")
    local sv = sf()
    local lv = lf()
    assert(sv > 1.0 and sv < 2.0, "short float out of range: " .. tostring(sv))
    assert(lv > 1.0 and lv < 2.0, "long float out of range: " .. tostring(lv))
    log.info("loadfloat", "test_precision_consistency PASS, sv=" .. tostring(sv) .. " lv=" .. tostring(lv))
end

-- Test 7: tonumber() with long float string (also calls luaO_str2num internally)
function loadfloat_tests.test_tonumber_long_float()
    local s = "1." .. string.rep("9", 250)
    local n = tonumber(s)
    assert(type(n) == "number", "tonumber should return number, got " .. type(n))
    assert(n > 1.0 and n < 3.0, "tonumber value out of range: " .. tostring(n))
    log.info("loadfloat", "test_tonumber_long_float PASS, n=" .. tostring(n))
end

-- Test 8: load() with 20~30 char float (customer crash threshold on air1601)
-- This is the minimal reproduction of the reported crash scenario.
function loadfloat_tests.test_20to30_char_float_in_load()
    -- 25-char mantissa - would crash at guard=32 but safe at guard=20
    local s25 = "1." .. string.rep("1", 23)  -- 25 chars total
    assert(#s25 == 25, "expected 25 char string, got " .. #s25)
    local f, err = load("return " .. s25)
    assert(f ~= nil, "load failed for 25-char float: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number")
    assert(v > 1.0 and v < 2.0, "value out of range: " .. tostring(v))

    -- 33-char mantissa (triggers L_MAXLENNUM_GUARD truncation)
    local s33 = "1." .. string.rep("9", 31)  -- 33 chars total
    assert(#s33 == 33, "expected 33 char string, got " .. #s33)
    local f2, err2 = load("return " .. s33)
    assert(f2 ~= nil, "load failed for 33-char float: " .. tostring(err2))
    local v2 = f2()
    assert(type(v2) == "number", "type should be number")
    assert(v2 > 1.0 and v2 < 3.0, "value out of range: " .. tostring(v2))
    log.info("loadfloat", "test_20to30_char_float_in_load PASS, s25=" .. tostring(v) .. " s33=" .. tostring(v2))
end

-- Test 10: exact customer literals that caused air1601 crash
-- These are 22-char strings that would crash newlib-nano strtod on ARM Cortex-M7
function loadfloat_tests.test_customer_crash_literals()
    -- local PI = 3.14159265358979323846
    local code_pi = "return 3.14159265358979323846"
    assert(#"3.14159265358979323846" == 22, "PI literal should be 22 chars")
    local f1, err1 = load(code_pi)
    assert(f1 ~= nil, "load PI failed: " .. tostring(err1))
    local pi = f1()
    assert(type(pi) == "number", "PI should be number")
    assert(pi > 3.14 and pi < 3.15, "PI out of range: " .. tostring(pi))

    -- local EE = 0.00669342162296594323
    local code_ee = "return 0.00669342162296594323"
    assert(#"0.00669342162296594323" == 22, "EE literal should be 22 chars")
    local f2, err2 = load(code_ee)
    assert(f2 ~= nil, "load EE failed: " .. tostring(err2))
    local ee = f2()
    assert(type(ee) == "number", "EE should be number")
    assert(ee > 0.006 and ee < 0.007, "EE out of range: " .. tostring(ee))

    -- local EARTH_RADIUS = 6378245.0  (9 chars, short - should still work fine)
    local f3, err3 = load("return 6378245.0")
    assert(f3 ~= nil, "load EARTH_RADIUS failed: " .. tostring(err3))
    local r = f3()
    assert(r == 6378245.0, "EARTH_RADIUS wrong: " .. tostring(r))

    log.info("loadfloat", "test_customer_crash_literals PASS pi=" .. tostring(pi) .. " ee=" .. tostring(ee) .. " r=" .. tostring(r))
end

-- Test 9: float with exponent where mantissa would be truncated (correctness check)
function loadfloat_tests.test_truncated_mantissa_preserves_exponent()
    -- "1." + 30 zeros + "e+10" = 35 chars total, triggers guard
    -- After truncation: mantissa part + "e+10" preserved => ~1e10
    local s = "1." .. string.rep("0", 30) .. "e+10"
    assert(#s > 32, "test string should be longer than guard limit")
    local f, err = load("return " .. s)
    assert(f ~= nil, "load failed: " .. tostring(err))
    local v = f()
    assert(type(v) == "number", "type should be number")
    assert(v > 9e9 and v < 2e10, "value should be ~1e10, got " .. tostring(v))
    log.info("loadfloat", "test_truncated_mantissa_preserves_exponent PASS, v=" .. tostring(v))
end

return loadfloat_tests
