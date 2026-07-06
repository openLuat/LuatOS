local tfs = rawget(_G, "tfs")

local M = {}

function M.test_c_layer_selftests()
    assert(tfs ~= nil, "tfs module not loaded")
    assert(type(tfs.utest) == "function", "tfs.utest missing")
    assert(tfs.utest("c_layer_selftests") == true,
           "TFS C-layer selftests failed")
end

return M
