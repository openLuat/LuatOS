// PC 模拟器专用:覆盖 components/u8g2/luat_lib_u8g2.c 的 LUAT_WEAK luat_u8g2_setup
// 当 i2c_id 或 spi_id == 21 时,把 display_cb 替换为 SDL2 渲染版本,把 u8g2 tile 数据
// 显示到 luat_sdl2 单例窗口(与 LVGL/AirUI 共享)。其它 id 走 default(no-op)。
// 仅在 GUI 构建中通过 xmake.lua 的 add_files 拉入,非 GUI 构建不受影响。

#include "luat_base.h"
#include "u8g2.h"
#include "luat_u8g2.h"
#include "luat_sdl2.h"
#include "luat_malloc.h"

#include <stdint.h>
#include <string.h>

// 拉窗口到前台需要 SDL 原生 API
#include "SDL2/SDL.h"

#define LUAT_LOG_TAG "u8g2.sdl2"
#include "luat_log.h"

// luat_u8g2_setup_default 未在 luat_u8g2.h 暴露,在这里前向声明
extern int luat_u8g2_setup_default(luat_u8g2_conf_t *conf);

// PC 模拟器识别 id:bsp/pc/port/driver/luat_i2c_pc.c 的 luat_i2c_exist 已对应放行
// SPI 走 bus_id==21 也不会被 luat_spi_pc.c 的虚拟总线路由(只认 bus_id==20),安全
#define LUAT_PC_U8G2_EMU_ID  21

// 内部 1bpp→RGB565 framebuffer。luat_sdl2_init 创建的是 RGB565 streaming texture,
// 每像素 2 字节,所以这里用 uint16_t。
static uint16_t* s_rgb_buf = NULL;
static int       s_rgb_w   = 0;
static int       s_rgb_h   = 0;
static uint8_t   s_sdl_inited = 0;

// 把 8 字节 1bpp tile 写入 s_rgb_buf 的 (px_x, px_y) 起始位置
// u8g2 tile 格式:byte 序号 = 横向列(0..7),bit 位 = 纵向行(bit0 = 顶,bit7 = 底)
static void tile_to_rgb565(const uint8_t* tile, int px_x, int px_y) {
    for (int col = 0; col < 8; col++) {
        uint8_t b = tile[col];
        for (int row = 0; row < 8; row++) {
            uint16_t color = (b >> row) & 1 ? 0xFFFF : 0x0000;  // 1=白 0=黑
            s_rgb_buf[(px_y + row) * s_rgb_w + (px_x + col)] = color;
        }
    }
}

// 第一次进入 display_cb 时调用,完成 SDL init + rgb_buf 分配
// 必须 lazy:luat_u8g2_setup_default 内部的 u8g2_InitDisplay 走的是原版 display_cb,
// 我们的 display_cb 是 default 之后才替换上的,所以 U8X8_MSG_DISPLAY_INIT 永远不会进
static void ensure_sdl_inited(u8x8_t *u8x8) {
    if (s_rgb_buf != NULL) return;
    s_rgb_w = u8x8->display_info->pixel_width;
    s_rgb_h = u8x8->display_info->pixel_height;
    size_t bytes = (size_t)s_rgb_w * (size_t)s_rgb_h * sizeof(uint16_t);
    s_rgb_buf = (uint16_t*)luat_heap_malloc(bytes);
    if (s_rgb_buf) {
        memset(s_rgb_buf, 0, bytes);
    }
    if (!s_sdl_inited) {
        luat_sdl2_conf_t conf = {
            .width  = (size_t)s_rgb_w,
            .height = (size_t)s_rgb_h,
            .title  = "LuatOS u8g2",
        };
        if (luat_sdl2_init(&conf) == 0) {
            s_sdl_inited = 1;
            LLOGD("u8g2.sdl2 luat_sdl2_init OK (%dx%d)", s_rgb_w, s_rgb_h);
            // 拉窗口到前台 + 解除最小化,避免被遮挡或藏在任务栏
            SDL_Window* win = (SDL_Window*)luat_sdl2_get_window();
            if (win != NULL) {
                SDL_ShowWindow(win);
                SDL_RaiseWindow(win);
            }
        } else {
            LLOGW("u8g2.sdl2 luat_sdl2_init failed (likely already inited by LVGL)");
        }
    }
}

static uint8_t u8x8_pc_sdl2_display_cb(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    // 任何消息都先保证 SDL 就绪(详见 ensure_sdl_inited 注释)
    ensure_sdl_inited(u8x8);

    switch (msg) {
        case U8X8_MSG_DISPLAY_DRAW_TILE: {
            if (s_rgb_buf == NULL || !s_sdl_inited) return 1;
            u8x8_tile_t* tile = (u8x8_tile_t*)arg_ptr;
            int x0 = tile->x_pos * 8;
            int y0 = tile->y_pos * 8;
            // 展开 arg_int 次重复、cnt 个水平 tile;u8g2 文档:
            // 起点 (x_pos, y_pos),后续 tile 横向右移,arg_int 决定整体重复次数
            for (int r = 0; r < arg_int; r++) {
                for (int i = 0; i < tile->cnt; i++) {
                    int x = x0 + (i + r * tile->cnt) * 8;
                    if (x + 8 > s_rgb_w) break;  // 越过右边界(罕见,防越界)
                    tile_to_rgb565(tile->tile_ptr + i * 8, x, y0);
                }
            }
            // 整帧上传:luat_sdl2_draw 的 pitch 硬编码为 r.w*2,做整帧上传最省心
            // (128x64 RGB565 = 16KB,传输成本可忽略)
            luat_sdl2_draw(0, 0, s_rgb_w - 1, s_rgb_h - 1, (uint32_t*)s_rgb_buf);
            // LLOGD("u8g2.sdl2 DRAW_TILE x0=%d y0=%d cnt=%d rep=%d", x0, y0, tile->cnt, arg_int);
            return 1;
        }

        case U8X8_MSG_DISPLAY_REFRESH: {
            if (s_sdl_inited) {
                luat_sdl2_flush();
                // LLOGD("u8g2.sdl2 REFRESH flushed");
            }
            return 1;
        }

        // 这些消息真实硬件上是 I2C/SPI 命令,模拟器无需处理
        case U8X8_MSG_DISPLAY_INIT:
        case U8X8_MSG_DISPLAY_SETUP_MEMORY:
        case U8X8_MSG_DISPLAY_SET_POWER_SAVE:
        case U8X8_MSG_DISPLAY_SET_FLIP_MODE:
        case U8X8_MSG_DISPLAY_SET_CONTRAST:
        default:
            return 1;
    }
}

// 强覆盖 components/u8g2/luat_lib_u8g2.c:1403 的 LUAT_WEAK luat_u8g2_setup
int luat_u8g2_setup(luat_u8g2_conf_t *conf) {
    int i2c_id = -1, spi_id = -1;
    luat_u8g2_get_bus_ids(&i2c_id, &spi_id);
    int ret = luat_u8g2_setup_default(conf);
    if (ret == 0 && (i2c_id == LUAT_PC_U8G2_EMU_ID || spi_id == LUAT_PC_U8G2_EMU_ID)) {
        LLOGD("u8g2 PC emulator: hijacking display_cb (i2c_id=%d, spi_id=%d)", i2c_id, spi_id);
        conf->u8g2.u8x8.display_cb = u8x8_pc_sdl2_display_cb;
    }
    return ret;
}
