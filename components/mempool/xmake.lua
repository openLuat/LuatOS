
includes("bget")
includes("tlsf3")

target("mempool")
    set_kind("static")
    add_deps("bget", "tlsf3")
target_end()
