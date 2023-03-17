set_project("LuatOS-BSP")
set_xmakever("2.6.3")

set_version("0.0.3", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

-- 这里用llvm和clang了,尝试一下
add_requires("llvm")
set_toolchains("@llvm")

local luatos = "../../"

-- set warning all as error
set_warnings("allextra")
set_optimize("fastest")
-- set language: c11
set_languages("c11", "cxx11")

add_defines("__LUATOS__", "__XMAKE_BUILD__", "WIN32")
add_ldflags("-lwinmm","-luser32","-lncrypt","-lAdvapi32","-lGdi32")

add_requires("libsdl")
add_packages("libsdl")

target("luatos")
    -- set kind
    set_kind("binary")
    set_targetdir("$(buildir)/out")
    
    -- add deps

    add_files("src/*.c",{public = true})
    add_files("port/*.c",{public = true})
    add_includedirs("include",{public = true})

    add_includedirs(luatos.."lua/include",{public = true})
    add_files(luatos.."lua/src/*.c")

    add_includedirs(luatos.."luat/include",{public = true})
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
            ,luatos.."luat/modules/luat_lib_libcoap.c"
            ,luatos.."luat/modules/luat_lib_uart.c"
            ,luatos.."luat/modules/luat_lib_gpio.c"
            ,luatos.."luat/modules/luat_lib_i2c.c"
            ,luatos.."luat/modules/luat_lib_spi.c"
            ,luatos.."luat/modules/luat_irq.c"
            )

    add_files(luatos.."luat/vfs/*.c")
    -- lfs
    add_includedirs(luatos.."components/lfs")
    add_files(luatos.."components/lfs/*.c")

    add_files(luatos.."components/sfd/*.c")
    -- lua-cjson
    add_includedirs(luatos.."components/lua-cjson")
    add_files(luatos.."components/lua-cjson/*.c")
    -- miniz
    add_includedirs(luatos.."components/miniz")
    add_files(luatos.."components/miniz/*.c")

    -- add_includedirs(luatos.."components/common")
    -- add_files(luatos.."components/common/*.c")

    -- add_includedirs(luatos.."components/fatfs")
    -- add_files(luatos.."components/fatfs/*.c")

    -- sdl2
    add_includedirs(luatos.."components/ui/sdl2")
    add_files(luatos.."components/ui/sdl2/*.c")
    -- u8g2
    add_includedirs(luatos.."components/u8g2")
    add_files(luatos.."components/u8g2/*.c")
    -- lcd
    add_includedirs(luatos.."components/lcd")
    add_files(luatos.."components/lcd/*.c")
    -- lvgl
    add_includedirs(luatos.."components/lvgl")
    add_includedirs(luatos.."components/lvgl/binding")
    add_includedirs(luatos.."components/lvgl/gen")
    add_includedirs(luatos.."components/lvgl/src")
    add_includedirs(luatos.."components/lvgl/font")
    add_includedirs(luatos.."components/lvgl/src/lv_font")
    add_includedirs(luatos.."components/lvgl/sdl2")
    add_files(luatos.."components/lvgl/**.c")
    -- 默认不编译lv的demos, 节省大量的编译时间
    remove_files(luatos.."components/lvgl/lv_demos/**.c")
    -- -- eink
    -- add_includedirs(luatos.."components/eink")
    -- add_includedirs(luatos.."components/epaper")
    -- add_files(luatos.."components/eink/*.c")
    -- add_files(luatos.."components/epaper/*.c")
    -- tjpgd
    add_files(luatos.."components/tjpgd/*.c")
    add_includedirs(luatos.."components/tjpgd")
    -- cjson
    add_includedirs(luatos.."components/cjson")
    add_files(luatos.."components/cjson/*.c")
    -- mbedtls
    add_files(luatos.."components/mbedtls/library/*.c")
    add_includedirs(luatos.."components/mbedtls/include")
    -- iotauth
    add_files(luatos.."components/iotauth/luat_lib_iotauth.c")
    -- qrcode
    add_includedirs(luatos.."components/qrcode")
    add_files(luatos.."components/qrcode/*.c")
    -- crypto
    add_files(luatos.."components/crypto/**.c")
    -- protobuf
    add_includedirs(luatos.."components/serialization/protobuf")
    add_files(luatos.."components/serialization/protobuf/*.c")
    -- libgnss
    add_includedirs(luatos.."components/minmea")
    add_files(luatos.."components/minmea/*.c")
    -- rsa
    add_files(luatos.."components/rsa/**.c")
    
target_end()
