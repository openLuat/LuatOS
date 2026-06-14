#include "luat_base.h"
#include <stdio.h>
#include <string.h>

#include "luat_malloc.h"

#define LUAT_LOG_TAG "socket_utest"
#include "luat_log.h"

#ifdef LUAT_BSP_PC
#include "luat_pc_dtls_utest.h"
#endif

static int finish_socket_utest(lua_State *L, int status, lua_KContext ctx) {
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

static int run_socket_utest_code(lua_State *L, const char *code) {
    int status;
    if (luaL_loadstring(L, code) != LUA_OK) {
        if (lua_isstring(L, -1)) {
            LLOGE("%s", lua_tostring(L, -1));
        }
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        return 1;
    }
    status = lua_pcallk(L, 0, 1, 0, 0, finish_socket_utest);
    return finish_socket_utest(L, status, 0);
}

/* Run a Lua chunk that takes `nargs` pre-pushed stack arguments. */
static int run_socket_utest_code_nargs(lua_State *L, const char *code, int nargs) {
    /* first_arg = top - nargs + 1: absolute index of the first caller-pushed arg.
     * We will move the loaded function to sit just above (i.e. immediately
     * before) that first arg, which is the layout lua_pcallk expects when
     * nargs is the count of caller-pushed args. */
    int first_arg = lua_gettop(L) - nargs + 1;
    int status;

    if (luaL_loadstring(L, code) != LUA_OK) {
        if (lua_isstring(L, -1)) {
            LLOGE("%s", lua_tostring(L, -1));
        }
        /* errmsg + nargs to clear, then leave 1 boolean result */
        lua_pop(L, 1 + nargs);
        lua_pushboolean(L, 0);
        return 1;
    }
    /* Stack: [..., arg1..argN, function]. Move function to just before args:
     *        [..., function, arg1..argN], which is what lua_pcallk wants. */
    lua_insert(L, first_arg);
    status = lua_pcallk(L, nargs, 1, 0, 0, finish_socket_utest);
    return finish_socket_utest(L, status, 0);
}

#ifdef LUAT_BSP_PC
/* Read a small file into a heap-allocated, NUL-terminated buffer. Returns
 * NULL on failure. The returned pointer must be released with luat_heap_free. */
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
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return NULL;
    }
    n = ftell(fp);
    if (n < 0) {
        fclose(fp);
        return NULL;
    }
    rewind(fp);
    /* +1 to NUL-terminate (mbedtls_x509_crt_parse / pk_parse_key expect it) */
    buf = (char *)luat_heap_malloc((size_t)n + 1);
    if (!buf) {
        fclose(fp);
        return NULL;
    }
    got = fread(buf, 1, (size_t)n, fp);
    fclose(fp);
    if (got != (size_t)n) {
        luat_heap_free(buf);
        return NULL;
    }
    buf[n] = '\0';
    if (out_len) *out_len = (size_t)n + 1;
    return buf;
}
#endif

/* =====================================================================
 *  DTLS PSK loopback (existing case "dtls_loopback_psk")
 * ===================================================================== */

static char *build_dtls_loopback_utest_code(uint16_t helper_port) {
    static const char *code_template =
        "local helper_port = %u "
        "local function wait_evt(topic, expected, timeout) "
        "  local result, evt, param = sys.waitUntil(topic, timeout) "
        "  return result ~= false and evt == expected and param == 0 "
        "end "
        "local function cleanup(netc, topic) "
        "  if not netc then return end "
        "  local close_succ, closed = socket.discon(netc) "
        "  if close_succ and not closed then sys.waitUntil(topic, 1000) end "
        "  socket.close(netc) "
        "  socket.release(netc) "
        "end "
        "local attempt = 1 "
        "local nonce = tostring((mcu and mcu.ticks and mcu.ticks()) or attempt) "
        "local topic = 'dtls_utest_event_' .. nonce .. '_' .. tostring(attempt) "
        "local netc = socket.create(nil, function(_, evt, param) sys.publish(topic, evt, param) end) "
        "assert(netc, 'socket.create failed') "
        "local token = 'dtls-utest:' .. os.date('%%Y%%m%%d%%H%%M%%S') .. ':' .. nonce .. ':' .. tostring(attempt) "
        "local ok, err = xpcall(function() "
        "  assert(socket.config(netc, nil, true, true, nil, nil, nil, 'luatos-dtls-psk', 'luatos-dtls-id', nil), 'socket.config failed') "
        "  local succ, online = socket.connect(netc, '127.0.0.1', helper_port) "
        "  assert(succ, 'dtls_connect_timeout') "
        "  local connect_pending = not online "
        "  local tx_succ, full, tx_done = false, false, false "
        "  for _ = 1, 100 do "
        "    tx_succ, full, tx_done = socket.tx(netc, token) "
        "    if tx_succ and not full then break end "
        "    sys.wait(100) "
        "  end "
        "  assert(tx_succ and not full, connect_pending and 'dtls_connect_timeout' or 'dtls_tx_timeout') "
        "  if not tx_done then "
        "    local result, evt, param = sys.waitUntil(topic, 10000) "
        "    assert(result ~= false, connect_pending and 'dtls_connect_timeout' or 'dtls_tx_timeout') "
        "    if connect_pending then "
        "      if evt == socket.ON_LINE then "
        "        assert(param == 0, 'dtls_connect_timeout') "
        "        result, evt, param = sys.waitUntil(topic, 10000) "
        "        assert(result ~= false and evt == socket.TX_OK and param == 0, 'dtls_tx_timeout') "
        "      else "
        "        assert(evt == socket.TX_OK and param == 0, 'dtls_connect_timeout') "
        "      end "
        "    else "
        "      assert(evt == socket.TX_OK and param == 0, 'dtls_tx_timeout') "
        "    end "
        "  end "
        "  local data = '' "
        "  for _ = 1, 30 do "
        "    local read_ok, read_data = socket.read(netc, #token) "
        "    assert(read_ok, 'dtls_echo_mismatch') "
        "    if type(read_data) == 'string' and #read_data > 0 then data = read_data break end "
        "    sys.wait(100) "
        "  end "
        "  assert(data == token, 'dtls_echo_mismatch') "
        "end, function(e) return e end) "
        "cleanup(netc, topic) "
        "if not ok then error(err) end "
        "return true";
    int code_len = snprintf(NULL, 0, code_template, helper_port);
    char *code;

    if (code_len <= 0) {
        return NULL;
    }
    code = luat_heap_malloc((size_t)code_len + 1);
    if (!code) {
        return NULL;
    }
    snprintf(code, (size_t)code_len + 1, code_template, helper_port);
    return code;
}

static int run_dtls_loopback_utest(lua_State *L) {
#ifdef LUAT_BSP_PC
    static const uint8_t psk[] = "luatos-dtls-psk";
    luat_pc_dtls_utest_server_t *server = NULL;
    char helper_error[32] = {0};
    char *code = NULL;
    uint16_t helper_port = 0;
    int helper_result;

    if (luat_pc_dtls_utest_server_start(&server, "luatos-dtls-id", psk, sizeof(psk) - 1) != 0) {
        lua_pushboolean(L, 0);
        return 1;
    }
    if (luat_pc_dtls_utest_server_wait_ready(server, 5000, &helper_port) != 0) {
        snprintf(helper_error, sizeof(helper_error), "%s", luat_pc_dtls_utest_server_error(server));
        LLOGE("%s", helper_error);
        luat_pc_dtls_utest_server_stop(server, 1000);
        lua_pushboolean(L, 0);
        return 1;
    }

    code = build_dtls_loopback_utest_code(helper_port);
    if (!code) {
        luat_pc_dtls_utest_server_stop(server, 1000);
        lua_pushboolean(L, 0);
        return 1;
    }

    run_socket_utest_code(L, code);
    luat_heap_free(code);

    snprintf(helper_error, sizeof(helper_error), "%s", luat_pc_dtls_utest_server_error(server));
    helper_result = luat_pc_dtls_utest_server_stop(server, 5000);
    if (helper_result != 0) {
        LLOGE("%s", helper_error[0] ? helper_error : "helper_start_failed");
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
    }
    return 1;
#else
    lua_pushboolean(L, 0);
    return 1;
#endif
}

/* =====================================================================
 *  DTLS CA-cert / mTLS loopback
 *
 *  Lua chunk expects 5 stack args (in order):
 *    1. mode: 1 = one-way cert (positive), 2 = CA mismatch (expect reject),
 *             3 = mTLS (client cert + key), 4 = parse-boundary (no helper).
 *    2. helper_port (ignored when mode == 4)
 *    3. ca_pem: string
 *    4. client_cert_pem: string or nil (only used by mode 3)
 *    5. client_key_pem: string or nil (only used by mode 3)
 * ===================================================================== */

static const char *dtls_loopback_cert_lua_chunk =
    "local mode, helper_port, ca_pem, client_cert_pem, client_key_pem = ... "
    "local function cleanup(netc, topic) "
    "  if not netc then return end "
    "  local close_succ, closed = socket.discon(netc) "
    "  if close_succ and not closed then sys.waitUntil(topic, 1000) end "
    "  socket.close(netc) "
    "  socket.release(netc) "
    "end "
    "local attempt = 1 "
    "local nonce = tostring((mcu and mcu.ticks and mcu.ticks()) or attempt) "
    "local topic = 'dtls_utest_event_' .. nonce .. '_' .. tostring(attempt) "
    "local netc = socket.create(nil, function(_, evt, param) sys.publish(topic, evt, param) end) "
    "assert(netc, 'socket.create failed') "
    "local token = 'dtls-cert-utest:' .. os.date('%Y%m%d%H%M%S') .. ':' .. nonce .. ':' .. tostring(attempt) "
    "local ok, err = xpcall(function() "
    "  if mode == 4 then "
    "    local r1 = socket.config(netc, nil, true, true, nil, nil, nil, 'not a pem') "
    "    assert(r1 == false, 'parse_boundary_not_pem_should_fail') "
    "    local r2 = socket.config(netc, nil, true, true, nil, nil, nil, '') "
    "    assert(r2 == false, 'parse_boundary_empty_should_fail') "
    "    local r3 = socket.config(netc, nil, true, true, nil, nil, nil, 'garbage der as pem') "
    "    assert(r3 == false, 'parse_boundary_garbage_should_fail') "
    "    return "
    "  end "
    "  if mode == 3 then "
    "    assert(socket.config(netc, nil, true, true, nil, nil, nil, ca_pem, client_cert_pem, client_key_pem), 'socket.config failed (mTLS)') "
    "  else "
    "    assert(socket.config(netc, nil, true, true, nil, nil, nil, ca_pem), 'socket.config failed (one-way cert)') "
    "  end "
    "  local succ, online = socket.connect(netc, '127.0.0.1', helper_port) "
    "  if mode == 2 then "
    "    if online then error('cert_mismatch_should_be_rejected') end "
    "    local connected = false "
    "    for _ = 1, 60 do "
    "      local r, evt, param = sys.waitUntil(topic, 500) "
    "      if r == false then break end "
    "      if evt == socket.ON_LINE and param == 0 then connected = true break end "
    "      if param and param < 0 then break end "
    "    end "
    "    assert(not connected, 'cert_mismatch_should_be_rejected') "
    "    return "
    "  end "
    "  assert(succ, 'dtls_connect_timeout') "
    "  local connect_pending = not online "
    "  local tx_succ, full, tx_done = false, false, false "
    "  for _ = 1, 100 do "
    "    tx_succ, full, tx_done = socket.tx(netc, token) "
    "    if tx_succ and not full then break end "
    "    sys.wait(100) "
    "  end "
    "  assert(tx_succ and not full, connect_pending and 'dtls_connect_timeout' or 'dtls_tx_timeout') "
    "  if not tx_done then "
    "    local result, evt, param = sys.waitUntil(topic, 10000) "
    "    assert(result ~= false, connect_pending and 'dtls_connect_timeout' or 'dtls_tx_timeout') "
    "    if connect_pending then "
    "      if evt == socket.ON_LINE then "
    "        assert(param == 0, 'dtls_connect_timeout') "
    "        result, evt, param = sys.waitUntil(topic, 10000) "
    "        assert(result ~= false and evt == socket.TX_OK and param == 0, 'dtls_tx_timeout') "
    "      else "
    "        assert(evt == socket.TX_OK and param == 0, 'dtls_connect_timeout') "
    "      end "
    "    else "
    "      assert(evt == socket.TX_OK and param == 0, 'dtls_tx_timeout') "
    "    end "
    "  end "
    "  local data = '' "
    "  for _ = 1, 30 do "
    "    local read_ok, read_data = socket.read(netc, #token) "
    "    assert(read_ok, 'dtls_echo_mismatch') "
    "    if type(read_data) == 'string' and #read_data > 0 then data = read_data break end "
    "    sys.wait(100) "
    "  end "
    "  assert(data == token, 'dtls_echo_mismatch') "
    "end, function(e) return e end) "
    "cleanup(netc, topic) "
    "if not ok then error(err) end "
    "return true";

static int run_dtls_loopback_cert_utest(lua_State *L, int mode) {
#ifdef LUAT_BSP_PC
    /* Cert assets live under <repo>/testcase/utest/net/dtls_basic/certs/.
     * PC runner's cwd is bsp/pc, so the relative path is ../../testcase/... */
#define DTLS_CERTS_DIR "../../testcase/utest/net/dtls_basic/certs"
    luat_pc_dtls_utest_server_t *server = NULL;
    char helper_error[32] = {0};
    char *ca_pem = NULL, *srv_cert_pem = NULL, *srv_key_pem = NULL;
    char *client_cert_pem = NULL, *client_key_pem = NULL;
    size_t ca_len = 0, srv_cert_len = 0, srv_key_len = 0;
    size_t client_cert_len = 0, client_key_len = 0;
    uint16_t helper_port = 0;
    int helper_result = 0;
    int require_client_cert = 0;

    if (mode == 1) {
        /* one-way cert: helper loads ca + server cert, client loads ca only */
        ca_pem = read_pem_file(DTLS_CERTS_DIR "/ca.crt", &ca_len);
        srv_cert_pem = read_pem_file(DTLS_CERTS_DIR "/server.crt", &srv_cert_len);
        srv_key_pem = read_pem_file(DTLS_CERTS_DIR "/server.key", &srv_key_len);
    } else if (mode == 2) {
        /* CA mismatch: helper signs with wrong CA, client still trusts the real CA */
        ca_pem = read_pem_file(DTLS_CERTS_DIR "/ca.crt", &ca_len);
        srv_cert_pem = read_pem_file(DTLS_CERTS_DIR "/wrong_server.crt", &srv_cert_len);
        srv_key_pem = read_pem_file(DTLS_CERTS_DIR "/wrong_server.key", &srv_key_len);
    } else if (mode == 3) {
        /* mTLS: helper requires client cert signed by ca */
        ca_pem = read_pem_file(DTLS_CERTS_DIR "/ca.crt", &ca_len);
        srv_cert_pem = read_pem_file(DTLS_CERTS_DIR "/server.crt", &srv_cert_len);
        srv_key_pem = read_pem_file(DTLS_CERTS_DIR "/server.key", &srv_key_len);
        client_cert_pem = read_pem_file(DTLS_CERTS_DIR "/client.crt", &client_cert_len);
        client_key_pem = read_pem_file(DTLS_CERTS_DIR "/client.key", &client_key_len);
        require_client_cert = 1;
    } else {
        /* mode 4 (parse boundary) does not need a helper */
    }

    if (mode != 4) {
        if (!ca_pem || !srv_cert_pem || !srv_key_pem) {
            LLOGE("read pem failed (mode=%d)", mode);
            goto fail;
        }
        if (mode == 3 && (!client_cert_pem || !client_key_pem)) {
            LLOGE("read client pem failed (mode=3)");
            goto fail;
        }
        if (luat_pc_dtls_utest_server_start_cert(&server,
                                                 (const uint8_t *)ca_pem, ca_len,
                                                 (const uint8_t *)srv_cert_pem, srv_cert_len,
                                                 (const uint8_t *)srv_key_pem, srv_key_len,
                                                 require_client_cert) != 0) {
            LLOGE("server_start_cert failed");
            goto fail;
        }
        if (luat_pc_dtls_utest_server_wait_ready(server, 5000, &helper_port) != 0) {
            snprintf(helper_error, sizeof(helper_error), "%s", luat_pc_dtls_utest_server_error(server));
            LLOGE("%s", helper_error);
            luat_pc_dtls_utest_server_stop(server, 1000);
            goto fail;
        }
    }

    /* Push Lua args: mode, helper_port, ca_pem, client_cert_pem, client_key_pem */
    lua_pushinteger(L, mode);
    lua_pushinteger(L, helper_port);
    lua_pushlstring(L, ca_pem ? ca_pem : "", ca_pem ? ca_len - 1 : 0);
    if (client_cert_pem) {
        lua_pushlstring(L, client_cert_pem, client_cert_len - 1);
    } else {
        lua_pushnil(L);
    }
    if (client_key_pem) {
        lua_pushlstring(L, client_key_pem, client_key_len - 1);
    } else {
        lua_pushnil(L);
    }
    run_socket_utest_code_nargs(L, dtls_loopback_cert_lua_chunk, 5);

    if (server) {
        snprintf(helper_error, sizeof(helper_error), "%s", luat_pc_dtls_utest_server_error(server));
        helper_result = luat_pc_dtls_utest_server_stop(server, 5000);
        if (helper_result != 0) {
            LLOGE("%s", helper_error[0] ? helper_error : "helper_start_failed");
            lua_pop(L, 1);
            lua_pushboolean(L, 0);
        }
    }

    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    if (client_cert_pem) luat_heap_free(client_cert_pem);
    if (client_key_pem) luat_heap_free(client_key_pem);
    return 1;

fail:
    if (ca_pem) luat_heap_free(ca_pem);
    if (srv_cert_pem) luat_heap_free(srv_cert_pem);
    if (srv_key_pem) luat_heap_free(srv_key_pem);
    if (client_cert_pem) luat_heap_free(client_cert_pem);
    if (client_key_pem) luat_heap_free(client_key_pem);
    lua_pushboolean(L, 0);
    return 1;
#else
    (void)mode;
    lua_pushboolean(L, 0);
    return 1;
#endif
}

static const char *get_socket_utest_code(const char *case_name) {
    if (!case_name || strcmp(case_name, "tcp_external_qq") == 0) {
        return
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
            "local function wait_evt(topic, expected, timeout) "
            "  local result, evt, param = sys.waitUntil(topic, timeout) "
            "  return result ~= false and evt == expected and param == 0 "
            "end "
            "local function attempt_once(attempt) "
            "  local topic = 'tcp_utest_event_' .. attempt "
            "  local netc = socket.create(nil, function(_, evt, param) sys.publish(topic, evt, param) end) "
            "  assert(netc, 'socket.create failed') "
            "  assert(socket.config(netc, nil, false, false), 'socket.config failed') "
            "  local succ, online = socket.connect(netc, 'www.qq.com', 80) "
            "  assert(succ, 'socket.connect failed') "
            "  if not online then "
            "    assert(wait_evt(topic, socket.ON_LINE, 30000), 'socket connect timeout') "
            "  end "
            "  local tx_succ, full, tx_done = socket.tx(netc, 'HEAD / HTTP/1.1\\r\\nHost: www.qq.com\\r\\nConnection: close\\r\\n\\r\\n') "
            "  assert(tx_succ and not full, 'socket.tx failed') "
            "  if not tx_done then "
            "    assert(wait_evt(topic, socket.TX_OK, 30000), 'socket tx timeout') "
            "  end "
            "  local data = '' "
            "  for _ = 1, 30 do "
            "    local read_ok, read_data = socket.read(netc, 1024) "
            "    if read_ok and type(read_data) == 'string' and #read_data > 0 then "
            "      data = read_data "
            "      break "
            "    end "
            "    local result, _, param = sys.waitUntil(topic, 1000) "
            "    if result ~= false and param == -1 then "
            "      break "
            "    end "
            "  end "
            "  local close_succ, closed = socket.discon(netc) "
            "  if close_succ and not closed then "
            "    sys.waitUntil(topic, 5000) "
            "  end "
            "  socket.close(netc) "
            "  return #data > 0 and string.find(data, 'HTTP/', 1, true) ~= nil "
            "end "
            "for attempt = 1, 3 do "
            "  local ok, result = pcall(attempt_once, attempt) "
            "  if ok and result then "
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

int luat_socket_utest(lua_State *L, const char *case_name) {
    const char *code = get_socket_utest_code(case_name);
    if (case_name && strcmp(case_name, "dtls_loopback_psk") == 0) {
        return run_dtls_loopback_utest(L);
    }
    if (case_name && strcmp(case_name, "dtls_loopback_cert") == 0) {
        return run_dtls_loopback_cert_utest(L, 1);
    }
    if (case_name && strcmp(case_name, "dtls_loopback_cert_mismatch") == 0) {
        return run_dtls_loopback_cert_utest(L, 2);
    }
    if (case_name && strcmp(case_name, "dtls_loopback_mtls") == 0) {
        return run_dtls_loopback_cert_utest(L, 3);
    }
    if (case_name && strcmp(case_name, "dtls_cert_parse_boundary") == 0) {
        return run_dtls_loopback_cert_utest(L, 4);
    }
    if (!code) {
        lua_pushboolean(L, 0);
        return 1;
    }
    return run_socket_utest_code(L, code);
}
