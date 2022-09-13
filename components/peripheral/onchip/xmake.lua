


target("onchip")
    set_kind("static")
    add_files("src/*.c")
    add_includedirs("inc",{public = true})
target_end()
