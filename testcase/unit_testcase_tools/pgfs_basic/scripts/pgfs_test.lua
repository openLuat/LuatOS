local pgfs = rawget(_G, "pgfs")
local pgfs_tests = {}

local function run_pgfs_case(case_name)
    assert(pgfs ~= nil, "pgfs module not loaded")
    assert(pgfs and type(pgfs.utest) == "function", "pgfs.utest 不存在")
    local ok = pgfs.utest(case_name)
    assert(ok == true, "pgfs.utest(" .. tostring(case_name) .. ") 应返回 true")
end

function pgfs_tests.test_pgfs_utest_generation_fallback()
    run_pgfs_case("generation_fallback_prefers_latest_valid")
end

function pgfs_tests.test_pgfs_utest_durable_boundary()
    run_pgfs_case("fclose_is_durable_boundary")
end

function pgfs_tests.test_pgfs_utest_powercut_recovery()
    run_pgfs_case("controlled_powercut_before_checkpoint")
end

function pgfs_tests.test_pgfs_utest_invalid_args()
    run_pgfs_case("control_invalid_args")
end

function pgfs_tests.test_pgfs_utest_c_layer_selftests()
    run_pgfs_case("c_layer_selftests")
end

function pgfs_tests.test_pgfs_utest_info_rebuild()
    run_pgfs_case("info_fast_path_and_rebuild")
end

function pgfs_tests.test_pgfs_utest_getc_path()
    run_pgfs_case("getc_line_read_path")
end

function pgfs_tests.test_pgfs_utest_directory_ops()
    run_pgfs_case("directory_listing_and_existence")
end

function pgfs_tests.test_pgfs_utest_large_unzip_repro()
    run_pgfs_case("large_unzip_repro")
end

return pgfs_tests
