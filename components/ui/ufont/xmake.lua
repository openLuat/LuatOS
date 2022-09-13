

target("ufont")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../lvgl/",{public = true})
    add_includedirs("../lvgl/src/lv_font",{public = true})
target_end()
