local t = {}

local lf_suite = {}

function lf_suite.test_little_flash_utest_identity_map()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_identity_map") == true, "lf.utest(ftl_identity_map) 应为 true")
end

function lf_suite.test_little_flash_utest_badblock_remap()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_badblock_remap") == true, "lf.utest(ftl_badblock_remap) 应为 true")
end

function lf_suite.test_little_flash_utest_powerfail_recovery()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_powerfail_recovery") == true, "lf.utest(ftl_powerfail_recovery) 应为 true")
end

function lf_suite.test_little_flash_utest_gc_trigger()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_gc_trigger") == true, "lf.utest(ftl_gc_trigger) 应为 true")
end

function lf_suite.test_little_flash_utest_gc_checkpoint_failure_keeps_journal()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_gc_checkpoint_failure_keeps_journal") == true, "lf.utest(ftl_gc_checkpoint_failure_keeps_journal) 应为 true")
end

function lf_suite.test_little_flash_utest_init_stats()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_init_stats") == true, "lf.utest(ftl_init_stats) 应为 true")
end

function lf_suite.test_little_flash_utest_oob_read_error_scan()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_oob_read_error_scan") == true, "lf.utest(ftl_oob_read_error_scan) 应为 true")
end

function lf_suite.test_little_flash_utest_wait_ready_timeout()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_wait_ready_timeout") == true, "lf.utest(ftl_wait_ready_timeout) 应为 true")
end

function lf_suite.test_little_flash_utest_recover_crc_invalid()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_recover_crc_invalid") == true, "lf.utest(ftl_recover_crc_invalid) 应为 true")
end

function lf_suite.test_little_flash_utest_recover_journal_out_of_range()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_recover_journal_out_of_range") == true, "lf.utest(ftl_recover_journal_out_of_range) 应为 true")
end

function lf_suite.test_little_flash_utest_repeat_mark_bad_idempotent()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_repeat_mark_bad_idempotent") == true, "lf.utest(ftl_repeat_mark_bad_idempotent) 应为 true")
end

function lf_suite.test_little_flash_utest_capacity_safety_margin()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_capacity_safety_margin") == true, "lf.utest(ftl_capacity_safety_margin) 应为 true")
end

function lf_suite.test_little_flash_utest_recover_state_machine()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_recover_state_machine") == true, "lf.utest(ftl_recover_state_machine) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_persist_replay()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_persist_replay") == true, "lf.utest(ftl_metadata_persist_replay) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_corrupt_fallback()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_corrupt_fallback") == true, "lf.utest(ftl_metadata_corrupt_fallback) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_latest_valid_slot()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_latest_valid_slot") == true, "lf.utest(ftl_metadata_latest_valid_slot) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_corrupt_apply_fallback_sane()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_corrupt_apply_fallback_sane") == true, "lf.utest(ftl_metadata_corrupt_apply_fallback_sane) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_slot_overflow_guard()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_slot_overflow_guard") == true, "lf.utest(ftl_metadata_slot_overflow_guard) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_tail_bad_blocks_fallback()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_tail_bad_blocks_fallback") == true, "lf.utest(ftl_metadata_tail_bad_blocks_fallback) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_region_continuity_on_tail_bad()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_region_continuity_on_tail_bad") == true, "lf.utest(ftl_metadata_region_continuity_on_tail_bad) 应为 true")
end

function lf_suite.test_little_flash_utest_metadata_recover_ignores_historical_bad_journal()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_metadata_recover_ignores_historical_bad_journal") == true, "lf.utest(ftl_metadata_recover_ignores_historical_bad_journal) 应为 true")
end

function lf_suite.test_little_flash_utest_init_refreshes_free_spares_after_recover()
    assert(lf and type(lf.utest) == "function", "lf.utest 不存在")
    assert(lf.utest("ftl_init_refreshes_free_spares_after_recover") == true, "lf.utest(ftl_init_refreshes_free_spares_after_recover) 应为 true")
end

t.lf_suite = lf_suite
return t
