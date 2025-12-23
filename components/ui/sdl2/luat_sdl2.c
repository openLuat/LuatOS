#include "luat_base.h"
#include "luat_sdl2.h"

#include "SDL2/SDL.h"

#define LUAT_LOG_TAG "sdl2"
#include "luat_log.h"

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *framebuffer = NULL;
static luat_sdl2_conf_t sdl_conf;

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
        // 将framebuffer的内容拷贝到渲染目标（窗口），准备呈现
        SDL_RenderCopy(renderer, framebuffer, NULL, NULL);
        // 实际执行呈现
        SDL_RenderPresent(renderer);
    }
    // 画面刷新后立刻处理（pump）SDL事件，保持窗口及触摸输入活跃
    luat_sdl2_pump_events();
}
