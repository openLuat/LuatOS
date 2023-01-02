/*
@module  http
@summary http 客户端
@version 1.0
@date    2022.09.05
@demo    socket
@tag LUAT_USE_HTTP
@usage
-- 使用http库,需要引入sysplus库, 且需要在task内使用
require "sys"
require "sysplus"

sys.taskInit(function()
	sys.wait(1000)
	local code,headers,body = http.request("GET", "http://www.example.com/abc").wait()
	log.info("http", code, body)
end)

*/

#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "http_parser.h"

#include "luat_http.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

#define HTTP_DEBUG 0
#if HTTP_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

static void http_send_message(luat_http_ctrl_t *http_ctrl);

static int http_close(luat_http_ctrl_t *http_ctrl){
	LLOGD("http close %p", http_ctrl);
	if (http_ctrl->netc){
		network_force_close_socket(http_ctrl->netc);
		network_release_ctrl(http_ctrl->netc);
	}
	if (http_ctrl->host){
		luat_heap_free(http_ctrl->host);
	}
	if (http_ctrl->url){
		luat_heap_free(http_ctrl->url);
	}
	if (http_ctrl->uri){
		luat_heap_free(http_ctrl->uri);
	}
	if (http_ctrl->req_header){
		luat_heap_free(http_ctrl->req_header);
	}
	if (http_ctrl->req_body){
		luat_heap_free(http_ctrl->req_body);
	}
	if (http_ctrl->dst){
		luat_heap_free(http_ctrl->dst);
	}
	if (http_ctrl->headers){
		luat_heap_free(http_ctrl->headers);
	}
	if (http_ctrl->body){
		luat_heap_free(http_ctrl->body);
	}
	luat_heap_free(http_ctrl);
	return 0;
}

static int32_t l_http_callback(lua_State *L, void* ptr){
	char* temp;
	char* header;
	char* value;
	uint16_t header_len = 0,value_len = 0;

    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)msg->ptr;
	uint64_t idp = http_ctrl->idp;

	LLOGD("l_http_callback arg1:%d is_download:%d idp:%d",msg->arg1,http_ctrl->is_download,idp);
	if (msg->arg1){
		lua_pushinteger(L, msg->arg1); // 把错误码返回去
		luat_cbcwait(L, idp, 1);
		goto exit;
	}

	lua_pushinteger(L, http_ctrl->parser.status_code);
	lua_newtable(L);
	// LLOGD("http_ctrl->headers:%.*s",http_ctrl->headers_len,http_ctrl->headers);
	header = http_ctrl->headers;
	while ( (http_ctrl->headers_len)>0 ){
		value = strstr(header,":")+1;
		if (value[1]==' '){
			value++;
		}
		temp = strstr(value,"\r\n")+2;
		header_len = value-header-1;
		value_len = temp-value-2;
		// LLOGD("header:%.*s",header_len,header);
		// LLOGD("value:%.*s",value_len,value);
		lua_pushlstring(L, header,header_len);
		lua_pushlstring(L, value,value_len);
		lua_settable(L, -3);
		http_ctrl->headers_len -= temp-header;
		header = temp;
	}
	LLOGD("http_ctrl->body:%.*s len:%d",http_ctrl->body_len,http_ctrl->body,http_ctrl->body_len);
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
	} else {
		// 非下载模式
		lua_pushlstring(L, http_ctrl->body, http_ctrl->body_len);
		luat_cbcwait(L, idp, 3); // code, headers, body
	}
exit:
	http_close(http_ctrl);
	return 0;
}

static void http_resp_error(luat_http_ctrl_t *http_ctrl, int error_code) {
	LLOGD("http_resp_error error_code:%d close_state:%d",error_code,http_ctrl->close_state);
	if (http_ctrl->close_state == 0 && http_ctrl->headers_complete && http_ctrl->re_request_count < HTTP_RE_REQUEST_MAX){
		http_ctrl->re_request_count++;
#ifdef LUAT_USE_LWIP
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), (0xff == http_ctrl->ip_addr.type)?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
#else
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), (0xff == http_ctrl->ip_addr.is_ipv6)?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
#endif
			goto error;
		}
	}else if (http_ctrl->close_state==0){
error:
		http_ctrl->close_state=1;
		network_close(http_ctrl->netc, 0);
		rtos_msg_t msg = {0};
		msg.handler = l_http_callback;
		msg.ptr = http_ctrl;
		msg.arg1 = error_code;
		luat_msgbus_put(&msg, 0);
	}
}

static int on_message_begin(http_parser* parser){
	LLOGD("on_message_begin");
    return 0;
}

static int on_url(http_parser* parser, const char *at, size_t length){
	LLOGD("on_url:%.*s",length,at);
    return 0;
}

static int on_status(http_parser* parser, const char *at, size_t length){
    LLOGD("on_status:%.*s",length,at);
    return 0;
}

static int on_header_field(http_parser* parser, const char *at, size_t length){
    LLOGD("on_header_field:%.*s",length,at);
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	if (http_ctrl->headers_complete){
		return 0;
	}
	// if(!strncasecmp(at, "Content-Length: ", 16)){
	// 	http_ctrl->resp_content_len = -1;
	// }
	if (!http_ctrl->headers){
		http_ctrl->headers = luat_heap_malloc(length+2);
	}else{
		http_ctrl->headers = luat_heap_realloc(http_ctrl->headers,http_ctrl->headers_len+length+2);
	}
	memcpy(http_ctrl->headers+http_ctrl->headers_len,at,length);
	memcpy(http_ctrl->headers+http_ctrl->headers_len+length, ":", 1);
	http_ctrl->headers_len += length+1;
    return 0;
}
	
static int on_header_value(http_parser* parser, const char *at, size_t length){
    LLOGD("on_header_value:%.*s",length,at);
	char tmp[16] = {0};
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	if (http_ctrl->headers_complete){
		return 0;
	}
	// if(http_ctrl->resp_content_len == -1){
	// 	memcpy(tmp, at, length);
	// 	http_ctrl->resp_content_len = atoi(tmp);
	// 	LLOGD("http_ctrl->resp_content_len:%d",http_ctrl->resp_content_len);
	// }
	http_ctrl->headers = luat_heap_realloc(http_ctrl->headers,http_ctrl->headers_len+length+3);
	memcpy(http_ctrl->headers+http_ctrl->headers_len,at,length);
	memcpy(http_ctrl->headers+http_ctrl->headers_len+length, "\r\n", 2);
	http_ctrl->headers_len += length+2;
    return 0;
}

static int on_headers_complete(http_parser* parser){
    LLOGD("on_headers_complete");
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	if (http_ctrl->headers_complete){
		return 0;
	}
	http_ctrl->headers[http_ctrl->headers_len] = 0x00;
	if (http_ctrl->is_download){
		luat_fs_remove(http_ctrl->dst);
		http_ctrl->fd = luat_fs_fopen(http_ctrl->dst, "w+");
		if (http_ctrl->fd == NULL) {
			LLOGE("open download file fail %s", http_ctrl->dst);
		}
	}
	http_ctrl->headers_complete = 1;
    return 0;
}

static int on_body(http_parser* parser, const char *at, size_t length){
	LLOGD("on_body:%.*s",length,at);
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;

	if (http_ctrl->is_download){
		if (http_ctrl->fd == NULL){
			luat_fs_remove(http_ctrl->dst);
			http_ctrl->fd = luat_fs_fopen(http_ctrl->dst, "w+");
			if (http_ctrl->fd == NULL) {
				LLOGE("open download file fail %s", http_ctrl->dst);
				http_resp_error(http_ctrl, HTTP_ERROR_DOWNLOAD);
				return -1;
			}
		}
		luat_fs_fwrite(at, length, 1, http_ctrl->fd);
	}else{
		if (!http_ctrl->body){
			http_ctrl->body = luat_heap_malloc(length+1);
		}else{
			http_ctrl->body = luat_heap_realloc(http_ctrl->body,http_ctrl->body_len+length+1);
		}
		memcpy(http_ctrl->body+http_ctrl->body_len,at,length);
	}
	http_ctrl->body_len += length;
    return 0;
}

static int on_message_complete(http_parser* parser){
    LLOGD("on_message_complete");
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	// http_ctrl->body[http_ctrl->body_len] = 0x00;
	if (http_ctrl->fd != NULL) {
		luat_fs_fclose(http_ctrl->fd);
		http_ctrl->fd = NULL;
	}
	LLOGD("status_code:%d",parser->status_code);
	LLOGD("content_length:%lld",parser->content_length);
	http_ctrl->close_state = 1;
	network_close(http_ctrl->netc, 0);
	rtos_msg_t msg = {0};
    msg.handler = l_http_callback;
	msg.ptr = http_ctrl;
	msg.arg1 = HTTP_OK;
	luat_msgbus_put(&msg, 0);
    return 0;
}

static int on_chunk_header(http_parser* parser){
	LLOGD("on_chunk_header");
	LLOGD("content_length:%lld",parser->content_length);
	// luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	// http_ctrl->is_chunk = 1;
    return 0;
}

// static int on_chunk_complete(http_parser* parser){
// 	// LLOGD("on_chunk_complete CALL on_message_complete");
// 	// on_message_complete(parser);
//     return 0;
// }


static uint32_t http_send(luat_http_ctrl_t *http_ctrl, uint8_t* data, size_t len) {
	if (len == 0)
		return 0;
	uint32_t tx_len = 0;
	// LLOGD("http_send data:%.*s",len,data);
	network_tx(http_ctrl->netc, data, len, 0, NULL, 0, &tx_len, 0);
	return tx_len;
}

static void http_send_message(luat_http_ctrl_t *http_ctrl){
	uint32_t tx_len = 0;
	// 发送请求行
	snprintf_(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX, "%s %s HTTP/1.1\r\n", http_ctrl->method, http_ctrl->uri);
	http_send(http_ctrl, http_ctrl->request_message, strlen(http_ctrl->request_message));
	// 强制添加host. TODO 判断自定义headers是否有host
	snprintf_(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX,  "Host: %s\r\n", http_ctrl->host);
	http_send(http_ctrl, http_ctrl->request_message, strlen(http_ctrl->request_message));

	if (http_ctrl->headers_complete){
		snprintf_(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX,  "Range: bytes=%d-\r\n", http_ctrl->body_len+1);
		http_send(http_ctrl, http_ctrl->request_message, strlen(http_ctrl->request_message));
	}
	
	// 发送自定义头部
	if (http_ctrl->req_header){
		http_send(http_ctrl, http_ctrl->req_header, strlen(http_ctrl->req_header));
	}

	// 结束头部
	http_send(http_ctrl, "\r\n", 2);
	// 发送body
	if (http_ctrl->req_body){
		http_send(http_ctrl, http_ctrl->req_body, http_ctrl->req_body_len);
	}
	//--------------------------------------------
	// 清理资源
	if (http_ctrl->host){
		luat_heap_free(http_ctrl->host);
		http_ctrl->host = NULL;
	}
	if (http_ctrl->url){
		luat_heap_free(http_ctrl->url);
		http_ctrl->url = NULL;
	}
	if (http_ctrl->uri){
		luat_heap_free(http_ctrl->uri);
		http_ctrl->uri = NULL;
	}
	if (http_ctrl->req_header){
		luat_heap_free(http_ctrl->req_header);
		http_ctrl->req_header = NULL;
	}
	if (http_ctrl->req_body){
		luat_heap_free(http_ctrl->req_body);
		http_ctrl->req_body = NULL;
		http_ctrl->req_body_len = 0;
	}
}

static int32_t luat_lib_http_callback(void *data, void *param){
	OS_EVENT *event = (OS_EVENT *)data;
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)param;
	int ret = 0;
	// LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	// LLOGD("luat_lib_http_callback %d %d",event->ID & 0x0fffffff,event->Param1);
	if (event->Param1){
		LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
		LLOGE("luat_lib_http_callback http_ctrl close %d %d",event->ID & 0x0fffffff,event->Param1);
		http_resp_error(http_ctrl, HTTP_ERROR_CLOSE);
		return -1;
	}
	if (event->ID == EV_NW_RESULT_LINK){
		return 0;
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		http_send_message(http_ctrl);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t total_len = 0;
		uint32_t rx_len = 0;
		int result = network_rx(http_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
		// LLOGD("result:%d total_len:%d",result,total_len);
		if (0 == result){
			if (total_len>0){
				char* resp_buff = luat_heap_malloc(total_len + 1);
				resp_buff[total_len] = 0x00;
next:
				result = network_rx(http_ctrl->netc, resp_buff, total_len, 0, NULL, NULL, &rx_len);
				LLOGD("result:%d rx_len:%d",result,rx_len);
				LLOGD("resp_buff:%.*s len:%d",total_len,resp_buff,total_len);
				if (result)
					goto next;
				if (rx_len == 0||result!=0) {
					luat_heap_free(resp_buff);
					http_resp_error(http_ctrl, HTTP_ERROR_RX);
					return -1;
				}
				
				int nParseBytes = http_parser_execute(&http_ctrl->parser, &http_ctrl->parser_settings, resp_buff, total_len);
				LLOGD("nParseBytes %d total_len %d", nParseBytes, total_len);
				
				luat_heap_free(resp_buff);
				if (nParseBytes != total_len){
					http_resp_error(http_ctrl, HTTP_ERROR_RX);
					return -1;
				}
				if (http_ctrl->close_state){
					return 0;
				}
			}
		}else{
			http_resp_error(http_ctrl, HTTP_ERROR_RX);
			return -1;
		}
	}else if(event->ID == EV_NW_RESULT_TX){

	}else if(event->ID == EV_NW_RESULT_CLOSE){
		// http_close(http_ctrl);
		return 0;
	}
	ret = network_wait_event(http_ctrl->netc, NULL, 0, NULL);
	LLOGD("network_wait_event %d", ret);
	if (ret < 0){
		http_resp_error(http_ctrl, HTTP_ERROR_CLOSE);
		return -1;
	}
    return 0;
}

static int http_add_header(luat_http_ctrl_t *http_ctrl, const char* name, const char* value){
	// LLOGD("http_add_header name:%s value:%s",name,value);
	// TODO 对value还需要进行urlencode
	strncat(http_ctrl->req_header, name, strlen(name));
	strncat(http_ctrl->req_header, ":", 1);
	strncat(http_ctrl->req_header, value, strlen(value));
	strncat(http_ctrl->req_header, "\r\n", 2);
	// LLOGD("http_ctrl->req_header:%s",http_ctrl->req_header);
}

static int http_set_url(luat_http_ctrl_t *http_ctrl) {
	char *tmp = http_ctrl->url;
    if (!strncmp("https://", http_ctrl->url, strlen("https://"))) {
        http_ctrl->is_tls = 1;
        tmp += strlen("https://");
    }
    else if (!strncmp("http://", http_ctrl->url, strlen("http://"))) {
        http_ctrl->is_tls = 0;
        tmp += strlen("http://");
    }
    else {
        LLOGI("only http/https supported %s", http_ctrl->url);
        return -1;
    }

	int tmplen = strlen(tmp);
	if (tmplen < 5) {
        LLOGI("url too short %s", http_ctrl->url);
        return -1;
    }
	char tmphost[256] = {0};
    char *tmpuri = NULL;
    for (size_t i = 0; i < tmplen; i++){
        if (tmp[i] == '/') {
			if (i > 255) {
				LLOGI("host too long %s", http_ctrl->url);
				return -1;
			}
            tmpuri = tmp + i;
            break;
        }else if(i == tmplen-1){
			tmphost[i+2] = '/';
			tmpuri = tmp + i+1;
		}
		tmphost[i] = tmp[i];
    }
	if (strlen(tmphost) < 1) {
        LLOGI("host not found %s", http_ctrl->url);
        return -1;
    }
    if (strlen(tmpuri) == 0) {
        tmpuri = "/";
    }
    // LLOGD("tmphost:%s",tmphost);
	// LLOGD("tmpuri:%s",tmpuri);
    for (size_t i = 1; i < strlen(tmphost); i++){
		if (tmphost[i] == ':') {
			tmphost[i] = '\0';
			http_ctrl->remote_port = atoi(tmphost + i + 1);
			break;
		}
    }
    if (http_ctrl->remote_port <= 0) {
        if (http_ctrl->is_tls)
            http_ctrl->remote_port = 443;
        else
            http_ctrl->remote_port = 80;
    }

    http_ctrl->host = luat_heap_malloc(strlen(tmphost) + 1);
    if (http_ctrl->host == NULL) {
        LLOGE("out of memory when malloc host");
        return -1;
    }
    memcpy(http_ctrl->host, tmphost, strlen(tmphost) + 1);

    http_ctrl->uri = luat_heap_malloc(strlen(tmpuri) + 1);
    if (http_ctrl->uri == NULL) {
        LLOGE("out of memory when malloc url");
        return -1;
    }
    memcpy(http_ctrl->uri, tmpuri, strlen(tmpuri) + 1);

	// LLOGD("http_ctrl->uri:%s",http_ctrl->uri);
	// LLOGD("http_ctrl->host:%s",http_ctrl->host);
	// LLOGD("http_ctrl->port:%d",http_ctrl->remote_port);
	return 0;
}

/*
http客户端
@api http.request(method,url,headers,body,opts,ca_file)
@string 请求方法, 支持 GET/POST
@string url地址
@tabal  请求头 可选 例如{["Content-Type"] = "application/x-www-form-urlencoded"}
@string body 可选
@table  额外配置 可选 包含dst:下载路径,可选 adapter:选择使用网卡,可选 debug:是否打开debug信息,可选
@string 服务器ca证书数据
@string 客户端ca证书数据
@string 客户端私钥加密数据
@string 客户端私钥口令数据
@return int code
@return tabal headers
@return string body
@usage
-- GET请求
local code, headers, body = http.request("GET","http://site0.cn/api/httptest/simple/time").wait()
log.info("http.get", code, headers, body)
-- POST请求
local code, headers, body = http.request("POST","http://httpbin.com/post", {}, "abc=123").wait()
log.info("http.post", code, headers, body)

-- GET请求,但下载到文件
local code, headers, body = http.request("GET","http://httpbin.com/", {}, "", {dst="/data.bin"}).wait()
log.info("http.get", code, headers, body)
*/
static int l_http_request(lua_State *L) {
	size_t server_cert_len,client_cert_len, client_key_len, client_password_len,len;
	const char *server_cert = NULL;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	int adapter_index = -1;
	char body_len[6] = {0};
	// mbedtls_debug_set_threshold(4);
	luat_http_ctrl_t *http_ctrl = (luat_http_ctrl_t *)luat_heap_malloc(sizeof(luat_http_ctrl_t));
	if (!http_ctrl){
		LLOGE("out of memory when malloc http_ctrl");
        lua_pushinteger(L,HTTP_ERROR_CONNECT);
		luat_pushcwait_error(L,1);
		return 1;
	}
	memset(http_ctrl, 0, sizeof(luat_http_ctrl_t));

	if (lua_istable(L, 5)){
		lua_pushstring(L, "adapter");
		if (LUA_TNUMBER == lua_gettable(L, 5)) {
			adapter_index = luaL_optinteger(L, -1, network_get_last_register_adapter());
		}else{
			adapter_index = network_get_last_register_adapter();
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
			http_ctrl->netc->is_debug = lua_toboolean(L, -1);
		}
		lua_pop(L, 1);

	}else{
		adapter_index = network_get_last_register_adapter();
	}

	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		LLOGD("bad network adapter index %d", adapter_index);
		goto error;
	}


	http_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!http_ctrl->netc){
		LLOGE("netc create fail");
		goto error;
	}
	network_init_ctrl(http_ctrl->netc, NULL, luat_lib_http_callback, http_ctrl);


	network_set_base_mode(http_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(http_ctrl->netc, 0);


    http_parser_init(&http_ctrl->parser, HTTP_RESPONSE);
	http_ctrl->parser.data = http_ctrl;

    http_parser_settings_init(&http_ctrl->parser_settings);
    // http_ctrl->parser_settings.on_message_begin = on_message_begin;
    // http_ctrl->parser_settings.on_url = on_url;
    // http_ctrl->parser_settings.on_status = on_status;
    http_ctrl->parser_settings.on_header_field = on_header_field;
    http_ctrl->parser_settings.on_header_value = on_header_value;
    http_ctrl->parser_settings.on_headers_complete = on_headers_complete;
    http_ctrl->parser_settings.on_body = on_body;
    http_ctrl->parser_settings.on_message_complete = on_message_complete;
	http_ctrl->parser_settings.on_chunk_header = on_chunk_header;
	// http_ctrl->parser_settings.on_chunk_complete = on_chunk_complete;


	const char *method = luaL_optlstring(L, 1, "GET", &len);
	if (len > 11) {
		LLOGE("method is too long %s", method);
		goto error;
	}
	memcpy(http_ctrl->method, method, len + 1);
	// LLOGD("method:%s",http_ctrl->method);

	const char *url = luaL_checklstring(L, 2, &len);
	http_ctrl->url = luat_heap_malloc(len + 1);
	memset(http_ctrl->url, 0, len + 1);
	memcpy(http_ctrl->url, url, len);

	// LLOGD("http_ctrl->url:%s",http_ctrl->url);

	http_ctrl->req_header = luat_heap_malloc(HTTP_RESP_HEADER_MAX_SIZE);
	memset(http_ctrl->req_header, 0, HTTP_RESP_HEADER_MAX_SIZE);

	if (lua_istable(L, 3)) {
		lua_pushnil(L);
		while (lua_next(L, 3) != 0) {
			const char *name = lua_tostring(L, -2);
			const char *value = lua_tostring(L, -1);
			http_add_header(http_ctrl,name,value);
			lua_pop(L, 1);
		}
	}
	if (lua_isstring(L, 4)) {
		const char *body = luaL_checklstring(L, 4, &(http_ctrl->req_body_len));
		http_ctrl->req_body = luat_heap_malloc((http_ctrl->req_body_len) + 1);
		memset(http_ctrl->req_body, 0, (http_ctrl->req_body_len) + 1);
		memcpy(http_ctrl->req_body, body, (http_ctrl->req_body_len));
		snprintf_(body_len, 6,"%d",(http_ctrl->req_body_len));
		http_add_header(http_ctrl,"Content-Length",body_len);
	}
	// else{
	// 	http_add_header(http_ctrl,"Content-Length","0");
	// }

	int ret = http_set_url(http_ctrl);
	if (ret){
		goto error;
	}

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
			network_set_client_cert(http_ctrl->netc, client_cert, client_cert_len+1,
					client_key, client_key_len+1,
					client_password, client_password_len+1);
		}
	}else{
		network_deinit_tls(http_ctrl->netc);
	}

#ifdef LUAT_USE_LWIP
	http_ctrl->ip_addr.type = 0xff;
#else
	http_ctrl->ip_addr.is_ipv6 = 0xff;
#endif
	http_ctrl->idp = luat_pushcwait(L);

#ifdef LUAT_USE_LWIP
	if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), (0xff == http_ctrl->ip_addr.type)?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
#else
	if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), (0xff == http_ctrl->ip_addr.is_ipv6)?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
#endif
		network_close(http_ctrl->netc, 0);
		goto error;
	}
    return 1;
error:
	http_close(http_ctrl);
    lua_pushinteger(L,HTTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_http[] =
{
	{"request",			ROREG_FUNC(l_http_request)},
	{ NULL,             ROREG_INT(0)}
};

static const rotable_Reg_t reg_http_emtry[] =
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
