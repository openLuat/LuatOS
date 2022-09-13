

includes("adapter")
includes("fota")
includes("libemqtt")
includes("libhttp")
includes("ota")

target("network")
    set_kind("static")
    add_deps("ota")
    add_deps("fota")
    add_deps("libemqtt")
    add_deps("libhttp")
target_end()
