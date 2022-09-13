

add_includedirs(".",{public = true})
target("qrcode")
    set_kind("static")
    add_files("./*.c")
target_end()
