set_project("luac")
set_xmakever("3.0.4")

set_version("1.0.3", {build = "%Y%m%d%H%M"})
add_rules("mode.debug", "mode.release")

local unpack = table.unpack or unpack
local luatos = "../../"
-- Resolve path to luatos-ext-components with this priority:
--   1. LUATOS_EXT_ROOT env var — explicit override; recommended for git worktrees and CI.
--      e.g.  $env:LUATOS_EXT_ROOT = "D:/github/luatos-ext-components"
--   2. Relative ../../../luatos-ext-components — standard side-by-side checkout layout.
--   3. Worktree safety net: if <repo_root>/.git is a file (worktree indicator), walk up
--      one extra level relative to the main repo root.  This is a best-effort heuristic
--      and is NOT the primary resolution path.
local function find_ext_root()
    local env_val = os.getenv("LUATOS_EXT_ROOT")
    if env_val and env_val ~= "" then
        return path.absolute(env_val)
    end
    local candidate = path.absolute(path.join(os.scriptdir(), "../../../luatos-ext-components"))
    if os.isdir(candidate) then return candidate end
    -- Worktree safety net: .git is a file (not a directory) inside a worktree.
    local repo_root = path.absolute(path.join(os.scriptdir(), "../.."))
    if os.isfile(path.join(repo_root, ".git")) then
        local alt = path.absolute(path.join(repo_root, "../../../luatos-ext-components"))
        if os.isdir(alt) then return alt end
    end
    return candidate  -- xmake will emit a clear missing-file error if path is still wrong
end
local luatos_ext_root = find_ext_root()
-- 2表示mbedtls 2.18.x，3表示mbedtls 3.x，4表示mbedtls 4.x
local mbedtls_version = 3

add_requires("gmssl")
add_packages("gmssl")

local function env_enabled(name)
    return os.getenv(name) == "y"
end

-- POSIX pthreads（Windows 通过 pthreads4w 提供）
if is_host("windows") then
    add_requires("pthreads4w")
end

-- audio_v2 默认使用 SDL2 音频设备；GUI 构建同时复用该依赖。
add_requires("libsdl2")
add_packages("libsdl2")

local function thirdparty_file_options()
    if is_host("windows") then
        return {cflags = {"/W0"}, cxflags = {"/W0"}}
    end
    return {cflags = {"-w"}, cxflags = {"-w"}}
end

local function add_thirdparty_files(...)
    local options = thirdparty_file_options()
    for _, pattern in ipairs({...}) do
        add_files(pattern, options)
    end
end

local function add_define_from_env(name)
    local value = os.getenv(name)
    if value and value ~= "" then
        add_defines(name .. "=" .. value)
    end
end

-- set_policy("build.optimization.lto", true)
-- set_warnings("all")
set_optimize("fastest")
-- set language: c11 and c++17
set_languages("gnu11", "cxx17")

-- 核心宏定义
add_defines("__LUATOS__", "__XMAKE_BUILD__")
-- mbedtls使用本地自定义配置
if mbedtls_version == 2 then
    add_defines("MBEDTLS_CONFIG_FILE=\"mbedtls_config_pc_mbedtls218.h\"")
elseif mbedtls_version == 4 then
    add_defines("MBEDTLS_CONFIG_FILE=\"mbedtls_config_pc_mbedtls4.h\"")
else
    add_defines("MBEDTLS_CONFIG_FILE=\"mbedtls_config_pc_mbedtls3.h\"")
end
-- coremark配置迭代数量
add_defines("ITERATIONS=300000")

if os.getenv("VM_64bit") == "1" then
    add_defines("LUAT_CONF_VM_64bit")
end

local use_gui = env_enabled("LUAT_USE_GUI")
local use_utest = env_enabled("LUAT_USE_UTEST")
local use_mgba = env_enabled("LUAT_USE_MGBA")

if use_gui then
    add_defines("LUAT_USE_GUI=1")
end
if use_utest then
    add_defines("LUAT_USE_UTEST=1")
end

if is_host("windows") then
    add_defines("LUAT_USE_WINDOWS")
    add_defines("_CRT_SECURE_NO_WARNINGS")
    add_cxflags("/utf-8")
    -- Enable C11 <stdatomic.h> for components that use atomic_int etc.
    -- (e.g. components/ndk/src/luat_ndk.c). MSVC requires this experimental flag
    -- because C11 atomics were opt-in until VS 2019 16.8 / MSVC 19.28.
    add_cflags("/experimental:c11atomics", {force = true})
    add_cxflags("/experimental:c11atomics", {force = true})
    add_includedirs("win32/include")
    add_files("win32/src/**.c")
elseif is_host("linux") then
    add_defines("LUA_USE_LINUX")
    add_defines("LUAT_CONF_USE_LIBSYS_SOURCE")
    add_cflags("-ffunction-sections -fdata-sections")
    add_cflags("-Wno-unused-parameter -Wno-unused-function -Wno-unused-variable")
    add_ldflags("-Wl,--gc-sections")
elseif is_host("macos") then
    add_defines("LUA_USE_MACOSX")
end

add_includedirs("include",{public = true})
add_includedirs(luatos.."lua/include",{public = true})
add_includedirs(luatos.."luat/include",{public = true})
add_includedirs("port/posix",{public = true})


target("luatos-lua")

    -- 始终生成调试符号，让崩溃时的 StackWalk64 能解析函数名和文件行号
    if is_host("windows") then
        set_symbols("debug")
        add_cflags("/Zi", {force = true})
        add_cxflags("/Zi", {force = true})
        add_ldflags("/DEBUG", {force = true})
    end

    -- set kind
    set_kind("binary")
    set_targetdir("$(builddir)/out")

    add_defines("LUAT_BSP_PC")
    -- fatfs 在 luat_conf_bsp.h 里已经 #define LUAT_USE_FATFS / LUAT_USE_FS_VFS,
    -- 不需要在 xmake 重复 add_defines(还会触发 MSVC C4005 重定义 warning)。
    add_files("src/*.c|luat_luadb_mod.c",{public = true})
    if is_host("windows") then
        add_files("src/luat_luadb_mod.c")
    end
    if mbedtls_version == 2 then
        remove_files("src/luat_pc_dtls_utest.c")
        remove_files("src/luat_pc_http_utest.c")
    end
    add_files("port/**.c")

    add_thirdparty_files(luatos.."lua/src/*.c")
    -- printf
    add_includedirs(luatos.."components/printf",{public = true})
    add_files(luatos.."components/printf/*.c")
    
    -- add_files(luatos.."luat/modules/*.c")

    if is_plat("linux", "macosx") then
        add_linkdirs("/opt/homebrew/lib", "/usr/local/lib")
        add_links("pthread", "m", "dl")
    end

    if is_host("windows") then
        add_packages("pthreads4w")
        add_links("ws2_32", "iphlpapi", "bcrypt")
    end

    -- i2c-tools
    add_includedirs(luatos.."components/i2c-tools")
    add_files(luatos.."components/i2c-tools/*.c")
    
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
            ,luatos.."luat/modules/luat_lib_rtc.c"
            ,luatos.."luat/modules/luat_lib_gpio.c"
            ,luatos.."luat/modules/luat_lib_spi.c"
            -- ,luatos.."luat/modules/luat_lib_softspi.c"
            ,luatos.."luat/modules/luat_lib_i2c.c"
            -- ,luatos.."luat/modules/luat_lib_softi2c.c"
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

    add_thirdparty_files(luatos.."components/lfs/*.c")

    -- add_files(luatos.."components/sfd/*.c")
    -- lua-cjson
    add_includedirs(luatos.."components/lua-cjson")
    add_thirdparty_files(luatos.."components/lua-cjson/*.c")
    -- cjson
    add_includedirs(luatos.."components/cjson")
    add_thirdparty_files(luatos.."components/cjson/*.c")
    -- ndk core
    add_includedirs(luatos.."components/ndk/include",{public = true})
    add_files(luatos.."components/ndk/src/*.c")
    add_files(luatos.."components/ndk/binding/*.c")
    -- fft core
    add_includedirs(luatos.."components/fft/inc", {public = true})
    add_files(luatos.."components/fft/src/*.c")
    add_files(luatos.."components/fft/binding/*.c")
    -- mbedtls
    if mbedtls_version == 2 then
        add_thirdparty_files(luatos.."components/mbedtls/library/*.c")
        add_includedirs(luatos.."components/mbedtls/include")
    elseif mbedtls_version == 4 then
        local mbedtls4_path = luatos.."components/mbedtls4/"
        add_defines("MBEDTLS_ALLOW_PRIVATE_ACCESS")
        add_includedirs(mbedtls4_path.."include", mbedtls4_path.."library")
        add_thirdparty_files(mbedtls4_path.."library/*.c")
    else
        add_thirdparty_files(luatos.."components/mbedtls3/library/*.c")
        add_includedirs(luatos.."components/mbedtls3/include")
    end

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

    -- gmssl: use local include (new uint32_t ciphertext_size) + local sm2_lib.c (new 16KB limit).
    -- The package lib provides all other gmssl symbols (aes, sha, x509, format_*, etc.).
    -- MSVC linker prefers .obj files over .lib for duplicate symbols, so our local sm2_lib.c wins.
    add_includedirs(luatos.."components/gmssl/include")
    add_files(luatos.."components/gmssl/src/sm2_lib.c")
    add_files(luatos.."components/gmssl/bind/*.c")

    -- iconv
    add_includedirs(luatos.."components/iconv")
    add_files(luatos.."components/iconv/*.c")

    -- miniz
    add_thirdparty_files(luatos .. "components/miniz/*.c")
    add_includedirs(luatos .. "components/miniz")

    -- fskv
    add_includedirs(luatos.."components/fskv")
    add_files(luatos.."components/fskv/luat_lib_fskv.c")

    -- ymodem
    add_includedirs(luatos.."components/ymodem",{public = true})
    add_files(luatos.."components/ymodem/*.c")

    -- profiler
    -- add_includedirs(luatos.."components/mempool/profiler/include",{public = true})
    -- add_files(luatos.."components/mempool/profiler/**.c")

    -- fastlz
    add_includedirs(luatos.."components/fastlz",{public = true})
    add_files(luatos.."components/fastlz/*.c")

    -- c_common
    add_includedirs(luatos.."components/common",{public = true})
    add_files(luatos.."components/common/*.c")

    if use_utest then
        if os.isdir(luatos.."components/utest/include") then
            add_includedirs(luatos.."components/utest/include", {public = true})
        end
        -- crypto/p256 utest 需要 luat_p256.h
        add_includedirs(luatos.."components/crypto/p256", {public = true})
        add_files(luatos.."components/utest/**.c")
        add_files("stubs/uart_dll_utest/luat_uart_dll_utest.c")
    end

    -- coremark
    add_includedirs(luatos.."components/coremark",{public = true})
    add_files(luatos.."components/coremark/*.c")

    -- memprof: Lua memory profiler
    add_includedirs(luatos.."components/memprof/include",{public = true})
    add_files(luatos.."components/memprof/src/*.c")
    add_files(luatos.."components/memprof/binding/*.c")

    -- sqlite3
    add_includedirs(luatos.."components/sqlite3/include",{public = true})
    add_files(luatos.."components/sqlite3/src/*.c")
    add_files(luatos.."components/sqlite3/binding/*.c")
    
    --mobile
    add_includedirs(luatos.."components/mobile")
    add_files(luatos.."components/mobile/*.c")

    -- sms
    add_includedirs(luatos.."components/sms/include",{public = true})
    add_files(luatos.."components/sms/**.c")

    -- audio
    add_includedirs(luatos.."/components/multimedia/",
                    luatos.."/components/multimedia/audio/include",
                    luatos.."/components/multimedia/mp3_decode",
                    luatos.."/components/multimedia/amr_decode/amr_common/dec/include",
                    luatos.."/components/multimedia/amr_decode/amr_nb/common/include",
                    luatos.."/components/multimedia/amr_decode/amr_nb/dec/include",
                    luatos.."/components/multimedia/amr_decode/amr_wb/dec/include",
                    luatos.."/components/multimedia/amr_decode/amr_wb/enc/include",
                    luatos.."/components/multimedia/amr_decode/amr_wb/enc/common/include",
                    luatos.."/components/multimedia/amr_decode/opencore-amrnb",
                    luatos.."/components/multimedia/amr_decode/opencore-amrwb",
                    luatos.."/components/multimedia/amr_decode/oscl",
                    luatos.."/components/multimedia/amr_decode/amr_nb/enc/src",
                    luatos.."/components/multimedia/dtmf_codec",
                    luatos.."/components/multimedia/vtool/include")
        add_files(luatos.."/components/multimedia/*.c|luat_multimedia_audio.c|luat_audio_tm8211.c|luat_audio_es8311.c")
        add_thirdparty_files(luatos.."/components/multimedia/amr_decode/**.c",
            luatos.."/components/multimedia/g711_codec/**.c",
            luatos.."/components/multimedia/dtmf_codec/**.c",
            luatos.."/components/multimedia/vtool/**.c")

        add_includedirs(luatos.."/components/common_api/include", {public = true})
        add_files(luatos.."/components/common_api/src/luat_common_api.c")
        add_files(luatos.."/components/multimedia/audio/src/*.c")
        add_files(luatos.."/components/multimedia/audio/binding/luat_lib_audio.c")
        add_files(luatos.."/components/multimedia/audio/codec_adapter/luat_audio_codec_port_no_op.c")
        add_files(luatos.."/components/multimedia/audio/codec_adapter/luat_audio_codec_port_raw.c")
        add_files(luatos.."/components/multimedia/audio/codec_adapter/luat_audio_codec_port_wav.c")
        add_files(luatos.."/components/multimedia/audio/codec_adapter/luat_audio_codec_port_mp3.c")
        add_files(luatos.."/components/multimedia/audio/codec_adapter/luat_audio_codec_port_amr_nb.c")
        add_files(luatos.."/components/multimedia/audio/codec_adapter/luat_audio_codec_port_amr_wb.c")

    -- speex codec
    if os.getenv("LUAT_SUPPORT_SPEEX") ~= "n" then
        add_defines("LUAT_SUPPORT_SPEEX=1")
        add_includedirs(luatos.."components/speex/include")
        add_thirdparty_files(luatos.."components/speex/libspeex/*.c")
        add_files(luatos.."components/multimedia/audio/codec_adapter/luat_audio_codec_port_speex.c")
    end

    -- audio_dsp（SpeexDSP 适配层，可选外部组件）
    -- 源码位于 luatos-ext-components/audio_dsp，与 mp4player 类似按需集成。
    -- 环境变量 LUAT_USE_AUDIO_DSP=y 强制启用，=n 强制禁用；未设置时按目录存在性自动检测。
    local use_audio_dsp = false
    local audio_dsp_src = luatos_ext_root .. "/audio_dsp"
    if os.isdir(audio_dsp_src) then
        local env_audio_dsp = os.getenv("LUAT_USE_AUDIO_DSP")
        if env_audio_dsp ~= "n" then
            use_audio_dsp = true
        end
    elseif os.getenv("LUAT_USE_AUDIO_DSP") == "y" then
        print("Warning: LUAT_USE_AUDIO_DSP=y but audio_dsp not found at: " .. audio_dsp_src)
    end

    if use_audio_dsp then
        add_defines("LUAT_USE_AUDIO_DSP=1")
        add_defines("FIXED_POINT")
        audio_dsp_src = audio_dsp_src:gsub("\\", "/")
        audio_dsp_src = audio_dsp_src:gsub("/$", "")

        add_includedirs(audio_dsp_src .. "/include")
        add_includedirs(audio_dsp_src .. "/speexdsp/include")
        add_files(audio_dsp_src .. "/port/*.c")
        add_thirdparty_files(audio_dsp_src .. "/speexdsp/src/*.c")
    end

    -- camera（PC 模拟器摄像头支持；Windows 下走 Media Foundation，其他平台空实现）
    add_includedirs(luatos.."components/camera")
    add_includedirs(luatos.."components/lcd")   -- luat_camera.h 需要 luat_lcd_conf_t
    add_files(luatos.."components/camera/luat_camera.c")
    add_files(luatos.."components/camera/luat_lib_camera.c")
    if is_host("windows") then
        add_links("Mf", "mfplat", "mfreadwrite", "mfuuid", "windowscodecs", "ole32", "oleaut32")
    end

    -- voip
    add_includedirs(luatos.."components/voip/include")
    add_files(luatos.."components/voip/src/*.c")
    add_files(luatos.."components/voip/binding/*.c")

    -- opus
    -- 只暴露 opus 根目录和公共 API 目录，避免 celt/silk/src 等内部短文件名头文件全局冲突
    -- 三档配置，环境变量 LUAT_OPUS_MODE 控制，默认 full（编码+解码，与原行为一致）：
    --   off    : 不编译 opus（仅当 bsp/pc/include/luat_conf_bsp.h 的 LUAT_SUPPORT_OPUS 关闭时可用）
    --   decode : 仅解码，体积最小（相对 full 去除全部编码链）
    --   full   : 编码+解码
    -- 实测体积（MSVC x86 代理口径，.text+.rdata，度量见 bsp/pc/measure_opus_size.ps1）：
    --   裁剪前基线 327.9KB → full /O1 约 206KB → decode /O1 约 119KB（另可选
    --   LUAT_OPUS_SMALL_FOOTPRINT=y 再省约 6KB，以算法换静态表，有音质/CPU 代价）。
    --   ARM 真机 -Os + gc-sections 下 decode 档预计 90-105KB，达到 100KB 级目标（待真机 map 验证）。
    -- 两档均永久剔除：multistream/projection/mapping_matrix（端口层未使用）、
    --   analysis/mlp/mlp_data（DISABLE_FLOAT_API 后为死代码）、mini_kfft（仅被已排除的
    --   qext_compare.c 引用）、debug.c（仅 #if 0 调试统计）、各 *_demo/*_compare 测试程序。
    -- Air1601 真机启用时（luatos-sdk-ccm42xx-gcc csdk/project/luatos/xmake.lua）请复用本清单，
    --   另需内部 includedirs：opus/src、celt、celt/arm、silk、silk/arm、silk/fixed。
    -- 原全量配置（回退用）：
    --   add_defines("OPUS_ARM_ASM","USE_ALLOCA","FIXED_POINT=1","OPUS_BUILD=1")
    --   add_includedirs(luatos.."/components/multimedia/opus",
    --                   luatos.."/components/multimedia/opus/include")
    --   add_thirdparty_files(luatos.."/components/multimedia/opus/celt/*.c|opus_custom_demo.c",
    --               luatos.."/components/multimedia/opus/celt/arm/armcpu.c",
    --               luatos.."/components/multimedia/opus/celt/arm/arm_celt_map.c",
    --               luatos.."/components/multimedia/opus/silk/*.c",
    --               luatos.."/components/multimedia/opus/silk/fixed/*.c",
    --               luatos.."/components/multimedia/opus/src/*.c|opus_compare.c|qext_compare.c|opus_demo.c")
    local opus_mode = os.getenv("LUAT_OPUS_MODE") or "full"
    if opus_mode ~= "off" then
        -- FIXED_POINT=1    定点实现（silk/float 不编译）
        -- DISABLE_FLOAT_API 不暴露 float PCM API；端口层只用 int16 API，定义后
        --                   opus_encoder 的 analysis/mlp 音调分析链成为死代码，可移出文件清单
        -- SMALL_FOOTPRINT  不默认启用：以算法换静态表（cwrs/modes/celt_lpc/PLC），有音质/CPU
        --                   代价；设环境变量 LUAT_OPUS_SMALL_FOOTPRINT=y 可 A/B 对比体积
        -- OPUS_ARM_ASM     x86 PC 上无意义，已移除（真机 ARM 由 SDK 仓库自行配置）
        add_defines("USE_ALLOCA","FIXED_POINT=1","OPUS_BUILD=1","DISABLE_FLOAT_API=1")
        if os.getenv("LUAT_OPUS_SMALL_FOOTPRINT") == "y" then
            add_defines("SMALL_FOOTPRINT=1")
        end
        if opus_mode == "decode" then
            -- 编码链未参与编译，同步裁掉端口层编码实现（见 opus_port.c 的宏守卫）
            add_defines("LUAT_OPUS_NO_ENCODER=1")
        end
        add_includedirs(luatos.."/components/multimedia/opus",
                        luatos.."/components/multimedia/opus/include"
                        )

        local opus_dir = luatos.."/components/multimedia/opus"

        -- ---------- src ----------
        -- 解码必需：opus_decoder 无条件依赖 extensions.c（opus_extension_iterator_*）
        local opus_src_common = {
            opus_dir.."/src/opus.c",
            opus_dir.."/src/opus_decoder.c",
            opus_dir.."/src/extensions.c",
        }
        -- 编码追加：repacketizer.c 被 opus_encoder.c 内部调用，编码档必留
        local opus_src_enc = {
            opus_dir.."/src/opus_encoder.c",
            opus_dir.."/src/repacketizer.c",
        }

        -- ---------- celt ----------
        -- 排除项：celt_encoder.c（仅编码）、mini_kfft.c（仅被已排除的 qext_compare.c 引用）
        -- 注意：entenc.c 为解码共享（bands/quant_bands/rate/cwrs/laplace/code_signs/shell_coder
        --       的编码分支引用 ec_enc_*），不可裁剪
        local opus_celt_common = {
            opus_dir.."/celt/bands.c",
            opus_dir.."/celt/celt.c",
            opus_dir.."/celt/celt_decoder.c",
            opus_dir.."/celt/celt_lpc.c",
            opus_dir.."/celt/cwrs.c",
            opus_dir.."/celt/entcode.c",
            opus_dir.."/celt/entdec.c",
            opus_dir.."/celt/entenc.c",
            opus_dir.."/celt/kiss_fft.c",
            opus_dir.."/celt/laplace.c",
            opus_dir.."/celt/mathops.c",
            opus_dir.."/celt/mdct.c",
            opus_dir.."/celt/modes.c",
            opus_dir.."/celt/pitch.c",
            opus_dir.."/celt/quant_bands.c",
            opus_dir.."/celt/rate.c",
            opus_dir.."/celt/vq.c",
        }
        local opus_celt_enc = {
            opus_dir.."/celt/celt_encoder.c",
        }

        -- ---------- silk ----------
        -- 解码必需清单（共享文件如 stereo_find_predictor/code_signs 保守归入解码档）
        local opus_silk_common = {
            opus_dir.."/silk/CNG.c",
            opus_dir.."/silk/PLC.c",
            opus_dir.."/silk/LP_variable_cutoff.c",
            opus_dir.."/silk/LPC_analysis_filter.c",
            opus_dir.."/silk/LPC_fit.c",
            opus_dir.."/silk/LPC_inv_pred_gain.c",
            opus_dir.."/silk/NLSF2A.c",
            opus_dir.."/silk/NLSF_decode.c",
            opus_dir.."/silk/NLSF_stabilize.c",
            opus_dir.."/silk/NLSF_unpack.c",
            opus_dir.."/silk/NLSF_VQ.c",
            opus_dir.."/silk/biquad_alt.c",
            opus_dir.."/silk/bwexpander.c",
            opus_dir.."/silk/bwexpander_32.c",
            opus_dir.."/silk/code_signs.c",
            opus_dir.."/silk/control_SNR.c",
            opus_dir.."/silk/control_audio_bandwidth.c",
            opus_dir.."/silk/control_codec.c",
            opus_dir.."/silk/dec_API.c",
            opus_dir.."/silk/decode_core.c",
            opus_dir.."/silk/decode_frame.c",
            opus_dir.."/silk/decode_indices.c",
            opus_dir.."/silk/decode_parameters.c",
            opus_dir.."/silk/decode_pitch.c",
            opus_dir.."/silk/decode_pulses.c",
            opus_dir.."/silk/decoder_set_fs.c",
            opus_dir.."/silk/gain_quant.c",
            opus_dir.."/silk/init_decoder.c",
            opus_dir.."/silk/interpolate.c",
            opus_dir.."/silk/inner_prod_aligned.c",
            opus_dir.."/silk/lin2log.c",
            opus_dir.."/silk/log2lin.c",
            opus_dir.."/silk/pitch_est_tables.c",
            opus_dir.."/silk/resampler.c",
            opus_dir.."/silk/resampler_down2.c",
            opus_dir.."/silk/resampler_down2_3.c",
            opus_dir.."/silk/resampler_private_AR2.c",
            opus_dir.."/silk/resampler_private_IIR_FIR.c",
            opus_dir.."/silk/resampler_private_down_FIR.c",
            opus_dir.."/silk/resampler_private_up2_HQ.c",
            opus_dir.."/silk/resampler_rom.c",
            opus_dir.."/silk/shell_coder.c",
            opus_dir.."/silk/sigm_Q15.c",
            opus_dir.."/silk/sort.c",
            opus_dir.."/silk/stereo_MS_to_LR.c",
            opus_dir.."/silk/stereo_decode_pred.c",
            opus_dir.."/silk/stereo_find_predictor.c",
            opus_dir.."/silk/sum_sqr_shift.c",
            opus_dir.."/silk/table_LSF_cos.c",
            opus_dir.."/silk/tables_LTP.c",
            opus_dir.."/silk/tables_NLSF_CB_NB_MB.c",
            opus_dir.."/silk/tables_NLSF_CB_WB.c",
            opus_dir.."/silk/tables_gain.c",
            opus_dir.."/silk/tables_other.c",
            opus_dir.."/silk/tables_pitch_lag.c",
            opus_dir.."/silk/tables_pulses_per_block.c",
        }
        local opus_silk_enc = {
            opus_dir.."/silk/A2NLSF.c",
            opus_dir.."/silk/HP_variable_cutoff.c",
            opus_dir.."/silk/NSQ.c",
            opus_dir.."/silk/NSQ_del_dec.c",
            opus_dir.."/silk/NLSF_del_dec_quant.c",
            opus_dir.."/silk/NLSF_encode.c",
            opus_dir.."/silk/NLSF_VQ_weights_laroia.c",
            opus_dir.."/silk/VAD.c",
            opus_dir.."/silk/VQ_WMat_EC.c",
            opus_dir.."/silk/ana_filt_bank_1.c",
            opus_dir.."/silk/check_control_input.c",
            opus_dir.."/silk/enc_API.c",
            opus_dir.."/silk/encode_indices.c",
            opus_dir.."/silk/encode_pulses.c",
            opus_dir.."/silk/init_encoder.c",
            opus_dir.."/silk/process_NLSFs.c",
            opus_dir.."/silk/quant_LTP_gains.c",
            opus_dir.."/silk/stereo_LR_to_MS.c",
            opus_dir.."/silk/stereo_encode_pred.c",
            opus_dir.."/silk/stereo_quant_pred.c",
        }

        -- ---------- silk/fixed ----------
        -- 解码档仅 vector_ops_FIX.c（silk_int16_array_maxabs 等被 decode_core 等使用）
        local opus_silk_fixed_common = {
            opus_dir.."/silk/fixed/vector_ops_FIX.c",
        }
        local opus_silk_fixed_enc = {
            opus_dir.."/silk/fixed/LTP_analysis_filter_FIX.c",
            opus_dir.."/silk/fixed/LTP_scale_ctrl_FIX.c",
            opus_dir.."/silk/fixed/apply_sine_window_FIX.c",
            opus_dir.."/silk/fixed/autocorr_FIX.c",
            opus_dir.."/silk/fixed/burg_modified_FIX.c",
            opus_dir.."/silk/fixed/corrMatrix_FIX.c",
            opus_dir.."/silk/fixed/encode_frame_FIX.c",
            opus_dir.."/silk/fixed/find_LPC_FIX.c",
            opus_dir.."/silk/fixed/find_LTP_FIX.c",
            opus_dir.."/silk/fixed/find_pitch_lags_FIX.c",
            opus_dir.."/silk/fixed/find_pred_coefs_FIX.c",
            opus_dir.."/silk/fixed/k2a_FIX.c",
            opus_dir.."/silk/fixed/k2a_Q16_FIX.c",
            opus_dir.."/silk/fixed/noise_shape_analysis_FIX.c",
            opus_dir.."/silk/fixed/pitch_analysis_core_FIX.c",
            opus_dir.."/silk/fixed/process_gains_FIX.c",
            opus_dir.."/silk/fixed/regularize_correlations_FIX.c",
            opus_dir.."/silk/fixed/residual_energy16_FIX.c",
            opus_dir.."/silk/fixed/residual_energy_FIX.c",
            opus_dir.."/silk/fixed/schur64_FIX.c",
            opus_dir.."/silk/fixed/schur_FIX.c",
            opus_dir.."/silk/fixed/warped_autocorrelation_FIX.c",
        }

        -- ---------- 组装文件清单 ----------
        local opus_files = {}
        for _, f in ipairs(opus_src_common) do table.insert(opus_files, f) end
        for _, f in ipairs(opus_celt_common) do table.insert(opus_files, f) end
        for _, f in ipairs(opus_silk_common) do table.insert(opus_files, f) end
        for _, f in ipairs(opus_silk_fixed_common) do table.insert(opus_files, f) end
        if opus_mode == "full" then
            for _, f in ipairs(opus_src_enc) do table.insert(opus_files, f) end
            for _, f in ipairs(opus_celt_enc) do table.insert(opus_files, f) end
            for _, f in ipairs(opus_silk_enc) do table.insert(opus_files, f) end
            for _, f in ipairs(opus_silk_fixed_enc) do table.insert(opus_files, f) end
        end
        -- 体积优先编译：全局 set_optimize("fastest")(/O2) 的内联/展开会显著膨胀 opus 代码，
        -- opus 语音帧处理实时性要求不高，单独降到 size 优先（MSVC /O1，GCC -Os），
        -- 真机侧建议同步叠加 -ffunction-sections -fdata-sections -Wl,--gc-sections
        local opus_opts = thirdparty_file_options()
        if is_mode("release") then
            local size_flag = is_host("windows") and "/O1" or "-Os"
            table.insert(opus_opts.cflags, size_flag)
            table.insert(opus_opts.cxflags, size_flag)
        end
        for _, f in ipairs(opus_files) do
            add_files(f, opus_opts)
        end
    end

    ----------------------------------------------------------------------
    -- 网络相关

    
    add_includedirs(luatos .. "components/common", {public = true})
    add_includedirs(luatos .. "components/network/adapter", {public = true})
    add_includedirs(luatos .. "components/ethernet/common", {public = true})
    add_files(luatos .. "components/network/adapter/*.c")

    -- rtp
    add_includedirs(luatos.."components/network/rtp",{public = true})
    add_files(luatos.."components/network/rtp/*.c")

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

    -- rtmp
    add_defines("LUAT_USE_RTMP=1")
    add_includedirs(luatos.."components/rtmp/include",{public = true})
    add_files(luatos.."components/rtmp/src/*.c")
    add_files(luatos.."components/rtmp/binding/*.c")

    -- sntp
    add_includedirs(luatos.."components/network/libsntp",{public = true})
    add_files(luatos.."components/network/libsntp/*.c")

    -- mqtt
    add_includedirs(luatos.."components/network/libemqtt",{public = true})
    add_files(luatos.."components/network/libemqtt/*.c")
    
    -- errdump
    add_includedirs(luatos.."components/network/errdump",{public = true})
    add_files(luatos.."components/network/errdump/*.c")

    -- wireguard
    add_includedirs(luatos.."components/network/wireguard/include",{public = true})
    add_files(luatos.."components/network/wireguard/src/*.c")

    -- httpsrv
    add_includedirs(luatos.."components/network/httpsrv/inc",{public = true})
    add_files(luatos.."components/network/httpsrv/src/*.c")
    -- add_files(luatos.."components/network/httpsrv/binding/*.c")

    -- ercoap
    -- add_includedirs(luatos.."components/network/ercoap/include",{public = true})
    -- add_files(luatos.."components/network/ercoap/src/*.c")
    -- add_files(luatos.."components/network/ercoap/binding/*.c")

    -- ws2812
    -- add_includedirs(luatos.."components/ws2812/include",{public = true})
    -- add_files(luatos.."components/ws2812/src/*.c")
    -- add_files(luatos.."components/ws2812/binding/*.c")

    -- onewire
    -- add_includedirs(luatos.."components/onewire/include",{public = true})
    -- add_files(luatos.."components/onewire/src/*.c")
    -- add_files(luatos.."components/onewire/binding/*.c")

    
    -- xxtea
    add_includedirs(luatos.."components/xxtea/include",{public = true})
    add_files(luatos.."components/xxtea/src/*.c")
    add_files(luatos.."components/xxtea/binding/*.c")

    -- fatfs
    add_includedirs(luatos.."components/fatfs")
    add_thirdparty_files(luatos.."components/fatfs/**.c")

    -- vtool
    add_includedirs(luatos.."components/multimedia/vtool/include")
    add_files(luatos.."components/multimedia/vtool/**.c")
    
    add_includedirs(luatos .. "components/hmeta")
    add_files(luatos .. "components/hmeta/**.c")

    -- sfud
    add_includedirs(luatos.."components/sfud",{public = true})
    add_files(luatos.."components/sfud/**.c")

    -- little_flash
    add_includedirs(luatos.."components/little_flash/inc",{public = true})
    add_includedirs(luatos.."components/little_flash/port",{public = true})
    add_files(luatos.."components/little_flash/**.c")
    add_includedirs(luatos.."components/pgfs",{public = true})
    add_files(luatos.."components/pgfs/**.c")
    add_defines("LUAT_USE_PGFS_COMPONENT=1")

    -- tfs (Tiny File System)
    add_includedirs(luatos.."components/tfs/inc",{public = true})
    add_files(luatos.."components/tfs/src/**.c")
    add_files(luatos.."components/tfs/vfs/**.c")

    -- 添加mreport
    -- add_includedirs(luatos.."components/mreport/include",{public = true})
    add_files(luatos.."components/mreport/src/*.c")

    -- 添加videoplayer
    add_includedirs(luatos.."components/videoplayer/include")
    add_includedirs(luatos.."components/tjpgd")
    add_includedirs(luatos.."components/lcd")
    add_includedirs(luatos.."components/u8g2")
    add_files(luatos.."components/tjpgd/*.c")
    add_files(luatos.."components/videoplayer/src/*.c")
    add_files(luatos.."components/videoplayer/binding/*.c")

    -- 添加 libwebp (仅解码器, 无SIMD, 无线程)
    add_defines("LUAT_USE_WEBP=1")
    add_includedirs(luatos.."components/libwebp")
    add_includedirs(luatos.."components/libwebp/include")
    add_thirdparty_files(luatos.."components/libwebp/src/dec/*.c")
    add_thirdparty_files(luatos.."components/libwebp/src/dsp/*.c")
    add_thirdparty_files(luatos.."components/libwebp/src/utils/*.c")

    -- nanopb
    add_includedirs(luatos.."components/nanopb/include",{public = true})
    add_files(luatos.."components/nanopb/src/*.c")
    -- add_files(luatos.."components/nanopb/binding/*.c")

    if true then
        -- lwip & zlink
        local lwip_path = luatos .. "components/network/lwip22/"
        add_includedirs(lwip_path .. "include")
        add_thirdparty_files(lwip_path .. "/api/**.c")
        add_thirdparty_files(lwip_path .. "/core/**.c")
        add_thirdparty_files(lwip_path .. "/netif/**.c")
        -- L2TP: lwip22 自带的 PPP 源码改由 components/network/l2tp/src/ppp 下的 vendor 副本编译
        -- (l2tp/src/ppp/ppp.c 已将 ppp_pcb 分配改为 mem_malloc/mem_free,
        --  因为本仓库 lwip22 的 memp_std.h 裁剪掉了 PPP/PPPOL2TP 内存池)
        remove_files(lwip_path .. "netif/ppp/**.c")
        
        add_files(luatos .. "components/network/adapter_lwip2/*.c")
        add_includedirs(luatos .. "components/network/adapter_lwip2/")
        add_files(luatos .. "components/ethernet/common/*.c")

        -- 继续添加netdrv核心代码 (VPN 子模块已拆出为独立目录)
        add_includedirs(luatos .. "components/network/netdrv/include")
        add_files(luatos .. "components/network/netdrv/**.c")

        -- L2TPv2 客户端子模块 (components/network/l2tp) + vendored lwip22 PPP 实现
        -- 注意: bsp/pc/include/lwipopts.h 写死 PPP_SUPPORT=0 且会重定义,
        -- 所以这里通过 LUAT_L2TP_PPP_BUILD + luat_ppp_opts_override.h 在
        -- ppp_opts.h 之后强制覆盖 PPP 特性集, 仅对该批文件附加编译宏.
        add_includedirs(luatos .. "components/network/l2tp/include")
        add_includedirs(luatos .. "components/network/l2tp/src/ppp")
        add_files(luatos .. "components/network/l2tp/src/ppp/*.c",
                  {defines = {"LUAT_L2TP_PPP_BUILD=1"}})
        add_files(luatos .. "components/network/l2tp/src/l2tp_client.c",
                  luatos .. "components/network/l2tp/src/l2tp_ctrl.c",
                  luatos .. "components/network/l2tp/src/l2tp_ppp.c",
                  {defines = {"LUAT_L2TP_PPP_BUILD=1"}})
        add_files(luatos .. "components/network/l2tp/src/luat_netdrv_l2tp.c")

        -- IKEv2/IPsec 客户端子模块 (components/network/ipsec)
        add_includedirs(luatos .. "components/network/ipsec/include")
        add_files(luatos .. "components/network/ipsec/src/*.c")

        -- OpenVPN 客户端子模块 (components/network/openvpn)
        add_includedirs(luatos .. "components/network/openvpn/include")
        add_files(luatos .. "components/network/openvpn/src/*.c")

        -- ICMP (用于 netdrv.ping 联调 LWIP 层拦截的测试, 需要 netdrv + icmp)
        add_includedirs(luatos .. "components/network/icmp/include")
        add_files(luatos .. "components/network/icmp/**.c")

        -- 添加airlink
        add_includedirs(luatos .. "components/airlink/include")
        add_files(luatos .. "components/airlink/**.c")

        -- 添加iperf
        add_includedirs(luatos .. "components/network/iperf/include")
        add_files(luatos .. "components/network/iperf/**.c")

        -- remove_files(luatos .. "components/airlink/src/driver/*.c")
        -- remove_files(luatos .. "components/airlink/src/exec/luat_airlink_cmd_exec_wlan.c")
        -- remove_files(luatos .. "components/airlink/src/exec/luat_airlink_cmd_exec_gpio.c")
        -- remove_files(luatos .. "components/airlink/src/exec/luat_airlink_cmd_exec_uart.c")
        remove_files(luatos .. "components/airlink/src/exec/luat_airlink_cmd_exec_bluetooth.c")
        
        remove_files(luatos .. "components/airlink/src/task/luat_airlink_spi_slave_task.c")
        
        -- 添加wlan
        add_includedirs(luatos .. "components/wlan")
        add_files(luatos .. "components/wlan/luat_lib_wlan.c")
        add_files("port/driver/luat_wlan_pc.c")
        add_files("port/driver/luat_audio_compat.c")
        if os.getenv("LUAT_USE_WLAN_NATIVE") == "y" then
            add_defines("LUAT_USE_WLAN_NATIVE")
            if is_plat("windows") then
                add_links("wlanapi", "ole32")
            end
        end

        -- 添加蓝牙
        add_includedirs(luatos .. "components/bluetooth/include")
        add_files(luatos .. "components/bluetooth/drv/luat_drv_ble_gatt.c")
    else
        add_includedirs(luatos .. "components/network/lwip/include")
        add_includedirs("lwip/include")    
    end

    -- nes
    add_includedirs(luatos.."components/nes/inc")
    add_includedirs(luatos.."components/nes/port")
    add_files(luatos.."components/nes/**.c")

    -- gbc
    add_includedirs(luatos.."components/gbc/inc")
    add_includedirs(luatos.."components/gbc/port")
    add_files(luatos.."components/gbc/src/**.c")
    add_files(luatos.."components/gbc/port/gbc_luatos_port.c")
    add_files(luatos.."components/gbc/port/gbc_airui_video.c")
    add_files(luatos.."components/gbc/luat_lib_gbc.c")

    -- 关联编译lora2库
    add_includedirs(luatos.."components/lora2")
    add_files(luatos.."components/lora2/**.c")

    -- tiny_epd: C core + 1.54-inch black/white driver + LuatOS Lua binding.
    add_includedirs(luatos.."components/tiny_epd/include")
    add_includedirs(luatos.."components/tiny_epd/port")
    add_files(luatos.."components/tiny_epd/src/tiny_epd_core.c")
    add_files(luatos.."components/tiny_epd/src/tiny_epd_gfx.c")
    add_files(luatos.."components/tiny_epd/src/tiny_epd_bitmap.c")
    add_files(luatos.."components/tiny_epd/src/tiny_epd_qrcode.c")
    add_files(luatos.."components/tiny_epd/src/tiny_epd_hzfont.c")
    add_files(luatos.."components/tiny_epd/src/tiny_epd_custom.c")
    add_files(luatos.."components/tiny_epd/drivers/tiny_epd_1in54.c")
    add_files(luatos.."components/tiny_epd/port/tiny_epd_port_luatos.c")
    add_files(luatos.."components/tiny_epd/binding/luat_lib_tiny_epd.c")

    if use_gui then
        add_packages("libsdl2")
        add_files("ui/*.c")
        -- 非 GUI 构建用的 u8g2 no-op stub;GUI 构建里 luat_u8g2_sdl2.c 才是强定义,会与之冲突
        remove_files("ui/luat_u8g2_pc.c")
        add_defines("U8G2_USE_LARGE_FONTS=1")

        -- sdl2
        add_includedirs(luatos.."components/ui/sdl2")
        add_files(luatos.."components/ui/sdl2/*.c")
        -- u8g2
        add_includedirs(luatos.."components/u8g2")
        add_files(luatos.."components/u8g2/*.c")
        -- u8g2 SDL2 模拟器(覆盖 LUAT_WEAK luat_u8g2_setup,i2c_id==21 / spi_id==21 时启用)
        add_files("ui/luat_u8g2_sdl2.c")
        -- lcd
        add_includedirs(luatos.."components/lcd")
        add_includedirs(luatos.."components/luat_image/include")
        add_files(luatos.."components/lcd/*.c")
        add_files(luatos.."components/luat_image/src/*.c")

        -- LVGL 9.4 + AIRUI - 最基础组件编译
        -- 头文件添加：lvgl9 
        add_includedirs(luatos.."components/airui")
        add_includedirs(luatos.."components/airui/lvgl9")
        add_includedirs(luatos.."components/airui/lvgl9/src")
        
        -- 先添加所有源文件
        add_thirdparty_files(luatos.."components/airui/lvgl9/src/**.c")

         -- ThorVG 内部库使用 C++ 编译,单独添加
         add_thirdparty_files(luatos.."components/airui/lvgl9/src/libs/**/*.cpp")
        -- 排除不需要的组件（按优先级排序）
        -- 1. 硬件驱动（PC 模拟器不需要）
        remove_files(luatos.."components/airui/lvgl9/src/drivers/**/*.c")
        remove_files(luatos.."components/airui/lvgl9/src/drivers/**/*.cpp")
        
        -- 2. 硬件加速绘制引擎（只保留软件渲染 SW）
        remove_files(luatos.."components/airui/lvgl9/src/draw/dma2d/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/eve/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/nema_gfx/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/nxp/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/opengles/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/renesas/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/vg_lite/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/sdl/**.c")
        remove_files(luatos.."components/airui/lvgl9/src/draw/espressif/**.c")
        
        -- 3. 库：排除不需要的库（可选功能）
        -- remove_files(luatos.."components/airui/lvgl9/src/libs/**.cpp")
        
        -- AIRUI 架构配置
        -- 1. 公共头文件
        add_includedirs(luatos.."components/airui/inc")
        
        -- 2. 包含 src 目录下的所有文件（递归）
        add_includedirs(luatos.."components/airui/src")
        add_files(luatos.."components/airui/src/**/*.c")
        
        -- 3. Lua 绑定层（binding，不在 src 目录下，需单独处理）
        add_includedirs(luatos.."components/airui/binding")
        add_files(luatos.."components/airui/binding/*.c")

        -- qrcode 和 tjpgd (tjpgd已在videoplayer处添加)
        add_includedirs(luatos.."components/qrcode")
        add_files(luatos.."components/qrcode/*.c")

        -- add_includedirs(luatos.."components/luatfonts")
        -- add_files(luatos.."components/luatfonts/**.c")

        -- gtfont PC simulator core
        -- add_includedirs(luatos.."components/gtfont")
        -- add_files(luatos.."components/gtfont/*.c")

        -- eink + epaper (mono e-paper stack) also available in GUI build
        add_includedirs(luatos.."components/eink")
        add_files(luatos.."components/eink/*.c")
        add_includedirs(luatos.."components/epaper")
        add_files(luatos.."components/epaper/*.c")

        -- hzfont component
        add_includedirs(luatos.."components/hzfont/inc")
        add_files(luatos.."components/hzfont/src/*.c")
        add_files(luatos.."components/hzfont/binding/*.c")

        -- pinyin component
        add_includedirs(luatos.."components/pinyin/inc")
        add_files(luatos.."components/pinyin/src/*.c")
        add_files(luatos.."components/pinyin/binding/*.c")



        -- tp (touch) core only; exclude hardware drivers on PC
        add_includedirs(luatos.."components/tp")
        add_files(luatos.."components/tp/luat_lib_tp.c")
        add_files(luatos.."components/tp/luat_tp.c")

    end

    -- 非 GUI 构建补齐最小单色显示栈：u8g2 + eink/epaper + qrcode。
    -- GUI 构建沿用原有范围，避免意外扩大 EINK 支持面。
    if not use_gui then
        add_includedirs(luatos.."components/qrcode")
        add_files(luatos.."components/qrcode/*.c")
        add_files(luatos.."components/u8g2/*.c")
        add_files("ui/luat_u8g2_pc.c")  -- provides luat_u8g2_setup (no SDL2 deps)
        add_includedirs(luatos.."components/eink")
        add_files(luatos.."components/eink/*.c")
        add_includedirs(luatos.."components/epaper")
        add_files(luatos.."components/epaper/*.c")

    end
    if use_mgba then
        add_defines("LUAT_USE_MGBA=1")
        add_defines("MGBA_CONFIG_FILE=\"mgba_config_luatos.h\"")
        
        -- mGBA 核心配置宏 - 只定义启用的功能
        add_defines("PLATFORM_LUATOS=1")
        add_defines("M_CORE_GBA=1")
        add_defines("M_CORE_GB=1")
        add_defines("LIBMGBA_ONLY=1")
        add_defines("BUILD_STATIC=1")
        add_defines("DISABLE_FRONTENDS=1")
        add_defines("USE_ZLIB=1")
        -- 使用 16 位颜色格式 (GBA 原生 RGB565)
        -- add_defines("COLOR_16_BIT=1")
        
        -- Windows 平台特定配置
        -- Windows CRT 已提供 strdup (作为 _strdup)，避免与 mGBA 自定义实现冲突
        if is_host("windows") then
            add_defines("HAVE_STRDUP")
        end
        
        -- 启用 GBA 和 GB 核心支持
        add_defines("M_CORE_GBA", "M_CORE_GB")
        
        -- 启用 VFS 支持 (不需要 ENABLE_DIRECTORIES)
        add_defines("ENABLE_VFS", "ENABLE_VFS_FILE")
        
        -- 注意: 禁用的功能不定义宏，mGBA 使用 #ifdef 检查
        
        -- mGBA 头文件
        add_includedirs(luatos.."components/mgba/include")
        add_includedirs(luatos.."components/mgba/src")
        add_includedirs(luatos.."components/mgba/src/include")
        add_includedirs(luatos.."components/mgba/src/src")  -- 用于相对路径包含 (如 "gba/cheats/gameshark.h")
        
        -- mGBA 核心源文件 (src/src 是 mGBA 项目结构)
        add_files(
            luatos.."components/mgba/src/src/core/*.c",
            luatos.."components/mgba/src/src/gba/*.c",
            luatos.."components/mgba/src/src/gb/*.c",
            luatos.."components/mgba/src/src/util/*.c",
            luatos.."components/mgba/src/src/arm/*.c",
            luatos.."components/mgba/src/src/sm83/*.c"
        )
        
        -- VFS 子模块 (文件和内存支持)
        add_files(
            luatos.."components/mgba/src/src/util/vfs/vfs-file.c",
            luatos.."components/mgba/src/src/util/vfs/vfs-mem.c"
        )
        
        -- GBA 子目录 (排除 debugger、test 和 video logger)
        add_files(
            luatos.."components/mgba/src/src/gba/cart/*.c",
            luatos.."components/mgba/src/src/gba/cheats/*.c",
            luatos.."components/mgba/src/src/gba/renderers/*.c",
            luatos.."components/mgba/src/src/gba/sio/*.c"
        )
        
        -- GB 子目录 (排除 debugger、test 和 extra)
        add_files(
            luatos.."components/mgba/src/src/gb/mbc/*.c",
            luatos.."components/mgba/src/src/gb/renderers/*.c",
            luatos.."components/mgba/src/src/gb/sio/*.c"
        )
        
        -- 排除不需要的平台相关文件
        remove_files(
            luatos.."components/mgba/src/src/platform/**/*.c",
            luatos.."components/mgba/src/src/debugger/**/*.c",
            luatos.."components/mgba/src/src/feature/**/*.c",
            luatos.."components/mgba/src/src/script/**/*.c",
            luatos.."components/mgba/src/src/tools/**/*.c",
            luatos.."components/mgba/src/src/third-party/**/*.c",
            luatos.."components/mgba/src/src/gba/test/**/*.c",
            luatos.."components/mgba/src/src/gb/test/**/*.c",
            luatos.."components/mgba/src/src/util/test/**/*.c",
            luatos.."components/mgba/src/src/arm/debugger/**/*.c",
            luatos.."components/mgba/src/src/sm83/debugger/**/*.c",
            -- 禁用脚本支持，排除 scripting.c
            luatos.."components/mgba/src/src/core/scripting.c",
            -- 禁用配置文件解析 (需要 inih 库)
            luatos.."components/mgba/src/src/util/configuration.c",
            -- 禁用 GUI 工具
            luatos.."components/mgba/src/src/util/gui.c",
            -- 禁用 ELF 支持
            luatos.."components/mgba/src/src/util/elf-read.c",
            -- 禁用 OpenGL 渲染
            luatos.."components/mgba/src/src/gba/renderers/gl.c"
        )
        
        -- 添加 Windows 平台内存管理函数 (anonymousMemoryMap 等)
        add_files(luatos.."components/mgba/src/src/platform/windows/memory.c")
        
        -- 添加自定义 version.c (因为 .c.in 需要 CMake 生成)
        add_files(luatos.."components/mgba/adapter/version.c")
        
        -- 添加桩函数实现
        add_files(luatos.."components/mgba/adapter/luat_mgba_stubs.c")
        
        -- 添加 mGBA 核心桥接层 (隔离 mGBA 头文件，避免 Table 冲突)
        add_files(luatos.."components/mgba/adapter/luat_mgba_core.c")
        
        -- 添加 Lua 绑定层
        add_files(luatos.."components/mgba/binding/luat_lib_gba.c")
        
        -- 添加 LuatOS 适配器
        add_files(luatos.."components/mgba/adapter/luat_mgba_adapter.c")
        -- VFS 适配器暂时禁用，避免 Table 冲突
        -- add_files(luatos.."components/mgba/adapter/luat_mgba_vfs.c")
        add_files(luatos.."components/mgba/adapter/luat_mgba_input.c")
        
        -- 视频和音频输出适配器 (需要 GUI 支持)
        if use_gui then
            add_files(luatos.."components/mgba/adapter/luat_mgba_video.c")
            add_files(luatos.."components/mgba/adapter/luat_mgba_audio.c")
            -- AirUI视频适配器 (需要 AirUI 支持)
            add_files(luatos.."components/mgba/adapter/luat_mgba_airui_video.c")
        end
        
        -- 添加 Windows 库
        add_links("shlwapi")
    end

    -- =========================================================
    -- mp4player（MP4/H.264/AAC 解码器）
    -- 源码目录由 luatos_ext_root 指向 luatos-ext-components/mp4player
    -- 示例（PowerShell）：
    --   $env:LUAT_USE_MP4PLAYER = "y"  # 显式启用
    --   $env:LUAT_USE_MP4PLAYER = "n"  # 显式禁用
    --   cmd /c build_windows_32bit_msvc.bat
    -- =========================================================
    -- 自动检测：如果 luatos_ext_root/mp4player 不存在，自动禁用 MP4
    local use_mp4player = false
    local mp4player_src = luatos_ext_root .. "/mp4player"
    if os.isdir(mp4player_src) then
        -- 检查环境变量 LUAT_USE_MP4PLAYER 的显式控制
        local env_mp4 = os.getenv("LUAT_USE_MP4PLAYER")
        if env_mp4 ~= "n" then
            use_mp4player = true
        end
    elseif os.getenv("LUAT_USE_MP4PLAYER") == "y" then
        -- 显式要求启用但目录不存在，给出警告（保留，不强制失败）
        print("Warning: LUAT_USE_MP4PLAYER=y but mp4player not found at: " .. mp4player_src)
    end
    
    if use_mp4player then
        add_defines("LUAT_USE_MP4PLAYER=1")

        local mp4player_src = luatos_ext_root .. "/mp4player"
        -- 统一为正斜杠，xmake 在 Windows 下两者均支持
        mp4player_src = mp4player_src:gsub("\\", "/")
        -- 确保末尾无斜杠
        mp4player_src = mp4player_src:gsub("/$", "")

        -- ---- 头文件搜索路径 ----
        -- port/ 最先，其 plat_support.h 优先覆盖 platform/ 原始版本
        add_includedirs(mp4player_src .. "/port")
        add_includedirs(mp4player_src .. "/audio_decode")
        add_includedirs(mp4player_src .. "/audio_decode/platform")
        add_includedirs(mp4player_src .. "/audio_decode/aac")
        add_includedirs(mp4player_src .. "/audio_decode/aac/include")
        add_includedirs(mp4player_src .. "/audio_decode/aac/libfaad")
        add_includedirs(mp4player_src .. "/video_decode")
        add_includedirs(mp4player_src .. "/video_decode/avcodec")
        add_includedirs(mp4player_src .. "/video_decode/avcodec/h264")

        -- ---- 音频公共模块 ----
        add_files(mp4player_src .. "/audio_decode/audio_rb.c")
        add_files(mp4player_src .. "/audio_decode/sound.c")

        -- ---- AAC 解码（libfaad，第三方代码，关闭所有警告）----
        add_thirdparty_files(mp4player_src .. "/audio_decode/aac/libfaad/*.c")

        -- ---- H.264 解码器（avcodec，FFmpeg 派生，关闭所有警告）----
        -- atomic_gcc.h 已在 MSVC 下添加 #ifdef _MSC_VER 兼容处理，无需额外 defines。
        add_thirdparty_files(mp4player_src .. "/video_decode/avcodec/h264/*.c")
        add_thirdparty_files(mp4player_src .. "/video_decode/avcodec/*.c")
        -- libavutil 是 avcodec 的底层库（av_frame_*, av_samples_*, av_image_*, av_opt_* 等）
        add_thirdparty_files(mp4player_src .. "/video_decode/avcodec/h264/libavutil/*.c")
        -- file_open.c 依赖 <fcntl.h> O_CREAT 等宏（config.h 未启用 HAVE_FCNTL），改用 PC stub
        remove_files(mp4player_src .. "/video_decode/avcodec/h264/libavutil/file_open.c")
        -- *_template.c 是通过 #include 引入的模板文件，不直接参与编译
        remove_files(mp4player_src .. "/video_decode/avcodec/*_template.c")
        remove_files(mp4player_src .. "/video_decode/avcodec/h264/*_template.c")
        -- yuv2rgb_neon.c 使用 ARM NEON intrinsics，PC 不可编译
        remove_files(mp4player_src .. "/video_decode/avcodec/yuv2rgb_neon.c")
        -- h264/yuv.c 与 SDL2 的 yuv_rgb_std.c 重复定义 yuv420_rgb24_std 等函数，排除之
        remove_files(mp4player_src .. "/video_decode/avcodec/h264/yuv.c")
        -- h264_decode.c 是独立的 H264 解码桥接层，供 luat_mp4_videoplayer.c 调用
        -- （以前因为与 components/h264/src/h264_decoder.c 符号冲突而被排除；
        --   现已移除 components/h264，因此可以正常编译）

        -- ---- MP4 解复用 + 解码协调层 ----
        add_files(mp4player_src .. "/video_decode/mp4_decode.c")
        add_files(mp4player_src .. "/video_decode/video_rb.c")

        -- ---- platform port（已适配 LuatOS VFS，仅含 luat_mp4player_port.c）----
        add_files(mp4player_src .. "/port/luat_mp4player_port.c")

        -- ---- PC audio stubs（替代 CCM42xx DAC/DMA 硬件驱动）----
        -- platform/ 中的 dac_sound.c / sys_dac.c 依赖 CCM42xx 外设寄存器，不编译；
        -- 改用 port/mp4player/ 中的 no-op stub。
        add_files("stubs/mp4player/dac_sound_pc.c")
        add_files("stubs/mp4player/sys_dac_pc.c")

        -- mp3
        add_includedirs(mp4player_src .. "/audio_decode/mp3")
        add_files(mp4player_src .. "/audio_decode/mp3/*.c")
    end
target_end()
