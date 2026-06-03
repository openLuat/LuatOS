#include "luat_base.h"
#include <string.h>

static int finish_http_utest(lua_State *L, int status, lua_KContext ctx) {
    (void)ctx;
    if (status != LUA_OK && status != LUA_YIELD) {
        lua_pop(L, 1);
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, lua_toboolean(L, -1));
    return 1;
}

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
