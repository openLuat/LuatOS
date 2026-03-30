/**
 * @file luat_mgba_video.c
 * @brief LuatOS mGBA SDL2 视频输出适配器实现
 * 
 * 该文件实现了 mGBA 帧缓冲到 SDL2 窗口的输出
 * 
 * 重要：所有 mGBA 相关内存分配使用标准 C malloc，而不是 LuatOS 堆。
 * 原因：mGBA 需要大块连续内存，且其内部内存管理
 * 与 LuatOS 堆不兼容，混用会导致堆损坏和崩溃。
 */

#include "luat_conf_bsp.h"

#ifdef LUAT_USE_MGBA

#include "luat_mgba.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#ifdef __LUATOS__
#include "luat_log.h"
#define LUAT_LOG_TAG "mgba.video"
#endif

/* 使用标准 C malloc/free 进行所有 mGBA 内存分配
 * 不使用 LuatOS 堆，避免堆损坏和兼容性问题 */
#define MGBA_MALLOC(size) malloc(size)
#define MGBA_FREE(ptr) free(ptr)
#define MGBA_REALLOC(ptr, size) realloc(ptr, size)

/* SDL2 头文件 - 仅在有 GUI 支持时包含 */
#ifdef LUAT_USE_GUI
#include <SDL2/SDL.h>
#else
/* 如果没有 GUI 支持，提供空实现 */
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
#endif

/* ========== GBA 视频常量 ========== */

#define GBA_VIDEO_WIDTH     240
#define GBA_VIDEO_HEIGHT    160
#define GBA_FPS             60
#define FRAME_TIME_MS       (1000 / GBA_FPS)

/* ========== 视频输出上下文结构 ========== */

struct luat_mgba_video {
    SDL_Window* window;
    SDL_Renderer* renderer;
    SDL_Texture* texture;
    
    int scale;              /**< 显示缩放倍数 */
    int fullscreen;         /**< 全屏标志 */
    int vsync;              /**< 垂直同步标志 */
    
    uint32_t window_width;  /**< 窗口宽度 */
    uint32_t window_height; /**< 窗口高度 */
    
    int initialized;        /**< 初始化标志 */
    int quit_requested;     /**< 退出请求标志 */
    
    Uint32 texture_format;  /**< 实际纹理格式 */
    int texture_pitch;      /**< 纹理行字节数 */
};

/* ========== 默认配置 ========== */

static const luat_mgba_video_config_t default_config = {
    .scale = 2,
    .title = "LuatOS mGBA",
    .fullscreen = 0,
    .vsync = 1
};

/* ========== 公共 API 实现 ========== */

void luat_mgba_video_get_default_config(luat_mgba_video_config_t* config) {
    if (config) {
        memcpy(config, &default_config, sizeof(luat_mgba_video_config_t));
    }
}

luat_mgba_video_t* luat_mgba_video_init(const luat_mgba_video_config_t* config) {
#ifdef LUAT_USE_GUI
    luat_mgba_video_config_t cfg;
    if (config) {
        memcpy(&cfg, config, sizeof(luat_mgba_video_config_t));
    } else {
        memcpy(&cfg, &default_config, sizeof(luat_mgba_video_config_t));
    }
    
    /* 验证缩放倍数 */
    if (cfg.scale < 1) cfg.scale = 1;
    if (cfg.scale > 4) cfg.scale = 4;
    
    /* 分配上下文 */
    luat_mgba_video_t* video = (luat_mgba_video_t*)MGBA_MALLOC(sizeof(luat_mgba_video_t));
    if (!video) {
        return NULL;
    }
    memset(video, 0, sizeof(luat_mgba_video_t));
    
    /* 初始化 SDL 视频子系统 */
    if (SDL_InitSubSystem(SDL_INIT_VIDEO) < 0) {
        #ifdef __LUATOS__
        LLOGE("SDL_InitSubSystem(VIDEO) failed: %s", SDL_GetError());
        #endif
        MGBA_FREE(video);
        return NULL;
    }
    
    /* 禁用文本输入事件 - 减少不必要的事件处理 */
    // SDL_StopTextInput();
    
    /* 计算窗口大小 */
    video->window_width = GBA_VIDEO_WIDTH * cfg.scale;
    video->window_height = GBA_VIDEO_HEIGHT * cfg.scale;
    video->scale = cfg.scale;
    video->fullscreen = cfg.fullscreen;
    video->vsync = cfg.vsync;
    
    /* 创建窗口 */
    Uint32 window_flags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE;
    if (cfg.fullscreen) {
        window_flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    }
    
    video->window = SDL_CreateWindow(
        cfg.title ? cfg.title : "LuatOS mGBA",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        video->window_width,
        video->window_height,
        window_flags
    );
    
    if (!video->window) {
        #ifdef __LUATOS__
        LLOGE("SDL_CreateWindow failed: %s", SDL_GetError());
        #endif
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        MGBA_FREE(video);
        return NULL;
    }
    
    /* 创建渲染器 */
    Uint32 renderer_flags = SDL_RENDERER_ACCELERATED;
    if (cfg.vsync) {
        renderer_flags |= SDL_RENDERER_PRESENTVSYNC;
    }
    
    video->renderer = SDL_CreateRenderer(
        video->window, -1, renderer_flags
    );
    
    if (!video->renderer) {
        #ifdef __LUATOS__
        LLOGE("SDL_CreateRenderer failed: %s", SDL_GetError());
        #endif
        SDL_DestroyWindow(video->window);
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        MGBA_FREE(video);
        return NULL;
    }
    
    /* 创建纹理 - 使用 ABGR8888 格式 (A8B8G8R8)
     * mGBA 32位颜色输出: R,G,B,X 通道顺序 (小端内存: [R][G][B][X])
     * SDL_PIXELFORMAT_ABGR8888: A8B8G8R8 (小端内存: [R][G][B][A])
     * 两者完全匹配，无需颜色转换
     */
    video->texture = SDL_CreateTexture(
        video->renderer,
        SDL_PIXELFORMAT_ABGR8888,
        SDL_TEXTUREACCESS_STREAMING,
        GBA_VIDEO_WIDTH,
        GBA_VIDEO_HEIGHT
    );
    
    /* 如果 ABGR8888 不支持，尝试 RGBA8888 (小端内存: [A][B][G][R]) */
    if (!video->texture) {
        video->texture = SDL_CreateTexture(
            video->renderer,
            SDL_PIXELFORMAT_RGBA8888,
            SDL_TEXTUREACCESS_STREAMING,
            GBA_VIDEO_WIDTH,
            GBA_VIDEO_HEIGHT
        );
    }
    
    /* 如果32位都不支持，回退到 RGB888 */
    if (!video->texture) {
        video->texture = SDL_CreateTexture(
            video->renderer,
            SDL_PIXELFORMAT_RGB888,
            SDL_TEXTUREACCESS_STREAMING,
            GBA_VIDEO_WIDTH,
            GBA_VIDEO_HEIGHT
        );
    }
    
    if (!video->texture) {
        #ifdef __LUATOS__
        LLOGE("SDL_CreateTexture failed: %s", SDL_GetError());
        #endif
        SDL_DestroyRenderer(video->renderer);
        SDL_DestroyWindow(video->window);
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        MGBA_FREE(video);
        return NULL;
    }
    
    /* 查询并保存实际纹理格式 */
    int access, w, h;
    if (SDL_QueryTexture(video->texture, &video->texture_format, &access, &w, &h) != 0) {
        #ifdef __LUATOS__
        LLOGE("SDL_QueryTexture failed: %s", SDL_GetError());
        #endif
        SDL_DestroyTexture(video->texture);
        SDL_DestroyRenderer(video->renderer);
        SDL_DestroyWindow(video->window);
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        MGBA_FREE(video);
        return NULL;
    }
    
    /* 根据格式计算 pitch */
    switch (video->texture_format) {
        case SDL_PIXELFORMAT_RGB565:
        case SDL_PIXELFORMAT_BGR565:
            video->texture_pitch = GBA_VIDEO_WIDTH * 2;
            break;
        case SDL_PIXELFORMAT_RGB24:
        case SDL_PIXELFORMAT_BGR24:
            video->texture_pitch = GBA_VIDEO_WIDTH * 3;
            break;
        default:
            video->texture_pitch = GBA_VIDEO_WIDTH * 4;  /* 32位格式 */
            break;
    }
    
    #ifdef __LUATOS__
    LLOGI("mGBA video texture format: 0x%08X, pitch: %d", 
          video->texture_format, video->texture_pitch);
    #endif
    
    /* 设置纹理缩放模式 - 使用线性插值获得更好的显示效果 */
    SDL_SetTextureScaleMode(video->texture, SDL_ScaleModeLinear);
    
    /* 设置窗口最小大小 */
    SDL_SetWindowMinimumSize(video->window, GBA_VIDEO_WIDTH, GBA_VIDEO_HEIGHT);
    
    video->initialized = 1;
    video->quit_requested = 0;
    
    /* 初始化后清屏 - 显示黑色背景 */
    SDL_SetRenderDrawColor(video->renderer, 0, 0, 0, 255);
    SDL_RenderClear(video->renderer);
    SDL_RenderPresent(video->renderer);
    
    #ifdef __LUATOS__
    LLOGI("mGBA video initialized: %dx%d, scale=%d", 
          GBA_VIDEO_WIDTH, GBA_VIDEO_HEIGHT, video->scale);
    #endif
    
    return video;
    
#else /* !LUAT_USE_GUI */
    /* 没有 GUI 支持，返回 NULL */
    #ifdef __LUATOS__
    LLOGW("mGBA video requires LUAT_USE_GUI to be enabled");
    #endif
    (void)config;
    return NULL;
#endif
}

void luat_mgba_video_deinit(luat_mgba_video_t* video) {
#ifdef LUAT_USE_GUI
    if (!video) {
        return;
    }
    
    if (video->texture) {
        SDL_DestroyTexture(video->texture);
        video->texture = NULL;
    }
    
    if (video->renderer) {
        SDL_DestroyRenderer(video->renderer);
        video->renderer = NULL;
    }
    
    if (video->window) {
        SDL_DestroyWindow(video->window);
        video->window = NULL;
    }
    
    /* 注意：不调用 SDL_QuitSubSystem，因为其他组件可能还在使用 SDL */
    
    video->initialized = 0;
    MGBA_FREE(video);
    
    #ifdef __LUATOS__
    LLOGI("mGBA video deinitialized");
    #endif
#else
    (void)video;
#endif
}

int luat_mgba_video_present(luat_mgba_video_t* video, 
    const luat_mgba_color_t* fb, uint32_t width, uint32_t height) {
#ifdef LUAT_USE_GUI
    if (!video || !video->initialized || !fb) {
        return -1;
    }
    
    if (!video->texture || !video->renderer) {
        return -2;
    }
    
    /* 根据实际纹理格式更新
     * RGBA8888: 32位格式，直接使用 mGBA 输出
     * pitch = width * 4 (32位 = 4字节)
     */
    int ret;
    if (video->texture_format == SDL_PIXELFORMAT_RGB565 || 
        video->texture_format == SDL_PIXELFORMAT_BGR565) {
        /* 16位格式：需要将32位数据转换为16位 */
        static uint16_t temp_buffer[GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT];
        for (int i = 0; i < width * height; i++) {
            uint32_t c = fb[i];
            uint8_t r = c & 0xFF;
            uint8_t g = (c >> 8) & 0xFF;
            uint8_t b = (c >> 16) & 0xFF;
            temp_buffer[i] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
        }
        ret = SDL_UpdateTexture(video->texture, NULL, temp_buffer, width * 2);
    } else if (video->texture_format == SDL_PIXELFORMAT_RGB24 ||
               video->texture_format == SDL_PIXELFORMAT_BGR24) {
        /* 24位格式：提取RGB通道 */
        static uint8_t temp_buffer[GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT * 3];
        for (int i = 0; i < width * height; i++) {
            uint32_t c = fb[i];
            temp_buffer[i * 3 + 0] = c & 0xFF;        /* R */
            temp_buffer[i * 3 + 1] = (c >> 8) & 0xFF;  /* G */
            temp_buffer[i * 3 + 2] = (c >> 16) & 0xFF; /* B */
        }
        ret = SDL_UpdateTexture(video->texture, NULL, temp_buffer, width * 3);
    } else if (video->texture_format == SDL_PIXELFORMAT_RGBA8888) {
        /* RGBA8888 格式 (小端内存: [A][B][G][R])
         * 需要从 mGBA 的 ABGR8888 ([R][G][B][A]) 转换
         */
        static uint32_t temp_buffer[GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT];
        for (int i = 0; i < width * height; i++) {
            uint32_t c = fb[i];
            uint8_t r = c & 0xFF;
            uint8_t g = (c >> 8) & 0xFF;
            uint8_t b = (c >> 16) & 0xFF;
            uint8_t a = (c >> 24) & 0xFF;
            temp_buffer[i] = (a << 24) | (b << 16) | (g << 8) | r;
        }
        ret = SDL_UpdateTexture(video->texture, NULL, temp_buffer, width * 4);
    } else if (video->texture_format == SDL_PIXELFORMAT_ARGB8888) {
        /* ARGB8888 格式 (小端内存: [B][G][R][A])
         * 需要从 mGBA 的 ABGR8888 ([R][G][B][A]) 转换
         */
        static uint32_t temp_buffer[GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT];
        for (int i = 0; i < width * height; i++) {
            uint32_t c = fb[i];
            uint8_t r = c & 0xFF;
            uint8_t g = (c >> 8) & 0xFF;
            uint8_t b = (c >> 16) & 0xFF;
            uint8_t a = (c >> 24) & 0xFF;
            temp_buffer[i] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        ret = SDL_UpdateTexture(video->texture, NULL, temp_buffer, width * 4);
    } else if (video->texture_format == SDL_PIXELFORMAT_BGRA8888) {
        /* BGRA8888 格式 (小端内存: [A][R][G][B])
         * 需要从 mGBA 的 ABGR8888 ([R][G][B][A]) 转换
         */
        static uint32_t temp_buffer[GBA_VIDEO_WIDTH * GBA_VIDEO_HEIGHT];
        for (int i = 0; i < width * height; i++) {
            uint32_t c = fb[i];
            uint8_t r = c & 0xFF;
            uint8_t g = (c >> 8) & 0xFF;
            uint8_t b = (c >> 16) & 0xFF;
            uint8_t a = (c >> 24) & 0xFF;
            temp_buffer[i] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        ret = SDL_UpdateTexture(video->texture, NULL, temp_buffer, width * 4);
    } else {
        /* 32位格式 (ABGR8888等)：直接使用 */
        ret = SDL_UpdateTexture(video->texture, NULL, fb, width * 4);
    }
    
    if (ret != 0) {
        #ifdef __LUATOS__
        LLOGE("SDL_UpdateTexture failed: %s", SDL_GetError());
        #endif
        return -3;
    }
    
    /* 清除渲染器 */
    SDL_RenderClear(video->renderer);
    
    /* 复制纹理到渲染器 (自动缩放) */
    ret = SDL_RenderCopy(video->renderer, video->texture, NULL, NULL);
    if (ret != 0) {
        #ifdef __LUATOS__
        LLOGE("SDL_RenderCopy failed: %s", SDL_GetError());
        #endif
        return -4;
    }
    
    /* 显示 */
    SDL_RenderPresent(video->renderer);
    
    return 0;
#else
    (void)video;
    (void)fb;
    (void)width;
    (void)height;
    return -1;
#endif
}

int luat_mgba_video_set_scale(luat_mgba_video_t* video, int scale) {
#ifdef LUAT_USE_GUI
    if (!video || !video->initialized) {
        return -1;
    }
    
    /* 验证缩放倍数 */
    if (scale < 1) scale = 1;
    if (scale > 4) scale = 4;
    
    if (video->fullscreen) {
        /* 全屏模式下只记录缩放倍数，不调整窗口 */
        video->scale = scale;
        return 0;
    }
    
    /* 计算新的窗口大小 */
    int new_width = GBA_VIDEO_WIDTH * scale;
    int new_height = GBA_VIDEO_HEIGHT * scale;
    
    /* 设置窗口大小 */
    SDL_SetWindowSize(video->window, new_width, new_height);
    
    video->scale = scale;
    video->window_width = new_width;
    video->window_height = new_height;
    
    return 0;
#else
    (void)video;
    (void)scale;
    return -1;
#endif
}

void luat_mgba_video_set_title(luat_mgba_video_t* video, const char* title) {
#ifdef LUAT_USE_GUI
    if (video && video->window && title) {
        SDL_SetWindowTitle(video->window, title);
    }
#else
    (void)video;
    (void)title;
#endif
}

void luat_mgba_video_set_fullscreen(luat_mgba_video_t* video, int fullscreen) {
#ifdef LUAT_USE_GUI
    if (!video || !video->window) {
        return;
    }
    
    SDL_SetWindowFullscreen(video->window, 
        fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
    
    video->fullscreen = fullscreen;
#else
    (void)video;
    (void)fullscreen;
#endif
}

int luat_mgba_video_handle_events(luat_mgba_video_t* video, luat_mgba_t* mgba_ctx) {
#ifdef LUAT_USE_GUI
    if (!video) {
        return 0;
    }
    
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            case SDL_QUIT:
                video->quit_requested = 1;
                return 1;  /* 用户请求退出 */
                
            case SDL_KEYDOWN:
            case SDL_KEYUP:
                if (mgba_ctx) {
                    int scancode = event.key.keysym.scancode;
                    int pressed = (event.type == SDL_KEYDOWN);
                    
                    /* 处理特殊按键 */
                    if (pressed && scancode == SDL_SCANCODE_ESCAPE) {
                        video->quit_requested = 1;
                        return 1;
                    }
                    
                    /* 映射到 GBA 按键 */
                    luat_mgba_handle_key_event(mgba_ctx, scancode, pressed);
                }
                break;
                
            case SDL_WINDOWEVENT:
                if (event.window.event == SDL_WINDOWEVENT_CLOSE) {
                    video->quit_requested = 1;
                    return 1;
                }
                break;
                
            default:
                break;
        }
    }
    
    return 0;
#else
    (void)video;
    (void)mgba_ctx;
    return 0;
#endif
}

#endif /* LUAT_USE_MGBA */