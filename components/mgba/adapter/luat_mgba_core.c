/**
 * @file luat_mgba_core.c
 * @brief mGBA 核心功能桥接层
 * 
 * 该文件包含 mGBA 头文件，提供桥接函数供适配器使用。
 * 通过分离编译单元，避免 mGBA 的 struct Table 与 Lua 的 Table 冲突。
 */

/* mGBA 头文件 - 必须在所有其他头文件之前包含 */
#include "mgba/core/core.h"
#include "mgba/core/interface.h"
#include "mgba/gba/interface.h"
#include "mgba-util/vfs.h"
#include "mgba-util/memory.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef __LUATOS__
#include "luat_fs.h"
#include "luat_mem.h"
#endif

/* ========== mCore 创建/销毁桥接 ========== */

void* mgba_core_create(int platform) {
    enum mPlatform plat;
    switch (platform) {
        case 0:  /* GBA */
            plat = mPLATFORM_GBA;
            break;
        case 1:  /* GB/GBC */
            plat = mPLATFORM_GB;
            break;
        default:
            plat = mPLATFORM_NONE;
            break;
    }
    
    struct mCore* core;
    if (plat == mPLATFORM_NONE) {
        core = mCoreCreate(mPLATFORM_GBA);
        if (!core) {
            core = mCoreCreate(mPLATFORM_GB);
        }
    } else {
        core = mCoreCreate(plat);
    }
    
    if (core) {
        /* 在 init 之前设置选项 */
        core->opts.skipBios = true;  /* 跳过 BIOS，因为没有 BIOS 文件 */
        core->opts.useBios = false;
        core->opts.mute = true;       /* 默认静音 */
        core->opts.volume = 0;
    }
    
    return core;
}

void mgba_core_destroy(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->deinit(c);
    }
}

int mgba_core_init(void* core) {
    if (!core) return -1;
    struct mCore* c = (struct mCore*)core;
    return c->init(c) ? 0 : -1;
}

/* ========== mCore 视频桥接 ========== */

void mgba_core_set_video_buffer(void* core, void* buffer, uint32_t width) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->setVideoBuffer(c, (mColor*)buffer, width);
    }
}

/* ========== mCore ROM 加载桥接 ========== */

/* 生成存档文件路径 */
static void _make_save_path(const char* rom_path, char* save_path, size_t save_path_size) {
    if (!rom_path || !save_path || save_path_size == 0) {
        return;
    }
    
    /* 跳过 /luadb/ 前缀（只读虚拟文件系统），使用当前目录 */
    const char* actual_path = rom_path;
    if (strncmp(rom_path, "/luadb/", 7) == 0) {
        actual_path = rom_path + 7;
    } else if (strncmp(rom_path, "/", 1) == 0 && strncmp(rom_path, "/lfs2/", 6) != 0) {
        actual_path = rom_path + 1;
    }
    
    /* 复制ROM路径 */
    strncpy(save_path, actual_path, save_path_size - 1);
    save_path[save_path_size - 1] = '\0';
    
    /* 查找最后一个点，替换为.sav */
    char* dot = strrchr(save_path, '.');
    if (dot) {
        /* 确保有足够空间 */
        if (save_path_size - (dot - save_path) > 4) {
            strcpy(dot, ".sav");
        }
    } else {
        /* 如果没有扩展名，追加.sav */
        size_t len = strlen(save_path);
        if (len + 4 < save_path_size) {
            strcat(save_path, ".sav");
        }
    }
}

int mgba_core_load_rom(void* core, const char* path) {
    if (!core || !path) return -1;
    
    struct mCore* c = (struct mCore*)core;
    
#ifdef __LUATOS__
    /* 使用 LuatOS VFS 读取文件到内存 */
    FILE* file = luat_fs_fopen(path, "rb");
    if (!file) {
        return -2;
    }
    
    /* 获取文件大小 */
    luat_fs_fseek(file, 0, SEEK_END);
    size_t size = luat_fs_ftell(file);
    luat_fs_fseek(file, 0, SEEK_SET);
    
    if (size == 0) {
        luat_fs_fclose(file);
        return -2;
    }
    
    /* 使用标准 C malloc 分配大块内存，不使用 LuatOS 堆 */
    void* data = malloc(size);
    if (!data) {
        luat_fs_fclose(file);
        return -3;
    }
    
    size_t read_size = luat_fs_fread(data, 1, size, file);
    luat_fs_fclose(file);
    
    if (read_size != size) {
        free(data);
        return -3;
    }
    
    /* 使用 VFileMemChunk 代替 VFileFromMemory
     * VFileMemChunk 会创建自己的内存副本并正确管理内存生命周期
     * VFileFromMemory 不会释放传入的内存，导致内存泄漏和潜在崩溃 
    */
    struct VFile* vf = VFileMemChunk(data, size);
    
    /* VFileMemChunk 已经复制了数据，可以释放原始缓冲区 */
    free(data);
    
    if (!vf) {
        return -3;
    }
#else
    struct VFile* vf = VFileFOpen(path, "rb");
    if (!vf) return -2;
#endif
    
    if (!c->loadROM(c, vf)) {
        return -4;
    }
    
    c->reset(c);
    
#ifdef __LUATOS__
    /* 自动加载存档文件 */
    char save_path[256];
    _make_save_path(path, save_path, sizeof(save_path));
    
    /* 尝试打开存档文件 */
    FILE* save_file = luat_fs_fopen(save_path, "rb");
    if (save_file) {
        /* 获取存档文件大小 */
        luat_fs_fseek(save_file, 0, SEEK_END);
        size_t save_size = luat_fs_ftell(save_file);
        luat_fs_fseek(save_file, 0, SEEK_SET);
        
        if (save_size > 0) {
            /* 读取存档数据 */
            void* save_data = malloc(save_size);
            if (save_data) {
                size_t save_read = luat_fs_fread(save_data, 1, save_size, save_file);
                if (save_read == save_size) {
                    /* 创建VFile并加载存档 */
                    struct VFile* save_vf = VFileMemChunk(save_data, save_size);
                    if (save_vf) {
                        if (c->loadSave) {
                            c->loadSave(c, save_vf);
                        }
                    }
                }
                free(save_data);
            }
        }
        luat_fs_fclose(save_file);
    }
#endif
    
    return 0;
}

int mgba_core_load_rom_data(void* core, const uint8_t* data, size_t len) {
    if (!core || !data || len == 0) return -1;
    
    struct mCore* c = (struct mCore*)core;
    
    /* 使用 VFileMemChunk 创建可管理的内存 VFile
     * VFileMemChunk 会复制数据并正确管理内存生命周期 */
    struct VFile* vf = VFileMemChunk(data, len);
    if (!vf) {
        return -2;
    }
    
    if (!c->loadROM(c, vf)) {
        return -3;
    }
    
    c->reset(c);
    return 0;
}

void mgba_core_unload_rom(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->unloadROM(c);
    }
}

/* ========== mCore 执行控制桥接 ========== */

void mgba_core_run_frame(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->runFrame(c);
    }
}

void mgba_core_reset(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->reset(c);
    }
}

/* ========== mCore 输入桥接 ========== */

void mgba_core_set_keys(void* core, uint32_t keys) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->setKeys(c, keys);
    }
}

uint32_t mgba_core_get_keys(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->getKeys(c);
    }
    return 0xFFFFFFFF;
}

/* ========== mCore 状态桥接 ========== */

size_t mgba_core_state_size(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->stateSize(c);
    }
    return 0;
}

int mgba_core_save_state(void* core, void* buffer) {
    if (!core || !buffer) return -1;
    struct mCore* c = (struct mCore*)core;
    return c->saveState(c, buffer) ? 0 : -1;
}

int mgba_core_load_state(void* core, const void* buffer) {
    if (!core || !buffer) return -1;
    struct mCore* c = (struct mCore*)core;
    return c->loadState(c, buffer) ? 0 : -1;
}

/* ========== mCore 音频桥接 ========== */

void mgba_core_set_audio_buffer_size(void* core, size_t size) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        c->setAudioBufferSize(c, size);
    }
}

size_t mgba_core_get_audio_buffer_size(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->getAudioBufferSize(c);
    }
    return 0;
}

unsigned mgba_core_audio_sample_rate(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->audioSampleRate(c);
    }
    return 0;
}

/* 获取音频缓冲区指针 */
struct mAudioBuffer;

void* mgba_core_get_audio_buffer(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->getAudioBuffer(c);
    }
    return NULL;
}

/* 从音频缓冲区读取样本
 * 返回实际读取的样本帧数
 * samples: 输出缓冲区 (int16_t 数组)
 * count: 要读取的样本帧数 (不是字节数)
 */
#include <mgba-util/audio-buffer.h>

size_t mgba_core_read_audio(void* core, int16_t* samples, size_t count) {
    if (!core || !samples || count == 0) {
        return 0;
    }
    struct mCore* c = (struct mCore*)core;
    struct mAudioBuffer* buffer = c->getAudioBuffer(c);
    if (!buffer) {
        return 0;
    }
    return mAudioBufferRead(buffer, samples, count);
}

/* 获取音频缓冲区可用样本数 */
size_t mgba_core_audio_available(void* core) {
    if (!core) {
        return 0;
    }
    struct mCore* c = (struct mCore*)core;
    struct mAudioBuffer* buffer = c->getAudioBuffer(c);
    if (!buffer) {
        return 0;
    }
    return mAudioBufferAvailable(buffer);
}

/* ========== mCore 存档桥接 ========== */

size_t mgba_core_savedata_clone(void* core, void** out) {
    if (!core || !out) return 0;
    struct mCore* c = (struct mCore*)core;
    return c->savedataClone(c, out);
}

int mgba_core_savedata_restore(void* core, const void* data, size_t size, int clean) {
    if (!core || !data) return -1;
    struct mCore* c = (struct mCore*)core;
    return c->savedataRestore(c, data, size, clean ? true : false) ? 0 : -1;
}

/* ========== mCore 信息桥接 ========== */

int mgba_core_platform(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->platform(c);
    }
    return -1;
}

size_t mgba_core_rom_size(void* core) {
    if (core) {
        struct mCore* c = (struct mCore*)core;
        return c->romSize(c);
    }
    return 0;
}

void mgba_core_get_game_info(void* core, char* title, size_t title_size, 
                             char* code, size_t code_size) {
    if (!core) return;
    
    struct mCore* c = (struct mCore*)core;
    struct mGameInfo info;
    memset(&info, 0, sizeof(info));
    
    c->getGameInfo(c, &info);
    
    if (title && title_size > 0 && info.title) {
        strncpy(title, info.title, title_size - 1);
        title[title_size - 1] = '\0';
    }
    
    if (code && code_size > 0 && info.code) {
        strncpy(code, info.code, code_size - 1);
        code[code_size - 1] = '\0';
    }
}