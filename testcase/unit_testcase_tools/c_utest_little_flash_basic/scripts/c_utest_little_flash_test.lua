-- little_flash FTL tests have been removed (Phase 1: FTL stripped from little_flash).
-- Real NAND FTL (bad-block / wear-levelling / GC) now lives in pgfs.
-- The little_flash driver itself is still tested via the normal script-layer tests.
local t = {}
local lf_suite = {}

function lf_suite.test_placeholder_ftl_stripped()
    -- FTL tests removed in Phase 1 migration (FTL → pgfs).
    -- little_flash NAND operations now use direct identity-address mapping.
    assert(true, "ftl_stripped_placeholder")
end

t.lf_suite = lf_suite
return t
