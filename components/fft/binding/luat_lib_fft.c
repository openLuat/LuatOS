#include "luat_base.h"
#include "luat_mem.h"

#include <math.h>
#include <string.h>

#include "fft_core.h"

#define LUAT_LOG_TAG "fft"
#include "luat_log.h"

#include "luat_conf_bsp.h"
#include "rotable2.h"
#include "luat_zbuff.h"

// helper: read float array from lua table (1-based)
static int read_lua_array_float(lua_State* L, int idx, float* out, int n) {
    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, idx, i+1);
        if (!lua_isnumber(L, -1)) { lua_pop(L, 1); return -1; }
        out[i] = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    return 0;
}

// helper: write float array into lua table (1-based)
static void write_lua_array_float(lua_State* L, float* a, int n) {
    lua_createtable(L, n, 0);
    for (int i = 0; i < n; i++) {
        lua_pushnumber(L, a[i]);
        lua_rawseti(L, -2, i+1);
    }
}

static int l_fft_generate_twiddles(lua_State* L) {
    int N = luaL_checkinteger(L, 1);
    if (N <= 1 || (N & (N-1))) return luaL_error(L, "N must be power of 2");
    int half = N/2;
    float* Wc = luat_heap_malloc(sizeof(float)*half);
    float* Ws = luat_heap_malloc(sizeof(float)*half);
    if (!Wc || !Ws) {
        if (Wc) luat_heap_free(Wc);
        if (Ws) luat_heap_free(Ws);
        return luaL_error(L, "no memory");
    }
    fft_generate_twiddles(N, Wc, Ws);
    write_lua_array_float(L, Wc, half);
    write_lua_array_float(L, Ws, half);
    luat_heap_free(Wc);
    luat_heap_free(Ws);
    return 2;
}

static int l_fft_run(lua_State* L) {
    int N = luaL_checkinteger(L, 3);
    if (N <= 1 || (N & (N-1))) return luaL_error(L, "N must be power of 2");

    float *r = NULL, *im = NULL, *Wc = NULL, *Ws = NULL;
    int r_free = 0, im_free = 0, wc_free = 0, ws_free = 0;

    // real
    luat_zbuff_t* zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) { r = (float*)zb->addr; }
    else { r = luat_heap_malloc(sizeof(float)*N); r_free = 1; if (!r) return luaL_error(L, "no memory"); if (read_lua_array_float(L, 1, r, N)) { if (r_free) luat_heap_free(r); return luaL_error(L, "real must be number array or zbuff"); } }
    // imag
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) { im = (float*)zb->addr; }
    else { im = luat_heap_malloc(sizeof(float)*N); im_free = 1; if (!im) { if (r_free) luat_heap_free(r); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 2, im, N)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); return luaL_error(L, "imag must be number array or zbuff"); } }
    // W_real
    zb = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
    if (zb) { Wc = (float*)zb->addr; }
    else { Wc = luat_heap_malloc(sizeof(float)*(N/2)); wc_free = 1; if (!Wc) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 4, Wc, N/2)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); if (wc_free) luat_heap_free(Wc); return luaL_error(L, "W_real must be number array or zbuff"); } }
    // W_imag
    zb = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
    if (zb) { Ws = (float*)zb->addr; }
    else { Ws = luat_heap_malloc(sizeof(float)*(N/2)); ws_free = 1; if (!Ws) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); if (wc_free) luat_heap_free(Wc); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 5, Ws, N/2)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); if (wc_free) luat_heap_free(Wc); if (ws_free) luat_heap_free(Ws); return luaL_error(L, "W_imag must be number array or zbuff"); } }

    fft_run_inplace(r, im, N, Wc, Ws);

    // if input was table, write back
    if (!luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) { lua_settop(L, 2); for (int i = 0; i < N; i++) { lua_pushnumber(L, r[i]); lua_rawseti(L, 1, i+1); } }
    if (!luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) { for (int i = 0; i < N; i++) { lua_pushnumber(L, im[i]); lua_rawseti(L, 2, i+1); } }

    if (r_free) luat_heap_free(r);
    if (im_free) luat_heap_free(im);
    if (wc_free) luat_heap_free(Wc);
    if (ws_free) luat_heap_free(Ws);
    return 0;
}

static int l_fft_ifft(lua_State* L) {
    int N = luaL_checkinteger(L, 3);
    if (N <= 1 || (N & (N-1))) return luaL_error(L, "N must be power of 2");

    float *r = NULL, *im = NULL, *Wc = NULL, *Ws = NULL;
    int r_free = 0, im_free = 0, wc_free = 0, ws_free = 0;
    luat_zbuff_t* zb = NULL;
    zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) { r = (float*)zb->addr; } else { r = luat_heap_malloc(sizeof(float)*N); r_free = 1; if (!r) return luaL_error(L, "no memory"); if (read_lua_array_float(L, 1, r, N)) { if (r_free) luat_heap_free(r); return luaL_error(L, "real must be number array or zbuff"); } }
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) { im = (float*)zb->addr; } else { im = luat_heap_malloc(sizeof(float)*N); im_free = 1; if (!im) { if (r_free) luat_heap_free(r); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 2, im, N)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); return luaL_error(L, "imag must be number array or zbuff"); } }
    zb = (luat_zbuff_t*)luaL_testudata(L, 4, LUAT_ZBUFF_TYPE);
    if (zb) { Wc = (float*)zb->addr; } else { Wc = luat_heap_malloc(sizeof(float)*(N/2)); wc_free = 1; if (!Wc) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 4, Wc, N/2)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); if (wc_free) luat_heap_free(Wc); return luaL_error(L, "W_real must be number array or zbuff"); } }
    zb = (luat_zbuff_t*)luaL_testudata(L, 5, LUAT_ZBUFF_TYPE);
    if (zb) { Ws = (float*)zb->addr; } else { Ws = luat_heap_malloc(sizeof(float)*(N/2)); ws_free = 1; if (!Ws) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); if (wc_free) luat_heap_free(Wc); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 5, Ws, N/2)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); if (wc_free) luat_heap_free(Wc); if (ws_free) luat_heap_free(Ws); return luaL_error(L, "W_imag must be number array or zbuff"); } }

    ifft_run_inplace(r, im, N, Wc, Ws);

    if (!luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) { lua_settop(L, 2); for (int i = 0; i < N; i++) { lua_pushnumber(L, r[i]); lua_rawseti(L, 1, i+1); } }
    if (!luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) { for (int i = 0; i < N; i++) { lua_pushnumber(L, im[i]); lua_rawseti(L, 2, i+1); } }

    if (r_free) luat_heap_free(r);
    if (im_free) luat_heap_free(im);
    if (wc_free) luat_heap_free(Wc);
    if (ws_free) luat_heap_free(Ws);
    return 0;
}

static int l_fft_integral(lua_State* L) {
    int n = luaL_checkinteger(L, 3);
    float df = (float)luaL_checknumber(L, 4);
    if (n <= 1 || (n & (n-1))) return luaL_error(L, "n must be power of 2");
    float *r = NULL, *im = NULL; int r_free = 0, im_free = 0;
    luat_zbuff_t* zb = NULL;
    zb = (luat_zbuff_t*)luaL_testudata(L, 1, LUAT_ZBUFF_TYPE);
    if (zb) { r = (float*)zb->addr; } else { r = luat_heap_malloc(sizeof(float)*n); r_free = 1; if (!r) return luaL_error(L, "no memory"); if (read_lua_array_float(L, 1, r, n)) { if (r_free) luat_heap_free(r); return luaL_error(L, "real must be number array or zbuff"); } }
    zb = (luat_zbuff_t*)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    if (zb) { im = (float*)zb->addr; } else { im = luat_heap_malloc(sizeof(float)*n); im_free = 1; if (!im) { if (r_free) luat_heap_free(r); return luaL_error(L, "no memory"); } if (read_lua_array_float(L, 2, im, n)) { if (r_free) luat_heap_free(r); if (im_free) luat_heap_free(im); return luaL_error(L, "imag must be number array or zbuff"); } }
    fft_integral_inplace(r, im, n, df);
    if (!luaL_testudata(L, 1, LUAT_ZBUFF_TYPE)) { lua_settop(L, 2); for (int i = 0; i < n; i++) { lua_pushnumber(L, r[i]); lua_rawseti(L, 1, i+1); } }
    if (!luaL_testudata(L, 2, LUAT_ZBUFF_TYPE)) { for (int i = 0; i < n; i++) { lua_pushnumber(L, im[i]); lua_rawseti(L, 2, i+1); } }
    if (r_free) luat_heap_free(r);
    if (im_free) luat_heap_free(im);
    return 0;
}

static const rotable_Reg_t reg_fft[] = {
    {"generate_twiddles", ROREG_FUNC(l_fft_generate_twiddles)},
    {"run",               ROREG_FUNC(l_fft_run)},
    {"ifft",              ROREG_FUNC(l_fft_ifft)},
    {"fft_integral",      ROREG_FUNC(l_fft_integral)},
    {NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_fft(lua_State *L) {
    luat_newlib2(L, reg_fft);
    return 1;
}


