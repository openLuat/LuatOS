


target("sfd")
    set_kind("static")
    add_files("./*.c")
    add_includedirs("../../fs/lfs",{public = true})
target_end()
