

-- includes("adapter")
-- includes("fota")
-- includes("libemqtt")
-- includes("libhttp")
includes("ota")

target("network")
    set_kind("static")
    add_deps("ota")
target_end()
