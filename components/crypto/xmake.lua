


target("crypto")
    set_kind("static")
    add_files("src/*.c")
    add_includedirs("inc",{public = true})
    add_includedirs("../mbedtls/include",{public = true})
target_end()
