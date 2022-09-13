


target("cmux")
    set_kind("static")
    add_files("*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../../shell",{public = true})
target_end()
