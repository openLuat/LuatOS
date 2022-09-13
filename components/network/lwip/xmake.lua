

target("lwip")
    set_kind("static")
    add_files("**/*.c")
    add_includedirs("include",{public = true})
    add_includedirs("port",{public = true})
    add_includedirs("port/arch",{public = true})
    add_includedirs("../../c_common",{public = true})
target_end()
