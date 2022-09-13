


target("camera")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../../ui/lcd",{public = true})
    add_includedirs("../../ui/u8g2",{public = true})
target_end()
