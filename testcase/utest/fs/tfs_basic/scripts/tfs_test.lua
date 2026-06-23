local tfs = rawget(_G, "tfs")

local M = {}

local function run_tfs_case(case_name)
    assert(tfs ~= nil, "tfs module not loaded")
    assert(type(tfs.utest) == "function", "tfs.utest 不存在")
    local ok = tfs.utest(case_name)
    assert(ok == true, "tfs.utest(" .. tostring(case_name) .. ") 应返回 true")
end

function M.test_format_mount_remount()
    run_tfs_case("format_mount_remount")
end

function M.test_inband_tags_persistence()
    run_tfs_case("inband_tags_persistence")
end

function M.test_mkfs_powercycle_generation()
    run_tfs_case("mkfs_powercycle_generation")
end

function M.test_unlink_powercycle_no_resurrect()
    run_tfs_case("unlink_powercycle_no_resurrect")
end

function M.test_flush_without_close_delta_replay()
    run_tfs_case("flush_without_close_delta_replay")
end

function M.test_closed_download_delta_replay()
    run_tfs_case("closed_download_delta_replay")
end

function M.test_checkpoint_reserve_enospc()
    run_tfs_case("checkpoint_reserve_enospc")
end

function M.test_high_occupancy_unmount_checkpoint()
    run_tfs_case("high_occupancy_unmount_checkpoint")
end

function M.test_high_occupancy_download_delta()
    run_tfs_case("high_occupancy_download_delta")
end

function M.test_checkpoint_anchor_start()
    run_tfs_case("checkpoint_anchor_start")
end

function M.test_anchor_publish_failure_keeps_old()
    run_tfs_case("anchor_publish_failure_keeps_old")
end

function M.test_auto_checkpoint_close_batch()
    run_tfs_case("auto_checkpoint_close_batch")
end

function M.test_bad_block_read_failure()
    run_tfs_case("bad_block_read_failure")
end

function M.test_full_scan_reclaims_checkpoint_blocks()
    run_tfs_case("full_scan_reclaims_checkpoint_blocks")
end

function M.test_c_layer_selftests()
    run_tfs_case("c_layer_selftests")
end

return M