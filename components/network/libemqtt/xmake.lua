

target("libemqtt")
    set_kind("static")
    add_files("*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../adapter",{public = true})
    add_includedirs("../../mbedtls/include",{public = true})
target_end()
