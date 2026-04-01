#include "luat_base.h"
#include "luat_sdl2.h"

#include "SDL2/SDL.h"

#define LUAT_LOG_TAG "sdl2"
#include "luat_log.h"

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *framebuffer = NULL;
static luat_sdl2_conf_t sdl_conf;

typedef struct {
    uint8_t enable;
    uint16_t rotation;
    size_t native_width;
    size_t native_height;
} luat_sdl2_preview_state_t;

static luat_sdl2_preview_state_t preview_state;

static void luat_sdl2_get_preview_size(size_t native_width, size_t native_height, size_t *preview_width, size_t *preview_height) {
    if (preview_width == NULL || preview_height == NULL) {
        return;
    }

    *preview_width = native_width;
    *preview_height = native_height;

    if (!preview_state.enable) {
        return;
    }

    if (preview_state.rotation == 90 || preview_state.rotation == 270) {
        *preview_width = native_height;
        *preview_height = native_width;
    }
}

static double luat_sdl2_get_preview_angle(void) {
    if (!preview_state.enable) {
        return 0.0;
    }

    switch (preview_state.rotation) {
        case 90:
            return 90.0;
        case 180:
            return 180.0;
        case 270:
            return 270.0;
        case 0:
        default:
            return 0.0;
    }
}

static void luat_sdl2_apply_preview_window_size(void) {
    if (window == NULL) {
        return;
    }

    size_t native_width = preview_state.native_width ? preview_state.native_width : sdl_conf.width;
    size_t native_height = preview_state.native_height ? preview_state.native_height : sdl_conf.height;
    size_t preview_width = native_width;
    size_t preview_height = native_height;
    luat_sdl2_get_preview_size(native_width, native_height, &preview_width, &preview_height);
    SDL_SetWindowSize(window, (int)preview_width, (int)preview_height);
}

// 定时调用此函数以保持 SDL2 事件泵活跃，避免窗口无响应
void luat_sdl2_pump_events(void) {
    SDL_Event e;
    // 循环处理所有等待的事件
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            // 当用户关闭窗口时，优雅退出程序
            exit(0);
        }
        // 其他事件不做处理，关键作用是让事件泵持续运行，防止界面假死
    }
}

int luat_sdl2_init(luat_sdl2_conf_t *conf) {
    if (framebuffer != NULL) {
        LLOGD("SDL2 aready inited");
        return -1;
    }
    if (SDL_InitSubSystem(SDL_INIT_VIDEO) != 0) {
        LLOGE("SDL_InitSubSystem failed: %s\n", SDL_GetError());
        return -1;
    }
    memcpy(&sdl_conf, conf, sizeof(luat_sdl2_conf_t));
    memset(&preview_state, 0, sizeof(preview_state));
    preview_state.native_width = conf->width;
    preview_state.native_height = conf->height;

    window = SDL_CreateWindow(conf->title == NULL ? "LuatOS" : conf->title,
                              SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                              conf->width, conf->height, 0);

    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    framebuffer = SDL_CreateTexture(renderer,
                                    SDL_PIXELFORMAT_RGB565,
                                    SDL_TEXTUREACCESS_STREAMING,
                                    conf->width,
                                    conf->height);
    luat_sdl2_pump_events();
    return 0;
}

int luat_sdl2_deinit(luat_sdl2_conf_t *conf) {
    SDL_DestroyTexture(framebuffer);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
    // free(fb);
    framebuffer = NULL;
    renderer = NULL;
    window = NULL;
    // fb = NULL;
    return 0;
}

void luat_sdl2_draw(int16_t x1, int16_t y1, int16_t x2, int16_t y2, uint32_t* data) {
    SDL_Rect r;
    r.x = x1;
    r.y = y1;
    r.w = x2 - x1 + 1;
    r.h = y2 - y1 + 1;

    // RGB565: 2 bytes per pixel
    SDL_UpdateTexture(framebuffer, &r, data, r.w * 2);
}

// 刷新渲染器，将framebuffer渲染到窗口，并立即处理SDL事件
void luat_sdl2_flush(void) {
    if (renderer && framebuffer)
    {
        size_t native_width = preview_state.native_width ? preview_state.native_width : sdl_conf.width;
        size_t native_height = preview_state.native_height ? preview_state.native_height : sdl_conf.height;
        size_t preview_width = native_width;
        size_t preview_height = native_height;
        luat_sdl2_get_preview_size(native_width, native_height, &preview_width, &preview_height);

        // 将framebuffer的内容拷贝到渲染目标（窗口），准备呈现
        SDL_RenderClear(renderer);
        if (preview_state.enable && preview_state.rotation != 0) {
            int preview_x = ((int)preview_width - (int)native_width) / 2;
            int preview_y = ((int)preview_height - (int)native_height) / 2;
            SDL_Rect dst = {
                .x = preview_x,
                .y = preview_y,
                .w = (int)native_width,
                .h = (int)native_height
            };
            SDL_RenderCopyEx(renderer, framebuffer, NULL, &dst, luat_sdl2_get_preview_angle(), NULL, SDL_FLIP_NONE);
        }
        else {
            SDL_RenderCopy(renderer, framebuffer, NULL, NULL);
        }
        // 实际执行呈现
        SDL_RenderPresent(renderer);
    }
    // 画面刷新后立刻处理（pump）SDL事件，保持窗口及触摸输入活跃
    luat_sdl2_pump_events();
}

void* luat_sdl2_get_window(void) {
    return window;
}

void luat_sdl2_set_upright_preview(uint8_t enable, uint16_t rotation, size_t native_width, size_t native_height) {
    preview_state.enable = enable ? 1 : 0;
    preview_state.rotation = rotation;
    preview_state.native_width = native_width ? native_width : sdl_conf.width;
    preview_state.native_height = native_height ? native_height : sdl_conf.height;
    luat_sdl2_apply_preview_window_size();
}
