set_project("luac")
set_xmakever("2.6.3")

set_version("1.0.3", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

local luatos = "../../"

-- set warning all as error
set_warnings("allextra")
set_optimize("fastest")
-- set language: c11
set_languages("c11", "cxx11")

add_defines("__LUATOS__", "__XMAKE_BUILD__")
add_defines("MBEDTLS_CONFIG_FILE=\"mbedtls_config_mini.h\"")

--add_ldflags("-Wl,-gc-sections")
if os.getenv("VM_64bit") == "1" then
    add_defines("LUAT_CONF_VM_64bit")
end

if is_host("windows") then
    -- add_defines("LUA_USE_WINDOWS")
    add_cflags("/utf-8")
    -- add_ldflags("-static")
-- elseif is_host("linux") then
--     add_defines("LUA_USE_LINUX")
-- elseif is_host("macos") then
--     add_defines("LUA_USE_MACOSX")
end


add_includedirs("include",{public = true})
add_includedirs(luatos.."lua/include",{public = true})
add_includedirs(luatos.."luat/include",{public = true})



target("luatos-lua")
    -- set kind
    set_kind("binary")
    set_targetdir("$(buildir)/out")

    add_files("src/*.c",{public = true})
    add_deps("luatos")
target_end()



target("luatos-luac")
    -- set kind
    set_kind("binary")
    set_targetdir("$(buildir)/out")

    add_files("src/*.c",{public = true})
    add_deps("luatos")
    add_defines("LUAT_USE_LUAC")
target_end()


target("luatos")
    -- set kind
    set_kind("static")
    set_targetdir("$(buildir)/out")
    
    -- add deps
    add_files("port/*.c",{public = true})

    add_files(luatos.."lua/src/*.c")
    -- printf
    add_includedirs(luatos.."components/printf",{public = true})
    add_files(luatos.."components/printf/*.c")
    
    -- add_files(luatos.."luat/modules/*.c")

    add_files(luatos.."luat/modules/crc.c"
            ,luatos.."luat/modules/luat_base.c"
            ,luatos.."luat/modules/luat_lib_fs.c"
            ,luatos.."luat/modules/luat_lib_rtos.c"
            ,luatos.."luat/modules/luat_lib_timer.c"
            ,luatos.."luat/modules/luat_lib_log.c"
            ,luatos.."luat/modules/luat_lib_zbuff.c"
            ,luatos.."luat/modules/luat_lib_pack.c"
            ,luatos.."luat/modules/luat_lib_crypto.c"
            )

    add_files(luatos.."luat/vfs/*.c")
    remove_files(luatos .. "luat/vfs/luat_fs_lfs2.c")
    remove_files(luatos .. "luat/vfs/luat_fs_luadb.c")
    remove_files(luatos .. "luat/vfs/luat_fs_fatfs.c")
    remove_files(luatos .. "luat/vfs/luat_fs_onefile.c")
    -- lfs
    -- add_includedirs(luatos.."components/lfs")
    -- add_files(luatos.."components/lfs/*.c")

    -- add_files(luatos.."components/sfd/*.c")
    -- lua-cjson
    add_includedirs(luatos.."components/lua-cjson")
    add_files(luatos.."components/lua-cjson/*.c")
    -- cjson
    -- add_includedirs(luatos.."components/cjson")
    -- add_files(luatos.."components/cjson/*.c")
    -- mbedtls
    add_files(luatos.."components/mbedtls/library/*.c")
    add_includedirs(luatos.."components/mbedtls/include")
    -- iotauth
    add_files(luatos.."components/iotauth/luat_lib_iotauth.c")
    -- crypto
    add_files(luatos.."components/crypto/**.c")
    -- protobuf
    -- add_includedirs(luatos.."components/serialization/protobuf")
    -- add_files(luatos.."components/serialization/protobuf/*.c")
    -- libgnss
    -- add_includedirs(luatos.."components/minmea")
    -- add_files(luatos.."components/minmea/*.c")
    -- rsa
    add_files(luatos.."components/rsa/**.c")
    
target_end()
