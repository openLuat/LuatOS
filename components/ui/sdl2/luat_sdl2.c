#include "luat_base.h"
#include "luat_sdl2.h"

#include "SDL2/SDL.h"
#if defined(_WIN32)
#include <windows.h>
#include <SDL_syswm.h>
#endif

#define LUAT_LOG_TAG "sdl2"
#include "luat_log.h"

static SDL_Window *window = NULL;
static SDL_Renderer *renderer = NULL;
static SDL_Texture *framebuffer = NULL;
static luat_sdl2_conf_t sdl_conf;
static int aspect_last_window_w = 0;
static int aspect_last_window_h = 0;
static uint8_t aspect_adjusting_window = 0;

// 屏幕适配比例, 当画面超过屏幕长宽时，缩放到屏幕长宽的90%以内
#define LUAT_SDL2_SCREEN_FIT_PERCENT 90

#if defined(_WIN32)
typedef struct {
    HWND hwnd;
    WNDPROC prev_wndproc;
    int aspect_w;
    int aspect_h;
    int frame_w;
    int frame_h;
} luat_sdl2_native_resize_t;

static luat_sdl2_native_resize_t native_resize;
#endif

typedef struct {
    uint8_t enable;
    uint16_t rotation;
    size_t native_width;
    size_t native_height;
} luat_sdl2_preview_state_t;

static luat_sdl2_preview_state_t preview_state;

static void luat_sdl2_present_current_frame(void);

#if defined(_WIN32)
static void luat_sdl2_refresh_window_frame(void) {
    if (native_resize.hwnd == NULL) {
        return;
    }

    RECT window_rect;
    RECT client_rect;
    if (!GetWindowRect(native_resize.hwnd, &window_rect) || !GetClientRect(native_resize.hwnd, &client_rect)) {
        return;
    }

    native_resize.frame_w = (window_rect.right - window_rect.left) - (client_rect.right - client_rect.left);
    native_resize.frame_h = (window_rect.bottom - window_rect.top) - (client_rect.bottom - client_rect.top);
}

static void luat_sdl2_apply_aspect_rect(RECT *rect, UINT edge) {
    if (rect == NULL || native_resize.aspect_w <= 0 || native_resize.aspect_h <= 0) {
        return;
    }

    int outer_w = rect->right - rect->left;
    int outer_h = rect->bottom - rect->top;
    int client_w = outer_w - native_resize.frame_w;
    int client_h = outer_h - native_resize.frame_h;
    if (client_w <= 0 || client_h <= 0) {
        return;
    }

    int width_driven = 0;
    switch (edge) {
        case WMSZ_LEFT:
        case WMSZ_RIGHT:
            width_driven = 1;
            break;
        case WMSZ_TOP:
        case WMSZ_BOTTOM:
            width_driven = 0;
            break;
        default:
            width_driven = abs(outer_w - aspect_last_window_w) >= abs(outer_h - aspect_last_window_h);
            break;
    }

    if (width_driven) {
        int target_client_h = (int)(((int64_t)client_w * native_resize.aspect_h + native_resize.aspect_w / 2) / native_resize.aspect_w);
        int target_outer_h = target_client_h + native_resize.frame_h;
        if (edge == WMSZ_TOP || edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT) {
            rect->top = rect->bottom - target_outer_h;
        } else {
            rect->bottom = rect->top + target_outer_h;
        }
    } else {
        int target_client_w = (int)(((int64_t)client_h * native_resize.aspect_w + native_resize.aspect_h / 2) / native_resize.aspect_h);
        int target_outer_w = target_client_w + native_resize.frame_w;
        if (edge == WMSZ_LEFT || edge == WMSZ_TOPLEFT || edge == WMSZ_BOTTOMLEFT) {
            rect->left = rect->right - target_outer_w;
        } else {
            rect->right = rect->left + target_outer_w;
        }
    }

    aspect_last_window_w = rect->right - rect->left;
    aspect_last_window_h = rect->bottom - rect->top;
}

static LRESULT CALLBACK luat_sdl2_window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    if (msg == WM_SIZING && hwnd == native_resize.hwnd) {
        luat_sdl2_apply_aspect_rect((RECT *)lparam, (UINT)wparam);
        return TRUE;
    }

    if ((msg == WM_SIZE || msg == WM_PAINT) && hwnd == native_resize.hwnd) {
        LRESULT result = CallWindowProc(native_resize.prev_wndproc, hwnd, msg, wparam, lparam);
        luat_sdl2_present_current_frame();
        return result;
    }

    return CallWindowProc(native_resize.prev_wndproc, hwnd, msg, wparam, lparam);
}

static void luat_sdl2_install_native_resize_hook(void) {
    if (window == NULL || native_resize.prev_wndproc != NULL) {
        return;
    }

    SDL_SysWMinfo wm_info;
    SDL_VERSION(&wm_info.version);
    if (!SDL_GetWindowWMInfo(window, &wm_info) || wm_info.subsystem != SDL_SYSWM_WINDOWS) {
        return;
    }

    native_resize.hwnd = wm_info.info.win.window;
    native_resize.prev_wndproc = (WNDPROC)SetWindowLongPtr(native_resize.hwnd, GWLP_WNDPROC, (LONG_PTR)luat_sdl2_window_proc);
    luat_sdl2_refresh_window_frame();
}

static void luat_sdl2_uninstall_native_resize_hook(void) {
    if (native_resize.hwnd != NULL && native_resize.prev_wndproc != NULL) {
        SetWindowLongPtr(native_resize.hwnd, GWLP_WNDPROC, (LONG_PTR)native_resize.prev_wndproc);
    }
    memset(&native_resize, 0, sizeof(native_resize));
}

static void luat_sdl2_set_native_aspect(size_t preview_width, size_t preview_height) {
    native_resize.aspect_w = (int)preview_width;
    native_resize.aspect_h = (int)preview_height;
    luat_sdl2_refresh_window_frame();
}
#else
static void luat_sdl2_install_native_resize_hook(void) {}
static void luat_sdl2_uninstall_native_resize_hook(void) {}
static void luat_sdl2_set_native_aspect(size_t preview_width, size_t preview_height) {
    (void)preview_width;
    (void)preview_height;
}
#endif

void luat_sdl2_get_preview_size(size_t native_width, size_t native_height, size_t *preview_width, size_t *preview_height) {
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

static void luat_sdl2_get_display_usable_bounds(SDL_Window *target_window, SDL_Rect *usable_bounds) {
    if (usable_bounds == NULL) {
        return;
    }

    int display_index = 0;
    if (target_window != NULL) {
        display_index = SDL_GetWindowDisplayIndex(target_window);
        if (display_index < 0) {
            display_index = 0;
        }
    }

    if (SDL_GetDisplayUsableBounds(display_index, usable_bounds) != 0) {
        usable_bounds->x = 0;
        usable_bounds->y = 0;
        usable_bounds->w = (int)sdl_conf.width;
        usable_bounds->h = (int)sdl_conf.height;
    }
}

static void luat_sdl2_calc_fitted_size(int container_w, int container_h,
                                       int content_w, int content_h,
                                       int max_percent,
                                       int *target_w, int *target_h) {
    if (target_w == NULL || target_h == NULL || container_w <= 0 || container_h <= 0 || content_w <= 0 || content_h <= 0) {
        return;
    }

    int max_w = container_w * max_percent / 100;
    int max_h = container_h * max_percent / 100;
    if (max_w <= 0) {
        max_w = container_w;
    }
    if (max_h <= 0) {
        max_h = container_h;
    }

    if (content_w <= max_w && content_h <= max_h) {
        *target_w = content_w;
        *target_h = content_h;
        return;
    }

    int fitted_w = max_w;
    int fitted_h = (int)((int64_t)content_h * fitted_w / content_w);
    if (fitted_h > max_h) {
        fitted_h = max_h;
        fitted_w = (int)((int64_t)content_w * fitted_h / content_h);
    }

    if (fitted_w <= 0) {
        fitted_w = 1;
    }
    if (fitted_h <= 0) {
        fitted_h = 1;
    }

    *target_w = fitted_w;
    *target_h = fitted_h;
}

static void luat_sdl2_update_aspect_window_size(int request_w, int request_h) {
    if (window == NULL || request_w <= 0 || request_h <= 0) {
        return;
    }

    size_t native_width = preview_state.native_width ? preview_state.native_width : sdl_conf.width;
    size_t native_height = preview_state.native_height ? preview_state.native_height : sdl_conf.height;
    size_t preview_width = native_width;
    size_t preview_height = native_height;
    luat_sdl2_get_preview_size(native_width, native_height, &preview_width, &preview_height);
    if (preview_width == 0 || preview_height == 0) {
        return;
    }

    int adjusted_w = request_w;
    int adjusted_h = request_h;
    int delta_w = abs(request_w - aspect_last_window_w);
    int delta_h = abs(request_h - aspect_last_window_h);

    if (aspect_last_window_w == 0 || aspect_last_window_h == 0 || delta_w >= delta_h) {
        adjusted_h = (int)(((int64_t)adjusted_w * (int)preview_height + (int)preview_width / 2) / (int)preview_width);
    } else {
        adjusted_w = (int)(((int64_t)adjusted_h * (int)preview_width + (int)preview_height / 2) / (int)preview_height);
    }

    if (adjusted_w <= 0) {
        adjusted_w = 1;
    }
    if (adjusted_h <= 0) {
        adjusted_h = 1;
    }

    if (adjusted_w == request_w && adjusted_h == request_h) {
        aspect_last_window_w = request_w;
        aspect_last_window_h = request_h;
        return;
    }

    aspect_adjusting_window = 1;
    aspect_last_window_w = adjusted_w;
    aspect_last_window_h = adjusted_h;
    SDL_SetWindowSize(window, adjusted_w, adjusted_h);
}

static void luat_sdl2_get_target_window_size(size_t preview_width, size_t preview_height, int *target_w, int *target_h) {
    SDL_Rect usable_bounds;
    luat_sdl2_get_display_usable_bounds(window, &usable_bounds);
    luat_sdl2_calc_fitted_size(usable_bounds.w, usable_bounds.h,
                               (int)preview_width, (int)preview_height,
                               LUAT_SDL2_SCREEN_FIT_PERCENT,
                               target_w, target_h);
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

// 将窗口居中显示
static void luat_sdl2_center_window(void) {
    if (window == NULL) {
        return;
    }

    int window_w = 0;
    int window_h = 0;
    SDL_GetWindowSize(window, &window_w, &window_h);
    if (window_w <= 0 || window_h <= 0) {
        return;
    }

    SDL_Rect usable_bounds;
    luat_sdl2_get_display_usable_bounds(window, &usable_bounds);

    int pos_x = usable_bounds.x + (usable_bounds.w - window_w) / 2;
    int pos_y = usable_bounds.y + (usable_bounds.h - window_h) / 2;
    SDL_SetWindowPosition(window, pos_x, pos_y);
    aspect_last_window_w = window_w;
    aspect_last_window_h = window_h;
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
    luat_sdl2_set_native_aspect(preview_width, preview_height);

    int target_w = 0;
    int target_h = 0;
    luat_sdl2_get_target_window_size(preview_width, preview_height, &target_w, &target_h);
    if (target_w <= 0 || target_h <= 0) {
        return;
    }

    SDL_SetWindowSize(window, target_w, target_h);
    luat_sdl2_center_window();
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
#if !defined(_WIN32)
        else if (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_SIZE_CHANGED && window != NULL && e.window.windowID == SDL_GetWindowID(window)) {
            if (aspect_adjusting_window) {
                aspect_adjusting_window = 0;
                aspect_last_window_w = e.window.data1;
                aspect_last_window_h = e.window.data2;
            } else {
                luat_sdl2_update_aspect_window_size(e.window.data1, e.window.data2);
            }
        }
        else if (e.type == SDL_WINDOWEVENT && (e.window.event == SDL_WINDOWEVENT_EXPOSED || e.window.event == SDL_WINDOWEVENT_RESIZED) &&
                 window != NULL && e.window.windowID == SDL_GetWindowID(window)) {
            luat_sdl2_present_current_frame();
        }
#endif
        // 其他事件不做处理，关键作用是让事件泵持续运行，防止界面假死
    }
}

static void luat_sdl2_present_current_frame(void) {
    if (renderer == NULL || framebuffer == NULL) {
        return;
    }

    SDL_RenderClear(renderer);
    if (preview_state.enable && preview_state.rotation != 0) {
        size_t native_width = preview_state.native_width ? preview_state.native_width : sdl_conf.width;
        size_t native_height = preview_state.native_height ? preview_state.native_height : sdl_conf.height;
        size_t preview_width = native_width;
        size_t preview_height = native_height;
        luat_sdl2_get_preview_size(native_width, native_height, &preview_width, &preview_height);

        int output_w = 0;
        int output_h = 0;
        if (SDL_GetRendererOutputSize(renderer, &output_w, &output_h) != 0 || output_w <= 0 || output_h <= 0) {
            SDL_GetWindowSize(window, &output_w, &output_h);
        }

        SDL_Rect dst = {
            .x = (int)(((int64_t)output_w - (int64_t)native_width * output_w / (int)preview_width) / 2),
            .y = (int)(((int64_t)output_h - (int64_t)native_height * output_h / (int)preview_height) / 2),
            .w = (int)((int64_t)native_width * output_w / (int)preview_width),
            .h = (int)((int64_t)native_height * output_h / (int)preview_height)
        };
        if (dst.w <= 0) {
            dst.w = 1;
        }
        if (dst.h <= 0) {
            dst.h = 1;
        }

        SDL_RenderCopyEx(renderer, framebuffer, NULL, &dst, luat_sdl2_get_preview_angle(), NULL, SDL_FLIP_NONE);
    }
    else {
        SDL_RenderCopy(renderer, framebuffer, NULL, NULL);
    }
    SDL_RenderPresent(renderer);
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

    int window_w = 0;
    int window_h = 0;
    luat_sdl2_get_target_window_size(conf->width, conf->height, &window_w, &window_h);
    if (window_w <= 0 || window_h <= 0) {
        window_w = (int)conf->width;
        window_h = (int)conf->height;
    }

    window = SDL_CreateWindow(conf->title == NULL ? "LuatOS" : conf->title,
                              SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                              window_w, window_h, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    luat_sdl2_center_window();
    luat_sdl2_install_native_resize_hook();
    luat_sdl2_set_native_aspect(conf->width, conf->height);

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
    luat_sdl2_uninstall_native_resize_hook();
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
        luat_sdl2_present_current_frame();
    }
    // 画面刷新后立刻处理（pump）SDL事件，保持窗口及触摸输入活跃
    luat_sdl2_pump_events();
}

void* luat_sdl2_get_window(void) {
    return window;
}

void luat_sdl2_set_upright_preview(uint8_t enable, uint16_t rotation, size_t native_width, size_t native_height) {
    uint8_t normalized_enable = enable ? 1 : 0;
    size_t normalized_width = native_width ? native_width : sdl_conf.width;
    size_t normalized_height = native_height ? native_height : sdl_conf.height;

    if (preview_state.enable == normalized_enable &&
        preview_state.rotation == rotation &&
        preview_state.native_width == normalized_width &&
        preview_state.native_height == normalized_height) {
        return;
    }

    preview_state.enable = normalized_enable;
    preview_state.rotation = rotation;
    preview_state.native_width = normalized_width;
    preview_state.native_height = normalized_height;
    luat_sdl2_apply_preview_window_size();
}
