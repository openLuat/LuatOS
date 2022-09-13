


target("dbg")
    set_kind("static")
    add_files("./*.c")
    add_includedirs(".",{public = true})
    add_includedirs("../../serialization/cmux",{public = true})
    add_includedirs("../../serialization/cjson",{public = true})
target_end()
