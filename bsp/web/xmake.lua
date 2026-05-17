set_project("luatos-web")
set_xmakever("3.0.4")

set_version("0.0.1", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

local luatos = "../../"

set_optimize("fastest")
set_languages("gnu11", "cxx17")

add_defines("__LUATOS__", "__XMAKE_BUILD__", "__EMSCRIPTEN__")

add_includedirs("include", {public = true})
add_includedirs("../pc/include", {public = true})
add_includedirs(luatos .. "lua/include", {public = true})
add_includedirs(luatos .. "luat/include", {public = true})
add_includedirs("../pc/port/posix", {public = true})

target("luatos-lua-web")
    set_kind("binary")
    set_targetdir("$(builddir)/out")

    add_files("src/*.c")
    add_files("port/network/*.c")

    add_files("../pc/port/luat_base_mini.c")
    add_files("../pc/port/luat_cmds.c")
    add_files("../pc/port/luat_crypto_mini.c")
    add_files("../pc/port/luat_fs_mini.c")
    add_files("../pc/port/luat_log_mini.c")
    add_files("../pc/port/luat_luadb2.c")
    add_files("../pc/port/luat_malloc_mini.c")
    add_files("../pc/port/luat_pcconf_pc.c")
    add_files("../pc/port/luat_mcu_pc.c")
    add_files("../pc/port/posix/luat_timer_engine.c")
    add_files("../pc/port/rtos/*.c")
    add_files("../pc/port/mock/*.c")

    add_files(luatos .. "lua/src/*.c")

    add_includedirs(luatos .. "components/printf", {public = true})
    add_files(luatos .. "components/printf/*.c")

    add_files(
        luatos .. "luat/modules/luat_base.c",
        luatos .. "luat/modules/luat_lib_fs.c",
        luatos .. "luat/modules/luat_lib_rtos.c",
        luatos .. "luat/modules/luat_lib_timer.c",
        luatos .. "luat/modules/luat_lib_log.c",
        luatos .. "luat/modules/luat_lib_zbuff.c",
        luatos .. "luat/modules/luat_lib_pack.c",
        luatos .. "luat/modules/luat_lib_mcu.c",
        luatos .. "luat/modules/luat_lib_bit64.c",
        luatos .. "luat/modules/luat_main.c"
    )

    add_files(luatos .. "luat/vfs/*.c")
    remove_files(luatos .. "luat/vfs/luat_fs_onefile.c")

    add_includedirs(luatos .. "components/lfs")
    add_files(luatos .. "components/lfs/*.c")

    add_includedirs(luatos .. "components/lua-cjson")
    add_files(luatos .. "components/lua-cjson/*.c")

    add_includedirs(luatos .. "components/cjson")
    add_files(luatos .. "components/cjson/*.c")

    add_includedirs(luatos .. "components/miniz")
    add_files(luatos .. "components/miniz/*.c")

    add_includedirs(luatos .. "components/common", {public = true})
    add_files(luatos .. "components/common/*.c")
