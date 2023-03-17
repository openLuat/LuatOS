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

add_defines("__LUATOS__", "__XMAKE_BUILD__")
add_cflags("-ffunction-sections","-fdata-sections", "-Wl,--gc-sections","-D_POSIX_C_SOURCE=199309L")
add_ldflags("-ffunction-sections","-fdata-sections", "-Wl,--gc-sections", "-lreadline","-lm","-pthread")

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

    add_files(luatos.."lua/src/*.c")
    add_files(luatos.."luat/modules/*.c")
    add_files(luatos.."luat/vfs/*.c")
    add_files(luatos.."components/common/*.c")
    -- add_files(luatos.."components/lcd/*.c")
    -- add_files(luatos.."components/sfd/*.c")
    -- add_files(luatos.."components/sfud/*.c")
    -- add_files(luatos.."components/statem/*.c")
    -- add_files(luatos.."components/nr_micro_shell/*.c")
    -- add_files(luatos.."components/eink/*.c")
    -- add_files(luatos.."components/epaper/*.c")
    -- add_files(luatos.."components/iconv/*.c")
    add_files(luatos.."components/lfs/*.c")
    add_files(luatos.."components/lua-cjson/*.c")
    -- add_files(luatos.."components/minmea/*.c")
    -- add_files(luatos.."components/u8g2/*.c")
    -- add_files(luatos.."components/fatfs/*.c")
    add_files(luatos.."luat/weak/*.c")
    -- add_files(luatos.."components/coremark/*.c")
    add_files(luatos.."components/cjson/*.c")
    
    add_includedirs(luatos.."lua/include",{public = true})
    add_includedirs(luatos.."luat/include",{public = true})
    add_includedirs(luatos.."components/common",{public = true})
    add_includedirs(luatos.."components/lcd",{public = true})
    add_includedirs(luatos.."components/sfud",{public = true})
    add_includedirs(luatos.."components/statem",{public = true})
    add_includedirs(luatos.."components/coremark",{public = true})
    add_includedirs(luatos.."components/cjson",{public = true})
    
    add_includedirs(luatos.."components/eink")
    add_includedirs(luatos.."components/epaper")
    add_includedirs(luatos.."components/iconv")
    add_includedirs(luatos.."components/lfs")
    add_includedirs(luatos.."components/lua-cjson")
    add_includedirs(luatos.."components/minmea")
    add_includedirs(luatos.."components/u8g2")
    add_includedirs(luatos.."components/fatfs")

    -- -- gtfont
    -- add_includedirs(luatos.."components/gtfont",{public = true})
    -- add_files(luatos.."components/gtfont/*.c")

    -- add_files(luatos.."components/i2c-tools/*.c")
    -- add_includedirs(luatos.."components/i2c-tools")
    
    -- add_files(luatos.."components/flashdb/src/*.c")
    -- add_files(luatos.."components/fal/src/*.c")
    -- add_includedirs(luatos.."components/flashdb/inc",{public = true})
    -- add_includedirs(luatos.."components/fal/inc",{public = true})

    add_files(luatos.."components/mbedtls/library/*.c")
    add_includedirs(luatos.."components/mbedtls/include")

    -- add_files(luatos.."components/zlib/*.c")
    -- add_includedirs(luatos.."components/zlib")

    -- add_files(luatos.."components/mlx90640-library/*.c")
    -- add_includedirs(luatos.."components/mlx90640-library")

    -- add_files(luatos.."components/camera/*.c")
    -- add_includedirs(luatos.."components/camera")

    -- add_files(luatos.."components/soft_keyboard/*.c")
    -- add_includedirs(luatos.."components/soft_keyboard")

    -- add_files(luatos.."components/multimedia/*.c")
    -- add_includedirs(luatos.."components/multimedia")

    -- add_files(luatos.."components/io_queue/*.c")
    -- add_includedirs(luatos.."components/io_queue")

    -- add_files(luatos.."components/tjpgd/*.c")
    -- add_includedirs(luatos.."components/tjpgd")

    -- -- shell & cmux
    -- add_includedirs(luatos.."components/shell",{public = true})
    -- add_includedirs(luatos.."components/cmux",{public = true})
    -- add_files(luatos.."components/shell/*.c")
    -- add_files(luatos.."components/cmux/*.c")

    -- -- ymodem
    -- add_includedirs(luatos.."components/ymodem",{public = true})
    -- add_files(luatos.."components/ymodem/*.c")

    -- -- usbapp
    -- add_includedirs(luatos.."components/usbapp",{public = true})
    -- add_files(luatos.."components/usbapp/*.c")
    -- -- network
    -- add_includedirs(luatos.."components/ethernet/common",{public = true})
    -- add_includedirs(luatos.."components/ethernet/w5500",{public = true})
    -- add_includedirs(luatos.."components/network/adapter",{public = true})
    -- add_files(luatos.."components/ethernet/**.c")
    -- add_files(luatos.."components/network/adapter/*.c")

    -- -- mqtt
    -- add_includedirs(luatos.."components/network/libemqtt",{public = true})
    -- add_files(luatos.."components/network/libemqtt/*.c")

    -- -- sntp
    -- add_includedirs(luatos.."components/network/libsntp",{public = true})
    -- add_files(luatos.."components/network/libsntp/*.c")

    -- -- http_parser
    -- add_includedirs(luatos.."components/network/http_parser",{public = true})
    -- add_files(luatos.."components/network/http_parser/*.c")
    
    -- -- libftp
    -- add_includedirs(luatos.."components/network/libftp",{public = true})
    -- add_files(luatos.."components/network/libftp/*.c")
    
    -- -- websocket
    -- add_includedirs(luatos.."components/network/websocket",{public = true})
    -- add_files(luatos.."components/network/websocket/*.c")

    
    -- -- http
    -- add_includedirs(luatos.."components/network/libhttp",{public = true})
    -- -- add_files(luatos.."components/network/libhttp/luat_lib_http.c")
    -- add_files(luatos.."components/network/libhttp/*.c")

    -- iotauth
    add_files(luatos.."components/iotauth/luat_lib_iotauth.c")

    -- qrcode
    add_includedirs(luatos.."components/qrcode",{public = true})
    add_files(luatos.."components/qrcode/*.c")

    -- -- lora
    -- add_includedirs(luatos.."components/lora",{public = true})
    -- add_files(luatos.."components/lora/**.c")

    -- -- fonts
    -- add_includedirs(luatos.."components/luatfonts",{public = true})
    -- add_files(luatos.."components/luatfonts/**.c")

    -- crypto
    add_files(luatos.."components/crypto/**.c")

    -- protobuf
    add_includedirs(luatos.."components/serialization/protobuf")
    add_files(luatos.."components/serialization/protobuf/*.c")
    
    -- rsa
    add_includedirs(luatos.."components/rsa/inc")
    add_files(luatos.."components/rsa/**.c")

    -- -- 添加fskv
    -- add_includedirs(luatos.."components/fskv")
    -- add_files(luatos.."components/fskv/*.c")

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

    add_files(luatos.."components/lvgl/**.c")
    -- 默认不编译lv的demos, 节省大量的编译时间
    remove_files(luatos.."components/lvgl/lv_demos/**.c")

    -- tjpgd
    add_files(luatos.."components/tjpgd/*.c")
    add_includedirs(luatos.."components/tjpgd")

target_end()
