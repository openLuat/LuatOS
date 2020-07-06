
/*
@module  http
@summary 执行http请求
@version 1.0
@date    2020.07.07
*/
#include "luat_base.h"
#include "luat_http.h"

#define LUAT_LOG_TAG "luat.http"
#include "luat_log.h"


/*
发起一个http请求
@function http.req(url, params, cb)
@string 目标URL,需要是https://或者http://开头,否则将当成http://开头
@table 可选参数. method方法,headers请求头,body数据,ca证书路径,timeout超时时长,
@function 回调方法
@return boolean 成功启动返回true,否则返回false.启动成功后,cb回调必然会调用一次
@usage 
-- GET请
http.req("http://www.baidu.com/", nil, functon(ret, code, headers, body)
    log.info("http", ret, code, header, body)
end) 
*/
static int l_http_req(lua_State *L) {
    if (!lua_isstring(L, 1)) {
        lua_pushliteral(L, "first arg must string");
        lua_error(L);
        return 0;
    }
    luat_lib_http_req_t req = {0};
    req.method = 1; // GET
    req.url = luaL_checklstring(L, 1, &(req.url_len));

    if (lua_istable(L, 2)) {
        lua_settop(L, 2);
        
        // 取method
        lua_pushliteral(L, "method");
        lua_gettable(L, -2);
        if (!lua_isnil(L, -1) && !lua_isinteger(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "method must be int");
            lua_error(L);
            return 0;
        }
        req.method = luaL_checkinteger(L, -1);
        lua_pop(L, 1);

        // 取callback
        lua_pushliteral(L, "cb");
        lua_gettable(L, -2);
        if (!lua_isnil(L, -1) && !lua_isfunction(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "cb must be function");
            lua_error(L);
            return 0;
        }
        req.cb = luaL_checkinteger(L, -1);
        lua_pop(L, 1);

        // 取headers

        // 取body,当前仅支持string
        lua_pushliteral(L, "body");
        lua_gettable(L, -2);
        if (!lua_isnil(L, -1) && !lua_isstring(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "body must be string");
            lua_error(L);
            return 0;
        }
        req.body.ptr = luaL_checklstring(L, -1, &(req.body.size));
        if (req.body.size > 0) {
            lua_insert(L, 1); // 把body压入堆栈,这样就不会被GC
        }
        lua_pop(L, 1);

        // 去ca证书路径
        lua_pushliteral(L, "ca");
        lua_gettable(L, -2);
        if (!lua_isnil(L, -1) && !lua_isstring(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "ca must be string");
            lua_error(L);
            return 0;
        }
        req.ca = luaL_checklstring(L, -1, &(req.ca_len));
        if (req.ca_len > 0) {
            lua_insert(L, 1); // 把body压入堆栈,这样就不会被GC
        }
        lua_pop(L, 1);
    }

    // 执行
    int re = luat_http_req(&req);
    if (re == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    else {
        LLOGW("http request return re=%ld", re);
        lua_pushboolean(L, 0);
        lua_pushinteger(L, re);
        return 2;
    }
}

#include "rotable.h"
static const rotable_Reg reg_http[] =
{
    { "req", l_http_req, 0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_http( lua_State *L ) {
    rotable_newlib(L, reg_http);
    return 1;
}
