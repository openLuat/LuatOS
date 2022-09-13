


target("i2c-tools")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
target_end()
