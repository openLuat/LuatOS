
target("mbedtls")
    set_kind("static")
    
    add_includedirs("include",{public = true})
    add_files("library/*.c")
target_end()
