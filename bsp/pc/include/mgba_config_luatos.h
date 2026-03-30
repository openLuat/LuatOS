#ifndef MGBA_CONFIG_LUATOS_H
#define MGBA_CONFIG_LUATOS_H

/**
 * @file mgba_config_luatos.h
 * @brief mGBA 编译配置 - 适配 LuatOS 平台
 * 
 * 该配置文件用于定制 mGBA 的编译选项，禁用不需要的功能以减少代码体积
 */

/* ========== 平台标识 ========== */
#define PLATFORM_LUATOS 1

/* ========== 核心功能开关 ========== */

/* 禁用调试器相关功能 */
#define ENABLE_DEBUGGERS 0
#define USE_DEBUGGERS 0
#define USE_GDB_STUB 0
#define USE_EDITLINE 0

/* 禁用不需要的外部依赖 */
#define USE_SQLITE3 0
#define USE_FFMPEG 0
#define USE_LIBZIP 0
#define USE_LZMA 0
#define USE_ELF 0
#define USE_FREETYPE 0
#define USE_DISCORD_RPC 0

/* JSON-C 用于脚本存储 API，禁用 */
#define USE_JSON_C 0

/* ========== 压缩支持 ========== */

/* 使用 LuatOS 已有的 miniz 替代 zlib */
#define USE_ZLIB 1
#define USE_MINIZIP 0
#define USE_PNG 0  /* 截图功能可选，后续添加 */

/* ========== Lua 脚本支持 ========== */

/* 禁用 mGBA 内置的 Lua 脚本，使用 LuatOS 的 Lua 5.3 */
#define USE_LUA 0
#define ENABLE_SCRIPTING 0

/* ========== 核心模拟器开关 ========== */

/* 启用 GBA 核心 */
#define M_CORE_GBA 1

/* 启用 GB/GBC 核心 */
#define M_CORE_GB 1

/* ========== 渲染配置 ========== */

/* 使用 32 位 BGRA 颜色格式 */
/* COLOR_16_BIT 和 COLOR_5_6_5 未定义表示使用32位颜色 */
/* mGBA 默认32位格式为 XBGR (通过 M_RGB8_TO_NATIVE 宏转换) */
/* 实际内存布局: [B][G][R][X] (小端) */
/* 对应 SDL_PIXELFORMAT_BGRA8888 (小端: [B][G][R][A]) */

/* ========== 前端配置 ========== */

/* 禁用内置前端，使用 LuatOS 的前端 */
#define BUILD_QT 0
#define BUILD_SDL 0
#define BUILD_LIBRETRO 0

/* 只构建库 */
#define LIBMGBA_ONLY 1
#define BUILD_STATIC 1
#define BUILD_SHARED 0
#define DISABLE_FRONTENDS 1

/* ========== 嵌入式优化 ========== */

#define MGBA_STANDALONE 0
#define MGBA_NO_MINIZ 0

/* 内存优化选项 */
/* #define MGBA_MINIMAL_MEMORY 1 */

/* ========== 日志配置 ========== */

/* 启用 mGBA 日志（调试用） */
/* #define MGBA_ENABLE_LOG 1 */

/* ========== 版本信息 ========== */

#define MGBA_VERSION_MAJOR 0
#define MGBA_VERSION_MINOR 10
#define MGBA_VERSION_PATCH 4

#endif /* MGBA_CONFIG_LUATOS_H */