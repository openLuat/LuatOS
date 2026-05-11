/**
 * @file luat_lib_gba.c
 * @brief LuatOS mGBA Lua 绑定层
 * 
 * 该文件实现了 Lua gba 模块的 API
 * 
 * @module gba
 * @summary Game Boy Advance 模拟器
 * @catalog 多媒体
 * @version 1.0
 * @date 2026.03.23
 * @tag LUAT_USE_MGBA
 */

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "gba"
#include "luat_log.h"

#ifdef LUAT_USE_MGBA

#include "luat_mgba.h"
#include <string.h>

/* AirUI支持 */
#ifdef LUAT_USE_AIRUI
#include "../../airui/inc/luat_airui_binding.h"
#endif

/* ========== 模块上下文 ========== */

/* 当前 mGBA 实例 */
static luat_mgba_t* g_gba_ctx = NULL;

/* 视频输出上下文 (SDL2模式) */
static luat_mgba_video_t* g_video_ctx = NULL;

/* AirUI视频输出上下文 (AirUI模式) */
#ifdef LUAT_USE_AIRUI
static luat_mgba_airui_video_t* g_airui_video_ctx = NULL;
#endif

/* 音频输出上下文 */
static luat_mgba_audio_t* g_audio_ctx = NULL;

/* 运行状态 */
static int g_running = 0;
static int g_frame_interval = 16;  /* 默认约 60 FPS */

/* 视频模式: 0=SDL2, 1=AirUI */
static int g_video_mode = 0;

/* 当前ROM路径 */
static char g_rom_path[256] = {0};

/* ========== 内部辅助函数 ========== */

/* 获取存档文件路径 */
static void _get_save_path(const char* rom_path, char* save_path, size_t size) {
    if (!rom_path || !save_path || size == 0) {
        return;
    }
    
    /* 跳过 /luadb/ 前缀（只读虚拟文件系统），使用当前目录或可写路径 */
    const char* actual_path = rom_path;
    if (strncmp(rom_path, "/luadb/", 7) == 0) {
        actual_path = rom_path + 7;  /* 跳过 "/luadb/" */
    } else if (strncmp(rom_path, "/", 1) == 0 && strncmp(rom_path, "/lfs2/", 6) != 0) {
        /* 其他虚拟路径也跳过前导斜杠 */
        actual_path = rom_path + 1;
    }
    
    /* 构建存档路径：使用当前目录（可写） */
    strncpy(save_path, actual_path, size - 1);
    save_path[size - 1] = '\0';
    
    char* dot = strrchr(save_path, '.');
    if (dot && (dot - save_path) + 4 < (int)size) {
        strcpy(dot, ".sav");
    } else if (strlen(save_path) + 4 < size) {
        strcat(save_path, ".sav");
    }
}

/* 自动保存SRAM */
static void _auto_save_sram(void) {
    if (!g_gba_ctx || g_rom_path[0] == '\0') {
        return;
    }
    
    char save_path[256];
    _get_save_path(g_rom_path, save_path, sizeof(save_path));
    
    int ret = luat_mgba_save_sram(g_gba_ctx, save_path);
    if (ret == 0) {
        LLOGI("gba auto-saved SRAM: %s", save_path);
    } else {
        LLOGW("gba auto-save SRAM failed: %s (ret=%d)", save_path, ret);
    }
}

static void video_callback(luat_mgba_t* ctx, luat_mgba_color_t* fb) {
    if (!fb) {
        LLOGW("video_callback: framebuffer is NULL");
        return;
    }
    
#ifdef LUAT_USE_AIRUI
    /* AirUI模式 */
    if (g_video_mode == 1 && g_airui_video_ctx) {
        int ret = luat_mgba_airui_video_present(g_airui_video_ctx, fb, ctx->width, ctx->height);
        if (ret != 0) {
            LLOGW("video_callback: airui_video_present failed: %d", ret);
        }
        return;
    }
#endif
    
    /* SDL2模式 */
    if (g_video_ctx) {
        int ret = luat_mgba_video_present(g_video_ctx, fb, ctx->width, ctx->height);
        if (ret != 0) {
            LLOGW("video_callback: video_present failed: %d", ret);
        }
    } else {
        LLOGW("video_callback: g_video_ctx is NULL");
    }
}

static void audio_callback(luat_mgba_t* ctx, int16_t* samples, size_t count) {
    if (g_audio_ctx && samples) {
        luat_mgba_audio_output(g_audio_ctx, samples, count);
    }
}

/* ========== Lua API 实现 ========== */

/*
 * gba.init(config)
 * 初始化模拟器
 * @param config 配置表 {scale=2, audio=true, sample_rate=44100, mode="sdl"|"airui"}
 * @return boolean, 成功返回 true
 */
static int l_gba_init(lua_State* L) {
    int ret;
    luat_mgba_video_config_t video_cfg;
    luat_mgba_audio_config_t audio_cfg;
    
    /* AirUI配置（仅在AirUI模式下使用） */
#ifdef LUAT_USE_AIRUI
    luat_mgba_airui_video_config_t airui_cfg;
    luat_mgba_airui_video_get_default_config(&airui_cfg);
#endif
    
    if (g_gba_ctx) {
        LLOGW("gba already initialized, call gba.deinit() first");
        lua_pushboolean(L, 0);
        lua_pushstring(L, "already initialized");
        return 2;
    }
    
    /* 重置视频模式 */
    g_video_mode = 0;
    
    /* 获取默认配置 */
    luat_mgba_video_get_default_config(&video_cfg);
    luat_mgba_audio_get_default_config(&audio_cfg);
    
    /* 解析配置参数 */
    if (lua_istable(L, 1)) {
        /* mode - 视频模式选择 */
        lua_getfield(L, 1, "mode");
        if (lua_isstring(L, -1)) {
            const char* mode = lua_tostring(L, -1);
#ifdef LUAT_USE_AIRUI
            if (strcmp(mode, "airui") == 0) {
                g_video_mode = 1;
                LLOGI("gba using AirUI video mode");
            } else
#endif
            {
                g_video_mode = 0;
                LLOGI("gba using SDL video mode");
            }
        }
        lua_pop(L, 1);
        
        /* scale */
        lua_getfield(L, 1, "scale");
        if (lua_isinteger(L, -1)) {
            int scale = (int)lua_tointeger(L, -1);
            video_cfg.scale = scale;
#ifdef LUAT_USE_AIRUI
            airui_cfg.scale = scale;
#endif
        }
        lua_pop(L, 1);
        
        /* fullscreen - 仅SDL模式支持 */
        lua_getfield(L, 1, "fullscreen");
        if (lua_isboolean(L, -1)) {
            video_cfg.fullscreen = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);
        
        /* vsync - 仅SDL模式支持 */
        lua_getfield(L, 1, "vsync");
        if (lua_isboolean(L, -1)) {
            video_cfg.vsync = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);
        
        /* title - 仅SDL模式支持 */
        lua_getfield(L, 1, "title");
        if (lua_isstring(L, -1)) {
            video_cfg.title = lua_tostring(L, -1);
        }
        lua_pop(L, 1);
        
        /* audio */
        lua_getfield(L, 1, "audio");
        if (lua_isboolean(L, -1)) {
            audio_cfg.enabled = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);
        
        /* sample_rate */
        lua_getfield(L, 1, "sample_rate");
        if (lua_isinteger(L, -1)) {
            audio_cfg.sample_rate = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
    }
    
    /* 初始化 mGBA 核心 */
    ret = luat_mgba_init(&g_gba_ctx, LUAT_MGBA_PLATFORM_AUTO);
    if (ret != 0) {
        LLOGE("gba.init failed: %d", ret);
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "init failed: %d", ret);
        return 2;
    }
    
#ifdef LUAT_USE_AIRUI
    /* AirUI模式初始化 */
    if (g_video_mode == 1) {
        g_airui_video_ctx = luat_mgba_airui_video_init(&airui_cfg);
        if (!g_airui_video_ctx) {
            LLOGE("gba AirUI video init failed");
            luat_mgba_deinit(g_gba_ctx);
            g_gba_ctx = NULL;
            lua_pushboolean(L, 0);
            lua_pushstring(L, "airui video init failed");
            return 2;
        }
        LLOGI("gba AirUI video initialized");
    } else
#endif
    {
        /* SDL模式初始化 */
        g_video_ctx = luat_mgba_video_init(&video_cfg);
        if (!g_video_ctx) {
            LLOGW("gba video init failed, continuing without video");
        }
    }
    
    /* 初始化音频输出 */
    if (audio_cfg.enabled) {
        g_audio_ctx = luat_mgba_audio_init(&audio_cfg);
        if (!g_audio_ctx) {
            LLOGW("gba audio init failed, continuing without audio");
        }
    }
    
    /* 设置回调 */
    luat_mgba_set_video_callback(g_gba_ctx, video_callback);
    luat_mgba_set_audio_callback(g_gba_ctx, audio_callback);
    
    g_running = 0;
    
    LLOGI("gba initialized");
    lua_pushboolean(L, 1);
    return 1;
}

/*
 * gba.deinit()
 * 释放模拟器资源
 */
static int l_gba_deinit(lua_State* L) {
    /* 退出前自动保存存档 */
    _auto_save_sram();
    
#ifdef LUAT_USE_AIRUI
    /* AirUI模式清理 */
    if (g_airui_video_ctx) {
        luat_mgba_airui_video_deinit(g_airui_video_ctx);
        g_airui_video_ctx = NULL;
    }
#endif
    
    /* SDL模式清理 */
    if (g_video_ctx) {
        luat_mgba_video_deinit(g_video_ctx);
        g_video_ctx = NULL;
    }
    
    if (g_audio_ctx) {
        luat_mgba_audio_deinit(g_audio_ctx);
        g_audio_ctx = NULL;
    }
    
    if (g_gba_ctx) {
        luat_mgba_deinit(g_gba_ctx);
        g_gba_ctx = NULL;
    }
    
    g_running = 0;
    g_rom_path[0] = '\0';
    
    LLOGI("gba deinitialized");
    return 0;
}

/*
 * gba.load(path)
 * 加载 ROM 文件
 * @param path ROM 文件路径
 * @return boolean, 成功返回 true
 */
static int l_gba_load(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int ret = luat_mgba_load_rom(g_gba_ctx, path);
    if (ret != 0) {
        LLOGE("gba.load failed: %d", ret);
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "load failed: %d", ret);
        return 2;
    }
    
    /* 保存ROM路径用于自动存档 */
    strncpy(g_rom_path, path, sizeof(g_rom_path) - 1);
    g_rom_path[sizeof(g_rom_path) - 1] = '\0';
    
    LLOGI("gba loaded: %s", path);
    
    /* 自动加载对应的SRAM文件 */
    char sram_path[256];
    strncpy(sram_path, path, sizeof(sram_path) - 1);
    sram_path[sizeof(sram_path) - 1] = '\0';
    
    /* 替换扩展名为.sav */
    char* dot = strrchr(sram_path, '.');
    if (dot && (dot - sram_path) + 4 < (int)sizeof(sram_path)) {
        strcpy(dot, ".sav");
    } else if (strlen(sram_path) + 4 < sizeof(sram_path)) {
        strcat(sram_path, ".sav");
    }
    
    /* 尝试加载存档 */
    ret = luat_mgba_load_sram(g_gba_ctx, sram_path);
    if (ret == 0) {
        LLOGI("gba auto-loaded SRAM: %s", sram_path);
    } else {
        LLOGD("gba no SRAM found or load failed: %s (ret=%d)", sram_path, ret);
    }
    
    lua_pushboolean(L, 1);
    return 1;
}

/*
 * gba.load_data(data)
 * 从内存数据加载 ROM
 * @param data ROM 数据 (string)
 * @return boolean, 成功返回 true
 */
static int l_gba_load_data(lua_State* L) {
    size_t len;
    const uint8_t* data = (const uint8_t*)luaL_checklstring(L, 1, &len);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int ret = luat_mgba_load_rom_data(g_gba_ctx, data, len);
    if (ret != 0) {
        LLOGE("gba.load_data failed: %d", ret);
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "load failed: %d", ret);
        return 2;
    }
    
    LLOGI("gba loaded from memory: %u bytes", (unsigned)len);
    lua_pushboolean(L, 1);
    return 1;
}

/*
 * gba.run()
 * 开始运行模拟器主循环
 */
static int l_gba_run(lua_State* L) {
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    g_running = 1;
    luat_mgba_resume(g_gba_ctx);
    
    /* 主循环 - 优化事件处理 */
    while (g_running) {
#ifdef LUAT_USE_AIRUI
        /* AirUI模式：检查退出请求 */
        if (g_video_mode == 1 && g_airui_video_ctx) {
            if (luat_mgba_airui_video_quit_requested(g_airui_video_ctx)) {
                g_running = 0;
                break;
            }
        } else
#endif
        {
            /* SDL模式：处理SDL事件 */
            if (g_video_ctx) {
                /* 循环处理直到没有更多事件 */
                int quit = luat_mgba_video_handle_events(g_video_ctx, g_gba_ctx);
                if (quit) {
                    g_running = 0;
                    break;
                }
            }
        }
        
        /* 执行一帧 */
        luat_mgba_run_frame(g_gba_ctx);
        
        /* 帧率控制 */
        int remaining_ms = g_frame_interval;
        while (remaining_ms > 0 && g_running) {
            int delay_ms = (remaining_ms > 5) ? 5 : remaining_ms;
            luat_timer_mdelay(delay_ms);
            remaining_ms -= delay_ms;
            
            /* 在延迟期间定期检查事件（仅SDL模式） */
            if (g_video_mode == 0 && g_video_ctx && remaining_ms > 0) {
                int quit = luat_mgba_video_handle_events(g_video_ctx, g_gba_ctx);
                if (quit) {
                    g_running = 0;
                    break;
                }
            }
        }
    }
    
    return 0;
}

/*
 * gba.step()
 * 执行单帧
 */
static int l_gba_step(lua_State* L) {
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    /* SDL模式：处理事件 */
    if (g_video_mode == 0 && g_video_ctx) {
        luat_mgba_video_handle_events(g_video_ctx, g_gba_ctx);
    }
    
    /* 执行一帧 */
    luat_mgba_run_frame(g_gba_ctx);
    
    return 0;
}

/*
 * gba.pause()
 * 暂停模拟器
 */
static int l_gba_pause(lua_State* L) {
    if (g_gba_ctx) {
        luat_mgba_pause(g_gba_ctx);
    }
    return 0;
}

/*
 * gba.resume()
 * 恢复模拟器
 */
static int l_gba_resume(lua_State* L) {
    if (g_gba_ctx) {
        luat_mgba_resume(g_gba_ctx);
    }
    return 0;
}

/*
 * gba.reset()
 * 重置游戏
 */
static int l_gba_reset(lua_State* L) {
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    luat_mgba_reset(g_gba_ctx);
    return 0;
}

/*
 * gba.key(name, pressed)
 * 设置按键状态
 * @param name 按键名称 (a, b, start, select, up, down, left, right, l, r)
 * @param pressed true 按下, false 释放
 */
static int l_gba_key(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    int pressed = lua_toboolean(L, 2);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int key = luat_mgba_key_from_name(name);
    if (key == 0) {
        luaL_error(L, "invalid key name: %s", name);
        return 0;
    }
    
    luat_mgba_set_key(g_gba_ctx, key, pressed);
    return 0;
}

/*
 * gba.keys(mask)
 * 批量设置按键状态
 * @param mask 按键位掩码
 */
static int l_gba_keys(lua_State* L) {
    uint16_t mask = (uint16_t)luaL_checkinteger(L, 1);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    luat_mgba_set_keys(g_gba_ctx, mask);
    return 0;
}

/*
 * gba.get_keys()
 * 获取当前按键状态
 * @return 按键位掩码
 */
static int l_gba_get_keys(lua_State* L) {
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    uint16_t keys = luat_mgba_get_keys(g_gba_ctx);
    lua_pushinteger(L, keys);
    return 1;
}

/*
 * gba.save(path)
 * 保存游戏状态
 * @param path 存档文件路径
 * @return boolean, 成功返回 true
 */
static int l_gba_save(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int ret = luat_mgba_save_state(g_gba_ctx, path);
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
 * gba.load_state(path)
 * 加载游戏状态
 * @param path 存档文件路径
 * @return boolean, 成功返回 true
 */
static int l_gba_load_state(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int ret = luat_mgba_load_state(g_gba_ctx, path);
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
 * gba.save_sram(path)
 * 保存游戏存档 (SRAM)
 * @param path 存档文件路径
 * @return boolean, 成功返回 true
 */
static int l_gba_save_sram(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int ret = luat_mgba_save_sram(g_gba_ctx, path);
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
 * gba.load_sram(path)
 * 加载游戏存档 (SRAM)
 * @param path 存档文件路径
 * @return boolean, 成功返回 true
 */
static int l_gba_load_sram(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    int ret = luat_mgba_load_sram(g_gba_ctx, path);
    lua_pushboolean(L, ret == 0);
    return 1;
}

/*
 * gba.get_info()
 * 获取游戏信息
 * @return table {title, code, platform, width, height, rom_size}
 */
static int l_gba_get_info(lua_State* L) {
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    luat_mgba_rom_info_t info;
    int ret = luat_mgba_get_rom_info(g_gba_ctx, &info);
    if (ret != 0) {
        lua_pushnil(L);
        return 1;
    }
    
    lua_createtable(L, 0, 6);
    
    lua_pushstring(L, info.title);
    lua_setfield(L, -2, "title");
    
    lua_pushstring(L, info.code);
    lua_setfield(L, -2, "code");
    
    lua_pushinteger(L, info.platform);
    lua_setfield(L, -2, "platform");
    
    lua_pushinteger(L, info.width);
    lua_setfield(L, -2, "width");
    
    lua_pushinteger(L, info.height);
    lua_setfield(L, -2, "height");
    
    lua_pushinteger(L, info.rom_size);
    lua_setfield(L, -2, "rom_size");
    
    return 1;
}

/*
 * gba.get_framebuffer()
 * 获取帧缓冲
 * @return zbuff 对象 (只读)
 */
static int l_gba_get_framebuffer(lua_State* L) {
    if (!g_gba_ctx) {
        luaL_error(L, "gba not initialized");
        return 0;
    }
    
    luat_mgba_color_t* fb = luat_mgba_get_framebuffer(g_gba_ctx);
    if (!fb) {
        lua_pushnil(L);
        return 1;
    }
    
    /* 返回帧缓冲作为 userdata (简化实现，返回指针) */
    lua_pushlightuserdata(L, fb);
    return 1;
}

/*
 * gba.set_scale(scale)
 * 设置显示缩放倍数
 * @param scale 缩放倍数 (1-4)
 */
static int l_gba_set_scale(lua_State* L) {
    int scale = (int)luaL_checkinteger(L, 1);
    
    if (g_video_ctx) {
        luat_mgba_video_set_scale(g_video_ctx, scale);
    }
    
#ifdef LUAT_USE_AIRUI
    /* AirUI模式下也尝试设置缩放 */
    if (g_video_mode == 1 && g_airui_video_ctx) {
        luat_mgba_airui_video_set_scale(g_airui_video_ctx, scale);
    }
#endif
    
    return 0;
}

/*
 * gba.set_fullscreen(fullscreen)
 * 设置全屏模式
 * @param fullscreen true 全屏, false 窗口
 */
static int l_gba_set_fullscreen(lua_State* L) {
    int fullscreen = lua_toboolean(L, 1);
    
    if (g_video_ctx) {
        luat_mgba_video_set_fullscreen(g_video_ctx, fullscreen);
    }
    
    return 0;
}

/*
 * gba.is_running()
 * 检查模拟器是否正在运行
 * @return boolean
 */
static int l_gba_is_running(lua_State* L) {
    lua_pushboolean(L, g_running && luat_mgba_is_running(g_gba_ctx));
    return 1;
}

#ifdef LUAT_USE_AIRUI
/*
 * gba.airui_set_scale(scale)
 * AirUI模式下设置显示缩放倍数
 * @param scale 缩放倍数 (1-4)
 * @return boolean 成功返回true
 */
static int l_gba_airui_set_scale(lua_State* L) {
    int scale = (int)luaL_checkinteger(L, 1);
    
    if (g_video_mode != 1 || !g_airui_video_ctx) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "not in AirUI mode");
        return 2;
    }
    
    int ret = luat_mgba_airui_video_set_scale(g_airui_video_ctx, scale);
    lua_pushboolean(L, ret == 0);
    if (ret != 0) {
        lua_pushfstring(L, "set scale failed: %d", ret);
        return 2;
    }
    return 1;
}

/*
 * gba.airui_show_controls(show)
 * AirUI模式下显示/隐藏控制按钮
 * @param show true显示, false隐藏
 */
static int l_gba_airui_show_controls(lua_State* L) {
    int show = lua_toboolean(L, 1);
    
    if (g_video_mode != 1 || !g_airui_video_ctx) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "not in AirUI mode");
        return 2;
    }
    
    luat_mgba_airui_video_show_controls(g_airui_video_ctx, show);
    lua_pushboolean(L, 1);
    return 1;
}

/*
 * gba.airui_quit_requested()
 * AirUI模式下检查是否有退出请求
 * @return boolean 有退出请求返回true
 */
static int l_gba_airui_quit_requested(lua_State* L) {
    if (g_video_mode != 1 || !g_airui_video_ctx) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int ret = luat_mgba_airui_video_quit_requested(g_airui_video_ctx);
    lua_pushboolean(L, ret);
    return 1;
}

/*
 * gba.airui_init_ex(config)
 * AirUI模式下初始化（扩展版，支持嵌入AirUI容器）
 * @param config 配置表 {
 *   scale=2,              -- 缩放倍数
 *   audio=true,           -- 启用音频
 *   parent=airui_obj,     -- AirUI父容器（必须）
 *   x=0, y=0,             -- 在父容器中的位置
 *   width=480,            -- 宽度
 *   height=320,           -- 高度
 *   show_controls=true,   -- 显示控制按钮
 * }
 * @return boolean, 成功返回 true
 */
static int l_gba_airui_init_ex(lua_State* L) {
    int ret;
    luat_mgba_airui_video_config_ex_t airui_cfg;
    luat_mgba_audio_config_t audio_cfg;
    
    memset(&airui_cfg, 0, sizeof(airui_cfg));
    luat_mgba_airui_video_get_default_config((luat_mgba_airui_video_config_t*)&airui_cfg);
    luat_mgba_audio_get_default_config(&audio_cfg);
    
    if (g_gba_ctx) {
        LLOGW("gba already initialized, call gba.deinit() first");
        lua_pushboolean(L, 0);
        lua_pushstring(L, "already initialized");
        return 2;
    }
    
    /* 解析配置参数 */
    if (lua_istable(L, 1)) {
        /* parent - AirUI父容器（必须） */
        lua_getfield(L, 1, "parent");
        if (lua_isuserdata(L, -1)) {
            /* 获取AirUI组件的userdata，并解包出obj字段 */
            airui_component_ud_t *ud = (airui_component_ud_t *)lua_touserdata(L, -1);
            lv_obj_t *parent_obj = airui_component_userdata_obj(ud);
            if (parent_obj) {
                airui_cfg.parent_obj = parent_obj;
                LLOGI("Got AirUI parent container: %p", airui_cfg.parent_obj);
            } else {
                LLOGE("Invalid AirUI parent container");
            }
        }
        lua_pop(L, 1);
        
        if (!airui_cfg.parent_obj) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, "parent container required");
            return 2;
        }
        
        /* scale */
        lua_getfield(L, 1, "scale");
        if (lua_isinteger(L, -1)) {
            airui_cfg.scale = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
        
        /* x */
        lua_getfield(L, 1, "x");
        if (lua_isinteger(L, -1)) {
            airui_cfg.x = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
        
        /* y */
        lua_getfield(L, 1, "y");
        if (lua_isinteger(L, -1)) {
            airui_cfg.y = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
        
        /* width */
        lua_getfield(L, 1, "width");
        if (lua_isinteger(L, -1)) {
            airui_cfg.width = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
        
        /* height */
        lua_getfield(L, 1, "height");
        if (lua_isinteger(L, -1)) {
            airui_cfg.height = (int)lua_tointeger(L, -1);
        }
        lua_pop(L, 1);
        
        /* show_controls */
        lua_getfield(L, 1, "show_controls");
        if (lua_isboolean(L, -1)) {
            airui_cfg.show_controls = lua_toboolean(L, -1) ? 1 : 0;
        }
        lua_pop(L, 1);
        
        /* audio */
        lua_getfield(L, 1, "audio");
        if (lua_isboolean(L, -1)) {
            audio_cfg.enabled = lua_toboolean(L, -1);
        }
        lua_pop(L, 1);
    }
    
    /* 初始化 mGBA 核心 */
    ret = luat_mgba_init(&g_gba_ctx, LUAT_MGBA_PLATFORM_AUTO);
    if (ret != 0) {
        LLOGE("gba.init failed: %d", ret);
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "init failed: %d", ret);
        return 2;
    }
    
    /* AirUI扩展模式初始化 */
    g_airui_video_ctx = luat_mgba_airui_video_init_ex(&airui_cfg);
    if (!g_airui_video_ctx) {
        LLOGE("gba AirUI video init_ex failed");
        luat_mgba_deinit(g_gba_ctx);
        g_gba_ctx = NULL;
        lua_pushboolean(L, 0);
        lua_pushstring(L, "airui video init_ex failed");
        return 2;
    }
    
    g_video_mode = 1;
    LLOGI("gba AirUI video initialized (ex mode)");
    
    /* 初始化音频输出 */
    if (audio_cfg.enabled) {
        g_audio_ctx = luat_mgba_audio_init(&audio_cfg);
        if (!g_audio_ctx) {
            LLOGW("gba audio init failed, continuing without audio");
        }
    }
    
    /* 设置回调 */
    luat_mgba_set_video_callback(g_gba_ctx, video_callback);
    luat_mgba_set_audio_callback(g_gba_ctx, audio_callback);
    
    /* 关键：恢复运行状态，使 step() 能正常执行 */
    luat_mgba_resume(g_gba_ctx);
    
    g_running = 0;  /* Lua层running状态，由主循环控制 */
    
    LLOGI("gba initialized (AirUI ex mode)");
    lua_pushboolean(L, 1);
    return 1;
}
#endif /* LUAT_USE_AIRUI */

/*
 * gba.stop()
 * 停止模拟器主循环
 */
static int l_gba_stop(lua_State* L) {
    /* 停止前自动保存存档 */
    _auto_save_sram();
    
    g_running = 0;
    return 0;
}

/* ========== 模块注册 ========== */

static const luaL_Reg gba_lib[] = {
    {"init",            l_gba_init},
    {"deinit",          l_gba_deinit},
    {"load",            l_gba_load},
    {"load_data",       l_gba_load_data},
    {"run",             l_gba_run},
    {"step",            l_gba_step},
    {"pause",           l_gba_pause},
    {"resume",          l_gba_resume},
    {"reset",           l_gba_reset},
    {"stop",            l_gba_stop},
    {"key",             l_gba_key},
    {"keys",            l_gba_keys},
    {"get_keys",        l_gba_get_keys},
    {"save",            l_gba_save},
    {"load_state",      l_gba_load_state},
    {"save_sram",       l_gba_save_sram},
    {"load_sram",       l_gba_load_sram},
    {"get_info",        l_gba_get_info},
    {"get_framebuffer", l_gba_get_framebuffer},
    {"set_scale",       l_gba_set_scale},
    {"set_fullscreen",  l_gba_set_fullscreen},
    {"is_running",      l_gba_is_running},
#ifdef LUAT_USE_AIRUI
    {"airui_init_ex",         l_gba_airui_init_ex},
    {"airui_set_scale",       l_gba_airui_set_scale},
    {"airui_show_controls",   l_gba_airui_show_controls},
    {"airui_quit_requested",  l_gba_airui_quit_requested},
#endif
    {NULL, NULL}
};

LUAMOD_API int luaopen_gba(lua_State* L) {
    luaL_newlib(L, gba_lib);
    
    /* 添加按键常量 */
    lua_pushinteger(L, LUAT_MGBA_KEY_A);
    lua_setfield(L, -2, "KEY_A");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_B);
    lua_setfield(L, -2, "KEY_B");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_SELECT);
    lua_setfield(L, -2, "KEY_SELECT");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_START);
    lua_setfield(L, -2, "KEY_START");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_RIGHT);
    lua_setfield(L, -2, "KEY_RIGHT");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_LEFT);
    lua_setfield(L, -2, "KEY_LEFT");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_UP);
    lua_setfield(L, -2, "KEY_UP");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_DOWN);
    lua_setfield(L, -2, "KEY_DOWN");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_R);
    lua_setfield(L, -2, "KEY_R");
    
    lua_pushinteger(L, LUAT_MGBA_KEY_L);
    lua_setfield(L, -2, "KEY_L");
    
    /* 平台常量 */
    lua_pushinteger(L, LUAT_MGBA_PLATFORM_GBA);
    lua_setfield(L, -2, "PLATFORM_GBA");
    
    lua_pushinteger(L, LUAT_MGBA_PLATFORM_GB);
    lua_setfield(L, -2, "PLATFORM_GB");
    
    lua_pushinteger(L, LUAT_MGBA_PLATFORM_GBC);
    lua_setfield(L, -2, "PLATFORM_GBC");
    
    lua_pushinteger(L, LUAT_MGBA_PLATFORM_AUTO);
    lua_setfield(L, -2, "PLATFORM_AUTO");
    
    return 1;
}

/*
 * 全局访问函数（供AirUI视频适配器使用）
 */
luat_mgba_t* luat_mgba_get_global_ctx(void) {
    return g_gba_ctx;
}

#else /* !LUAT_USE_MGBA */

/* 没有 mGBA 支持时提供空实现 */

LUAMOD_API int luaopen_gba(lua_State* L) {
    LLOGW("gba module not available: LUAT_USE_MGBA not defined");
    lua_newtable(L);
    return 1;
}

#endif /* LUAT_USE_MGBA */