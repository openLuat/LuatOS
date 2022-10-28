/*
@module  http2
@summary http2客户端
@version 1.0
@date    2022.09.05
@demo network
*/

#include "luat_base.h"

#ifdef LUAT_USE_NETWORK

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

#define HTTP_REQUEST_BUF_LEN_MAX 1024
#define HTTP_RESP_HEADER_MAX_SIZE (4096)

#define HTTP_ERROR_STATE 	(-1)
#define HTTP_ERROR_HEADER 	(-2)
#define HTTP_ERROR_BODY 	(-3)
#define HTTP_ERROR_CONNECT 	(-4)
#define HTTP_ERROR_CLOSE 	(-5)
#define HTTP_ERROR_RX 		(-6)

typedef struct{
	network_ctrl_t *netc;		// http netc
	luat_ip_addr_t ip_addr;		// http ip
	uint8_t is_tls;             // 是否SSL
	const char *host; 			// http host
	uint16_t remote_port; 		// 远程端口号
	const char *url;
	const char *uri;
	const char *method;
	Buffer_Struct req_head_buf;
//	const char *req_header;
	const char *req_body;
	size_t req_body_len;
	const char *dst;
	uint8_t is_download;
	uint8_t request_message[HTTP_REQUEST_BUF_LEN_MAX];

	// 响应相关
	uint8_t resp_header_parsed;
	char* resp_headers;
	char *resp_buff;
	uint32_t resp_buff_len;
	uint32_t resp_content_len;
	FILE* fd;
	uint32_t fd_writed;
	uint8_t fd_ok;
	uint64_t idp;
	uint16_t timeout;
	uint8_t close_state;
}luat_http_ctrl_t;

static int http_close(luat_http_ctrl_t *http_ctrl){
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
	if (http_ctrl->method){
		luat_heap_free(http_ctrl->method);
	}
//	if (http_ctrl->req_header){
//		luat_heap_free(http_ctrl->req_header);
//	}
	if (http_ctrl->resp_headers){
		luat_heap_free(http_ctrl->resp_headers);
	}
	OS_DeInitBuffer(&http_ctrl->req_head_buf);
	if (http_ctrl->req_body){
		luat_heap_free(http_ctrl->req_body);
	}
	if (http_ctrl->dst){
		luat_heap_free(http_ctrl->dst);
	}
	if (http_ctrl->resp_buff){
		luat_heap_free(http_ctrl->resp_buff);
	}
	luat_heap_free(http_ctrl);
	return 0;
}

static int32_t l_http_callback(lua_State *L, void* ptr){
	char code[6] = {0};
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);

    luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)msg->ptr;
	uint64_t idp = http_ctrl->idp;

	// LLOGD("l_http_callback arg1:%d is_download:%d idp:%d",msg->arg1,http_ctrl->is_download,idp);
	if (msg->arg1){
		lua_pushinteger(L, msg->arg1); // 把错误码返回去
		luat_cbcwait(L, idp, 1);
		http_close(http_ctrl);
		return 0;
	}

	// 解析status code
	uint16_t code_offset = strlen("HTTP/1.x ");
	uint16_t code_len = 3;
	strncpy(code, http_ctrl->resp_headers+code_offset,code_len);
	lua_pushinteger(L, atoi(code));
	// 解析出header
	char *body_rec = http_ctrl->resp_headers + strlen(http_ctrl->resp_headers);
	lua_newtable(L);
	char* temp;
	char *header;
	char *value;
	uint16_t header_len,value_len;
	temp = strstr(http_ctrl->resp_headers,"\r\n")+2;
	while ( temp < body_rec){
		header = temp;
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
	}

	// 处理body, 需要区分下载模式和非下载模式
	if (http_ctrl->is_download) {
		// 下载模式
		if (http_ctrl->fd_ok) {
			// 下载操作一切正常, 返回长度
			lua_pushinteger(L, http_ctrl->resp_content_len);
			luat_cbcwait(L, idp, 3); // code, headers, body
			return 0;
		}
		if (http_ctrl->fd != NULL) {
			// 下载中断了!!
			luat_fs_fclose(http_ctrl->fd);
			luat_fs_remove(http_ctrl->dst); // 移除文件
		}
		// 下载失败, 返回错误码
		lua_pushinteger(L, -1);
		luat_cbcwait(L, idp, 3); // code, headers, body
		return 0;
	} else {
		// 非下载模式
		lua_pushlstring(L, http_ctrl->resp_buff, http_ctrl->resp_content_len);
		luat_cbcwait(L, idp, 3); // code, headers, body
	}
	http_close(http_ctrl);
	return 0;
}

static void http_resp_error(luat_http_ctrl_t *http_ctrl, int error_code) {
	if (http_ctrl->close_state==0){
		http_ctrl->close_state=1;
		network_close(http_ctrl->netc, 0);
		rtos_msg_t msg = {0};
		msg.handler = l_http_callback;
		msg.ptr = http_ctrl;
		msg.arg1 = error_code;
		luat_msgbus_put(&msg, 0);
	}
}

static void http_parse_resp_content_length(luat_http_ctrl_t *http_ctrl,uint32_t headers_len) {
	// LLOGD("http_parse_resp_content_length headers_len:%d",headers_len);
	http_ctrl->resp_content_len=0;
	char* temp;
	char *header;
	uint16_t header_len;
	temp = strstr(http_ctrl->resp_buff,"\r\n")+2;
	while ( temp < http_ctrl->resp_buff+headers_len){
		header = temp;
		temp = strstr(header,"\r\n")+2;
		header_len = temp-header-1;
		// LLOGD("header:%.*s",header_len,header);
		if(!strncasecmp(header, "Content-Length: ", 16)){
			char tmp[16] = {0};
			header += strlen("Content-Length: ");
			memcpy(tmp, header, temp - header-2); // TODO 还需要判断一下长度
			http_ctrl->resp_content_len = atoi(tmp);
			if (http_ctrl->resp_content_len < 0) {
				LLOGD("resp Content-Length not good, %s", tmp);
				http_ctrl->resp_content_len = 0;
			}
			break;
		}
	}
	// LLOGD("http_parse_resp_content_length Content-Length:%d",http_ctrl->resp_content_len);
}

static int http_resp_parse_header(luat_http_ctrl_t *http_ctrl) {
	if (strncmp("HTTP/1.", http_ctrl->resp_buff, strlen("HTTP/1."))){
		// 开头几个字节不是HTTP/1 ? 可以断开连接了
		LLOGW("resp NOT startwith HTTP/1.");
		http_resp_error(http_ctrl, HTTP_ERROR_STATE); // 非法响应
		return -1;
	}
	else {
		char* header_end = strstr(http_ctrl->resp_buff, "\r\n\r\n");
		if (header_end != NULL) {
			http_ctrl->resp_header_parsed = 1; // 肯定收到头部了, 可以处理了
			// 把body的位置先保存起来
			char* body_start = header_end + 4;
			// 分隔header与body
			header_end[2] = 0x00; // 将第二个\r设置为0, 预防Content-Length就是最后一个header
			http_parse_resp_content_length(http_ctrl,header_end-http_ctrl->resp_buff+2);
			http_ctrl->resp_headers = http_ctrl->resp_buff; // 留着解析全部header
			if (http_ctrl->resp_content_len > 0) {
				// 还有数据
				uint32_t header_size = (size_t)(body_start - http_ctrl->resp_headers);
				if (http_ctrl->resp_buff_len > header_size) {
					// 已经有部分/全部body数据了
					http_ctrl->resp_buff = luat_heap_malloc(http_ctrl->resp_buff_len - header_size);
					if (http_ctrl->resp_buff == NULL) {
						LLOGE("out of memory when malloc buff for http resp");
						http_resp_error(http_ctrl, HTTP_ERROR_HEADER); // 炸了
						return -1;
					}
					http_ctrl->resp_buff_len = http_ctrl->resp_buff_len - header_size;
					mempcpy(http_ctrl->resp_buff, header_end + 4, http_ctrl->resp_buff_len);
					// TODO 把http_ctrl->resp_headers进行realloc会不会好一些
				}
				else {
					http_ctrl->resp_buff = NULL;
					http_ctrl->resp_buff_len = 0;
				}
			}
			else {
				// 没有数据了,直接结束吧
				// 首先, 把headers指向当前buff, 为后续header table做保留
				// http_ctrl->resp_headers = http_ctrl->resp_buff;
				// 重置 resp 缓冲区, 因为没有数据,直接NULL就行
				http_ctrl->resp_buff = NULL;
				http_ctrl->resp_buff_len = 0;
			}
			return 0;
		}else {
			// 防御一下太大的header
			if (http_ctrl->resp_buff_len > HTTP_RESP_HEADER_MAX_SIZE) {
				LLOGW("http resp header too big!!!");
				http_resp_error(http_ctrl, HTTP_ERROR_HEADER); // 非法响应
				return -1;
			}
			else {
				// 数据不够, 头部也不齐, 等下一波的数据.
				// 后续还需要根据ticks判断一下timeout, 或者timer?
				return -2;
			}
		}
	}
}

static int http_read_packet(luat_http_ctrl_t *http_ctrl){
	if (http_ctrl->resp_header_parsed == 0) {
		if (http_ctrl->resp_buff_len < 10) {
			return 0; // 继续等头部. TODO 超时判断
		}
		int ret = http_resp_parse_header(http_ctrl);
		if (ret < 0) {
			LLOGE("http_resp_parse_header ret:%d",ret);
			return ret; // -2 未接收完 其他为出错
		}
		// 能到这里, 头部已经解析完成了
		// 如果是下载模式, 打开文件, 开始写
		if (http_ctrl->is_download) {
			luat_fs_remove(http_ctrl->dst);
			http_ctrl->fd = luat_fs_fopen(http_ctrl->dst, "w+");
			if (http_ctrl->fd == NULL) {
				LLOGE("open download file fail %s", http_ctrl->dst);
			}
		}
	}

	// 下面是body的处理了
	rtos_msg_t msg = {0};
    msg.handler = l_http_callback;
	msg.ptr = http_ctrl;
	msg.arg1 = 0;

	if (http_ctrl->is_download) {
		// 写数据
		if (http_ctrl->resp_buff_len > 0) {
			if (http_ctrl->fd != NULL) {
				luat_fs_fwrite(http_ctrl->resp_buff, http_ctrl->resp_buff_len, 1, http_ctrl->fd);
			}
			http_ctrl->fd_writed += http_ctrl->resp_buff_len;
			// 释放buff, 等待下一波数据
			http_ctrl->resp_buff_len = 0;
			luat_heap_free(http_ctrl->resp_buff);
			http_ctrl->resp_buff = NULL;
		}
		if (http_ctrl->fd_writed == http_ctrl->resp_content_len) {
			if (http_ctrl->fd != NULL) {
				luat_fs_fclose(http_ctrl->fd);
				http_ctrl->fd = NULL;
				http_ctrl->fd_ok = 1; // 标记成功
			}
			// 读完写完, 完结散花
			network_close(http_ctrl->netc, 0);
			http_ctrl->close_state=1;
			luat_msgbus_put(&msg, 0);
			return 0;
		}else if (http_ctrl->resp_buff_len > http_ctrl->resp_content_len){
			http_resp_error(http_ctrl, HTTP_ERROR_BODY);
			return -1;
		}
	}
	else { // 非下载模式, 等数据齐了就结束
		// LLOGD("resp_buff_len:%d resp_content_len:%d",http_ctrl->resp_buff_len,http_ctrl->resp_content_len);
		if (http_ctrl->resp_buff_len == http_ctrl->resp_content_len) {
			network_close(http_ctrl->netc, 0);
			http_ctrl->close_state=1;
			luat_msgbus_put(&msg, 0);
			return 0;
		}else if (http_ctrl->resp_buff_len > http_ctrl->resp_content_len){
			http_resp_error(http_ctrl, HTTP_ERROR_BODY);
			return -1;
		}
	}
	// 其他情况就是继续等数据, 后续还得判断timeout
	return 0;
}

static uint32_t http_send(luat_http_ctrl_t *http_ctrl, uint8_t* data, size_t len) {
	if (len == 0)
		return 0;
	uint32_t tx_len = 0;
	// LLOGD("http_send data:%.*s",len,data);
	network_tx(http_ctrl->netc, data, len, 0, http_ctrl->ip_addr.is_ipv6?NULL:&(http_ctrl->ip_addr), NULL, &tx_len, 0);
	return tx_len;
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
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), http_ctrl->ip_addr.is_ipv6?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
			// network_close(http_ctrl->netc, 0);
			http_resp_error(http_ctrl, HTTP_ERROR_CONNECT);
			return -1;
    	}
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		//memset(http_ctrl->request_message, 0, HTTP_REQUEST_BUF_LEN_MAX);
		uint32_t tx_len = 0;
		// 发送请求行
		snprintf_(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX, "%s %s HTTP/1.0\r\n", http_ctrl->method, http_ctrl->uri);
		http_send(http_ctrl, http_ctrl->request_message, strlen(http_ctrl->request_message));
		// 强制添加host. TODO 判断自定义headers是否有host
		snprintf_(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX,  "Host: %s\r\n", http_ctrl->host);
		http_send(http_ctrl, http_ctrl->request_message, strlen(http_ctrl->request_message));
		// 发送自定义头部
//		if (http_ctrl->req_header){
//			http_send(http_ctrl, http_ctrl->req_header, strlen(http_ctrl->req_header));
//		}
		if (http_ctrl->req_head_buf.Data) {
			http_send(http_ctrl, http_ctrl->req_head_buf.Data, http_ctrl->req_head_buf.Pos);
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
		if (http_ctrl->method){
			luat_heap_free(http_ctrl->method);
			http_ctrl->method = NULL;
		}
//		if (http_ctrl->req_header){
//			luat_heap_free(http_ctrl->req_header);
//			http_ctrl->req_header = NULL;
//		}
		OS_DeInitBuffer(&http_ctrl->req_head_buf);
		if (http_ctrl->req_body){
			luat_heap_free(http_ctrl->req_body);
			http_ctrl->req_body = NULL;
			http_ctrl->req_body_len = 0;
		}
		//------------------------------
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t total_len = 0;
		uint32_t rx_len = 0;
		int result = network_rx(http_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
		// LLOGD("result:%d total_len:%d",result,total_len);
		if (0 == result){
			if (total_len>0){
				if (0 == http_ctrl->resp_buff_len){
					http_ctrl->resp_buff = luat_heap_malloc(total_len + 1);
					http_ctrl->resp_buff[total_len] = 0x00;
				}else{
					http_ctrl->resp_buff = luat_heap_realloc(http_ctrl->resp_buff,http_ctrl->resp_buff_len+total_len+1);
					http_ctrl->resp_buff[http_ctrl->resp_buff_len+total_len] = 0x00;
				}
next:
				result = network_rx(http_ctrl->netc, http_ctrl->resp_buff+(http_ctrl->resp_buff_len), total_len, 0, NULL, NULL, &rx_len);
				// LLOGD("result:%d rx_len:%d",result,rx_len);
				if (result)
					goto next;
				if (rx_len == 0||result!=0) {
					http_resp_error(http_ctrl, HTTP_ERROR_RX);
					return -1;
				}
				http_ctrl->resp_buff_len += total_len;
				// LLOGD("http_ctrl->resp_buff:%.*s len:%d",http_ctrl->resp_buff_len,http_ctrl->resp_buff,http_ctrl->resp_buff_len);
				http_read_packet(http_ctrl);
			}
		}else{
			http_resp_error(http_ctrl, HTTP_ERROR_RX);
			return -1;
		}
	}else if(event->ID == EV_NW_RESULT_TX){

	}else if(event->ID == EV_NW_RESULT_CLOSE){

	}

	network_wait_event(http_ctrl->netc, NULL, 0, NULL);
    return 0;
}

static int http_add_header(luat_http_ctrl_t *http_ctrl, const char* name, const char* value){
	// LLOGD("http_add_header name:%s value:%s",name,value);
	// TODO 对value还需要进行urlencode
//	if (http_ctrl->req_header){
//		http_ctrl->req_header = luat_heap_realloc(http_ctrl->req_header, strlen(http_ctrl->req_header)+strlen(name)+strlen(value)+4);
//		strncat(http_ctrl->req_header, name, strlen(name));
//		strncat(http_ctrl->req_header, ":", 1);
//		strncat(http_ctrl->req_header, value, strlen(value));
//		strncat(http_ctrl->req_header, "\r\n", 2);
//	}else{
//		http_ctrl->req_header = luat_heap_malloc(strlen(name)+strlen(value)+4);
//		memset(http_ctrl->req_header, 0, strlen(name)+strlen(value)+4);
//		sprintf_(http_ctrl->req_header, "%s:%s\r\n", name,value);
//	}
	// LLOGD("http_ctrl->req_header:%s",http_ctrl->req_header);
	OS_BufferWrite(&http_ctrl->req_head_buf, name, strlen(name));
	OS_BufferWrite(&http_ctrl->req_head_buf, ":", 1);
	OS_BufferWrite(&http_ctrl->req_head_buf, value, strlen(value));
	OS_BufferWrite(&http_ctrl->req_head_buf, "\r\n", 2);
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
        if (tmp[i] == ":") {
            tmp[i] = 0x00;
            http_ctrl->remote_port = atoi(&tmp[i+1]);
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
http2客户端
@api http2.request(method,url,headers,body,opts,ca_file)
@string 请求方法, 支持 GET/POST
@string url地址
@tabal  请求头 可选 例如{["Content-Type"] = "application/x-www-form-urlencoded"}
@string body 可选
@tabal  额外配置 可选 包含dst:下载路径,可选 adapter:选择使用网卡,可选
@string 证书 可选
@return int code
@return tabal headers
@return string body
@usage
local code, headers, body = http2.request("GET","http://site0.cn/api/httptest/simple/time").wait()
log.info("http2.get", code, headers, body)
*/
static int l_http_request(lua_State *L) {
	size_t client_cert_len, client_key_len, client_password_len,len;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	int adapter_index;
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

	}else{
		adapter_index = network_get_last_register_adapter();
	}

	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		goto error;
	}


	http_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!http_ctrl->netc){
		LLOGE("netc create fail");
		goto error;
	}
	network_init_ctrl(http_ctrl->netc, NULL, luat_lib_http_callback, http_ctrl);

	http_ctrl->netc->is_debug = 1;
	network_set_base_mode(http_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(http_ctrl->netc, 0);

	const char *method = luaL_optlstring(L, 1, "GET", &len);
	http_ctrl->method = luat_heap_malloc(len + 1);
	memset(http_ctrl->method, 0, len + 1);
	memcpy(http_ctrl->method, method, len);
	// LLOGD("method:%s",http_ctrl->method);

	const char *url = luaL_checklstring(L, 2, &len);
	http_ctrl->url = luat_heap_malloc(len + 1);
	memset(http_ctrl->url, 0, len + 1);
	memcpy(http_ctrl->url, url, len);

	// LLOGD("http_ctrl->url:%s",http_ctrl->url);
	OS_InitBuffer(&http_ctrl->req_head_buf, 4096);
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
			client_cert = luaL_checklstring(L, 6, &client_cert_len);
		}
		if (lua_isstring(L, 7)){
			client_key = luaL_checklstring(L, 7, &client_key_len);
		}
		if (lua_isstring(L, 8)){
			client_password = luaL_checklstring(L, 8, &client_password_len);
		}
		network_init_tls(http_ctrl->netc, client_cert?2:0);
		if (client_cert){
			network_set_client_cert(http_ctrl->netc, client_cert, client_cert_len,
					client_key, client_key_len,
					client_password, client_password_len);
		}
	}else{
		network_deinit_tls(http_ctrl->netc);
	}

	if (!strncmp("GET", http_ctrl->method, strlen("GET"))) {
        LLOGI("HTTP GET");
    }
    else if (!strncmp("POST", http_ctrl->method, strlen("POST"))) {
        LLOGI("HTTP POST");
    }else {
        LLOGI("only GET/POST supported %s", http_ctrl->method);
        goto error;
    }

	http_ctrl->ip_addr.is_ipv6 = 0xff;
	http_ctrl->idp = luat_pushcwait(L);

	ret = network_wait_link_up(http_ctrl->netc, 0);
	if (ret == 0){
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), http_ctrl->ip_addr.is_ipv6?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
        	http_resp_error(http_ctrl, HTTP_ERROR_CONNECT);
			return 0;
    	}
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

LUAMOD_API int luaopen_http( lua_State *L ) {
    luat_newlib2(L, reg_http);
    return 1;
}

#else

#define LUAT_LOG_TAG "http2"
#include "luat_log.h"

#include "rotable2.h"
static const rotable_Reg_t reg_http[] =
{
	{ NULL,             ROREG_INT(0)}
};
LUAMOD_API int luaopen_http( lua_State *L ) {
    luat_newlib2(L, reg_http);
	LLOGE("reg_http2 require network enable!!");
    return 1;
}
#endif


