// AI-MANAGED: true
// 编译真实l_uart_rx函数；仅替代Lua栈和zbuff外部依赖。
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint8_t* addr; size_t len, used; } luat_zbuff_t;
typedef struct { luat_zbuff_t buff; int userdata, pushed; } lua_State;
static int peek_result, read_result, resize_failure, peek_calls, read_calls, resize_calls, logged;
#define LUAT_ZBUFF_TYPE "zbuff"
#define LLOGE(...) ((void)++logged)
static int luaL_checkinteger(lua_State* L, int idx) { (void)L; (void)idx; return 12; }
static int lua_isuserdata(lua_State* L, int idx) { (void)idx; return L->userdata; }
static void* luaL_checkudata(lua_State* L, int idx, const char* type) {
    (void)idx; (void)type; return &L->buff;
}
static void lua_pushinteger(lua_State* L, int value) { L->pushed = value; }
static int luat_uart_dispatch_rx_size(uint8_t id) { (void)id; peek_calls++; return peek_result; }
static int luat_uart_dispatch_read(uint8_t id, void* ptr, size_t length) {
    (void)id; read_calls++;
    if (read_result > 0 && (size_t)read_result <= length) memset(ptr, 0x5a, (size_t)read_result);
    return read_result;
}
static int __zbuff_resize(luat_zbuff_t* b, uint32_t n) {
    resize_calls++;
    if (resize_failure) return -1;
    assert(n < 1024);
    void* p = realloc(b->addr, n);
    assert(p != NULL); b->addr = p; b->len = n;
    return 0;
}

/* SOURCE_UNDER_TEST */

static lua_State make_state(size_t length, size_t used) {
    lua_State L = {.buff = {.addr = malloc(64), .len = length, .used = used}, .userdata = 1, .pushed = -99};
    assert(L.buff.addr != NULL); memset(L.buff.addr, 0xa5, 64);
    peek_calls = read_calls = resize_calls = resize_failure = 0;
    return L;
}
static void test_short_read(void) {
    lua_State L = make_state(16, 4);
    peek_result = 5; read_result = 2;
    assert(l_uart_rx(&L) == 1);
#ifdef TEST_BASELINE
    assert(L.pushed == 5 && L.buff.used == 9);
    assert(L.buff.addr[6] == 0xa5);
    puts("DEFECT_REPRODUCED: peek=5 actual=2 reported=5 used_includes_stale_tail=1");
#else
    assert(L.pushed == 2 && L.buff.used == 6);
    assert(L.buff.addr[3] == 0xa5 && L.buff.addr[4] == 0x5a && L.buff.addr[6] == 0xa5);
    puts("actual_short_read_preserves_prefix_and_tail: PASS");
#endif
    free(L.buff.addr);
}
#ifndef TEST_BASELINE
static void test_empty_or_negative_peek(void) {
    int values[] = {0, -103};
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        lua_State L = make_state(16, 4);
        peek_result = values[i]; read_result = 0;
        assert(l_uart_rx(&L) == 1 && L.pushed == 0 && L.buff.used == 4);
        assert(read_calls == 0 && resize_calls == 0); free(L.buff.addr);
    }
}
static void test_zero_negative_or_invalid_read(void) {
    int values[] = {0, -103, 6};
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        lua_State L = make_state(16, 4);
        peek_result = 5; read_result = values[i];
        assert(l_uart_rx(&L) == 1 && L.pushed == 0 && L.buff.used == 4);
        assert(read_calls == 1); free(L.buff.addr);
    }
}
static void test_resize_success_and_failure(void) {
    lua_State L = make_state(8, 8);
    peek_result = 5; read_result = 5;
    assert(l_uart_rx(&L) == 1 && L.pushed == 5 && L.buff.used == 13);
    assert(L.buff.len == 13 && resize_calls == 1 && read_calls == 1);
    for (size_t i = 0; i < 8; i++) assert(L.buff.addr[i] == 0xa5);
    free(L.buff.addr);
    L = make_state(8, 8); resize_failure = 1;
    assert(l_uart_rx(&L) == 1 && L.pushed == 0 && L.buff.used == 8 && L.buff.len == 8);
    assert(resize_calls == 1 && read_calls == 0); free(L.buff.addr);
}
static void test_capacity_and_userdata(void) {
    lua_State L = make_state(UINT32_MAX, UINT32_MAX);
    peek_result = 1; read_result = 1;
    assert(l_uart_rx(&L) == 1 && L.pushed == 0 && L.buff.used == UINT32_MAX);
    assert(read_calls == 0 && resize_calls == 0); free(L.buff.addr);
    L = make_state(8, 9);
    assert(l_uart_rx(&L) == 1 && L.pushed == 0 && L.buff.used == 9 && peek_calls == 0);
    free(L.buff.addr);
    L = make_state(8, 4); L.userdata = 0;
    assert(l_uart_rx(&L) == 1 && L.pushed == 0 && peek_calls == 0); free(L.buff.addr);
}
#endif
int main(void) {
    test_short_read();
#ifndef TEST_BASELINE
    test_empty_or_negative_peek(); test_zero_negative_or_invalid_read();
    test_resize_success_and_failure(); test_capacity_and_userdata();
#endif
    printf("lua_rx_suite_complete logged=%d\n", logged);
    return 0;
}
