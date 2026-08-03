#include "luat_base.h"
#include <string.h>
#include <stdio.h>

#include "luat_malloc.h"

#define LUAT_LOG_TAG "http_utest"
#include "luat_log.h"

#ifdef LUAT_BSP_PC
#include "luat_pc_http_utest.h"
#endif

static int finish_http_utest(lua_State *L, int status, lua_KContext ctx) {
    (void)ctx;
    if (status != LUA_OK && status != LUA_YIELD) {
        if (lua_isstring(L, -1)) {
            LLOGE("%s", lua_tostring(L, -1));
        }
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, lua_toboolean(L, -1));
    return 1;
}

/* Run a Lua chunk that takes `nargs` pre-pushed stack arguments. */
static int run_http_utest_code_nargs(lua_State *L, const char *code, int nargs) {
    int first_arg = lua_gettop(L) - nargs + 1;
    int status;

    if (luaL_loadstring(L, code) != LUA_OK) {
        if (lua_isstring(L, -1)) {
            LLOGE("%s", lua_tostring(L, -1));
        }
        lua_pop(L, 1 + nargs);
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_insert(L, first_arg);
    status = lua_pcallk(L, nargs, 1, 0, 0, finish_http_utest);
    return finish_http_utest(L, status, 0);
}

#ifdef LUAT_BSP_PC
/* Read a small file into a heap-allocated, NUL-terminated buffer. */
static char *read_pem_file(const char *rel_path, size_t *out_len) {
    FILE *fp = fopen(rel_path, "rb");
    char *buf = NULL;
    long n;
    size_t got;

    if (out_len) *out_len = 0;
    if (!fp) {
        LLOGE("fopen %s failed", rel_path);
        return NULL;
    }
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return NULL; }
    n = ftell(fp);
    if (n < 0) { fclose(fp); return NULL; }
    rewind(fp);
    buf = (char *)luat_heap_malloc((size_t)n + 1);
    if (!buf) { fclose(fp); return NULL; }
    got = fread(buf, 1, (size_t)n, fp);
    fclose(fp);
    if (got != (size_t)n) { luat_heap_free(buf); return NULL; }
    buf[n] = '\0';
    if (out_len) *out_len = (size_t)n + 1;
    return buf;
}

#define HTTP_CERTS_DIR "../../testcase/utest/net/dtls_basic/certs"

/* ─── Parameterized Lua chunk for local HTTP/HTTPS tests ──────────────────────
 * Stack args: port (int), scenario (string), ca_pem (string or nil)
 */
static const char *http_local_lua_chunk =
    "local port, scenario, ca_pem = ... "
    "local scheme = ca_pem and 'https' or 'http' "
    "local base = scheme .. '://127.0.0.1:' .. tostring(port) "
    "local method, path, hdrs, req_body, timeout, expect_code, expect_substr = 'GET', '/', nil, nil, 15000, 200, nil "
    "if scenario == 'get' then "
    "  path = '/' "
    "  expect_substr = 'OK' "
    "elseif scenario == 'get_json' then "
    "  path = '/get' "
    "  expect_substr = 'ok' "
    "elseif scenario == 'post_echo' then "
    "  method, path = 'POST', '/post' "
    "  hdrs = {['Content-Type']='application/json'} "
    "  req_body = '{\"hello\":\"world\"}' "
    "  expect_substr = 'ok' "
    "elseif scenario == 'status_404' then "
    "  path = '/status/404' "
    "  expect_code = 404 "
    "elseif scenario == 'status_500' then "
    "  path = '/status/500' "
    "  expect_code = 500 "
    "elseif scenario == 'status_301' then "
    "  path = '/status/301' "
    "  expect_code = 301 "
    "elseif scenario == 'large_body' then "
    "  path = '/bytes/65536' "
    "  timeout = 30000 "
    "elseif scenario == 'headers' then "
    "  path = '/headers' "
    "  hdrs = {['X-Test-Header']='luatos-utest'} "
    "  expect_substr = 'X-Test-Header' "
    "elseif scenario == 'timeout' then "
    "  path = '/slow' "
    "  timeout = 1500 "
    "  expect_code = -8 "
    "elseif scenario == 'server_drop' then "
    "  path = '/drop' "
    "  timeout = 10000 "
    "  expect_code = -5 "
    "elseif scenario == 'malformed' then "
    "  path = '/malformed' "
    "  timeout = 10000 "
    "  expect_code = -2 "
    "elseif scenario == 'connect_refused' then "
    "  base = scheme .. '://127.0.0.1:1' "
    "  path = '/' "
    "  timeout = 5000 "
    "  expect_code = -4 "
    "else "
    "  error('unknown scenario: ' .. tostring(scenario)) "
    "end "
    "local opts = {timeout = timeout} "
    "local code, headers, body = http.request(method, base .. path, hdrs, req_body, opts, ca_pem).wait() "
    "if expect_code < 0 then "
    "  assert(type(code) == 'number' and code < 0, scenario .. ': expected negative error, got ' .. tostring(code)) "
    "  if expect_code == -8 then "
    "    assert(code == -8 or code == -5 or code == -6, scenario .. ': expected timeout/close error, got ' .. tostring(code)) "
    "  elseif expect_code == -5 then "
    "    assert(code == -5 or code == -6, scenario .. ': expected close/rx error, got ' .. tostring(code)) "
    "  elseif expect_code == -2 then "
    "    assert(code == -2 or code == -5 or code == -6, scenario .. ': expected header/close error, got ' .. tostring(code)) "
    "  elseif expect_code == -4 then "
    "    assert(code < 0, scenario .. ': expected connect error, got ' .. tostring(code)) "
    "  end "
    "else "
    "  assert(code == expect_code, scenario .. ': expected ' .. expect_code .. ', got ' .. tostring(code)) "
    "end "
    "if expect_substr and type(body) == 'string' then "
    "  assert(body:find(expect_substr, 1, true), scenario .. ': body missing ' .. expect_substr) "
    "end "
    "if scenario == 'large_body' then "
    "  assert(type(body) == 'string' and #body == 65536, 'large_body: expected 65536 bytes, got ' .. tostring(body and #body or 'nil')) "
    "end "
    "return true";

/* ─── Concurrent test chunk ───────────────────────────────────────────────────
 * Stack args: port (int), ca_pem (string or nil)
 */
static const char *http_local_concurrent_lua_chunk =
    "local port, ca_pem = ... "
    "local scheme = ca_pem and 'https' or 'http' "
    "local base = scheme .. '://127.0.0.1:' .. tostring(port) "
    "local N = 8 "
    "local results = {} "
    "local done_count = 0 "
    "for i = 1, N do "
    "  sys.taskInit(function() "
    "    local code = http.request('GET', base .. '/get', nil, nil, {timeout=15000}, ca_pem).wait() "
    "    results[i] = code "
    "    done_count = done_count + 1 "
    "  end) "
    "end "
    "for _ = 1, 300 do "
    "  if done_count >= N then break end "
    "  sys.wait(100) "
    "end "
    "assert(done_count >= N, 'concurrent: only ' .. done_count .. '/' .. N .. ' done') "
    "local ok_count = 0 "
    "for i = 1, N do "
    "  if results[i] == 200 then ok_count = ok_count + 1 end "
    "end "
    "assert(ok_count >= N - 1, 'concurrent: only ' .. ok_count .. '/' .. N .. ' got 200') "
    "return true";

/* ─── Stress loop + memleak detection chunk ───────────────────────────────────
 * Stack args: port (int), ca_pem (string or nil), iterations (int)
 */
static const char *http_local_stress_lua_chunk =
    "local port, ca_pem, iterations = ... "
    "local scheme = ca_pem and 'https' or 'http' "
    "local base = scheme .. '://127.0.0.1:' .. tostring(port) "
    "sys.wait(200) "
    "local mem_before = rtos.meminfo() "
    "for i = 1, iterations do "
    "  local code, headers, body = http.request('GET', base .. '/get', nil, nil, {timeout=15000}, ca_pem).wait() "
    "  assert(code == 200, 'stress iter ' .. i .. ': got ' .. tostring(code)) "
    "  sys.wait(50) "
    "end "
    "sys.wait(500) "
    "local mem_after = rtos.meminfo() "
    "local diff = mem_before - mem_after "
    "assert(diff < 8192, 'memleak: lost ' .. diff .. ' bytes over ' .. iterations .. ' iterations') "
    "return true";

/* ─── HTTPS cert mismatch chunk ───────────────────────────────────────────────
 * Stack args: port (int), wrong_ca_pem (string)
 */
static const char *https_local_cert_mismatch_lua_chunk =
    "local port, wrong_ca_pem = ... "
    "local base = 'https://127.0.0.1:' .. tostring(port) "
    "local code = http.request('GET', base .. '/', nil, nil, {timeout=15000}, wrong_ca_pem).wait() "
    "assert(type(code) == 'number' and code < 0, 'cert_mismatch: expected negative error, got ' .. tostring(code)) "
    "return true";

/* ─── Orchestration: start server, run chunk, stop server ───────────────────── */
static int run_http_local_utest(lua_State *L, int use_tls, const char *scenario) {
    luat_pc_http_utest_server_t *server = NULL;
    luat_pc_http_utest_cfg_t cfg;
    char *ca_pem = NULL, *srv_cert_pem = NULL, *srv_key_pem = NULL;
    size_t ca_len = 0, srv_cert_len = 0, srv_key_len = 0;
    uint16_t helper_port = 0;
    int helper_result;

    memset(&cfg, 0, sizeof(cfg));
    cfg.use_tls = use_tls;

    if (use_tls) {
        ca_pem = read_pem_file(HTTP_CERTS_DIR "/ca.crt", &ca_len);
        srv_cert_pem = read_pem_file(HTTP_CERTS_DIR "/server.crt", &srv_cert_len);
        srv_key_pem = read_pem_file(HTTP_CERTS_DIR "/server.key", &srv_key_len);
        if (!ca_pem || !srv_cert_pem || !srv_key_pem) {
            LLOGE("read cert pem failed");
            goto fail;
        }
        cfg.ca_pem = (const uint8_t *)ca_pem;
        cfg.ca_pem_len = ca_len;
        cfg.srv_cert_pem = (const uint8_t *)srv_cert_pem;
        cfg.srv_cert_pem_len = srv_cert_len;
        cfg.srv_key_pem = (const uint8_t *)srv_key_pem;
        cfg.srv_key_pem_len = srv_key_len;
    }

    if (luat_pc_http_utest_server_start(&server, &cfg) != 0) {
        LLOGE("server_start failed");
        goto fail;
    }
    if (luat_pc_http_utest_server_wait_ready(server, 5000, &helper_port) != 0) {
        LLOGE("server_wait_ready failed: %s", luat_pc_http_utest_server_error(server));
        luat_pc_http_utest_server_stop(server, 1000);
        goto fail;
    }

    /* Push args: port, scenario, ca_pem */
    lua_pushinteger(L, helper_port);
    lua_pushstring(L, scenario);
    if (use_tls && ca_pem) {
        lua_pushlstring(L, ca_pem, ca_len - 1);
    } else {
        lua_pushnil(L);
    }
    run_http_utest_code_nargs(L, http_local_lua_chunk, 3);

    helper_result = luat_pc_http_utest_server_stop(server, 5000);
    if (helper_result != 0) {
        LLOGE("server_stop error: %s", luat_pc_http_utest_server_error(server));
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
    }

    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    return 1;

fail:
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    lua_pushboolean(L, 0);
    return 1;
}

static int run_http_local_concurrent_utest(lua_State *L, int use_tls) {
    luat_pc_http_utest_server_t *server = NULL;
    luat_pc_http_utest_cfg_t cfg;
    char *ca_pem = NULL, *srv_cert_pem = NULL, *srv_key_pem = NULL;
    size_t ca_len = 0, srv_cert_len = 0, srv_key_len = 0;
    uint16_t helper_port = 0;

    memset(&cfg, 0, sizeof(cfg));
    cfg.use_tls = use_tls;

    if (use_tls) {
        ca_pem = read_pem_file(HTTP_CERTS_DIR "/ca.crt", &ca_len);
        srv_cert_pem = read_pem_file(HTTP_CERTS_DIR "/server.crt", &srv_cert_len);
        srv_key_pem = read_pem_file(HTTP_CERTS_DIR "/server.key", &srv_key_len);
        if (!ca_pem || !srv_cert_pem || !srv_key_pem) goto fail;
        cfg.ca_pem = (const uint8_t *)ca_pem;
        cfg.ca_pem_len = ca_len;
        cfg.srv_cert_pem = (const uint8_t *)srv_cert_pem;
        cfg.srv_cert_pem_len = srv_cert_len;
        cfg.srv_key_pem = (const uint8_t *)srv_key_pem;
        cfg.srv_key_pem_len = srv_key_len;
    }

    if (luat_pc_http_utest_server_start(&server, &cfg) != 0) goto fail;
    if (luat_pc_http_utest_server_wait_ready(server, 5000, &helper_port) != 0) {
        luat_pc_http_utest_server_stop(server, 1000);
        goto fail;
    }

    lua_pushinteger(L, helper_port);
    if (use_tls && ca_pem) {
        lua_pushlstring(L, ca_pem, ca_len - 1);
    } else {
        lua_pushnil(L);
    }
    run_http_utest_code_nargs(L, http_local_concurrent_lua_chunk, 2);

    luat_pc_http_utest_server_stop(server, 5000);
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    return 1;

fail:
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    lua_pushboolean(L, 0);
    return 1;
}

static int run_http_local_stress_utest(lua_State *L, int use_tls, int iterations) {
    luat_pc_http_utest_server_t *server = NULL;
    luat_pc_http_utest_cfg_t cfg;
    char *ca_pem = NULL, *srv_cert_pem = NULL, *srv_key_pem = NULL;
    size_t ca_len = 0, srv_cert_len = 0, srv_key_len = 0;
    uint16_t helper_port = 0;

    memset(&cfg, 0, sizeof(cfg));
    cfg.use_tls = use_tls;

    if (use_tls) {
        ca_pem = read_pem_file(HTTP_CERTS_DIR "/ca.crt", &ca_len);
        srv_cert_pem = read_pem_file(HTTP_CERTS_DIR "/server.crt", &srv_cert_len);
        srv_key_pem = read_pem_file(HTTP_CERTS_DIR "/server.key", &srv_key_len);
        if (!ca_pem || !srv_cert_pem || !srv_key_pem) goto fail;
        cfg.ca_pem = (const uint8_t *)ca_pem;
        cfg.ca_pem_len = ca_len;
        cfg.srv_cert_pem = (const uint8_t *)srv_cert_pem;
        cfg.srv_cert_pem_len = srv_cert_len;
        cfg.srv_key_pem = (const uint8_t *)srv_key_pem;
        cfg.srv_key_pem_len = srv_key_len;
    }

    if (luat_pc_http_utest_server_start(&server, &cfg) != 0) goto fail;
    if (luat_pc_http_utest_server_wait_ready(server, 5000, &helper_port) != 0) {
        luat_pc_http_utest_server_stop(server, 1000);
        goto fail;
    }

    lua_pushinteger(L, helper_port);
    if (use_tls && ca_pem) {
        lua_pushlstring(L, ca_pem, ca_len - 1);
    } else {
        lua_pushnil(L);
    }
    lua_pushinteger(L, iterations);
    run_http_utest_code_nargs(L, http_local_stress_lua_chunk, 3);

    luat_pc_http_utest_server_stop(server, 5000);
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    return 1;

fail:
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    lua_pushboolean(L, 0);
    return 1;
}

static int run_https_local_cert_mismatch_utest(lua_State *L) {
    luat_pc_http_utest_server_t *server = NULL;
    luat_pc_http_utest_cfg_t cfg;
    char *ca_pem = NULL, *srv_cert_pem = NULL, *srv_key_pem = NULL;
    char *wrong_ca_pem = NULL;
    size_t ca_len = 0, srv_cert_len = 0, srv_key_len = 0, wrong_ca_len = 0;
    uint16_t helper_port = 0;

    memset(&cfg, 0, sizeof(cfg));
    cfg.use_tls = 1;

    /* Server uses wrong_server cert (signed by wrong CA) */
    ca_pem = read_pem_file(HTTP_CERTS_DIR "/ca.crt", &ca_len);
    srv_cert_pem = read_pem_file(HTTP_CERTS_DIR "/wrong_server.crt", &srv_cert_len);
    srv_key_pem = read_pem_file(HTTP_CERTS_DIR "/wrong_server.key", &srv_key_len);
    /* Client will trust the real CA */
    wrong_ca_pem = read_pem_file(HTTP_CERTS_DIR "/ca.crt", &wrong_ca_len);

    if (!ca_pem || !srv_cert_pem || !srv_key_pem || !wrong_ca_pem) goto fail;

    cfg.ca_pem = (const uint8_t *)ca_pem;
    cfg.ca_pem_len = ca_len;
    cfg.srv_cert_pem = (const uint8_t *)srv_cert_pem;
    cfg.srv_cert_pem_len = srv_cert_len;
    cfg.srv_key_pem = (const uint8_t *)srv_key_pem;
    cfg.srv_key_pem_len = srv_key_len;

    if (luat_pc_http_utest_server_start(&server, &cfg) != 0) goto fail;
    if (luat_pc_http_utest_server_wait_ready(server, 5000, &helper_port) != 0) {
        luat_pc_http_utest_server_stop(server, 1000);
        goto fail;
    }

    lua_pushinteger(L, helper_port);
    lua_pushlstring(L, wrong_ca_pem, wrong_ca_len - 1);
    run_http_utest_code_nargs(L, https_local_cert_mismatch_lua_chunk, 2);

    luat_pc_http_utest_server_stop(server, 5000);
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    if (wrong_ca_pem) luat_heap_free(wrong_ca_pem);
    return 1;

fail:
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    if (wrong_ca_pem) luat_heap_free(wrong_ca_pem);
    lua_pushboolean(L, 0);
    return 1;
}
#endif /* LUAT_BSP_PC */

/* ─── External network cases (original) ─────────────────────────────────────── */
static const char *get_http_utest_code(const char *case_name) {
    if (!case_name || strcmp(case_name, "http_external_qq") == 0) {
        return
            "if not sysplus then _G.sysplus = require('sysplus') end "
            "local ready = false "
            "for _ = 1, 30 do "
            "  local adapter = socket.dft() "
            "  local ok = socket.adapter(adapter) "
            "  local ip = socket.localIP(adapter) "
            "  if ok and type(ip) == 'string' and ip ~= '0.0.0.0' then "
            "    ready = true "
            "    break "
            "  end "
            "  sys.wait(1000) "
            "end "
            "assert(ready, 'network not ready') "
            "for attempt = 1, 3 do "
            "  local code, headers = http.request('GET', 'http://www.qq.com', nil, nil, {timeout = 30000}).wait() "
            "  if type(code) == 'number' and code >= 100 and code < 600 and type(headers) == 'table' then "
            "    return true "
            "  end "
            "  if attempt < 3 then "
            "    sys.wait(1000) "
            "  end "
            "end "
            "return false";
    }
    if (strcmp(case_name, "https_external_qq") == 0) {
        return
            "if not sysplus then _G.sysplus = require('sysplus') end "
            "local ready = false "
            "for _ = 1, 30 do "
            "  local adapter = socket.dft() "
            "  local ok = socket.adapter(adapter) "
            "  local ip = socket.localIP(adapter) "
            "  if ok and type(ip) == 'string' and ip ~= '0.0.0.0' then "
            "    ready = true "
            "    break "
            "  end "
            "  sys.wait(1000) "
            "end "
            "assert(ready, 'network not ready') "
            "for attempt = 1, 3 do "
            "  local code, headers = http.request('GET', 'https://www.qq.com', nil, nil, {timeout = 30000}).wait() "
            "  if type(code) == 'number' and code >= 100 and code < 600 and type(headers) == 'table' then "
            "    return true "
            "  end "
            "  if attempt < 3 then "
            "    sys.wait(1000) "
            "  end "
            "end "
            "return false";
    }
    return NULL;
}

int luat_http_utest(lua_State *L, const char *case_name) {
    if (!case_name) {
        lua_pushboolean(L, 0);
        return 1;
    }

#ifdef LUAT_BSP_PC
    /* ─── Local HTTP cases ─── */
    if (strcmp(case_name, "http_local_get") == 0)
        return run_http_local_utest(L, 0, "get");
    if (strcmp(case_name, "http_local_get_json") == 0)
        return run_http_local_utest(L, 0, "get_json");
    if (strcmp(case_name, "http_local_post_echo") == 0)
        return run_http_local_utest(L, 0, "post_echo");
    if (strcmp(case_name, "http_local_status_404") == 0)
        return run_http_local_utest(L, 0, "status_404");
    if (strcmp(case_name, "http_local_status_500") == 0)
        return run_http_local_utest(L, 0, "status_500");
    if (strcmp(case_name, "http_local_status_301") == 0)
        return run_http_local_utest(L, 0, "status_301");
    if (strcmp(case_name, "http_local_large_body") == 0)
        return run_http_local_utest(L, 0, "large_body");
    if (strcmp(case_name, "http_local_headers") == 0)
        return run_http_local_utest(L, 0, "headers");
    if (strcmp(case_name, "http_local_timeout") == 0)
        return run_http_local_utest(L, 0, "timeout");
    if (strcmp(case_name, "http_local_server_drop") == 0)
        return run_http_local_utest(L, 0, "server_drop");
    if (strcmp(case_name, "http_local_malformed") == 0)
        return run_http_local_utest(L, 0, "malformed");
    if (strcmp(case_name, "http_local_connect_refused") == 0)
        return run_http_local_utest(L, 0, "connect_refused");
    if (strcmp(case_name, "http_local_concurrent") == 0)
        return run_http_local_concurrent_utest(L, 0);
    if (strcmp(case_name, "http_local_stress_loop") == 0)
        return run_http_local_stress_utest(L, 0, 20);

    /* ─── Local HTTPS cases ─── */
    if (strcmp(case_name, "https_local_get") == 0)
        return run_http_local_utest(L, 1, "get");
    if (strcmp(case_name, "https_local_get_json") == 0)
        return run_http_local_utest(L, 1, "get_json");
    if (strcmp(case_name, "https_local_post_echo") == 0)
        return run_http_local_utest(L, 1, "post_echo");
    if (strcmp(case_name, "https_local_large_body") == 0)
        return run_http_local_utest(L, 1, "large_body");
    if (strcmp(case_name, "https_local_timeout") == 0)
        return run_http_local_utest(L, 1, "timeout");
    if (strcmp(case_name, "https_local_cert_mismatch") == 0)
        return run_https_local_cert_mismatch_utest(L);
    if (strcmp(case_name, "https_local_concurrent") == 0)
        return run_http_local_concurrent_utest(L, 1);
    if (strcmp(case_name, "https_local_stress_loop") == 0)
        return run_http_local_stress_utest(L, 1, 10);
#endif /* LUAT_BSP_PC */

    /* ─── External network cases (fallback) ─── */
    {
        const char *code = get_http_utest_code(case_name);
        int status;
        if (!code) {
            lua_pushboolean(L, 0);
            return 1;
        }
        if (luaL_loadstring(L, code) != LUA_OK) {
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
            return 1;
        }
        status = lua_pcallk(L, 0, 1, 0, 0, finish_http_utest);
        return finish_http_utest(L, status, 0);
    }
}
