


target("vmx")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
target_end()
