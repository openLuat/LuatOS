/**
 * @file luat_mgba_stubs.c
 * @brief mGBA 缺失函数桩实现
 * 
 * 提供 mGBA 编译所需的缺失函数实现
 * 注意：VFS 相关函数已在 vfs.c 中实现
 */

#include <mgba-util/vfs.h>
#include <mgba-util/table.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

/* ========== Configuration 结构体定义 ========== */
/* 必须与 configuration.h 中的定义一致 */

struct Configuration {
    struct Table sections;
    struct Table root;
};

/* Configuration 的表析构回调 */
static void _configTableDeinit(void* table) {
    TableDeinit(table);
    free(table);
}

static void _configSectionDeinit(void* string) {
    free(string);
}

/* ========== Configuration 桩函数 ========== */

void ConfigurationInit(struct Configuration* config) {
    if (config) {
        HashTableInit(&config->sections, 0, _configTableDeinit);
        HashTableInit(&config->root, 0, _configSectionDeinit);
    }
}

void ConfigurationDeinit(struct Configuration* config) {
    if (config) {
        HashTableDeinit(&config->sections);
        HashTableDeinit(&config->root);
    }
}

void ConfigurationSetValue(struct Configuration* config, const char* section, const char* key, const char* value) {
    /* 空实现 */
}

void ConfigurationSetIntValue(struct Configuration* config, const char* section, const char* key, int value) {
    /* 空实现 */
}

void ConfigurationSetUIntValue(struct Configuration* config, const char* section, const char* key, unsigned int value) {
    /* 空实现 */
}

void ConfigurationSetFloatValue(struct Configuration* config, const char* section, const char* key, float value) {
    /* 空实现 */
}

const char* ConfigurationGetValue(const struct Configuration* config, const char* section, const char* key) {
    return NULL;
}

void ConfigurationEnumerate(const struct Configuration* config, const char* section,
    void (*handler)(const char* key, const char* value, void* user), void* user) {
    /* 空实现 */
}

bool ConfigurationHasSection(const struct Configuration* config, const char* section) {
    return false;
}

void ConfigurationClearValue(struct Configuration* config, const char* section, const char* key) {
    /* 空实现 */
}

void ConfigurationDeleteSection(struct Configuration* config, const char* section) {
    /* 空实现 */
}

void ConfigurationEnumerateSections(const struct Configuration* config,
    void (*handler)(const char* sectionName, void* user), void* user) {
    /* 空实现 */
}

/* 文件读写函数 - 需要 ENABLE_VFS */
bool ConfigurationRead(struct Configuration* config, const char* path) {
    return false;
}

bool ConfigurationWrite(const struct Configuration* config, const char* path) {
    return false;
}

bool ConfigurationWriteSection(const struct Configuration* config, const char* path, const char* section) {
    return false;
}

/* VFile 读写函数 */
bool ConfigurationReadVFile(struct Configuration* config, struct VFile* vf) {
    return false;
}

bool ConfigurationWriteVFile(const struct Configuration* config, struct VFile* vf) {
    return false;
}

/* ========== Video Logger 桩函数 ========== */

struct mVideoLogger;
struct mVideoLogContext;
struct mCore;

void* mVideoLoggerRendererCreate(void) {
    return NULL;
}

void mVideoLoggerRendererRun(void* logger) {
    /* 空实现 */
}

void mVideoLoggerAttachChannel(void* logger, void* channel) {
    /* 空实现 */
}

void* mVideoLogContextCreate(void) {
    return NULL;
}

void mVideoLogContextLoad(void* ctx, void* vf) {
    /* 空实现 */
}

void mVideoLogContextDestroy(void* ctx) {
    /* 空实现 */
}

void mVideoLogContextRewind(void* ctx) {
    /* 空实现 */
}

void* mVideoLogContextInitialState(void* ctx) {
    return NULL;
}

void mVideoLoggerAddChannel(void* logger, void* channel) {
    /* 空实现 */
}

void* mVideoThreadProxyCreate(void* core) {
    return NULL;
}

void* mVideoLogCoreFind(void* core, const char* name) {
    return NULL;
}

/* ========== Video Proxy Renderer 桩函数 ========== */

void* GBAVideoProxyRendererCreate(void) {
    return NULL;
}

void GBAVideoProxyRendererShim(void* renderer) {
    /* 空实现 */
}

void GBAVideoProxyRendererUnshim(void* renderer) {
    /* 空实现 */
}

void* GBVideoProxyRendererCreate(void) {
    return NULL;
}

void GBVideoProxyRendererShim(void* renderer) {
    /* 空实现 */
}

void GBVideoProxyRendererUnshim(void* renderer) {
    /* 空实现 */
}