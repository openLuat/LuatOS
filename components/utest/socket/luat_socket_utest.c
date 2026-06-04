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
    if (!code) {
        lua_pushboolean(L, 0);
        return 1;
    }
    return run_socket_utest_code(L, code);
}
