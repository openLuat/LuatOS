set_project("luac")
set_xmakever("2.8.2")

set_version("1.0.3", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

local luatos = "../../"

add_requires("libuv v1.49.2")
add_packages("libuv")


add_requires("gmssl")
add_packages("gmssl")

-- set warning all as error
set_warnings("allextra")
set_optimize("fastest")
-- set language: c11
set_languages("gnu11")

-- 核心宏定义
add_defines("__LUATOS__", "__XMAKE_BUILD__")
-- mbedtls使用本地自定义配置
add_defines("MBEDTLS_CONFIG_FILE=\"mbedtls_config_pc.h\"")
-- coremark配置迭代数量
add_defines("ITERATIONS=300000")

if os.getenv("VM_64bit") == "1" then
    add_defines("LUAT_CONF_VM_64bit")
end

if os.getenv("LUAT_USE_GUI") == "y" then
    add_defines("LUAT_USE_GUI=1")
    add_requires("libsdl2")
    add_packages("libsdl2")
    -- freetype 用于 PC 端 gtfont 仿真渲染（使用本地freetype）
    -- add_requires("freetype")
    -- add_packages("freetype")
    -- add_requires("libsdl 2.26.2")
    -- add_packages("libsdl 2.26.2")
end

if os.getenv("LUAT_USE_LVGL9") == "y" then
    add_defines("LUAT_USE_LVGL9=1")
end

if is_host("windows") then
    add_defines("LUAT_USE_WINDOWS")
    add_defines("_CRT_SECURE_NO_WARNINGS")
    add_cflags("/utf-8")
    add_includedirs("win32/include")
elseif is_host("linux") then
    add_defines("LUA_USE_LINUX")
    add_cflags("-ffunction-sections -fdata-sections")
    add_cflags("-Wno-unused-parameter -Wno-unused-function -Wno-unused-variable")
    add_ldflags("-Wl,--gc-sections")
elseif is_host("macos") then
    add_defines("LUA_USE_MACOSX")
end


add_includedirs("include",{public = true})
add_includedirs(luatos.."lua/include",{public = true})
add_includedirs(luatos.."luat/include",{public = true})
-- add_includedirs("libuv/include",{public = true})


target("luatos-lua")
    -- set kind
    set_kind("binary")
    set_targetdir("$(builddir)/out")

    add_files("src/*.c",{public = true})
    add_files("port/**.c")

    add_files(luatos.."lua/src/*.c")
    -- printf
    add_includedirs(luatos.."components/printf",{public = true})
    add_files(luatos.."components/printf/*.c")
    
    -- add_files(luatos.."luat/modules/*.c")

    if is_plat("linux", "macosx") then
        add_links("pthread", "m", "dl")
        add_links("avformat", "avcodec", "avutil", "swresample")    -- FFmpeg
    end

    add_files(luatos.."luat/modules/luat_base.c"
            ,luatos.."luat/modules/luat_lib_fs.c"
            ,luatos.."luat/modules/luat_lib_rtos.c"
            ,luatos.."luat/modules/luat_lib_timer.c"
            ,luatos.."luat/modules/luat_lib_log.c"
            ,luatos.."luat/modules/luat_lib_zbuff.c"
            ,luatos.."luat/modules/luat_lib_pack.c"
            ,luatos.."luat/modules/luat_lib_crypto.c"
            ,luatos.."luat/modules/luat_lib_mcu.c"
            ,luatos.."luat/modules/luat_lib_bit64.c"
            ,luatos.."luat/modules/luat_lib_uart.c"
            ,luatos.."luat/modules/luat_lib_mqttcore.c"
            ,luatos.."luat/modules/luat_lib_libcoap.c"
            ,luatos.."luat/modules/luat_lib_rtc.c"
            ,luatos.."luat/modules/luat_lib_gpio.c"
            ,luatos.."luat/modules/luat_lib_spi.c"
            ,luatos.."luat/modules/luat_lib_i2c.c"
            ,luatos.."luat/modules/luat_lib_i2s.c"
            ,luatos.."luat/modules/luat_lib_wdt.c"
            ,luatos.."luat/modules/luat_lib_pm.c"
            ,luatos.."luat/modules/luat_lib_adc.c"
            ,luatos.."luat/modules/luat_lib_pwm.c"
            ,luatos.."luat/modules/luat_irq.c"
            ,luatos.."luat/modules/luat_lib_can.c"
            ,luatos.."luat/modules/luat_lib_otp.c"
            ,luatos.."luat/modules/luat_main.c"
            )

    add_files(luatos.."luat/vfs/*.c")
    -- remove_files(luatos .. "luat/vfs/luat_fs_lfs2.c")
    -- remove_files(luatos .. "luat/vfs/luat_fs_luadb.c")
    -- remove_files(luatos .. "luat/vfs/luat_fs_fatfs.c")
    remove_files(luatos .. "luat/vfs/luat_fs_onefile.c")
    -- lfs
    add_includedirs(luatos.."components/lfs")
    add_files(luatos.."components/lfs/*.c")

    -- add_files(luatos.."components/sfd/*.c")
    -- lua-cjson
    add_includedirs(luatos.."components/lua-cjson")
    add_files(luatos.."components/lua-cjson/*.c")
    -- cjson
    add_includedirs(luatos.."components/cjson")
    add_files(luatos.."components/cjson/*.c")
    -- fft core
    add_includedirs(luatos.."components/fft/inc", {public = true})
    add_files(luatos.."components/fft/src/*.c")
    add_files(luatos.."components/fft/binding/*.c")
    -- mbedtls
    add_files(luatos.."components/mbedtls/library/*.c")
    add_includedirs(luatos.."components/mbedtls/include")
    -- iotauth
    add_includedirs(luatos.."components/iotauth")
    add_files(luatos.."components/iotauth/*.c")
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

    -- gmssl
    -- add_includedirs(luatos.."components/gmssl/include")
    -- add_files(luatos.."components/gmssl/src/**.c")
    add_files(luatos.."components/gmssl/bind/*.c")

    -- iconv
    add_includedirs(luatos.."components/iconv")
    add_files(luatos.."components/iconv/*.c")

    -- miniz
    add_files(luatos .. "components/miniz/*.c")
    add_includedirs(luatos .. "components/miniz")

    -- fskv
    add_includedirs(luatos.."components/fskv")
    add_files(luatos.."components/fskv/luat_lib_fskv.c")

    -- ymodem
    add_includedirs(luatos.."components/ymodem",{public = true})
    add_files(luatos.."components/ymodem/*.c")

    -- profiler
    add_includedirs(luatos.."components/mempool/profiler/include",{public = true})
    add_files(luatos.."components/mempool/profiler/**.c")

    -- fastlz
    add_includedirs(luatos.."components/fastlz",{public = true})
    add_files(luatos.."components/fastlz/*.c")

    -- c_common
    add_includedirs(luatos.."components/common",{public = true})
    add_files(luatos.."components/common/*.c")

    -- coremark
    add_includedirs(luatos.."components/coremark",{public = true})
    add_files(luatos.."components/coremark/*.c")

    -- sqlite3
    add_includedirs(luatos.."components/sqlite3/include",{public = true})
    add_files(luatos.."components/sqlite3/src/*.c")
    add_files(luatos.."components/sqlite3/binding/*.c")
    
    --mobile
    add_includedirs(luatos.."components/mobile")
    add_files(luatos.."components/mobile/*.c")

    --ffmpeg
    add_includedirs("ffmpeg_x86/include")
    add_includedirs("ffmpeg_x86")
    add_files("ffmpeg_x86/ffmpeg.c")

    -- multimedia
    add_includedirs(luatos.."components/multimedia",{public = true})
    add_files(luatos.."components/multimedia/luat_lib_multimedia_audio.c")
    add_files(luatos.."components/multimedia/luat_audio_tm8211.c")
    add_files(luatos.."components/multimedia/luat_audio_es8311.c")

    ----------------------------------------------------------------------
    -- 网络相关

    
    add_includedirs(luatos .. "components/common", {public = true})
    add_includedirs(luatos .. "components/network/adapter", {public = true})
    add_includedirs(luatos .. "components/ethernet/common", {public = true})
    add_files(luatos .. "components/network/adapter/*.c")

    -- 网络上层协议
    -- http_parser
    add_includedirs(luatos.."components/network/http_parser",{public = true})
    add_files(luatos.."components/network/http_parser/*.c")
    
    -- http
    add_includedirs(luatos.."components/network/libhttp",{public = true})
    add_files(luatos.."components/network/libhttp/*.c")

    -- libftp
    -- add_includedirs(luatos.."components/network/libftp",{public = true})
    -- add_files(luatos.."components/network/libftp/*.c")
    
    -- websocket
    add_includedirs(luatos.."components/network/websocket",{public = true})
    add_files(luatos.."components/network/websocket/*.c")

    -- sntp
    add_includedirs(luatos.."components/network/libsntp",{public = true})
    add_files(luatos.."components/network/libsntp/*.c")

    -- mqtt
    add_includedirs(luatos.."components/network/libemqtt",{public = true})
    add_files(luatos.."components/network/libemqtt/*.c")
    
    -- errdump
    add_includedirs(luatos.."components/network/errdump",{public = true})
    add_files(luatos.."components/network/errdump/*.c")

    -- ercoap
    add_includedirs(luatos.."components/network/ercoap/include",{public = true})
    add_files(luatos.."components/network/ercoap/src/*.c")
    add_files(luatos.."components/network/ercoap/binding/*.c")

    -- ws2812
    add_includedirs(luatos.."components/ws2812/include",{public = true})
    add_files(luatos.."components/ws2812/src/*.c")
    add_files(luatos.."components/ws2812/binding/*.c")

    -- onewire
    add_includedirs(luatos.."components/onewire/include",{public = true})
    -- add_files(luatos.."components/onewire/src/*.c")
    -- add_files(luatos.."components/onewire/binding/*.c")

    
    -- xxtea
    add_includedirs(luatos.."components/xxtea/include",{public = true})
    add_files(luatos.."components/xxtea/src/*.c")
    add_files(luatos.."components/xxtea/binding/*.c")

    -- fatfs
    add_includedirs(luatos.."components/fatfs")
    add_files(luatos.."components/fatfs/**.c")

    -- vtool
    add_includedirs(luatos.."components/multimedia/vtool/include")
    add_files(luatos.."components/multimedia/vtool/**.c")
    
    add_includedirs(luatos .. "components/hmeta")
    add_files(luatos .. "components/hmeta/**.c")

    if is_host("windows") then
        -- lwip & zlink
        local lwip_path = luatos .. "components/network/lwip22/"
        add_includedirs(lwip_path .. "include")
        add_files(lwip_path .. "/api/**.c")
        add_files(lwip_path .. "/core/**.c")
        add_files(lwip_path .. "/netif/**.c")
        add_files(lwip_path .. "/port/win32/*.c")
        add_defines("NO_SYS=0")
        
        add_includedirs(luatos .. "components/network/ulwip/include")
        add_files(luatos .. "components/network/ulwip/**.c")
        
        add_files(luatos .. "components/network/adapter_lwip2/*.c")
        add_includedirs(luatos .. "components/network/adapter_lwip2/")
        add_files(luatos .. "components/ethernet/common/*.c")
    else
        add_includedirs(luatos .. "components/network/lwip/include")
        add_includedirs("lwip/include")    
    end

    if os.getenv("LUAT_USE_GUI") == "y" then
        add_files("ui/*.c")
        add_defines("U8G2_USE_LARGE_FONTS=1")

        -- sdl2
        add_includedirs(luatos.."components/ui/sdl2")
        add_files(luatos.."components/ui/sdl2/*.c")
        -- u8g2
        add_includedirs(luatos.."components/u8g2")
        add_files(luatos.."components/u8g2/*.c")
        -- lcd
        add_includedirs(luatos.."components/lcd")
        add_files(luatos.."components/lcd/*.c")
        
        -- LVGL 版本选择
        if os.getenv("LUAT_USE_LVGL9") == "y" then
            -- LVGL 9.4 + EasyLVGL - 最基础组件编译
            -- LVGL 9 源码路径
            add_includedirs(luatos.."components/easylvgl/lvgl9")
            add_includedirs(luatos.."components/easylvgl/lvgl9/src")
            
            -- 先添加所有源文件
            add_files(luatos.."components/easylvgl/lvgl9/src/**.c")
            
            -- 排除不需要的组件（按优先级排序）
            -- 1. 硬件驱动（PC 模拟器不需要）
            remove_files(luatos.."components/easylvgl/lvgl9/src/drivers/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/drivers/**/*.cpp")
            
            -- 2. 硬件加速绘制引擎（只保留软件渲染 SW）
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/dma2d/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/eve/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/nema_gfx/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/nxp/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/opengles/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/renesas/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/vg_lite/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/sdl/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/espressif/**/*.c")
            remove_files(luatos.."components/easylvgl/lvgl9/src/draw/convert/**/*.c")
            
            -- 3. 库：排除所有，然后重新添加 bin_decoder（核心依赖）
            -- remove_files(luatos.."components/easylvgl/lvgl9/src/libs/**/*.c")
            -- remove_files(luatos.."components/easylvgl/lvgl9/src/libs/**/*.cpp")
            -- add_files(luatos.."components/easylvgl/lvgl9/src/libs/bin_decoder/*.c")
            
            -- 4. 其他功能模块（sysmon, translation, xml 等）
            -- remove_files(luatos.."components/easylvgl/lvgl9/src/others/**/*.c")
            -- remove_files(luatos.."components/easylvgl/lvgl9/src/others/**/*.cpp")
            
            -- 5. 操作系统抽象层（如果使用 LV_OS_NONE）
            -- remove_files(luatos.."components/easylvgl/lvgl9/src/osal/**/*.c")
            
            -- 6. 控件：先全部包含，确保编译通过
            -- 所有控件都会被编译（没有被排除）
            
            -- 7. 保留主题编译（主题需要控件的类定义）
            -- 主题文件会自动编译（没有被排除）
            
            -- EasyLVGL 核心代码
            add_includedirs(luatos.."components/easylvgl/inc")
            add_includedirs(luatos.."components/easylvgl/src")
            add_files(luatos.."components/easylvgl/src/*.c")
            
            -- EasyLVGL Lua 绑定
            add_includedirs(luatos.."components/easylvgl/binding")
            add_files(luatos.."components/easylvgl/binding/*.c")
            
            -- EasyLVGL SDL2 驱动
            add_includedirs(luatos.."components/easylvgl/sdl2")
            add_files(luatos.."components/easylvgl/sdl2/*.c")
        else
            -- LVGL 7.13 (原有配置)
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
        end

        -- qrcode 和 tjpgd
        add_includedirs(luatos.."components/qrcode")
        add_includedirs(luatos.."components/tjpgd")
        add_files(luatos.."components/tjpgd/*.c")
        add_files(luatos.."components/qrcode/*.c")

        add_includedirs(luatos.."components/luatfonts")
        add_files(luatos.."components/luatfonts/**.c")

        -- gtfont PC simulator core
        add_includedirs(luatos.."components/gtfont")
        add_includedirs(luatos.."components/eink")
        -- add_files(luatos.."components/gtfont/*.c")
        
        -- hzfont component
        add_includedirs(luatos.."components/hzfont/inc")
        add_files(luatos.."components/hzfont/src/*.c")
        add_files(luatos.."components/hzfont/binding/*.c")

        -- pinyin component
        add_includedirs(luatos.."components/pinyin/inc")
        add_files(luatos.."components/pinyin/src/*.c")
        add_files(luatos.."components/pinyin/binding/*.c")

        -- airui
        -- add_includedirs(luatos_exts.."/airui/include")
        -- add_files(luatos_exts.."/airui/**.c")

        -- tp (touch) core only; exclude hardware drivers on PC
        add_includedirs(luatos.."components/tp")
        add_files(luatos.."components/tp/luat_lib_tp.c")
        add_files(luatos.."components/tp/luat_tp.c")

    end
target_end()
