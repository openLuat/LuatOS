-- memprof basic tests
-- In LuatOS, C modules registered via luaL_requiref are only set as globals,
-- not in package.loaded. Access memprof directly as a global.
local memprof = _G.memprof
assert(type(memprof) == "userdata" or type(memprof) == "table",
    "memprof global not registered; ensure LUAT_USE_MEMPROF is set")
local T = {}

-- test: snapshot returns a table with expected fields
function T.test_snapshot_fields()
    local snap = memprof.snapshot()
    assert(type(snap) == "table", "snapshot() must return a table")
    local expected = {"str_short", "str_long", "table", "proto", "lclosure", "cclosure", "udata", "thread"}
    for _, k in ipairs(expected) do
        assert(type(snap[k]) == "table", "snapshot missing field: " .. k)
        assert(type(snap[k].count) == "number", k .. ".count must be number")
        assert(type(snap[k].bytes) == "number", k .. ".bytes must be number")
        assert(snap[k].count >= 0, k .. ".count must be >= 0")
        assert(snap[k].bytes >= 0, k .. ".bytes must be >= 0")
    end
    assert(type(snap.total_bytes) == "number", "snapshot missing total_bytes")
    assert(snap.total_bytes > 0, "total_bytes should be > 0")
    log.info("memprof", "test_snapshot_fields PASS, total_bytes=" .. snap.total_bytes)
end

-- test: total() returns a positive number
function T.test_total()
    local t = memprof.total()
    assert(type(t) == "number", "total() must return a number")
    assert(t > 0, "total() should be > 0")
    log.info("memprof", "test_total PASS, total=" .. t)
end

-- test: dump() runs without error
function T.test_dump()
    memprof.dump()
    log.info("memprof", "test_dump PASS")
end

-- test: diff() returns correct delta structure
function T.test_diff()
    local snap1 = memprof.snapshot()
    -- allocate some tables to create a measurable difference
    local _t = {}
    for i = 1, 20 do _t[i] = {} end
    local snap2 = memprof.snapshot()
    local d = memprof.diff(snap1, snap2)
    assert(type(d) == "table", "diff() must return a table")
    assert(type(d.table) == "table", "diff missing 'table' field")
    assert(type(d.table.count_delta) == "number", "diff.table.count_delta must be number")
    assert(type(d.table.bytes_delta) == "number", "diff.table.bytes_delta must be number")
    assert(d.table.count_delta >= 20, "expected at least 20 new tables, got " .. d.table.count_delta)
    assert(type(d.total_bytes_delta) == "number", "diff missing total_bytes_delta")
    log.info("memprof", "test_diff PASS, new_tables=" .. d.table.count_delta ..
             ", bytes_delta=" .. d.total_bytes_delta)
end

-- test: two consecutive snapshots without allocation are stable
function T.test_snapshot_stability()
    collectgarbage()
    local s1 = memprof.snapshot()
    local s2 = memprof.snapshot()
    -- allow up to 4KB difference (snapshot tables themselves cost memory)
    local delta = math.abs(s2.total_bytes - s1.total_bytes)
    assert(delta < 4096, "snapshot not stable: delta=" .. delta)
    log.info("memprof", "test_snapshot_stability PASS, delta=" .. delta)
end

return T
