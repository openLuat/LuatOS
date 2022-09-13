

target("network_adapter")
    set_kind("static")
    add_files("*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../../mbedtls/include",{public = true})
    add_includedirs("../../ethernet/common",{public = true})
    add_includedirs("../../ethernet/w5500",{public = true})
target_end()
