#include "luat_pcsim_host.h"
#include "luat_log.h"
#include "SDL2/SDL.h"
#include "miniz.h"
#if defined(_WIN32)
#include <windows.h>
#include <SDL_syswm.h>
#endif
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define LUAT_LOG_TAG "pcsim"

static int s_pixel_perfect = 0;
static int s_headless = 0;
static uint64_t s_parent_hwnd = 0;
static int s_parent_off_x = 0;
static int s_parent_off_y = 0;
static int s_ctl_port = 0;
static int s_parent_ok = 1;
static int s_last_parent_x = 0x7fffffff;
static int s_last_parent_y = 0x7fffffff;
static int s_last_parent_w = -1;
static int s_last_parent_h = -1;

static SDL_Window *s_window = NULL;
static SDL_Renderer *s_renderer = NULL;
static SDL_Texture *s_texture = NULL;
static int s_native_w = 0;
static int s_native_h = 0;

static SDL_mutex *s_shot_mu = NULL;
static SDL_cond *s_shot_cv = NULL;

static uint8_t *s_frame_rgb565 = NULL;
static size_t s_frame_cap = 0;
static size_t s_frame_len = 0;
static uint32_t s_frame_seq = 0;
static uint32_t s_frame_last_ticks = 0;
static Uint32 s_synth_buttons = 0;

#define PCSIM_CLICK_HOLD_MS 20
#define PCSIM_CLICK_GAP_MS 60

void luat_pcsim_host_set_pixel_perfect(int enable)
{
    s_pixel_perfect = enable ? 1 : 0;
}

int luat_pcsim_host_pixel_perfect(void)
{
    return s_pixel_perfect;
}

void luat_pcsim_host_set_parent_hwnd(uint64_t hwnd)
{
    s_parent_hwnd = hwnd;
}

uint64_t luat_pcsim_host_parent_hwnd(void)
{
    return s_parent_hwnd;
}

void luat_pcsim_host_set_parent_offset(int x, int y)
{
    s_parent_off_x = x;
    s_parent_off_y = y;
}

void luat_pcsim_host_set_headless(int enable)
{
    s_headless = enable ? 1 : 0;
}

int luat_pcsim_host_headless(void)
{
    return s_headless;
}

int luat_pcsim_host_parse_agent_ctl(const char *addr)
{
    const char *colon;
    char host[64];
    size_t host_len;
    int port = 0;
    char *endptr = NULL;

    if (addr == NULL || addr[0] == 0) {
        LLOGE("empty --agent-ctl");
        return -1;
    }
    colon = strrchr(addr, ':');
    if (colon == NULL || colon == addr || colon[1] == 0) {
        LLOGE("invalid --agent-ctl: %s", addr);
        return -1;
    }
    host_len = (size_t)(colon - addr);
    if (host_len >= sizeof(host)) {
        LLOGE("invalid --agent-ctl host: %s", addr);
        return -1;
    }
    memcpy(host, addr, host_len);
    host[host_len] = 0;
    if (strcmp(host, "127.0.0.1") != 0 && strcmp(host, "localhost") != 0) {
        LLOGE("--agent-ctl must bind loopback, got %s", host);
        return -1;
    }
    port = (int)strtol(colon + 1, &endptr, 10);
    if (endptr == colon + 1 || *endptr != 0 || port < 1 || port > 65535) {
        LLOGE("invalid --agent-ctl port: %s", colon + 1);
        return -1;
    }
    s_ctl_port = port;
    return 0;
}

int luat_pcsim_host_agent_ctl_port(void)
{
    return s_ctl_port;
}

uint32_t luat_pcsim_host_window_flags(uint32_t base_flags)
{
    if (!s_pixel_perfect && s_parent_hwnd == 0 && !s_headless) {
        return base_flags;
    }
    base_flags &= ~(uint32_t)SDL_WINDOW_RESIZABLE;
    base_flags &= ~(uint32_t)SDL_WINDOW_ALLOW_HIGHDPI;
    if (s_parent_hwnd != 0 || s_headless) {
        base_flags &= ~(uint32_t)SDL_WINDOW_SHOWN;
        base_flags |= (uint32_t)SDL_WINDOW_HIDDEN;
    }
    return base_flags;
}

int luat_pcsim_host_force_native_size(void)
{
    return s_pixel_perfect || s_parent_hwnd != 0 || s_headless;
}

int luat_pcsim_host_parent_ok(void)
{
    return s_parent_ok;
}

#if defined(_WIN32)
static int overlay_rect(HWND parent, POINT *pt, int *out_w, int *out_h)
{
    RECT rc;
    int w;
    int h;
    if (parent == NULL || !IsWindow(parent) || !GetClientRect(parent, &rc) || pt == NULL || out_w == NULL || out_h == NULL) {
        return -1;
    }
    w = s_native_w > 0 ? s_native_w : (rc.right - rc.left - s_parent_off_x);
    h = s_native_h > 0 ? s_native_h : (rc.bottom - rc.top - s_parent_off_y);
    if (w <= 0 || h <= 0) {
        return -1;
    }
    pt->x = s_parent_off_x;
    pt->y = s_parent_off_y;
    if (!ClientToScreen(parent, pt)) {
        return -1;
    }
    *out_w = w;
    *out_h = h;
    return 0;
}

/* Chromium GPU 合成会盖住 WS_CHILD。SDL 做成宿主的 owned popup，按客户区偏移铺在舞台上。 */
static int place_over_parent(HWND child, HWND parent)
{
    POINT pt;
    int w;
    int h;
    LONG_PTR style;

    if (child == NULL || overlay_rect(parent, &pt, &w, &h) != 0) {
        return -1;
    }
    if (GetAncestor(child, GA_PARENT) != GetDesktopWindow()) {
        SetParent(child, NULL);
    }
    style = GetWindowLongPtrA(child, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_CHILD);
    style |= WS_POPUP | WS_VISIBLE;
    SetWindowLongPtrA(child, GWL_STYLE, style);
    SetWindowLongPtrA(child, GWL_EXSTYLE, WS_EX_TOOLWINDOW);
    SetWindowLongPtrA(child, GWLP_HWNDPARENT, (LONG_PTR)parent);
    SetWindowPos(child, HWND_TOP, pt.x, pt.y, w, h, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    s_last_parent_x = pt.x;
    s_last_parent_y = pt.y;
    s_last_parent_w = w;
    s_last_parent_h = h;
    return 0;
}
#endif

int luat_pcsim_host_apply_window(void *sdl_window)
{
#if defined(_WIN32)
    SDL_Window *window = (SDL_Window *)sdl_window;
    SDL_SysWMinfo info;
    HWND child;
    HWND parent;

    if (window != NULL && s_headless) {
        SDL_HideWindow(window);
        SDL_VERSION(&info.version);
        if (SDL_GetWindowWMInfo(window, &info) != SDL_FALSE && info.subsystem == SDL_SYSWM_WINDOWS && info.info.win.window) {
            ShowWindow(info.info.win.window, SW_HIDE);
            SetWindowLongPtrA(info.info.win.window, GWL_EXSTYLE, GetWindowLongPtrA(info.info.win.window, GWL_EXSTYLE) | WS_EX_TOOLWINDOW);
        }
        s_parent_ok = 1;
        return 0;
    }
    if (window == NULL || s_parent_hwnd == 0) {
        s_parent_ok = 1;
        return 0;
    }
    SDL_VERSION(&info.version);
    if (SDL_GetWindowWMInfo(window, &info) == SDL_FALSE || info.subsystem != SDL_SYSWM_WINDOWS) {
        LLOGE("SDL_GetWindowWMInfo failed: %s", SDL_GetError());
        s_parent_ok = 0;
        return -1;
    }
    child = info.info.win.window;
    parent = (HWND)(uintptr_t)s_parent_hwnd;
    if (child == NULL || parent == NULL || !IsWindow(parent)) {
        LLOGE("parent hwnd is invalid: %llu", (unsigned long long)s_parent_hwnd);
        s_parent_ok = 0;
        return -1;
    }
    if (place_over_parent(child, parent) != 0) {
        LLOGE("pcsim host failed to overlay parent hwnd");
        s_parent_ok = 0;
        return -1;
    }
    SDL_ShowWindow(window);
    s_parent_ok = 1;
    return 0;
#else
    if (sdl_window != NULL && s_headless) {
        SDL_HideWindow((SDL_Window *)sdl_window);
    }
    if (s_parent_hwnd != 0) {
        LLOGW("--parent-hwnd ignored on this platform");
    }
    s_parent_ok = 1;
    return 0;
#endif
}

int luat_pcsim_host_bind(void *sdl_window, void *sdl_renderer, void *sdl_texture, int native_w, int native_h)
{
    s_window = (SDL_Window *)sdl_window;
    s_renderer = (SDL_Renderer *)sdl_renderer;
    s_texture = (SDL_Texture *)sdl_texture;
    s_native_w = native_w;
    s_native_h = native_h;
    if (s_shot_mu == NULL) {
        s_shot_mu = SDL_CreateMutex();
        s_shot_cv = SDL_CreateCond();
    }
    if (s_window != NULL && luat_pcsim_host_apply_window(s_window) != 0) {
        LLOGW("pcsim host embed failed, keep top-level window");
        s_parent_ok = 0;
        if (!s_headless) {
            SDL_ShowWindow(s_window);
        }
    }
    LLOGI("pcsim host bind %dx%d pixel_perfect=%d headless=%d parent=%llu ctl=%d parent_ok=%d",
          native_w, native_h, s_pixel_perfect, s_headless, (unsigned long long)s_parent_hwnd, s_ctl_port, s_parent_ok);
    return 0;
}

void luat_pcsim_host_unbind(void)
{
    s_window = NULL;
    s_renderer = NULL;
    s_texture = NULL;
    s_native_w = 0;
    s_native_h = 0;
    s_synth_buttons = 0;
}

int luat_pcsim_host_ready(void)
{
    return s_renderer != NULL && s_texture != NULL && s_native_w > 0 && s_native_h > 0;
}

int luat_pcsim_host_native_width(void)
{
    return s_native_w;
}

int luat_pcsim_host_native_height(void)
{
    return s_native_h;
}

static int clamp_coord(int v, int maxv)
{
    if (maxv <= 0) {
        return 0;
    }
    if (v < 0) {
        return 0;
    }
    if (v > maxv - 1) {
        return maxv - 1;
    }
    return v;
}

static Uint32 map_button(const char *button)
{
    if (button != NULL && strcmp(button, "right") == 0) {
        return SDL_BUTTON_RIGHT;
    }
    if (button != NULL && strcmp(button, "middle") == 0) {
        return SDL_BUTTON_MIDDLE;
    }
    return SDL_BUTTON_LEFT;
}

static void push_motion(int x, int y)
{
    SDL_Event e;
    memset(&e, 0, sizeof(e));
    e.type = SDL_MOUSEMOTION;
    e.motion.windowID = s_window ? SDL_GetWindowID(s_window) : 0;
    e.motion.x = x;
    e.motion.y = y;
    e.motion.xrel = 0;
    e.motion.yrel = 0;
    e.motion.state = s_synth_buttons;
    SDL_PushEvent(&e);
}

static void push_button(int x, int y, Uint32 button, Uint8 state, int clicks)
{
    SDL_Event e;
    memset(&e, 0, sizeof(e));
    e.type = state == SDL_PRESSED ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
    e.button.windowID = s_window ? SDL_GetWindowID(s_window) : 0;
    e.button.button = (Uint8)button;
    e.button.state = state;
    e.button.clicks = (Uint8)(clicks > 0 ? clicks : 1);
    e.button.x = x;
    e.button.y = y;
    if (state == SDL_PRESSED) {
        s_synth_buttons |= SDL_BUTTON(button);
    } else {
        s_synth_buttons &= ~SDL_BUTTON(button);
    }
    SDL_PushEvent(&e);
}

static void click_n(int x, int y, Uint32 button, int n)
{
    int i;
    for (i = 0; i < n; i++) {
        if (i > 0) {
            SDL_Delay(PCSIM_CLICK_GAP_MS);
        }
        push_motion(x, y);
        push_button(x, y, button, SDL_PRESSED, i + 1);
        SDL_Delay(PCSIM_CLICK_HOLD_MS);
        push_button(x, y, button, SDL_RELEASED, i + 1);
    }
}

int luat_pcsim_host_inject_pointer(const char *type, int x, int y, const char *button, int from_x, int from_y, int dx, int dy)
{
    Uint32 btn;
    int w = s_native_w > 0 ? s_native_w : 1;
    int h = s_native_h > 0 ? s_native_h : 1;
    if (type == NULL) {
        return -1;
    }
    x = clamp_coord(x, w);
    y = clamp_coord(y, h);
    from_x = clamp_coord(from_x, w);
    from_y = clamp_coord(from_y, h);
    btn = map_button(button);

    if (strcmp(type, "move") == 0) {
        push_motion(x, y);
    } else if (strcmp(type, "down") == 0) {
        push_motion(x, y);
        push_button(x, y, btn, SDL_PRESSED, 1);
    } else if (strcmp(type, "up") == 0) {
        push_motion(x, y);
        push_button(x, y, btn, SDL_RELEASED, 1);
    } else if (strcmp(type, "click") == 0) {
        click_n(x, y, btn, 1);
    } else if (strcmp(type, "dblclick") == 0) {
        click_n(x, y, btn, 2);
    } else if (strcmp(type, "tripleclick") == 0) {
        click_n(x, y, btn, 3);
    } else if (strcmp(type, "drag") == 0) {
        push_motion(from_x, from_y);
        push_button(from_x, from_y, btn, SDL_PRESSED, 1);
        SDL_Delay(PCSIM_CLICK_HOLD_MS);
        push_motion(x, y);
        push_button(x, y, btn, SDL_RELEASED, 1);
    } else if (strcmp(type, "scroll") == 0 || strcmp(type, "hscroll") == 0) {
        SDL_Event e;
        memset(&e, 0, sizeof(e));
        e.type = SDL_MOUSEWHEEL;
        e.wheel.windowID = s_window ? SDL_GetWindowID(s_window) : 0;
        e.wheel.x = strcmp(type, "hscroll") == 0 ? dx : 0;
        e.wheel.y = strcmp(type, "hscroll") == 0 ? 0 : dy;
        e.wheel.direction = SDL_MOUSEWHEEL_NORMAL;
        push_motion(x, y);
        SDL_PushEvent(&e);
    } else {
        return -1;
    }
    return 0;
}

static SDL_Keycode map_key_name(const char *name)
{
    if (name == NULL || name[0] == 0) {
        return SDLK_UNKNOWN;
    }
    if (strcmp(name, "Return") == 0 || strcmp(name, "Enter") == 0) {
        return SDLK_RETURN;
    }
    if (strcmp(name, "Backspace") == 0) {
        return SDLK_BACKSPACE;
    }
    if (strcmp(name, "Escape") == 0) {
        return SDLK_ESCAPE;
    }
    if (strcmp(name, "Tab") == 0) {
        return SDLK_TAB;
    }
    if (strcmp(name, "Up") == 0) {
        return SDLK_UP;
    }
    if (strcmp(name, "Down") == 0) {
        return SDLK_DOWN;
    }
    if (strcmp(name, "Left") == 0) {
        return SDLK_LEFT;
    }
    if (strcmp(name, "Right") == 0) {
        return SDLK_RIGHT;
    }
    if (strcmp(name, "Left Ctrl") == 0 || strcmp(name, "Ctrl") == 0) {
        return SDLK_LCTRL;
    }
    if (strcmp(name, "Left Shift") == 0 || strcmp(name, "Shift") == 0) {
        return SDLK_LSHIFT;
    }
    if (strcmp(name, "Left Alt") == 0 || strcmp(name, "Alt") == 0) {
        return SDLK_LALT;
    }
    if (strlen(name) == 1) {
        return (SDL_Keycode)tolower((unsigned char)name[0]);
    }
    return SDL_GetKeyFromName(name);
}

static void push_key(SDL_Keycode key, Uint8 state)
{
    SDL_Event e;
    memset(&e, 0, sizeof(e));
    e.type = state == SDL_PRESSED ? SDL_KEYDOWN : SDL_KEYUP;
    e.key.windowID = s_window ? SDL_GetWindowID(s_window) : 0;
    e.key.state = state;
    e.key.repeat = 0;
    e.key.keysym.sym = key;
    e.key.keysym.scancode = SDL_GetScancodeFromKey(key);
    SDL_PushEvent(&e);
}

int luat_pcsim_host_inject_key(const char *type, const char **keys, int key_count, const char *text)
{
    int i;
    if (type == NULL) {
        return -1;
    }
    if (strcmp(type, "type") == 0) {
        SDL_Event e;
        if (text == NULL) {
            return -1;
        }
        memset(&e, 0, sizeof(e));
        e.type = SDL_TEXTINPUT;
        e.text.windowID = s_window ? SDL_GetWindowID(s_window) : 0;
        strncpy(e.text.text, text, sizeof(e.text.text) - 1);
        SDL_PushEvent(&e);
        return 0;
    }
    if (keys == NULL || key_count <= 0) {
        return -1;
    }
    if (strcmp(type, "key_down") == 0) {
        SDL_Keycode key = map_key_name(keys[0]);
        if (key == SDLK_UNKNOWN) {
            return -2;
        }
        push_key(key, SDL_PRESSED);
        return 0;
    }
    if (strcmp(type, "key_up") == 0) {
        SDL_Keycode key = map_key_name(keys[0]);
        if (key == SDLK_UNKNOWN) {
            return -2;
        }
        push_key(key, SDL_RELEASED);
        return 0;
    }
    if (strcmp(type, "key") == 0) {
        for (i = 0; i < key_count; i++) {
            SDL_Keycode key = map_key_name(keys[i]);
            if (key == SDLK_UNKNOWN) {
                return -2;
            }
            push_key(key, SDL_PRESSED);
        }
        for (i = key_count - 1; i >= 0; i--) {
            push_key(map_key_name(keys[i]), SDL_RELEASED);
        }
        return 0;
    }
    return -1;
}

typedef struct {
    uint8_t *buf;
    size_t size;
    size_t cap;
} pcsim_png_buf_t;

static mz_bool pcsim_png_putter(const void *pBuf, int len, void *pUser)
{
    pcsim_png_buf_t *ctx = (pcsim_png_buf_t *)pUser;
    size_t n;
    uint8_t *grown;
    if (len <= 0) {
        return MZ_TRUE;
    }
    n = (size_t)len;
    if (ctx->size + n > ctx->cap) {
        size_t ncap = ctx->cap ? ctx->cap : 4096;
        while (ncap < ctx->size + n) {
            ncap *= 2;
        }
        grown = (uint8_t *)realloc(ctx->buf, ncap);
        if (grown == NULL) {
            return MZ_FALSE;
        }
        ctx->buf = grown;
        ctx->cap = ncap;
    }
    memcpy(ctx->buf + ctx->size, pBuf, n);
    ctx->size += n;
    return MZ_TRUE;
}

static void pcsim_put_be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static size_t pcsim_png_append_chunk(uint8_t *dst, const char type[4], const uint8_t *data, size_t len)
{
    uint32_t crc;
    pcsim_put_be32(dst, (uint32_t)len);
    memcpy(dst + 4, type, 4);
    if (len > 0 && data != NULL) {
        memcpy(dst + 8, data, len);
    }
    crc = (uint32_t)mz_crc32(MZ_CRC32_INIT, dst + 4, 4 + len);
    pcsim_put_be32(dst + 8 + len, crc);
    return 12 + len;
}

/*
 * LuatOS 定义了 MINIZ_NO_MALLOC，tdefl_write_image_to_png_file_in_memory 内部 MZ_MALLOC 恒为 NULL。
 * 必须自己 malloc 压缩器，走 tdefl 低层 API。调用方用 free() 释放 *out_png。
 */
static int encode_png_from_rgb565(const uint8_t *rgb565, int width, int height, uint8_t **out_png, size_t *out_len)
{
    static const uint8_t png_sig[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };
    size_t npx;
    size_t bpl;
    size_t raw_len;
    size_t i;
    size_t y;
    size_t png_len;
    size_t off;
    int flags;
    uint8_t ihdr[13];
    uint8_t *rgb = NULL;
    uint8_t *filtered = NULL;
    tdefl_compressor *comp = NULL;
    pcsim_png_buf_t zbuf;
    memset(&zbuf, 0, sizeof(zbuf));

    if (rgb565 == NULL || width <= 0 || height <= 0 || out_png == NULL || out_len == NULL) {
        return -1;
    }
    npx = (size_t)width * (size_t)height;
    bpl = (size_t)width * 3;
    raw_len = (size_t)height * (1 + bpl);
    rgb = (uint8_t *)malloc(npx * 3);
    filtered = (uint8_t *)malloc(raw_len);
    if (rgb == NULL || filtered == NULL) {
        free(rgb);
        free(filtered);
        return -1;
    }
    for (i = 0; i < npx; i++) {
        uint16_t packed = (uint16_t)(rgb565[i * 2] | ((uint16_t)rgb565[i * 2 + 1] << 8));
        uint8_t r5 = (uint8_t)((packed >> 11) & 0x1f);
        uint8_t g6 = (uint8_t)((packed >> 5) & 0x3f);
        uint8_t b5 = (uint8_t)(packed & 0x1f);
        rgb[i * 3 + 0] = (uint8_t)((r5 << 3) | (r5 >> 2));
        rgb[i * 3 + 1] = (uint8_t)((g6 << 2) | (g6 >> 4));
        rgb[i * 3 + 2] = (uint8_t)((b5 << 3) | (b5 >> 2));
    }
    for (y = 0; y < (size_t)height; y++) {
        filtered[y * (1 + bpl)] = 0;
        memcpy(filtered + y * (1 + bpl) + 1, rgb + y * bpl, bpl);
    }
    free(rgb);
    rgb = NULL;

    comp = (tdefl_compressor *)malloc(sizeof(tdefl_compressor));
    if (comp == NULL) {
        free(filtered);
        return -1;
    }
    flags = 128 | 0x01000; /* TDEFL_DEFAULT_MAX_PROBES | TDEFL_WRITE_ZLIB_HEADER */
    if (tdefl_init(comp, pcsim_png_putter, &zbuf, flags) != TDEFL_STATUS_OKAY ||
        tdefl_compress_buffer(comp, filtered, raw_len, TDEFL_FINISH) != TDEFL_STATUS_DONE ||
        zbuf.size == 0) {
        LLOGW("screenshot: tdefl compress failed");
        free(comp);
        free(filtered);
        free(zbuf.buf);
        return -1;
    }
    free(comp);
    free(filtered);

    png_len = 8 + 25 + 12 + zbuf.size + 12;
    *out_png = (uint8_t *)malloc(png_len);
    if (*out_png == NULL) {
        free(zbuf.buf);
        return -1;
    }
    memcpy(*out_png, png_sig, 8);
    memset(ihdr, 0, sizeof(ihdr));
    pcsim_put_be32(ihdr, (uint32_t)width);
    pcsim_put_be32(ihdr + 4, (uint32_t)height);
    ihdr[8] = 8;
    ihdr[9] = 2;
    off = 8;
    off += pcsim_png_append_chunk(*out_png + off, "IHDR", ihdr, sizeof(ihdr));
    off += pcsim_png_append_chunk(*out_png + off, "IDAT", zbuf.buf, zbuf.size);
    off += pcsim_png_append_chunk(*out_png + off, "IEND", NULL, 0);
    free(zbuf.buf);
    if (off != png_len) {
        free(*out_png);
        *out_png = NULL;
        return -1;
    }
    *out_len = png_len;
    return 0;
}

static void luat_pcsim_host_sync_parent_size(void)
{
#if defined(_WIN32)
    SDL_SysWMinfo info;
    HWND child;
    HWND parent;
    POINT pt;
    int w;
    int h;
    if (s_window == NULL || s_parent_hwnd == 0 || !s_parent_ok) {
        return;
    }
    parent = (HWND)(uintptr_t)s_parent_hwnd;
    if (overlay_rect(parent, &pt, &w, &h) != 0) {
        return;
    }
    if (pt.x == s_last_parent_x && pt.y == s_last_parent_y && w == s_last_parent_w && h == s_last_parent_h) {
        return;
    }
    SDL_VERSION(&info.version);
    if (SDL_GetWindowWMInfo(s_window, &info) == SDL_FALSE || info.subsystem != SDL_SYSWM_WINDOWS) {
        return;
    }
    child = info.info.win.window;
    if (child == NULL) {
        return;
    }
    SetWindowPos(child, HWND_TOP, pt.x, pt.y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    s_last_parent_x = pt.x;
    s_last_parent_y = pt.y;
    s_last_parent_w = w;
    s_last_parent_h = h;
#endif
}

static void capture_rgb565_on_video_thread(void)
{
    int width = s_native_w;
    int height = s_native_h;
    size_t raw_size;
    size_t dst_len;
    uint8_t *raw;
    int x;
    int y;
    int changed = 0;

    if (s_renderer == NULL || s_texture == NULL || width <= 0 || height <= 0) {
        return;
    }
    dst_len = (size_t)width * (size_t)height * 2;
    if (s_frame_rgb565 == NULL || s_frame_cap < dst_len) {
        free(s_frame_rgb565);
        s_frame_rgb565 = (uint8_t *)malloc(dst_len);
        s_frame_cap = s_frame_rgb565 ? dst_len : 0;
        s_frame_len = 0;
        if (s_frame_rgb565 == NULL) {
            return;
        }
    }
    raw_size = (size_t)width * (size_t)height * 4;
    raw = (uint8_t *)malloc(raw_size);
    if (raw == NULL) {
        return;
    }
    SDL_RenderClear(s_renderer);
    SDL_RenderCopy(s_renderer, s_texture, NULL, NULL);
    if (SDL_RenderReadPixels(s_renderer, NULL, SDL_PIXELFORMAT_ARGB8888, raw, width * 4) != 0) {
        free(raw);
        SDL_RenderPresent(s_renderer);
        return;
    }
    SDL_RenderPresent(s_renderer);
    for (y = 0; y < height; y++) {
        for (x = 0; x < width; x++) {
            uint8_t *px = raw + ((size_t)y * (size_t)width + (size_t)x) * 4;
            uint16_t packed = (uint16_t)(((px[2] >> 3) << 11) | ((px[1] >> 2) << 5) | (px[0] >> 3));
            size_t off = ((size_t)y * (size_t)width + (size_t)x) * 2;
            uint16_t old = 0;
            if (s_frame_len == dst_len) {
                old = (uint16_t)(s_frame_rgb565[off] | ((uint16_t)s_frame_rgb565[off + 1] << 8));
            }
            s_frame_rgb565[off] = (uint8_t)(packed & 0xff);
            s_frame_rgb565[off + 1] = (uint8_t)(packed >> 8);
            if (old != packed) {
                changed = 1;
            }
        }
    }
    free(raw);
    s_frame_len = dst_len;
    if (changed || s_frame_seq == 0) {
        s_frame_seq++;
        if (s_frame_seq == 0) {
            s_frame_seq = 1;
        }
    }
}

void luat_pcsim_host_poll(void)
{
    uint32_t now;
    if (s_headless && s_window != NULL) {
        SDL_HideWindow(s_window);
    } else {
        luat_pcsim_host_sync_parent_size();
    }
    if (s_shot_mu == NULL) {
        return;
    }
    SDL_LockMutex(s_shot_mu);
    now = SDL_GetTicks();
    if (s_ctl_port > 0 && s_renderer != NULL && (s_frame_last_ticks == 0 || now - s_frame_last_ticks >= 66)) {
        capture_rgb565_on_video_thread();
        s_frame_last_ticks = now;
        if (s_frame_len > 0) {
            SDL_CondSignal(s_shot_cv);
        }
    }
    SDL_UnlockMutex(s_shot_mu);
}

int luat_pcsim_host_copy_frame(uint32_t min_seq, uint8_t *out, size_t cap, uint32_t *seq, int *w, int *h, uint8_t *format, uint16_t *stride)
{
    if (out == NULL || seq == NULL || w == NULL || h == NULL || format == NULL || stride == NULL) {
        return -1;
    }
    if (s_shot_mu == NULL) {
        return -1;
    }
    SDL_LockMutex(s_shot_mu);
    if (s_frame_rgb565 == NULL || s_frame_len == 0 || s_frame_seq <= min_seq) {
        SDL_UnlockMutex(s_shot_mu);
        return 1;
    }
    if (cap < s_frame_len) {
        SDL_UnlockMutex(s_shot_mu);
        return -1;
    }
    memcpy(out, s_frame_rgb565, s_frame_len);
    *seq = s_frame_seq;
    *w = s_native_w;
    *h = s_native_h;
    *format = 1;
    *stride = (uint16_t)(s_native_w * 2);
    SDL_UnlockMutex(s_shot_mu);
    return 0;
}

int luat_pcsim_host_screenshot_png(uint8_t **out_png, size_t *out_len, int *out_w, int *out_h)
{
    uint8_t *copy = NULL;
    size_t copy_len = 0;
    size_t expect;
    int w = 0;
    int h = 0;
    int rc;
    uint32_t start;
    SDL_Event wake;

    if (out_png == NULL || out_len == NULL) {
        return -1;
    }
    *out_png = NULL;
    *out_len = 0;
    if (s_shot_mu == NULL) {
        return -1;
    }

    SDL_LockMutex(s_shot_mu);
    if (s_frame_rgb565 == NULL || s_frame_len == 0) {
        memset(&wake, 0, sizeof(wake));
        wake.type = SDL_USEREVENT;
        SDL_PushEvent(&wake);
        start = SDL_GetTicks();
        while (s_frame_rgb565 == NULL || s_frame_len == 0) {
            uint32_t elapsed = SDL_GetTicks() - start;
            if (elapsed >= 2000) {
                SDL_UnlockMutex(s_shot_mu);
                LLOGW("screenshot: no rgb565 frame yet");
                return -2;
            }
            if (SDL_CondWaitTimeout(s_shot_cv, s_shot_mu, (Uint32)(2000 - elapsed)) != 0) {
                SDL_UnlockMutex(s_shot_mu);
                LLOGW("screenshot: wait for rgb565 timed out");
                return -2;
            }
        }
    }
    w = s_native_w;
    h = s_native_h;
    copy_len = s_frame_len;
    expect = (size_t)w * (size_t)h * 2;
    if (w <= 0 || h <= 0 || copy_len != expect) {
        SDL_UnlockMutex(s_shot_mu);
        LLOGW("screenshot: bad frame size %dx%d len=%u", w, h, (unsigned)copy_len);
        return -1;
    }
    copy = (uint8_t *)malloc(copy_len);
    if (copy == NULL) {
        SDL_UnlockMutex(s_shot_mu);
        return -1;
    }
    memcpy(copy, s_frame_rgb565, copy_len);
    SDL_UnlockMutex(s_shot_mu);

    rc = encode_png_from_rgb565(copy, w, h, out_png, out_len);
    free(copy);
    if (rc != 0) {
        LLOGW("screenshot: png encode failed");
        return -3;
    }
    if (out_w) {
        *out_w = w;
    }
    if (out_h) {
        *out_h = h;
    }
    return 0;
}
