/** @file luat_plcui_platform_sdl.c
 * SDL display, pointer input, host screenshots and LuatOS VFS for plcui.
 * All functions run on the Lua/UI thread; no SDL worker calls into LVGL.
 */
#include "luat_base.h"
#if defined(LUAT_USE_PLCUI_SDL2)
#include "luat_plcui_platform.h"
#include "luat_plcui_conf.h"
#include "luat_fs.h"
#include "luat_timer_engine.h"
#include "luat_pcsim_host.h"
#include <SDL2/SDL.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>

/* Synchronization and platform services stay behind the common interface. */
static atomic_flag refresh_lock = ATOMIC_FLAG_INIT;

uint32_t plcui_platform_state_lock(void)
{
    while (atomic_flag_test_and_set_explicit(&refresh_lock, memory_order_acquire)) {}
    return 0;
}

void plcui_platform_state_unlock(uint32_t token)
{
    (void)token;
    atomic_flag_clear_explicit(&refresh_lock, memory_order_release);
}

const char *plcui_platform_name(void) { return "sdl"; }

int plcui_platform_bind_touch(struct luat_tp_config *config)
{
    /* Match AIRUI: physical TP binding is harmless on PC; SDL provides input. */
    (void)config;
    return 0;
}

/* lv_init already installs the PC software image codecs. */
int plcui_platform_image_init(void) { return 0; }
void plcui_platform_image_deinit(void) {}
uint32_t plcui_platform_image_hw_count(void) { return 0; }
uint32_t plcui_platform_image_sw_count(void) { return 0; }

typedef struct {
    int16_t x;
    int16_t y;
    bool pressed;
} plcui_pointer_t;

static struct {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;
    lv_display_t *display;
    lv_indev_t *pointer;
    uint16_t *frame;
    uint16_t *draw;
    int width;
    int height;
    plcui_pointer_t samples[128];
    unsigned head;
    unsigned tail;
    plcui_pointer_t last;
    bool initialized;
} g_sdl;

/* Owned by the Lua/UI thread. The engine callback only receives a session token;
   it never dereferences a timer slot or any SDL/LVGL object. */
static luat_timer_handle_t refresh_timer;

int plcui_platform_timer_start(uint32_t period_ms, void (*callback)(void *), void *parameter)
{
    if (refresh_timer) return -1;
    refresh_timer = luat_timer_engine_create(callback, parameter);
    if (!refresh_timer) return -1;
    if (luat_timer_engine_start(refresh_timer, period_ms, 1) != 0) {
        plcui_platform_timer_stop();
        return -1;
    }
    return 0;
}

void plcui_platform_timer_stop(void)
{
    if (!refresh_timer) return;
    luat_timer_engine_stop(refresh_timer);
    luat_timer_engine_delete(refresh_timer);
    refresh_timer = NULL;
}

static uint32_t plcui_sdl_tick(void)
{
    return SDL_GetTicks();
}

static void plcui_sdl_flush(lv_display_t *display, const lv_area_t *area, uint8_t *pixels)
{
    int width = lv_area_get_width(area);
    int height = lv_area_get_height(area);
    if (area->x1 >= 0 && area->y1 >= 0 && area->x2 < g_sdl.width && area->y2 < g_sdl.height) {
        for (int row = 0; row < height; ++row) {
            memcpy(g_sdl.frame + (area->y1 + row) * g_sdl.width + area->x1,
                   pixels + (size_t)row * width * sizeof(uint16_t),
                   (size_t)width * sizeof(uint16_t));
        }
    }
    if (lv_display_flush_is_last(display)) {
        SDL_UpdateTexture(g_sdl.texture, NULL, g_sdl.frame, g_sdl.width * (int)sizeof(uint16_t));
        SDL_RenderClear(g_sdl.renderer);
        SDL_RenderCopy(g_sdl.renderer, g_sdl.texture, NULL, NULL);
        SDL_RenderPresent(g_sdl.renderer);
    }
    lv_display_flush_ready(display);
}

static void plcui_sdl_pointer_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    (void)indev;
    if (g_sdl.head != g_sdl.tail) {
        g_sdl.last = g_sdl.samples[g_sdl.head];
        g_sdl.head = (g_sdl.head + 1U) % 128U;
    }
    data->point.x = g_sdl.last.x;
    data->point.y = g_sdl.last.y;
    data->state = g_sdl.last.pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    data->continue_reading = g_sdl.head != g_sdl.tail;
}

static void plcui_sdl_pointer_push(int x, int y, bool pressed)
{
    unsigned next = (g_sdl.tail + 1U) % 128U;
    if (next == g_sdl.head) {
        g_sdl.head = (g_sdl.head + 1U) % 128U;
    }
    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(g_sdl.window, &window_width, &window_height);
    if (window_width > 0 && window_height > 0) {
        x = x * g_sdl.width / window_width;
        y = y * g_sdl.height / window_height;
    }
    g_sdl.samples[g_sdl.tail].x = (int16_t)x;
    g_sdl.samples[g_sdl.tail].y = (int16_t)y;
    g_sdl.samples[g_sdl.tail].pressed = pressed;
    g_sdl.tail = next;
}

static lv_obj_t *plcui_sdl_focused_input(lv_obj_t *root)
{
    if (!root) return NULL;
    if (lv_obj_check_type(root, &lv_textarea_class) && lv_obj_has_state(root, LV_STATE_FOCUSED)) {
        return root;
    }
    uint32_t count = lv_obj_get_child_count(root);
    for (uint32_t i = 0; i < count; ++i) {
        lv_obj_t *found = plcui_sdl_focused_input(lv_obj_get_child(root, (int32_t)i));
        if (found) return found;
    }
    return NULL;
}

int plcui_platform_init(int width, int height)
{
    if (g_sdl.initialized || width <= 0 || height <= 0 || width > 2048 || height > 2048) return -1;
    memset(&g_sdl, 0, sizeof(g_sdl));
    if (SDL_InitSubSystem(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) return -1;
    g_sdl.width = width;
    g_sdl.height = height;
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    g_sdl.window = SDL_CreateWindow("plcui 0.2 | LuatOS PC",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, width, height,
        luat_pcsim_host_window_flags(SDL_WINDOW_SHOWN));
    if (!g_sdl.window) goto failed;
    g_sdl.renderer = SDL_CreateRenderer(g_sdl.window, -1, SDL_RENDERER_SOFTWARE);
    if (!g_sdl.renderer) goto failed;
    g_sdl.texture = SDL_CreateTexture(g_sdl.renderer, SDL_PIXELFORMAT_RGB565,
        SDL_TEXTUREACCESS_STREAMING, width, height);
    if (!g_sdl.texture) goto failed;
    g_sdl.frame = (uint16_t *)calloc((size_t)width * height, sizeof(uint16_t));
    g_sdl.draw = (uint16_t *)calloc((size_t)width * PLCUI_DISPLAY_LINES, sizeof(uint16_t));
    if (!g_sdl.frame || !g_sdl.draw) goto failed;
    g_sdl.display = lv_display_create(width, height);
    if (!g_sdl.display) goto failed;
    lv_display_set_default(g_sdl.display);
    lv_display_set_color_format(g_sdl.display, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(g_sdl.display, g_sdl.draw, NULL,
        (uint32_t)((size_t)width * PLCUI_DISPLAY_LINES * sizeof(uint16_t)), LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(g_sdl.display, plcui_sdl_flush);
    lv_timer_set_period(lv_display_get_refr_timer(g_sdl.display), PLCUI_REFRESH_PERIOD_MS);
    g_sdl.pointer = lv_indev_create();
    if (!g_sdl.pointer) goto failed;
    lv_indev_set_type(g_sdl.pointer, LV_INDEV_TYPE_POINTER);
    lv_indev_set_display(g_sdl.pointer, g_sdl.display);
    lv_indev_set_read_cb(g_sdl.pointer, plcui_sdl_pointer_read);
    lv_timer_set_period(lv_indev_get_read_timer(g_sdl.pointer), PLCUI_REFRESH_PERIOD_MS);
    lv_tick_set_cb(plcui_sdl_tick);
    SDL_StartTextInput();
    g_sdl.initialized = true;
    return 0;
failed:
    plcui_platform_deinit();
    return -1;
}

void plcui_platform_deinit(void)
{
    plcui_platform_timer_stop();
    if (g_sdl.pointer) lv_indev_delete(g_sdl.pointer);
    if (g_sdl.display) lv_display_delete(g_sdl.display);
    if (g_sdl.texture) SDL_DestroyTexture(g_sdl.texture);
    if (g_sdl.renderer) SDL_DestroyRenderer(g_sdl.renderer);
    if (g_sdl.window) SDL_DestroyWindow(g_sdl.window);
    free(g_sdl.draw);
    free(g_sdl.frame);
    memset(&g_sdl, 0, sizeof(g_sdl));
    SDL_QuitSubSystem(SDL_INIT_VIDEO | SDL_INIT_EVENTS);
}

void plcui_platform_poll(void)
{
    if (!g_sdl.initialized) return;
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
        case SDL_MOUSEBUTTONDOWN:
        case SDL_MOUSEBUTTONUP:
            if (event.button.button == SDL_BUTTON_LEFT) {
                plcui_sdl_pointer_push(event.button.x, event.button.y, event.type == SDL_MOUSEBUTTONDOWN);
            }
            break;
        case SDL_MOUSEMOTION:
            plcui_sdl_pointer_push(event.motion.x, event.motion.y, (event.motion.state & SDL_BUTTON_LMASK) != 0);
            break;
        case SDL_TEXTINPUT: {
            lv_obj_t *target = plcui_sdl_focused_input(lv_screen_active());
            if (target) lv_textarea_add_text(target, event.text.text);
            break;
        }
        case SDL_KEYDOWN: {
            if (event.key.keysym.sym == SDLK_F12) {
                const char *directory = getenv("PLCUI_CAPTURE_DIR");
                if (directory) {
                    char path[512];
                    int length = snprintf(path, sizeof(path), "%s/simulator-capture.bmp", directory);
                    if (length > 0 && (size_t)length < sizeof(path)) plcui_platform_snapshot(path);
                }
                break;
            }
            lv_obj_t *target = plcui_sdl_focused_input(lv_screen_active());
            if (!target) break;
            switch (event.key.keysym.sym) {
            case SDLK_BACKSPACE: lv_textarea_delete_char(target); break;
            case SDLK_DELETE: lv_textarea_delete_char_forward(target); break;
            case SDLK_LEFT: lv_textarea_cursor_left(target); break;
            case SDLK_RIGHT: lv_textarea_cursor_right(target); break;
            case SDLK_RETURN:
            case SDLK_KP_ENTER:
                if (lv_textarea_get_one_line(target)) lv_obj_send_event(target, LV_EVENT_READY, NULL);
                else lv_textarea_add_char(target, '\n');
                break;
            case SDLK_ESCAPE: lv_obj_send_event(target, LV_EVENT_CANCEL, NULL); break;
            default: break;
            }
            break;
        }
        case SDL_QUIT:
            plcui_sdl_pointer_push(g_sdl.last.x, g_sdl.last.y, false);
            SDL_HideWindow(g_sdl.window);
            break;
        case SDL_WINDOWEVENT:
            if (event.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
                plcui_sdl_pointer_push(g_sdl.last.x, g_sdl.last.y, false);
            } else if (event.window.event == SDL_WINDOWEVENT_EXPOSED) {
                SDL_RenderClear(g_sdl.renderer);
                SDL_RenderCopy(g_sdl.renderer, g_sdl.texture, NULL, NULL);
                SDL_RenderPresent(g_sdl.renderer);
            }
            break;
        default: break;
        }
    }
}

lv_display_t *plcui_platform_display(void)
{
    return g_sdl.display;
}

int plcui_platform_snapshot(const char *path)
{
    if (!g_sdl.initialized || !path || !path[0]) return -1;
    lv_refr_now(g_sdl.display);
    SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormatFrom(g_sdl.frame,
        g_sdl.width, g_sdl.height, 16, g_sdl.width * (int)sizeof(uint16_t), SDL_PIXELFORMAT_RGB565);
    if (!surface) return -1;
    int result = SDL_SaveBMP(surface, path);
    SDL_FreeSurface(surface);
    return result;
}

#endif
