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

// u8g2 tile buffer 两种布局:
// - VERTICAL_TOP_LSB(ssd1306/sh1106):byte (y_byte, x_pixel) = column x_pixel, rows [y_byte*8..y_byte*8+7]
//   bit 0 = 顶 (y=0),bit 7 = 底 (y=7)
// - HORIZONTAL_RIGHT_LSB(st7305):byte (y_pixel, x_byte) = row y_pixel, columns [x_byte*8..x_byte*8+7]
//   bit 7 = 左 (x=0),bit 0 = 右 (x=7)
// 两种 layout 的 byte addressing 一致(r*tile_width + c),但 byte 内 bit 解读相反。
// 实际 DRAW_TILE 时 tile_ptr 是 u8g2->tile_buf_ptr + src_tile_row * tile_width * 8
// 指向 tile_width * 8 = 一行 tile 的全部 8 个 pixel row 字节。
#define LAYOUT_VERTICAL_TOP_LSB    0  // ssd1306/sh1106 系列
#define LAYOUT_HORIZONTAL_RIGHT_LSB 1  // st7305/st7920/sh1122/ld7032 系列
static int s_layout = LAYOUT_VERTICAL_TOP_LSB;  // 缺省按 ssd1306 走(096 测试用例)

// 内部 1bpp→RGB565 framebuffer。luat_sdl2_init 创建的是 RGB565 streaming texture,
// 每像素 2 字节,所以这里用 uint16_t。
static uint16_t* s_rgb_buf = NULL;
static int       s_rgb_w   = 0;
static int       s_rgb_h   = 0;
static uint8_t   s_sdl_inited = 0;

// SDL2 窗口物理放大倍数:环境变量 LUAT_U8G2_SDL2_SCALE=N (1~8, 默认 1)
// 168x384 的 st7305 物理像素小,放大后在大屏显示器上字看着大,1bpp 用 SDL2 stretch 抗锯齿会变柔,
// 这里做最近邻放大,1 像素 = N×N 大块,保持黑白硬边
static int s_sdl_scale = 1;

// 把一个 tile row 写入 s_rgb_buf。tile_row 指向 u8g2 buffer 的 1 个 DRAW_TILE chunk:
//   大小 = tile_width * 8 字节(对 1bpp 来说 = 8 像素高的一整行 tile)。
//
// 两种 layout 的 chunk 大小一样(byte 数 = tile_width * 8),
// 但 chunk 内 byte 的含义不同:
//
// VERTICAL_TOP_LSB(ssd1306/sh1106):1 byte = 1 column × 8 vertical pixels(bit 0=顶)。
//   chunk = tile_width*8 字节(对 ssd1306:16*8=128 字节 = 1 page = 128 列 × 8 行)。
//   1 chunk 覆盖 1 个 y_byte 段(8 行)上的所有列(对 ssd1306:全部 128 列)。
//   byte 在 chunk 内的索引 = 像素 x 列号,byte 内的 bit 0..7 = 段内行 0..7。
//
// HORIZONTAL_RIGHT_LSB(st7305/st7920/sh1122/ld7032):
//   1 byte = 1 row × 8 horizontal pixels(bit 7=左,bit 0=右)。
//   chunk = tile_width*8 字节(对 st7305 168x384:21*8=168 字节 = 8 行 × 21 byte 列)。
//   byte (r, c) at offset r*tile_width + c,8 行 r=0..7,byte 列 c=0..tile_width-1。
//   1 chunk 覆盖 8 行 × tile_width*8 = 8 行 × 168 列(st7305 整个 168 列宽)。
//
// 两种 layout 的 1 chunk 高度都是 8 像素,所以 y0 = tile->y_pos * 8 是统一的。
// x0 = 0,因为 1 chunk 在水平方向覆盖整行 tile(对 ssd1306 全部 128 列,对 st7305 全部 168 列)。
static void tile_row_to_rgb565(const uint8_t* tile_row, int tile_width,
                                int px_x, int px_y) {
    if (s_layout == LAYOUT_VERTICAL_TOP_LSB) {
        // chunk = tile_width*8 字节,1 byte = 1 column × 8 vertical pixels
        // byte 索引 = 像素 x 列号;bit 0..7 = 行 0..7
        int total_cols = tile_width * 8;
        for (int col = 0; col < total_cols; col++) {
            uint8_t b = tile_row[col];
            for (int bit = 0; bit < 8; bit++) {
                int px = px_x + col;
                int py = px_y + bit;
                if (px >= s_rgb_w || py >= s_rgb_h) continue;
                uint16_t color = (b >> bit) & 1 ? 0xFFFF : 0x0000;
                s_rgb_buf[py * s_rgb_w + px] = color;
            }
        }
    } else {
        // HORIZONTAL_RIGHT_LSB:byte (r, c) = 1 row × 8 horizontal pixels
        // pixel position: x = px_x + c*8 + (7-bit), y = px_y + r
        // bit 7 = leftmost (col 0 of those 8),bit 0 = rightmost
        for (int r = 0; r < 8; r++) {
            for (int c = 0; c < tile_width; c++) {
                uint8_t b = tile_row[r * tile_width + c];
                for (int bit = 0; bit < 8; bit++) {
                    int px = px_x + c * 8 + (7 - bit);
                    int py = px_y + r;
                    if (px >= s_rgb_w || py >= s_rgb_h) continue;
                    uint16_t color = (b >> bit) & 1 ? 0xFFFF : 0x0000;
                    s_rgb_buf[py * s_rgb_w + px] = color;
                }
            }
        }
    }
}

// 把 s_rgb_buf 整个最近邻放大 N 倍到 s_rgb_buf_scaled
// 168x384 在 N=4 时 672x1536,在 PC 显示器上字大,1bpp 硬边看着清楚
static void rgb_buf_nearest_scale(const uint16_t* src, int src_w, int src_h,
                                  uint16_t* dst, int dst_w, int dst_h, int n) {
    for (int y = 0; y < src_h; y++) {
        for (int x = 0; x < src_w; x++) {
            uint16_t c = src[y * src_w + x];
            int dy0 = y * n;
            int dx0 = x * n;
            for (int dy = 0; dy < n; dy++) {
                for (int dx = 0; dx < n; dx++) {
                    dst[(dy0 + dy) * dst_w + (dx0 + dx)] = c;
                }
            }
        }
    }
}

// 第一次进入 display_cb 时调用,完成 SDL init + rgb_buf 分配
// 必须 lazy:luat_u8g2_setup_default 内部的 u8g2_InitDisplay 走的是原版 display_cb,
// 我们的 display_cb 是 default 之后才替换上的,所以 U8X8_MSG_DISPLAY_INIT 永远不会进
static uint16_t* s_rgb_buf_scaled = NULL;
static int       s_rgb_scaled_w = 0;
static int       s_rgb_scaled_h = 0;

static void ensure_sdl_inited(u8x8_t *u8x8) {
    if (s_rgb_buf != NULL) return;
    s_rgb_w = u8x8->display_info->pixel_width;
    s_rgb_h = u8x8->display_info->pixel_height;
    size_t bytes = (size_t)s_rgb_w * (size_t)s_rgb_h * sizeof(uint16_t);
    s_rgb_buf = (uint16_t*)luat_heap_malloc(bytes);
    if (s_rgb_buf) {
        memset(s_rgb_buf, 0, bytes);
    }
    // 读取放大倍数,默认 1(不放大)
    const char* env_scale = getenv("LUAT_U8G2_SDL2_SCALE");
    if (env_scale && env_scale[0]) {
        int n = atoi(env_scale);
        if (n >= 1 && n <= 8) s_sdl_scale = n;
    }
    // 预分配放大后的 framebuffer
    if (s_sdl_scale > 1) {
        s_rgb_scaled_w = s_rgb_w * s_sdl_scale;
        s_rgb_scaled_h = s_rgb_h * s_sdl_scale;
        size_t sbytes = (size_t)s_rgb_scaled_w * (size_t)s_rgb_scaled_h * sizeof(uint16_t);
        s_rgb_buf_scaled = (uint16_t*)luat_heap_malloc(sbytes);
        if (s_rgb_buf_scaled) {
            memset(s_rgb_buf_scaled, 0, sbytes);
        }
    } else {
        s_rgb_scaled_w = s_rgb_w;
        s_rgb_scaled_h = s_rgb_h;
    }
    if (!s_sdl_inited) {
        luat_sdl2_conf_t conf = {
            .width  = (size_t)s_rgb_scaled_w,
            .height = (size_t)s_rgb_scaled_h,
            .title  = "LuatOS u8g2",
        };
        if (luat_sdl2_init(&conf) == 0) {
            s_sdl_inited = 1;
            LLOGD("u8g2.sdl2 luat_sdl2_init OK (%dx%d, scale=%d, layout=%d)",
                  s_rgb_scaled_w, s_rgb_scaled_h, s_sdl_scale, s_layout);
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

// dump 当前 SDL 渲染输出到 BMP。模仿 components/ui/sdl2/luat_sdl2.c 的
// luat_sdl2_screenshot_bmp:用 SDL_RenderReadPixels 读 renderer,不直接读 s_rgb_buf
// (s_rgb_buf 路径上 dump 出来不可靠,renderer 才是用户真正看到的画面)。
// 返回 0 成功,负数失败。
static int dump_renderer_bmp(const char* path) {
    // renderer/framebuffer 是 luat_sdl2.c 内部的 static,这里通过获取窗口后用 SDL API 自己渲染读出
    SDL_Window* win = (SDL_Window*)luat_sdl2_get_window();
    if (win == NULL) return -1;
    SDL_Renderer* ren = SDL_GetRenderer(win);
    if (ren == NULL) return -2;

    int win_w = 0, win_h = 0;
    SDL_GetRendererOutputSize(ren, &win_w, &win_h);
    if (win_w <= 0 || win_h <= 0) return -3;

    // SDL_RenderReadPixels 读最近一次渲染的输出(可能不含正在展示的 1bpp 内容,需要先 RenderPresent)
    // u8g2 的 DRAW_TILE → luat_sdl2_draw → SDL_UpdateTexture → 等到 REFRESH 才 luat_sdl2_flush
    // 我们已经在调用 dump 前 flush 过了(REFRESH 流程),所以这里直接读
    size_t raw_size = (size_t)win_w * (size_t)win_h * 4;
    uint8_t* raw = (uint8_t*)malloc(raw_size);
    if (raw == NULL) return -4;
    if (SDL_RenderReadPixels(ren, NULL, SDL_PIXELFORMAT_ARGB8888, raw, win_w * 4) != 0) {
        LLOGE("u8g2.sdl2 SDL_RenderReadPixels failed: %s", SDL_GetError());
        free(raw);
        return -5;
    }

    // 写 24-bit BMP(airui 的 luat_sdl2_screenshot_bmp 写法)
    int row_size = win_w * 3;
    int pad_size = (4 - (row_size % 4)) % 4;
    int image_size = (row_size + pad_size) * win_h;
    uint32_t file_size = 54 + (uint32_t)image_size;

    FILE* fp = fopen(path, "wb");
    if (fp == NULL) {
        LLOGE("u8g2.sdl2 dump: cannot open %s", path);
        free(raw);
        return -6;
    }

    uint8_t bmp_fh[14] = {0};
    bmp_fh[0] = 'B'; bmp_fh[1] = 'M';
    // little-endian file_size
    bmp_fh[2] = (uint8_t)(file_size);
    bmp_fh[3] = (uint8_t)(file_size >> 8);
    bmp_fh[4] = (uint8_t)(file_size >> 16);
    bmp_fh[5] = (uint8_t)(file_size >> 24);
    bmp_fh[10] = 54;

    uint8_t bmp_ih[40] = {0};
    bmp_ih[0] = 40;
    // width
    bmp_ih[4] = (uint8_t)(win_w);
    bmp_ih[5] = (uint8_t)(win_w >> 8);
    bmp_ih[6] = (uint8_t)(win_w >> 16);
    bmp_ih[7] = (uint8_t)(win_w >> 24);
    // height
    bmp_ih[8] = (uint8_t)(win_h);
    bmp_ih[9] = (uint8_t)(win_h >> 8);
    bmp_ih[10] = (uint8_t)(win_h >> 16);
    bmp_ih[11] = (uint8_t)(win_h >> 24);
    bmp_ih[12] = 1;    // planes
    bmp_ih[14] = 24;   // bpp
    bmp_ih[20] = (uint8_t)(image_size);
    bmp_ih[21] = (uint8_t)(image_size >> 8);
    bmp_ih[22] = (uint8_t)(image_size >> 16);
    bmp_ih[23] = (uint8_t)(image_size >> 24);

    fwrite(bmp_fh, 1, 14, fp);
    fwrite(bmp_ih, 1, 40, fp);

    // ARGB8888 → BGR24,BMP 是 bottom-up
    uint8_t pad[3] = {0, 0, 0};
    for (int y = win_h - 1; y >= 0; y--) {
        const uint8_t* row = raw + (size_t)y * win_w * 4;
        for (int x = 0; x < win_w; x++) {
            uint8_t b = row[x * 4 + 0];
            uint8_t g = row[x * 4 + 1];
            uint8_t r = row[x * 4 + 2];
            uint8_t bgr[3] = {b, g, r};
            fwrite(bgr, 1, 3, fp);
        }
        if (pad_size > 0) fwrite(pad, 1, pad_size, fp);
    }
    fclose(fp);
    free(raw);
    return 0;
}

static uint8_t u8x8_pc_sdl2_display_cb(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr) {
    // 任何消息都先保证 SDL 就绪(详见 ensure_sdl_inited 注释)
    ensure_sdl_inited(u8x8);

    // dump 调试状态:提到函数顶部,DRAW_TILE 和 REFRESH 都能访问
    static int s_dump_call = 0;
    static int s_dump_count = 0;
    static int s_dump_total = -1;

    switch (msg) {
        case U8X8_MSG_DISPLAY_DRAW_TILE: {
            if (s_rgb_buf == NULL || !s_sdl_inited) return 1;
            u8x8_tile_t* tile = (u8x8_tile_t*)arg_ptr;
            int x0 = tile->x_pos * 8;
            int y0 = tile->y_pos * 8;
            // u8g2 文档:起点 (x_pos, y_pos),后续 tile 横向右移,arg_int 决定整体重复次数
            // 真实调用中 arg_int 一般是 1(单页),但保险起见仍展开
            // tile_ptr 是一整行 tile 数据(tile_width * 8 字节,8 像素高)
            // 一次写完一整行,而不是分 tile,因为 layout 字节序是按行排的
            tile_row_to_rgb565(tile->tile_ptr, tile->cnt, x0, y0);
            // 整帧上传:luat_sdl2_draw 的 pitch 硬编码为 r.w*2,做整帧上传最省心
            // SCALE>1 时:先最近邻放大到 s_rgb_buf_scaled,再上传放大后的 buffer
            if (s_sdl_scale > 1 && s_rgb_buf_scaled) {
                rgb_buf_nearest_scale(s_rgb_buf, s_rgb_w, s_rgb_h,
                                      s_rgb_buf_scaled, s_rgb_scaled_w, s_rgb_scaled_h,
                                      s_sdl_scale);
                luat_sdl2_draw(0, 0, s_rgb_scaled_w - 1, s_rgb_scaled_h - 1,
                               (uint32_t*)s_rgb_buf_scaled);
            } else {
                luat_sdl2_draw(0, 0, s_rgb_w - 1, s_rgb_h - 1, (uint32_t*)s_rgb_buf);
            }
            return 1;
        }

        case U8X8_MSG_DISPLAY_REFRESH: {
            if (s_sdl_inited) {
                luat_sdl2_flush();
            }
            // REFRESH 在所有 DRAW_TILE 完成之后触发,是 dump 整帧的最佳时机
            if (s_dump_total < 0) {
                const char* env0 = getenv("LUAT_U8G2_SDL2_DUMP_BMP");
                if (env0 && env0[0]) {
                    if ((env0[0] == 'C' || env0[0] == 'c') && env0[1] == 'O') {
                        s_dump_total = atoi(env0 + 6);
                        if (s_dump_total <= 0 || s_dump_total > 100) s_dump_total = 3;
                    } else {
                        s_dump_total = 3;
                    }
                } else {
                    s_dump_total = 0;
                }
            }
            if (s_dump_total > 0 && s_dump_call < s_dump_total && s_sdl_inited) {
                char path[64];
                snprintf(path, sizeof(path), "u8g2_frame_%03d.bmp", s_dump_count);
                if (dump_renderer_bmp(path) == 0) {
                    LLOGI("u8g2.sdl2 dumped %s frame=%d", path, s_dump_count);
                }
                s_dump_count++;
                s_dump_call++;
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
        // 根据 ll_hvline 决定 tile buffer 解读方式
        if (conf->u8g2.ll_hvline == u8g2_ll_hvline_horizontal_right_lsb) {
            s_layout = LAYOUT_HORIZONTAL_RIGHT_LSB;
        } else {
            s_layout = LAYOUT_VERTICAL_TOP_LSB;
        }
        LLOGD("u8g2 PC emulator: hijacking display_cb (i2c_id=%d, spi_id=%d, layout=%d, tile_w=%d, pix_w=%d, pix_h=%d)",
              i2c_id, spi_id, s_layout,
              conf->u8g2.u8x8.display_info->tile_width,
              conf->u8g2.u8x8.display_info->pixel_width,
              conf->u8g2.u8x8.display_info->pixel_height);
        conf->u8g2.u8x8.display_cb = u8x8_pc_sdl2_display_cb;
    }
    return ret;
}
