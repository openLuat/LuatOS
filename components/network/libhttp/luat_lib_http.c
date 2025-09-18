/*
@module  http
@summary http 客户端
@version 1.0
@date    2022.09.05
@demo    http
@tag LUAT_USE_NETWORK
@usage
-- 支持  http 1.0 和 http 1.1, 不支持http2.0
-- 支持 GET/POST/PUT/DELETE/HEAD 等常用方法
-- http 客户端示例, 详细示例请参考demo
sys.taskInit(function()
	sys.wait(1000)
	local code,headers,body = http.request("GET", "http://www.example.com/abc").wait()
	log.info("http", code, body)
end)

*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "http_parser.h"
#include "luat_http.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"


#ifndef LUAT_HTTP_DEBUG
#define LUAT_HTTP_DEBUG 0
#endif
#if LUAT_HTTP_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

int http_close(luat_http_ctrl_t *http_ctrl);
int http_set_url(luat_http_ctrl_t *http_ctrl, const char* url, const char* method);

static int http_add_header(luat_http_ctrl_t *http_ctrl, const char* name, const char* value){
	if (name == NULL || value == NULL || strlen(name) == 0 || strlen(value) == 0) {
		return -1;
	}
	size_t len = strlen(name) + strlen(value) + 4;
	if (http_ctrl->req_header == NULL) {
		http_ctrl->req_header = luat_heap_malloc(len + 1);
		if (http_ctrl->req_header == NULL) {
			LLOGE("out of memory when malloc custom headers");
			return -1;
		}
		http_ctrl->req_header[0] = 0;
	}
	else {
		void *ptr = luat_heap_realloc(http_ctrl->req_header, strlen(http_ctrl->req_header) + len + 1);
		if (ptr == NULL) {
			LLOGE("out of memory when malloc custom headers");
			return -1;
		}
		http_ctrl->req_header = ptr;
	}
	memcpy(http_ctrl->req_header + strlen(http_ctrl->req_header), name, strlen(name) + 1);
	memcpy(http_ctrl->req_header + strlen(http_ctrl->req_header), ": ", 3);
	memcpy(http_ctrl->req_header + strlen(http_ctrl->req_header), value, strlen(value) + 1);
	memcpy(http_ctrl->req_header + strlen(http_ctrl->req_header), "\r\n", 3);
	return 0;
}

/*
http客户端
@api http.request(method,url,headers,body,opts,ca_file,client_ca, client_key, client_password)
@string 请求方法, 支持 GET/POST 等合法的HTTP方法
@string url地址, 支持 http和https, 支持域名, 支持自定义端口
@tabal  请求头 可选 例如 {["Content-Type"] = "application/x-www-form-urlencoded"}
@string/zbuff body 可选
@table  额外配置 可选 包含 timeout:超时时间单位ms 可选,默认10分钟,写0即永久等待 dst:下载路径,可选 adapter:选择使用网卡,可选 debug:是否打开debug信息,可选,ipv6:是否为ipv6 默认不是,可选 callback:下载回调函数,参数 content_len:总长度 body_len:以下载长度 userdata 用户传参,可选 userdata:回调自定义传参  
@string 服务器ca证书数据, 可选, 一般不需要
@string 客户端ca证书数据, 可选, 一般不需要, 双向https认证才需要
@string 客户端私钥加密数据, 可选, 一般不需要, 双向https认证才需要
@string 客户端私钥口令数据, 可选, 一般不需要, 双向https认证才需要
@return int code , 服务器反馈的值>=100, 最常见的是200.如果是底层错误,例如连接失败, 返回值小于0
@return tabal headers 当code>100时, 代表服务器返回的头部数据 
@return string/int body 服务器响应的内容字符串,如果是下载模式, 则返回文件大小
@usage

--[[
code报错信息列表:
-1 HTTP_ERROR_STATE 错误的状态, 一般是底层异常,请报issue
-2 HTTP_ERROR_HEADER 错误的响应头部, 通常是服务器问题
-3 HTTP_ERROR_BODY 错误的响应体,通常是服务器问题
-4 HTTP_ERROR_CONNECT 连接服务器失败, 未联网,地址错误,域名错误
-5 HTTP_ERROR_CLOSE 提前断开了连接, 网络或服务器问题
-6 HTTP_ERROR_RX 接收数据报错, 网络问题
-7 HTTP_ERROR_DOWNLOAD 下载文件过程报错, 网络问题或下载路径问题
-8 HTTP_ERROR_TIMEOUT 超时, 包括连接超时,读取数据超时
-9 HTTP_ERROR_FOTA fota功能报错,通常是更新包不合法
]]

-- GET请求
local code, headers, body = http.request("GET","http://site0.cn/api/httptest/simple/time").wait()
log.info("http.get", code, headers, body)
-- POST请求
local code, headers, body = http.request("POST","http://httpbin.com/post", {}, "abc=123").wait()
log.info("http.post", code, headers, body)

-- GET请求,但下载到文件
local code, headers, body = http.request("GET","http://httpbin.com/", {}, "", {dst="/data.bin"}).wait()
log.info("http.get", code, headers, body)

-- 自定义超时时间, 5000ms
http.request("GET","http://httpbin.com/", nil, nil, {timeout=5000}).wait()

-- 分段下载
local heads = {["Range"] = "bytes=0-99"} --下载0-99之间的数据
http.request("GET","http://httpbin.air32.cn/get", heads, nil, {timeout=5000}).wait()
*/
static int l_http_request(lua_State *L) {
	size_t server_cert_len = 0,client_cert_len = 0, client_key_len = 0, client_password_len = 0,len = 0;
	const char *server_cert = NULL;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	int adapter_index = -1;
	char body_len[16] = {0};
	// mbedtls_debug_set_threshold(4);

	luat_http_ctrl_t *http_ctrl = (luat_http_ctrl_t *)luat_heap_malloc(sizeof(luat_http_ctrl_t));
	if (!http_ctrl){
		LLOGE("out of memory when malloc http_ctrl");
        lua_pushinteger(L,HTTP_ERROR_CONNECT);
		luat_pushcwait_error(L,1);
		return 1;
	}
	memset(http_ctrl, 0, sizeof(luat_http_ctrl_t));

	http_ctrl->timeout = 0;
	int use_ipv6 = 0;
	int is_debug = 0;

	if (lua_istable(L, 5)){
		lua_pushstring(L, "adapter");
		if (LUA_TNUMBER == lua_gettable(L, 5)) {
			adapter_index = luaL_optinteger(L, -1, network_register_get_default());
		}else{
			adapter_index = network_register_get_default();
		}
		lua_pop(L, 1);

		lua_pushstring(L, "timeout");
		if (LUA_TNUMBER == lua_gettable(L, 5)) {
			http_ctrl->timeout = luaL_optinteger(L, -1, 0);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "dst");
		if (LUA_TSTRING == lua_gettable(L, 5)) {
			const char *dst = luaL_checklstring(L, -1, &len);
			http_ctrl->dst = luat_heap_malloc(len + 1);
			memset(http_ctrl->dst, 0, len + 1);
			memcpy(http_ctrl->dst, dst, len);
			http_ctrl->is_download = 1;
		}
		lua_pop(L, 1);

		lua_pushstring(L, "debug");
		if (LUA_TBOOLEAN == lua_gettable(L, 5)) {
			is_debug = lua_toboolean(L, -1);
		}
		lua_pop(L, 1);

#ifdef LUAT_USE_FOTA
		http_ctrl->address = 0xffffffff;
		http_ctrl->length = 0;
		lua_pushstring(L, "fota");
		int type = lua_gettable(L, 5);
		if (LUA_TBOOLEAN == type) {
			http_ctrl->isfota = lua_toboolean(L, -1);
		}else if (LUA_TTABLE == type) {
			http_ctrl->isfota = 1;
			lua_pushstring(L, "address");
			if (LUA_TNUMBER == lua_gettable(L, -2)) {
				http_ctrl->address = luaL_checkinteger(L, -1);
			}
			lua_pop(L, 1);
			lua_pushstring(L, "length");
			if (LUA_TNUMBER == lua_gettable(L, -2)) {
				http_ctrl->length = luaL_checkinteger(L, -1);
			}
			lua_pop(L, 1);
			lua_pushstring(L, "param1");
			if (LUA_TUSERDATA == lua_gettable(L, -2)) {
				http_ctrl->spi_device = (luat_spi_device_t*)lua_touserdata(L, -1);
			}
			lua_pop(L, 1);
		}
		lua_pop(L, 1);
#endif
		lua_pushstring(L, "ipv6");
		if (LUA_TBOOLEAN == lua_gettable(L, 5) && lua_toboolean(L, -1)) {
			use_ipv6 = 1;
		}
		lua_pop(L, 1);

		lua_pushstring(L, "callback");
		if (LUA_TFUNCTION == lua_gettable(L, 5)) {
			http_ctrl->http_cb = (void*)luaL_ref(L, LUA_REGISTRYINDEX);
		}

		if (http_ctrl->http_cb){
			lua_pushstring(L, "userdata");
			lua_gettable(L, 5);
			http_ctrl->http_cb_userdata = (void*)luaL_ref(L, LUA_REGISTRYINDEX);
		}
	}else{
		adapter_index = network_register_get_default();
	}
#ifdef LUAT_USE_FOTA
	if (http_ctrl->isfota == 1 && http_ctrl->is_download == 1){
		LLOGE("Only one can be selected for FOTA and Download");
		goto error;
	}
#endif
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		LLOGE("bad network adapter index %d", adapter_index);
		goto error;
	}

	http_ctrl->netc = network_alloc_ctrl((uint8_t)adapter_index);
	if (!http_ctrl->netc){
		LLOGE("netc create fail");
		goto error;
	}
	#ifdef LUAT_USE_FOTA
	if (http_ctrl->timeout < 1000 && http_ctrl->isfota) {
		http_ctrl->timeout = HTTP_TIMEOUT * 2;
	}
	#endif
	if (http_ctrl->timeout < 1000) {
		if (http_ctrl->is_download) {
			http_ctrl->timeout = HTTP_TIMEOUT;
		}
		else {
			http_ctrl->timeout = 60*1000;
		}
	}
	LLOGD("http action timeout %dms", http_ctrl->timeout);

    luat_http_client_init(http_ctrl, use_ipv6);
	http_ctrl->netc->is_debug = (uint8_t)is_debug;
	http_ctrl->debug_onoff = (uint8_t)is_debug;
	const char *method = luaL_optlstring(L, 1, "GET", &len);
	if (len > 11) {
		LLOGE("method is too long %s", method);
		goto error;
	}
	// memcpy(http_ctrl->method, method, len + 1);
	// LLOGD("method:%s",http_ctrl->method);

	if (strcmp("POST", method) == 0 || strcmp("PUT", method) == 0){
		http_ctrl->is_post = 1;
	}
	
	const char *url = luaL_checklstring(L, 2, &len);
	// http_ctrl->url = luat_heap_malloc(len + 1);
	// memset(http_ctrl->url, 0, len + 1);
	// memcpy(http_ctrl->url, url, len);
    

	int ret = http_set_url(http_ctrl, url, method);
	if (ret){
		goto error;
	}

	// LLOGD("http_ctrl->url:%s",http_ctrl->url);
#ifndef LUAT_USE_TLS
		if (http_ctrl->is_tls){
			LLOGE("NOT SUPPORT TLS");
			goto error;
		}
#endif

	if (lua_istable(L, 3)) {
		lua_pushnil(L);
		while (lua_next(L, 3) != 0) {
			const char *name = lua_tostring(L, -2);
			const char *value = lua_tostring(L, -1);
			if (!strcmp("Host", name) || !strcmp("host", name)) {
				http_ctrl->custom_host = 1;
			}
			if (strcmp("Content-Length", name)) {
				http_add_header(http_ctrl,name,value);
			}
			lua_pop(L, 1);
		}
	}
	if (lua_isstring(L, 4)) {
		const char *body = luaL_checklstring(L, 4, &(http_ctrl->req_body_len));
		http_ctrl->req_body = luat_heap_malloc((http_ctrl->req_body_len) + 1);
		// TODO 检测req_body是否为NULL 
		memset(http_ctrl->req_body, 0, (http_ctrl->req_body_len) + 1);
		memcpy(http_ctrl->req_body, body, (http_ctrl->req_body_len));
		snprintf_(body_len, 16,"%d",(http_ctrl->req_body_len));
		http_add_header(http_ctrl,"Content-Length",body_len);
	}else if(lua_isuserdata(L, 4)){//zbuff
		http_ctrl->zbuff_body = ((luat_zbuff_t *)luaL_checkudata(L, 4, LUAT_ZBUFF_TYPE));
		if (http_ctrl->is_post){
			snprintf_(body_len, 16,"%d",(http_ctrl->zbuff_body->used));
			http_add_header(http_ctrl,"Content-Length",body_len);
		}
	}

    // TODO 对 req_header进行realloc

	if (http_ctrl->is_tls){
		if (lua_isstring(L, 6)){
			server_cert = luaL_checklstring(L, 6, &server_cert_len);
		}
		if (lua_isstring(L, 7)){
			client_cert = luaL_checklstring(L, 7, &client_cert_len);
		}
		if (lua_isstring(L, 8)){
			client_key = luaL_checklstring(L, 8, &client_key_len);
		}
		if (lua_isstring(L, 9)){
			client_password = luaL_checklstring(L, 9, &client_password_len);
		}
		network_init_tls(http_ctrl->netc, (server_cert || client_cert)?2:0);
		if (server_cert){
			network_set_server_cert(http_ctrl->netc, (const unsigned char *)server_cert, server_cert_len+1);
		}
		if (client_cert){
			network_set_client_cert(http_ctrl->netc, (const unsigned char *)client_cert, client_cert_len+1,
					(const unsigned char *)client_key, client_key_len+1,
					(const unsigned char *)client_password, client_password_len+1);
		}
	}else{
		network_deinit_tls(http_ctrl->netc);
	}

	network_set_ip_invaild(&http_ctrl->ip_addr);
	http_ctrl->idp = luat_pushcwait(L);

    if (luat_http_client_start_luatos(http_ctrl)) {
        goto error;
    }
    return 1;
error:
	// if (http_ctrl->timeout_timer){
	// 	luat_stop_rtos_timer(http_ctrl->timeout_timer);
	// }
	http_close(http_ctrl);
    lua_pushinteger(L,HTTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 1;
}

#include "rotable2.h"
const rotable_Reg_t reg_http[] =
{
	{"request",			ROREG_FUNC(l_http_request)},
	{ NULL,             ROREG_INT(0)}
};

const rotable_Reg_t reg_http_emtry[] =
{
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_http( lua_State *L ) {
#ifdef LUAT_USE_NETWORK
    luat_newlib2(L, reg_http);
#else
    luat_newlib2(L, reg_http_emtry);
	LLOGE("reg_http require network enable!!");
#endif
    lua_pushvalue(L, -1);
    lua_setglobal(L, "http2"); 
    return 1;
}

//------------------------------------------------------
int32_t l_http_callback(lua_State *L, void* ptr){
	(void)ptr;
	char* temp;
	char* header;
	char* value;
	uint16_t header_len = 0,value_len = 0;

    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)msg->ptr;
	uint64_t idp = http_ctrl->idp;
	if (http_ctrl->timeout_timer){
		luat_stop_rtos_timer(http_ctrl->timeout_timer);
		luat_release_rtos_timer(http_ctrl->timeout_timer);
		http_ctrl->timeout_timer = NULL;
	}
	LLOGD("l_http_callback arg1:%d is_download:%d idp:%d",msg->arg1,http_ctrl->is_download,idp);
	if (msg->arg1!=0 && msg->arg1!=HTTP_ERROR_FOTA ){
		if (msg->arg1 == HTTP_CALLBACK){
			lua_geti(L, LUA_REGISTRYINDEX, (int)http_ctrl->http_cb);
			// int userdata_type = lua_type(L, -2);
			if (lua_isfunction(L, -1)) {
				lua_pushinteger(L, http_ctrl->resp_content_len);
				lua_pushinteger(L, msg->arg2);
				if (http_ctrl->http_cb_userdata){
					lua_geti(L, LUA_REGISTRYINDEX, (int)http_ctrl->http_cb_userdata);
					lua_call(L, 3, 0);
				}else{
					lua_call(L, 2, 0);
				}
			}
			return 0;
		}else{
			lua_pushinteger(L, msg->arg1); // 把错误码返回去
			luat_cbcwait(L, idp, 1);
			goto exit;
		}
	}
	
	lua_pushinteger(L, msg->arg1==HTTP_ERROR_FOTA?HTTP_ERROR_FOTA:http_ctrl->parser.status_code);
	lua_newtable(L);
	// LLOGD("http_ctrl->headers:%.*s",http_ctrl->headers_len,http_ctrl->headers);
	header = http_ctrl->headers;
	while ( (http_ctrl->headers_len)>0 ){
		value = strstr(header,":")+1;
		if (value[1]==' '){
			value++;
		}
		temp = strstr(value,"\r\n")+2;
		header_len = (uint16_t)(value-header)-1;
		value_len = (uint16_t)(temp-value)-2;
		LLOGD("header:%.*s",header_len,header);
		LLOGD("value:%.*s",value_len,value);
		lua_pushlstring(L, header,header_len);
		lua_pushlstring(L, value,value_len);
		lua_settable(L, -3);
		http_ctrl->headers_len -= temp-header;
		header = temp;
	}
	// LLOGD("http_ctrl->body:%.*s len:%d",http_ctrl->body_len,http_ctrl->body,http_ctrl->body_len);
	// 处理body, 需要区分下载模式和非下载模式
	if (http_ctrl->is_download) {
		// 下载模式
		if (http_ctrl->fd == NULL) {
			// 下载操作一切正常, 返回长度
			lua_pushinteger(L, http_ctrl->body_len);
			luat_cbcwait(L, idp, 3); // code, headers, body
			goto exit;
		}else if (http_ctrl->fd != NULL) {
			// 下载中断了!!
			luat_fs_fclose(http_ctrl->fd);
			luat_fs_remove(http_ctrl->dst); // 移除文件
		}
		// 下载失败, 返回错误码
		lua_pushinteger(L, -1);
		luat_cbcwait(L, idp, 3); // code, headers, body
		goto exit;
	}
#ifdef LUAT_USE_FOTA
	else if(http_ctrl->isfota && http_ctrl->parser.status_code == 200){
		lua_pushinteger(L, http_ctrl->body_len);
		luat_cbcwait(L, idp, 3); // code, headers, body
	}
#endif
	else if (http_ctrl->zbuff_body) {
		lua_pushinteger(L, http_ctrl->body_len);
		luat_cbcwait(L, idp, 3); // code, headers, body
	}
	else {
		// 非下载模式
		lua_pushlstring(L, http_ctrl->body, http_ctrl->body_len);
		luat_cbcwait(L, idp, 3); // code, headers, body
	}
exit:
	if (http_ctrl->http_cb){
		luaL_unref(L, LUA_REGISTRYINDEX, (int)http_ctrl->http_cb);
		http_ctrl->http_cb = 0;
		if (http_ctrl->http_cb_userdata){
			luaL_unref(L, LUA_REGISTRYINDEX, (int)http_ctrl->http_cb_userdata);
			http_ctrl->http_cb_userdata = 0;
		}
	}
	http_close(http_ctrl);
	return 0;
}

void luat_http_client_onevent(luat_http_ctrl_t *http_ctrl, int error_code, int arg) {
	// network_close(http_ctrl->netc, 0);
	if (!http_ctrl->luatos_mode) return;
	rtos_msg_t msg = {0};
	msg.handler = l_http_callback;
	msg.ptr = http_ctrl;
	msg.arg1 = error_code;
	msg.arg2 = arg;
	luat_msgbus_put(&msg, 0);
}
