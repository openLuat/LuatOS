

target("lcd")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../u8g2/",{public = true})
    add_includedirs("../qrcode/",{public = true})
    add_includedirs("../tjpgd/",{public = true})
    add_includedirs("../gtfont/",{public = true})
target_end()
