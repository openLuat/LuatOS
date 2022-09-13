


target("flashdb")
    set_kind("static")
    add_files("src/*.c")
    add_includedirs("inc",{public = true})
    add_includedirs("../fal/inc",{public = true})
target_end()
