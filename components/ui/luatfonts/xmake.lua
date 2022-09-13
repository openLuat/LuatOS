


target("luatfonts")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../u8g2",{public = true})
    add_includedirs("../lvgl",{public = true})
    add_includedirs("../lvgl/src",{public = true})
target_end()
