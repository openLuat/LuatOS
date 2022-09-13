


target("tjpgd")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../lcd",{public = true})
    add_includedirs("../u8g2/",{public = true})
target_end()
