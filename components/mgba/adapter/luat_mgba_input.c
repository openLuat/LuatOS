/**
 * @file luat_mgba_input.c
 * @brief LuatOS mGBA 输入处理适配器实现
 * 
 * 该文件实现了键盘输入到 GBA 按键的映射
 */

#include "luat_conf_bsp.h"

#ifdef LUAT_USE_MGBA

#include "luat_mgba.h"

#ifdef __LUATOS__
#include "luat_log.h"
#define LUAT_LOG_TAG "mgba.input"
#else
#include <stdio.h>
#endif

#include <string.h>

/* SDL2 扫描码定义 - 仅在有 GUI 支持时包含 */
#ifdef LUAT_USE_GUI
#include <SDL2/SDL_scancode.h>
#else
/* 如果没有 GUI 支持，定义常用的 SDL 扫描码 */
#define SDL_SCANCODE_UNKNOWN 0
#define SDL_SCANCODE_A 4
#define SDL_SCANCODE_B 5
#define SDL_SCANCODE_S 22
#define SDL_SCANCODE_X 27
#define SDL_SCANCODE_Z 29
#define SDL_SCANCODE_RETURN 40
#define SDL_SCANCODE_LSHIFT 225
#define SDL_SCANCODE_RSHIFT 229
#define SDL_SCANCODE_UP 82
#define SDL_SCANCODE_DOWN 81
#define SDL_SCANCODE_LEFT 80
#define SDL_SCANCODE_RIGHT 79
#define SDL_SCANCODE_ESCAPE 41
#endif

/* ========== 按键映射表 ========== */

/**
 * @brief 按键映射结构
 */
typedef struct {
    int scancode;       /**< SDL 扫描码 */
    int gba_key;        /**< GBA 按键位掩码 */
    const char* name;   /**< 按键名称 */
} key_mapping_t;

/**
 * @brief 默认键盘映射表
 * 
 * 映射关系：
 * - X -> A
 * - Z -> B
 * - Enter -> START
 * - Shift (Right) -> SELECT
 * - 方向键 -> 对应方向
 * - A -> L (左肩键)
 * - S -> R (右肩键)
 */
static const key_mapping_t key_mappings[] = {
    { SDL_SCANCODE_X,       LUAT_MGBA_KEY_A,      "A" },
    { SDL_SCANCODE_Z,       LUAT_MGBA_KEY_B,      "B" },
    { SDL_SCANCODE_RETURN,  LUAT_MGBA_KEY_START,  "START" },
    { SDL_SCANCODE_RSHIFT,  LUAT_MGBA_KEY_SELECT, "SELECT" },
    { SDL_SCANCODE_UP,      LUAT_MGBA_KEY_UP,     "UP" },
    { SDL_SCANCODE_DOWN,    LUAT_MGBA_KEY_DOWN,   "DOWN" },
    { SDL_SCANCODE_LEFT,    LUAT_MGBA_KEY_LEFT,   "LEFT" },
    { SDL_SCANCODE_RIGHT,   LUAT_MGBA_KEY_RIGHT,  "RIGHT" },
    { SDL_SCANCODE_A,       LUAT_MGBA_KEY_L,      "L" },
    { SDL_SCANCODE_S,       LUAT_MGBA_KEY_R,      "R" },
    /* 备用映射 - 左 Shift 也映射到 SELECT */
    { SDL_SCANCODE_LSHIFT,  LUAT_MGBA_KEY_SELECT, "SELECT" },
    { 0, 0, NULL }  /* 终止符 */
};

/* ========== 按键状态跟踪 ========== */

/**
 * @brief 当前按键状态表 - 跟踪每个扫描码的状态
 * 0 = 未按下, 1 = 已按下
 */
static int key_pressed_state[SDL_NUM_SCANCODES] = {0};

/* ========== 公共 API 实现 ========== */

int luat_mgba_key_from_scancode(int scancode) {
    for (const key_mapping_t* mapping = key_mappings; mapping->name != NULL; mapping++) {
        if (mapping->scancode == scancode) {
            return mapping->gba_key;
        }
    }
    return 0;  /* 无映射 */
}

void luat_mgba_handle_key_event(luat_mgba_t* ctx, int scancode, int pressed) {
    if (!ctx) {
        return;
    }
    
    /* 注意：不再过滤重复事件，避免漏掉KEYUP导致按键卡住
     * 重复事件本身无害，GBA核心会正确处理状态
     */
    int gba_key = luat_mgba_key_from_scancode(scancode);
    if (gba_key != 0) {
        luat_mgba_set_key(ctx, gba_key, pressed);
        
        /* 更新跟踪状态用于调试 */
        if (scancode >= 0 && scancode < SDL_NUM_SCANCODES) {
            key_pressed_state[scancode] = pressed ? 1 : 0;
        }
        
#ifdef __LUATOS__
        /* 调试日志 - 仅在状态变化时输出 */
        if (pressed) {
            LLOGD("Key pressed: %s (0x%04X)", luat_mgba_key_name(gba_key), gba_key);
        } else {
            LLOGD("Key released: %s (0x%04X)", luat_mgba_key_name(gba_key), gba_key);
        }
#endif
    }
}

const char* luat_mgba_key_name(int key) {
    /* 按键名称查找表 */
    static const struct {
        int key;
        const char* name;
    } key_names[] = {
        { LUAT_MGBA_KEY_A,      "A" },
        { LUAT_MGBA_KEY_B,      "B" },
        { LUAT_MGBA_KEY_SELECT, "SELECT" },
        { LUAT_MGBA_KEY_START,  "START" },
        { LUAT_MGBA_KEY_RIGHT,  "RIGHT" },
        { LUAT_MGBA_KEY_LEFT,   "LEFT" },
        { LUAT_MGBA_KEY_UP,     "UP" },
        { LUAT_MGBA_KEY_DOWN,   "DOWN" },
        { LUAT_MGBA_KEY_R,      "R" },
        { LUAT_MGBA_KEY_L,      "L" },
        { 0, NULL }
    };
    
    for (int i = 0; key_names[i].name != NULL; i++) {
        if (key_names[i].key == key) {
            return key_names[i].name;
        }
    }
    
    return "UNKNOWN";
}

/* ========== 高级输入 API ========== */

/**
 * @brief 按键名称字符串到按键码的映射
 */
typedef struct {
    const char* name;
    int key;
} key_name_map_t;

static const key_name_map_t key_name_map[] = {
    { "a",      LUAT_MGBA_KEY_A },
    { "A",      LUAT_MGBA_KEY_A },
    { "b",      LUAT_MGBA_KEY_B },
    { "B",      LUAT_MGBA_KEY_B },
    { "start",  LUAT_MGBA_KEY_START },
    { "START",  LUAT_MGBA_KEY_START },
    { "select", LUAT_MGBA_KEY_SELECT },
    { "SELECT", LUAT_MGBA_KEY_SELECT },
    { "up",     LUAT_MGBA_KEY_UP },
    { "UP",     LUAT_MGBA_KEY_UP },
    { "down",   LUAT_MGBA_KEY_DOWN },
    { "DOWN",   LUAT_MGBA_KEY_DOWN },
    { "left",   LUAT_MGBA_KEY_LEFT },
    { "LEFT",   LUAT_MGBA_KEY_LEFT },
    { "right",  LUAT_MGBA_KEY_RIGHT },
    { "RIGHT",  LUAT_MGBA_KEY_RIGHT },
    { "l",      LUAT_MGBA_KEY_L },
    { "L",      LUAT_MGBA_KEY_L },
    { "r",      LUAT_MGBA_KEY_R },
    { "R",      LUAT_MGBA_KEY_R },
    { NULL, 0 }
};

/**
 * @brief 从按键名称字符串获取按键码
 * @param name 按键名称
 * @return 按键码，0 表示无效
 */
int luat_mgba_key_from_name(const char* name) {
    if (!name) {
        return 0;
    }
    
    for (const key_name_map_t* map = key_name_map; map->name != NULL; map++) {
        if (strcmp(map->name, name) == 0) {
            return map->key;
        }
    }
    
    return 0;
}

#endif /* LUAT_USE_MGBA */