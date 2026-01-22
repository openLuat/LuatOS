local fskv_tests = {}

-- Re-init and clear KV store so each test is independent
local function reset_db()
    assert(fskv, "fskv is not available")
    assert(fskv.init(), "fskv init failed")
    if fskv.clear then
        assert(fskv.clear(), "fskv clear failed")
    elseif fskv.clr then
        assert(fskv.clr(), "fskv clear failed")
    end
end

-- Small helper for float comparison
local function is_close(a, b, eps)
    eps = eps or 1e-3
    return math.abs(a - b) <= eps
end

function fskv_tests.test_init_and_clear()
    log.info("fskv_tests", "init and clear")
    reset_db()
    local used, total, count = fskv.stat()
    assert(type(used) == "number" and type(total) == "number" and type(count) == "number", "stat result type mismatch")
    assert(total > 0, "total capacity should be positive")
end

-- Verify storing and reading all supported basic types
function fskv_tests.test_set_get_basic()
    log.info("fskv_tests", "set/get basic types")
    reset_db()
    assert(fskv.set("ut_bool", true))
    assert(fskv.set("ut_int", 123))
    assert(fskv.set("ut_number", 1.23))
    assert(fskv.set("ut_str", "luatos"))
    assert(fskv.set("ut_table", {name="wendal", age=18}))
    assert(fskv.set("ut_str_int", "123"))
    assert(fskv.set("1", "123"))

    assert(fskv.get("ut_bool") == true, "boolean mismatch")
    assert(fskv.get("ut_int") == 123, "integer mismatch")
    local num = fskv.get("ut_number")
    assert(is_close(num, 1.23, 1e-3), "float mismatch")
    assert(fskv.get("ut_str") == "luatos", "string mismatch")
    local t = fskv.get("ut_table")
    assert(type(t) == "table" and t.name == "wendal" and t.age == 18, "table mismatch")
    assert(fskv.get("ut_str_int") == "123", "stringified number mismatch")
    assert(fskv.get("1") == "123", "single byte key mismatch")
end

function fskv_tests.test_delete()
    log.info("fskv_tests", "delete key")
    reset_db()
    assert(fskv.set("ut_del", "to-delete"))
    assert(fskv.del("ut_del"), "delete failed")
    assert(fskv.get("ut_del") == nil, "key should be nil after delete")
end

-- Verify sett can upsert nested fields and delete fields when value is nil
function fskv_tests.test_sett_and_subkey()
    log.info("fskv_tests", "sett and subkey")
    reset_db()

    assert(fskv.set("ut_table", {name="wendal"}))
    assert(fskv.sett("ut_table", "age", 18))
    assert(fskv.sett("ut_table", "flag", true))
    local full = fskv.get("ut_table")
    assert(type(full) == "table" and full.age == 18 and full.flag == true, "sett update failed")
    local age = fskv.get("ut_table", "age")
    assert(age == 18, "subkey read failed")

    assert(fskv.set("ut_mykv", "123"))
    assert(fskv.sett("ut_mykv", "age", "123"))
    local kv = fskv.get("ut_mykv")
    assert(type(kv) == "table" and kv.age == "123", "string to table convert failed")

    assert(fskv.set("ut_remove", {age=18, name="wendal"}))
    assert(fskv.sett("ut_remove", "name", nil))
    local rm = fskv.get("ut_remove")
    assert(type(rm) == "table" and rm.name == nil and rm.age == 18, "field removal failed")
end

-- Ensure iter/next walks through keys and stat reports sane values
function fskv_tests.test_iteration()
    log.info("fskv_tests", "iterate keys")
    reset_db()
    local keys = {"ut_iter1", "ut_iter2", "ut_iter3"}
    for i, k in ipairs(keys) do
        assert(fskv.set(k, i), string.format("write %s failed", k))
    end

    local iter = fskv.iter()
    assert(iter ~= nil, "iter creation failed")
    local seen = {}
    while true do
        local k = fskv.next(iter)
        if not k then break end
        seen[k] = true
    end

    for _, k in ipairs(keys) do
        assert(seen[k], string.format("key not found via iter: %s", k))
    end

    local used, total, count = fskv.stat()
    assert(type(count) == "number" and count >= #keys, "kv count mismatch")
    assert(type(used) == "number" and type(total) == "number", "space stat mismatch")
end

return fskv_tests
