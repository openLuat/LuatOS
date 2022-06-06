
/*
@module  http
@summary 执行http请求
@version 1.0
@date    2020.07.07
@demo http
*/
#include "luat_base.h"
#include "luat_http.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

static int l_http_reqcommon(lua_State *L, uint8_t method);

static int luat_http_msghandler(lua_State *L, void* ptr) {
    luat_lib_http_resp_t *resp = ptr;
    int recount = 0;
    if (resp) {
        LLOGD("http resp code=%ld", resp->code);
        if (resp->luacb) {
            lua_geti(L, LUA_REGISTRYINDEX, resp->luacb);
            lua_pushinteger(L, resp->code);
            lua_newtable(L); // headers 暂时不处理
            if (resp->body.size > 0) {
                recount = 3;
                lua_pushlstring(L, resp->body.ptr, resp->body.size);
            }
            else {
                recount = 2;
            }
            lua_call(L, recount, 0);
            luaL_unref(L, LUA_REGISTRYINDEX, resp->luacb);
        }
        luat_http_resp_gc(resp);
    }
    return 0;
}

static int luat_http_cb_impl(luat_lib_http_resp_t *resp) {
    if (resp->luacb == 0) {
        LLOGD("http resp without lua callback code=%ld", resp->code);
        luat_http_resp_gc(resp);
        return 0; //
    }
    rtos_msg_t msg;
    msg.handler = luat_http_msghandler;
    msg.ptr = resp;
    msg.arg1 = resp->code;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
    return 0;
}

/*
发起一个http get请求（推荐用http.get/post/put/delete方法）
@api http.req(url, params, cb)
@string 目标URL,需要是https://或者http://开头,否则将当成http://开头
@table 可选参数. method方法,headers请求头,body数据,ca证书路径,timeout超时时长,
@function 回调方法
@return boolean 成功启动返回true,否则返回false.启动成功后,cb回调必然会调用一次
@usage
-- GET请求
http.req("http://www.baidu.com/", nil, function(ret, code, headers, body)
    log.info("http", ret, code, header, body)
end)
*/
static int l_http_req(lua_State *L) {
    return l_http_reqcommon(L, LUAT_HTTP_GET);
}
/*
发起一个http get请求
@api http.get(url, params, cb)
@string 目标URL,需要是https://或者http://开头,否则将当成http://开头
@table 可选参数. headers请求头,body数据,ca证书路径,timeout超时时长,
@function 回调方法
@return boolean 成功启动返回true,否则返回false.启动成功后,cb回调必然会调用一次
@usage
-- GET请求
http.get("http://www.baidu.com/", nil, function(ret, code, headers, body)
    log.info("http", ret, code, header, body)
end)
*/
static int l_http_get(lua_State *L) {
    return l_http_reqcommon(L, LUAT_HTTP_GET);
}

/*
发起一个http post请求
@api http.post(url, params, cb)
@string 目标URL,需要是https://或者http://开头,否则将当成http://开头
@table 可选参数. headers请求头,body数据,ca证书路径,timeout超时时长,
@function 回调方法
@return boolean 成功启动返回true,否则返回false.启动成功后,cb回调必然会调用一次
@usage
-- POST请求
http.post("http://www.baidu.com/", {body=json.encode(data)}, function(ret, code, headers, body)
    log.info("http", ret, code, header, body)
end)
*/
static int l_http_post(lua_State *L) {
    return l_http_reqcommon(L, LUAT_HTTP_POST);
}
/*
发起一个http put请求
@api http.put(url, params, cb)
@string 目标URL,需要是https://或者http://开头,否则将当成http://开头
@table 可选参数. headers请求头,body数据,ca证书路径,timeout超时时长,
@function 回调方法
@return boolean 成功启动返回true,否则返回false.启动成功后,cb回调必然会调用一次
@usage
-- PUT请求
http.put("http://www.baidu.com/", {body=json.encode(data)}, function(ret, code, headers, body)
    log.info("http", ret, code, header, body)
end)
*/
static int l_http_put(lua_State *L) {
    return l_http_reqcommon(L, LUAT_HTTP_PUT);
}
/*
发起一个http delete请求
@api http.delete(url, params, cb)
@string 目标URL,需要是https://或者http://开头,否则将当成http://开头
@table 可选参数. headers请求头,body数据,ca证书路径,timeout超时时长,
@function 回调方法
@return boolean 成功启动返回true,否则返回false.启动成功后,cb回调必然会调用一次
@usage
-- DELETE请求
http.delete("http://www.baidu.com/", nil, function(ret, code, headers, body)
    log.info("http", ret, code, header, body)
end)
*/
static int l_http_delete(lua_State *L) {
    return l_http_reqcommon(L, LUAT_HTTP_DELETE);
}

static int l_http_reqcommon(lua_State *L, uint8_t method) {
    if (!lua_isstring(L, 1)) {
        lua_pushliteral(L, "first arg must string");
        lua_error(L);
        return 0;
    }
    luat_lib_http_req_t *req = luat_heap_malloc(sizeof(luat_lib_http_req_t));
    if (req == NULL) {
        lua_pushstring(L, "sys out of memory");
        lua_error(L);
        return 0;
    }
    memset(req, 0, sizeof(luat_lib_http_req_t));

    req->method = method;
    char* tmp = (char*)luaL_checklstring(L, 1, &(req->url_len));
    req->url = luat_heap_malloc(req->url_len+1);
    if (req->url == NULL) {
        luat_heap_free(req);
        lua_pushstring(L, "sys out of memory");
        lua_error(L);
        return 0;
    }
    memset(req->url, 0, req->url_len + 1);
    memcpy(req->url, tmp, req->url_len + 1);
    LLOGD("http url=%s", req->url);


    // 先取一下回调
    if (lua_isfunction(L, 3)) {
        lua_settop(L, 3);
        req->luacb = luaL_ref(L, LUA_REGISTRYINDEX);
    }

    if (lua_istable(L, 2)) {
        //lua_settop(L, 2); // 移除掉其他参数

        // 取method
        lua_pushliteral(L, "method");
        if (lua_gettable(L, 2)) {
            if (lua_isinteger(L, -1)) {
                req->method = luaL_checkinteger(L, -1);
            }
        }
        lua_pop(L, 1);


        // 取下载路径
        lua_pushliteral(L, "dw");
        if (lua_gettable(L, 2) == LUA_TSTRING){
            size_t dw_path_sz = 0;
            const char* dw = luaL_checklstring(L, -1, &dw_path_sz);
            if (dw_path_sz > 31) {
                LLOGD("download path is too long!!!");
                lua_pushliteral(L, "download path is too long!!!");
                lua_error(L);
                return 0;
            }
            strcpy(req->dwpath, dw);
        }
        lua_pop(L, 1);

        // 取headers

        // 取body,当前仅支持string
        lua_pushliteral(L, "body");
        lua_gettable(L, 2);
        if (!lua_isnil(L, -1) && !lua_isstring(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "body must be string");
            lua_error(L);
            luat_http_req_gc(req);
            return 0;
        }
        else if (lua_isstring(L, -1)) {
            tmp = (char*)luaL_checklstring(L, -1, &(req->body.size));
            if (req->body.size > 0) {
                req->body.ptr = luat_heap_malloc(req->body.size);
                memcpy(req->body.ptr, tmp, req->body.size);
            }
        }
        lua_pop(L, 1);

        // 去ca证书路径
        lua_pushliteral(L, "ca");
        lua_gettable(L, 2);
        if (!lua_isnil(L, -1) && !lua_isstring(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "ca must be string");
            lua_error(L);
            luat_http_req_gc(req);
            return 0;
        }
        else if (lua_isstring(L, -1)) {
            tmp = (char*)luaL_checklstring(L, -1, &(req->ca_len));
            if (req->ca_len > 0) {
                req->ca = luat_heap_malloc(req->ca_len);
                memcpy(req->ca, tmp, req->ca_len);
            }
        }
        lua_pop(L, 1);

        // timeout设置
        lua_pushliteral(L, "timeout");
        lua_gettable(L, 2);
        if (!lua_isnil(L, -1) && !lua_isinteger(L, -1)) {
            lua_pop(L, 1);
            lua_pushliteral(L, "timeout must be int");
            lua_error(L);
            luat_http_req_gc(req);
            return 0;
        }
        else if (lua_isinteger(L, -1)) {
            req->timeout_s = luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
    }

    req->httpcb = luat_http_cb_impl;
    if (req->timeout_s <= 5) {
        req->timeout_s = 5;
    }

    // 执行
    int re = luat_http_req(req);
    if (re == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    else {
        luat_http_req_gc(req);
        LLOGW("http request return re=%ld", re);
        lua_pushboolean(L, 0);
        lua_pushinteger(L, re);
        return 2;
    }
}

#include "rotable2.h"
static const rotable_Reg_t reg_http[] =
{
    { "req",    ROREG_FUNC(l_http_req)},
    { "get",    ROREG_FUNC(l_http_get)},
    { "post",   ROREG_FUNC(l_http_post)},
    { "put",    ROREG_FUNC(l_http_put)},
    { "delete", ROREG_FUNC(l_http_delete)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_http( lua_State *L ) {
    luat_newlib2(L, reg_http);
    return 1;
}

void luat_http_req_gc(luat_lib_http_req_t *req) {
    if (req == NULL) {
        return;
    }
    if (req->url) {
        luat_heap_free(req->url);
    }
    if (req->headers.size > 0) {
        for (size_t i = 0; i < req->headers.size; i++)
        {
            luat_heap_free(*(req->headers.ptr + i));
        }
    }
    if (req->body.size > 0) {
        luat_heap_free(req->body.ptr);
    }

    luat_heap_free(req);
}

void luat_http_resp_gc(luat_lib_http_resp_t *resp) {
    if (resp == NULL) {
        return;
    }
    if (resp->headers.size > 0) {
        for (size_t i = 0; i < resp->headers.size; i++)
        {
            luat_heap_free(*(resp->headers.ptr + i));
        }
    }
    if (resp->body.size > 0) {
        luat_heap_free(resp->body.ptr);
    }
    luat_heap_free(resp);
}
