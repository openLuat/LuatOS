local t = {}

local ndk_suite = {}
function ndk_suite.test_ndk_utest_available()
    assert(ndk and type(ndk.utest) == "function", "ndk.utest does not exist")
end

function ndk_suite.test_ndk_utest_lifecycle_basic()
    assert(ndk.utest("lifecycle_basic") == true, "ndk.utest(lifecycle_basic) should be true")
end

function ndk_suite.test_ndk_utest_invalid_image()
    assert(ndk.utest("invalid_image") == true, "ndk.utest(invalid_image) should be true")
end

function ndk_suite.test_ndk_utest_isa_option()
    assert(ndk.utest("isa_option_rv32imf") == true, "ndk.utest(isa_option_rv32imf) should be true")
end

function ndk_suite.test_ndk_utest_exec_fadd()
    assert(ndk.utest("exec_fadd") == true, "ndk.utest(exec_fadd) should be true")
end

t.ndk_suite = ndk_suite
return t
