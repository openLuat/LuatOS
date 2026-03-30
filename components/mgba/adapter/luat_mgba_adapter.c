/**
 * @file luat_mgba_adapter.c
 * @brief LuatOS mGBA 核心适配器实现
 * 
 * 该文件实现了 mGBA 核心与 LuatOS 的集成。
 * 通过桥接函数调用 mGBA 功能，避免头文件冲突。
 * 
 * 重要：所有 mGBA 相关内存分配使用标准 C malloc，而不是 LuatOS 堆。
 * 原因：mGBA 需要大块连续内存 (ROM 可达 32MB)，且其内部内存管理
 * 与 LuatOS 堆不兼容，混用会导致堆损坏和崩溃。
 */

#include "luat_mgba.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* 
 * 使用标准 C malloc/free 进行所有 mGBA 内存分配
 * 不使用 LuatOS 堆，避免堆损坏和兼容性问题
 */
#define MGBA_MALLOC(size) malloc(size)
#define MGBA_FREE(ptr) free(ptr)
#define MGBA_REALLOC(ptr, size) realloc(ptr, size)

/* ========== GBA 视频常量 ========== */

#define GBA_VIDEO_HORIZONTAL_PIXELS 240
#define GBA_VIDEO_VERTICAL_PIXELS 160

/* ========== mGBA 桥接函数声明 ========== */

/* 这些函数在 luat_mgba_core.c 中实现 */
extern void* mgba_core_create(int platform);
extern void mgba_core_destroy(void* core);
extern int mgba_core_init(void* core);
extern void mgba_core_set_video_buffer(void* core, void* buffer, uint32_t width);
extern int mgba_core_load_rom(void* core, const char* path);
extern int mgba_core_load_rom_data(void* core, const uint8_t* data, size_t len);
extern void mgba_core_unload_rom(void* core);
extern void mgba_core_run_frame(void* core);
extern void mgba_core_reset(void* core);
extern void mgba_core_set_keys(void* core, uint32_t keys);
extern uint32_t mgba_core_get_keys(void* core);
extern size_t mgba_core_state_size(void* core);
extern int mgba_core_save_state(void* core, void* buffer);
extern int mgba_core_load_state(void* core, const void* buffer);
extern void mgba_core_set_audio_buffer_size(void* core, size_t size);
extern size_t mgba_core_get_audio_buffer_size(void* core);
extern unsigned mgba_core_audio_sample_rate(void* core);
extern void* mgba_core_get_audio_buffer(void* core);
extern size_t mgba_core_read_audio(void* core, int16_t* samples, size_t count);
extern size_t mgba_core_audio_available(void* core);
extern size_t mgba_core_savedata_clone(void* core, void** out);
extern int mgba_core_savedata_restore(void* core, const void* data, size_t size, int clean);
extern int mgba_core_platform(void* core);
extern size_t mgba_core_rom_size(void* core);
extern void mgba_core_get_game_info(void* core, char* title, size_t title_size, 
                                     char* code, size_t code_size);

/* ========== 生命周期 API 实现 ========== */

int luat_mgba_init(luat_mgba_t** ctx_out, int platform) {
    if (!ctx_out) {
        return -1;
    }
    
    luat_mgba_t* ctx = (luat_mgba_t*)MGBA_MALLOC(sizeof(luat_mgba_t));
    if (!ctx) {
        return -2;
    }
    memset(ctx, 0, sizeof(luat_mgba_t));
    
    ctx->core = mgba_core_create(platform);
    if (!ctx->core) {
        MGBA_FREE(ctx);
        return -3;
    }
    
    if (mgba_core_init(ctx->core) != 0) {
        MGBA_FREE(ctx);
        return -4;
    }
    
    ctx->width = GBA_VIDEO_HORIZONTAL_PIXELS;
    ctx->height = GBA_VIDEO_VERTICAL_PIXELS;
    
    ctx->framebuffer = (luat_mgba_color_t*)MGBA_MALLOC(
        ctx->width * ctx->height * sizeof(luat_mgba_color_t)
    );
    if (!ctx->framebuffer) {
        mgba_core_destroy(ctx->core);
        MGBA_FREE(ctx);
        return -5;
    }
    
    /* 初始化帧缓冲区为黑色 (ABGR8888: 0xFF000000 = 不透明黑色) */
    memset(ctx->framebuffer, 0, ctx->width * ctx->height * sizeof(luat_mgba_color_t));
    
    mgba_core_set_video_buffer(ctx->core, ctx->framebuffer, ctx->width);
    
    ctx->running = 0;
    ctx->paused = 0;
    ctx->initialized = 1;
    ctx->audio_rate = 44100;
    
    *ctx_out = ctx;
    return 0;
}

int luat_mgba_deinit(luat_mgba_t* ctx) {
    if (!ctx) {
        return -1;
    }
    
    if (ctx->core) {
        mgba_core_destroy(ctx->core);
        ctx->core = NULL;
    }
    
    if (ctx->framebuffer) {
        MGBA_FREE(ctx->framebuffer);
        ctx->framebuffer = NULL;
    }
    
    ctx->initialized = 0;
    ctx->running = 0;
    
    MGBA_FREE(ctx);
    return 0;
}

int luat_mgba_is_initialized(luat_mgba_t* ctx) {
    return ctx && ctx->initialized;
}

/* ========== ROM 加载实现 ========== */

int luat_mgba_load_rom(luat_mgba_t* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) {
        return -1;
    }
    
    int ret = mgba_core_load_rom(ctx->core, path);
    if (ret == 0) {
        ctx->running = 1;
    }
    
    return ret;
}

int luat_mgba_load_rom_data(luat_mgba_t* ctx, const uint8_t* data, size_t len) {
    if (!ctx || !ctx->core || !data || len == 0) {
        return -1;
    }
    
    int ret = mgba_core_load_rom_data(ctx->core, data, len);
    if (ret == 0) {
        ctx->running = 1;
    }
    
    return ret;
}

int luat_mgba_unload_rom(luat_mgba_t* ctx) {
    if (!ctx || !ctx->core) {
        return -1;
    }
    
    mgba_core_unload_rom(ctx->core);
    ctx->running = 0;
    
    return 0;
}

/* ========== 执行控制实现 ========== */

int luat_mgba_run_frame(luat_mgba_t* ctx) {
    if (!ctx || !ctx->core || !ctx->running) {
        return -1;
    }
    
    if (ctx->paused) {
        return 0;
    }
    
    /* 运行一帧 */
    mgba_core_run_frame(ctx->core);
    
    /* 视频回调 */
    if (ctx->video_cb) {
        ctx->video_cb(ctx, ctx->framebuffer);
    }
    
    /* 音频回调 - 从 mGBA 获取音频数据 */
    if (ctx->audio_cb) {
        /* 使用静态缓冲区读取音频样本
         * GBA 每帧产生约 735 个样本 (44100Hz / 60fps)
         * 分配 2048 个样本帧的空间 (足够两帧)
         */
        static int16_t audio_samples[2048 * 2]; /* 立体声 = 2 通道 */
        
        /* 读取音频样本 */
        size_t samples_read = mgba_core_read_audio(ctx->core, audio_samples, 2048);
        
        if (samples_read > 0) {
            /* 调用回调传递音频数据 */
            ctx->audio_cb(ctx, audio_samples, samples_read);
        }
    }
    
    return 0;
}

int luat_mgba_run_frames(luat_mgba_t* ctx, int count) {
    if (!ctx || !ctx->core || !ctx->running || count <= 0) {
        return 0;
    }
    
    int executed = 0;
    for (int i = 0; i < count && !ctx->paused; i++) {
        mgba_core_run_frame(ctx->core);
        executed++;
        
        /* 音频回调 - 每帧后处理音频 */
        if (ctx->audio_cb) {
            static int16_t audio_samples[2048 * 2];
            size_t samples_read = mgba_core_read_audio(ctx->core, audio_samples, 2048);
            if (samples_read > 0) {
                ctx->audio_cb(ctx, audio_samples, samples_read);
            }
        }
    }
    
    if (ctx->video_cb && executed > 0) {
        ctx->video_cb(ctx, ctx->framebuffer);
    }
    
    return executed;
}

void luat_mgba_pause(luat_mgba_t* ctx) {
    if (ctx) {
        ctx->paused = 1;
    }
}

void luat_mgba_resume(luat_mgba_t* ctx) {
    if (ctx) {
        ctx->paused = 0;
    }
}

int luat_mgba_reset(luat_mgba_t* ctx) {
    if (!ctx || !ctx->core) {
        return -1;
    }
    
    mgba_core_reset(ctx->core);
    return 0;
}

int luat_mgba_is_running(luat_mgba_t* ctx) {
    return ctx && ctx->running && !ctx->paused;
}

/* ========== 输入控制实现 ========== */

void luat_mgba_set_key(luat_mgba_t* ctx, int key, int pressed) {
    if (!ctx || !ctx->core) {
        return;
    }
    
    uint32_t current_keys = mgba_core_get_keys(ctx->core);
    uint32_t new_keys;
    
    /* mGBA内部keysActive格式：位=1表示按下，位=0表示释放
     * 这与GBA硬件寄存器（低电平有效）相反
     * GBA硬件会在读取时自动转换为 0x3FF ^ keysActive
     */
    if (pressed) {
        new_keys = current_keys | key;   /* 设置该位（按下） */
    } else {
        new_keys = current_keys & ~key;  /* 清除该位（释放） */
    }
    
    mgba_core_set_keys(ctx->core, new_keys);
}

void luat_mgba_set_keys(luat_mgba_t* ctx, uint16_t keys) {
    if (!ctx || !ctx->core) {
        return;
    }
    
    mgba_core_set_keys(ctx->core, ~keys);
}

uint16_t luat_mgba_get_keys(luat_mgba_t* ctx) {
    if (!ctx || !ctx->core) {
        return 0;
    }
    
    return ~(uint16_t)mgba_core_get_keys(ctx->core);
}

/* ========== 存档管理实现 ========== */

int luat_mgba_save_state(luat_mgba_t* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) {
        return -1;
    }
    
    size_t state_size = mgba_core_state_size(ctx->core);
    if (state_size == 0) {
        return -2;
    }
    
    void* state = MGBA_MALLOC(state_size);
    if (!state) {
        return -3;
    }
    
    if (mgba_core_save_state(ctx->core, state) != 0) {
        MGBA_FREE(state);
        return -4;
    }
    
    FILE* fp = fopen(path, "wb");
    if (!fp) {
        MGBA_FREE(state);
        return -5;
    }
    
    size_t written = fwrite(state, 1, state_size, fp);
    fclose(fp);
    
    MGBA_FREE(state);
    
    return (written == state_size) ? 0 : -6;
}

int luat_mgba_load_state(luat_mgba_t* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) {
        return -1;
    }
    
    size_t state_size = mgba_core_state_size(ctx->core);
    if (state_size == 0) {
        return -2;
    }
    
    void* state = MGBA_MALLOC(state_size);
    if (!state) {
        return -3;
    }
    
    FILE* fp = fopen(path, "rb");
    if (!fp) {
        MGBA_FREE(state);
        return -4;
    }
    
    size_t read_size = fread(state, 1, state_size, fp);
    fclose(fp);
    
    if (read_size != state_size) {
        MGBA_FREE(state);
        return -5;
    }
    
    int ret = mgba_core_load_state(ctx->core, state);
    MGBA_FREE(state);
    
    return ret;
}

/**
 * @brief 转换存档路径，处理虚拟路径
 * @param input_path 输入路径（可能是虚拟路径如 /luadb/game.gba）
 * @param output_path 输出路径（本地文件系统路径）
 * @param size 输出路径缓冲区大小
 */
static void _convert_save_path(const char* input_path, char* output_path, size_t size) {
    if (!input_path || !output_path || size == 0) {
        return;
    }
    
    /* 跳过 /luadb/ 前缀（只读虚拟文件系统），使用当前目录 */
    const char* actual_path = input_path;
    if (strncmp(input_path, "/luadb/", 7) == 0) {
        actual_path = input_path + 7;
    } else if (strncmp(input_path, "/", 1) == 0 && strncmp(input_path, "/lfs2/", 6) != 0) {
        /* 其他虚拟路径（除了/lfs2/）也跳过前导斜杠 */
        actual_path = input_path + 1;
    }
    
    strncpy(output_path, actual_path, size - 1);
    output_path[size - 1] = '\0';
}

int luat_mgba_save_sram(luat_mgba_t* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) {
        return -1;
    }
    
    /* 转换路径 */
    char save_path[256];
    _convert_save_path(path, save_path, sizeof(save_path));
    
    void* sram = NULL;
    size_t sram_size = mgba_core_savedata_clone(ctx->core, &sram);
    if (sram_size == 0 || !sram) {
        return -2;
    }
    
    FILE* fp = fopen(save_path, "wb");
    if (!fp) {
        MGBA_FREE(sram);
        return -3;
    }
    
    size_t written = fwrite(sram, 1, sram_size, fp);
    fclose(fp);
    
    MGBA_FREE(sram);
    
    return (written == sram_size) ? 0 : -4;
}

int luat_mgba_load_sram(luat_mgba_t* ctx, const char* path) {
    if (!ctx || !ctx->core || !path) {
        return -1;
    }
    
    /* 转换路径 */
    char load_path[256];
    _convert_save_path(path, load_path, sizeof(load_path));
    
    FILE* fp = fopen(load_path, "rb");
    if (!fp) {
        return -2;
    }
    
    fseek(fp, 0, SEEK_END);
    size_t file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    
    void* sram = MGBA_MALLOC(file_size);
    if (!sram) {
        fclose(fp);
        return -3;
    }
    
    size_t read_size = fread(sram, 1, file_size, fp);
    fclose(fp);
    
    if (read_size != file_size) {
        MGBA_FREE(sram);
        return -4;
    }
    
    int ret = mgba_core_savedata_restore(ctx->core, sram, file_size, 1);
    MGBA_FREE(sram);
    
    return ret;
}

/* ========== 配置实现 ========== */

int luat_mgba_set_audio_rate(luat_mgba_t* ctx, int rate) {
    if (!ctx || !ctx->core || rate <= 0) {
        return -1;
    }
    
    ctx->audio_rate = rate;
    mgba_core_set_audio_buffer_size(ctx->core, 1024);
    
    return 0;
}

int luat_mgba_set_video_buffer(luat_mgba_t* ctx, luat_mgba_color_t* buffer) {
    if (!ctx || !ctx->core || !buffer) {
        return -1;
    }
    
    if (ctx->framebuffer) {
        MGBA_FREE(ctx->framebuffer);
    }
    
    ctx->framebuffer = buffer;
    mgba_core_set_video_buffer(ctx->core, buffer, ctx->width);
    
    return 0;
}

luat_mgba_color_t* luat_mgba_get_framebuffer(luat_mgba_t* ctx) {
    if (!ctx) {
        return NULL;
    }
    return ctx->framebuffer;
}

/* ========== 信息获取实现 ========== */

int luat_mgba_get_rom_info(luat_mgba_t* ctx, luat_mgba_rom_info_t* info) {
    if (!ctx || !ctx->core || !info) {
        return -1;
    }
    
    memset(info, 0, sizeof(luat_mgba_rom_info_t));
    
    info->platform = mgba_core_platform(ctx->core);
    info->rom_size = mgba_core_rom_size(ctx->core);
    info->width = ctx->width;
    info->height = ctx->height;
    
    mgba_core_get_game_info(ctx->core, 
                            info->title, sizeof(info->title),
                            info->code, sizeof(info->code));
    
    return 0;
}

void luat_mgba_get_gba_video_size(uint32_t* width, uint32_t* height) {
    if (width) *width = GBA_VIDEO_HORIZONTAL_PIXELS;
    if (height) *height = GBA_VIDEO_VERTICAL_PIXELS;
}

/* ========== 回调设置实现 ========== */

void luat_mgba_set_video_callback(luat_mgba_t* ctx, 
    void (*callback)(luat_mgba_t* ctx, luat_mgba_color_t* fb)) {
    if (ctx) {
        ctx->video_cb = callback;
    }
}

void luat_mgba_set_audio_callback(luat_mgba_t* ctx,
    void (*callback)(luat_mgba_t* ctx, int16_t* samples, size_t count)) {
    if (ctx) {
        ctx->audio_cb = callback;
    }
}