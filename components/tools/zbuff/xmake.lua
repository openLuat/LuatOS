


target("zbuff")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../pack",{public = true})
target_end()
