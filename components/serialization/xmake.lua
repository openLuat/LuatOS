

includes("cjson")
includes("cmux")
includes("lua-cjson")
includes("miniz")
includes("protobuf")
includes("zlib")

target("serialization")
    set_kind("static")
    add_deps("cjson")
    add_deps("cmux")
    add_deps("lua-cjson")
    add_deps("miniz")
    add_deps("protobuf")
    add_deps("zlib")
target_end()
