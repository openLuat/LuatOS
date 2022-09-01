#include "luat_base.h"
#include "luat_http.h"
#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

#define HTTP_REQUEST_BUF_LEN_MAX 1024
typedef struct{
	// http_broker_handle_t broker;// mqtt broker
	network_ctrl_t *netc;		    // http netc
	luat_ip_addr_t ip_addr;		// mqtt ip
	uint8_t is_tls;
	const char *host; 			// mqtt host
	uint16_t remote_port; 		// 远程端口号
	const char *url;
	const char *uri;
	const char *method;
	const char *header;
	const char *body;
	uint8_t request_message[HTTP_REQUEST_BUF_LEN_MAX];
	uint8_t *reply_message;
	uint64_t* idp;
	uint32_t keepalive;   		// 心跳时长 单位s
	uint8_t adapter_index; 		// 适配器索引号, 似乎并没有什么用
}luat_http_ctrl_t;

static int http_close(luat_http_ctrl_t *http_ctrl){

}



static int32_t l_http_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)msg->ptr;
    uint64_t* idp = (uint64_t*)http_ctrl->idp;

	if (!strncmp("HTTP/1.", http_ctrl->reply_message, strlen("HTTP/1."))){
		uint16_t code_offset = strlen("HTTP/1.x ");
		uint16_t code_len = 3;
		char *header = strstr(http_ctrl->reply_message,"\r\n")+2;
		char *body = strstr(header,"\r\n\r\n")+4;
		uint16_t header_len = strlen(header)-strlen(body)-4;
		lua_pushlstring(L, http_ctrl->reply_message+code_offset,code_len);
		lua_pushlstring(L, header,header_len);
		lua_pushlstring(L, body,strlen(body)-2);
		luat_cbcwait(L, *idp, 3);
    }

	return 0;
}

static int32_t luat_lib_http_callback(void *data, void *param){
	OS_EVENT *event = (OS_EVENT *)data;
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)param;
	int ret = 0;
	LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("luat_lib_mqtt_callback %d %d",event->ID & 0x0fffffff,event->Param1);
	if (event->ID == EV_NW_RESULT_LINK){
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), http_ctrl->ip_addr.is_ipv6?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
			network_close(http_ctrl->netc, 0);
			return -1;
    	}
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		if (http_ctrl->header){
			snprintf(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX, 
					"%s %s HTTP/1.1\r\nHost: %s\r\n%s\r\n", 
					http_ctrl->method,http_ctrl->uri,http_ctrl->host,http_ctrl->header);
		}else{
			snprintf(http_ctrl->request_message, HTTP_REQUEST_BUF_LEN_MAX, 
					"%s %s HTTP/1.1\r\nHost: %s\r\n\r\n", 
					http_ctrl->method,http_ctrl->uri,http_ctrl->host);
		}
		LLOGD("http_ctrl->request_message:%s",http_ctrl->request_message);
		uint32_t tx_len = 0;
		network_tx(http_ctrl->netc, http_ctrl->request_message, strlen(http_ctrl->request_message), 0, http_ctrl->ip_addr.is_ipv6?NULL:&(http_ctrl->ip_addr), NULL, &tx_len, 0);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		if (event->Param1==0){
			uint32_t total_len = 0;
			uint32_t rx_len = 0;
			int result = network_rx(http_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
			http_ctrl->reply_message = luat_heap_malloc(total_len + 1);
			result = network_rx(http_ctrl->netc, http_ctrl->reply_message, total_len, 0, NULL, NULL, &rx_len);
			if (rx_len == 0||result!=0) {
				//
			}
			// LLOGD("http_ctrl->reply_message:%s",http_ctrl->reply_message);

			rtos_msg_t msg = {0};
    		msg.handler = l_http_callback;
			msg.ptr = http_ctrl;
			luat_msgbus_put(&msg, 0);
		}
	}else if(event->ID == EV_NW_RESULT_TX){

	}else if(event->ID == EV_NW_RESULT_CLOSE){

	}
	if (event->Param1){
		// mqtt_close_socket(mqtt_ctrl);
	}
	network_wait_event(http_ctrl->netc, NULL, 0, NULL);
    return 0;
}

static int http_add_header(luat_http_ctrl_t *http_ctrl, const char* name, const char* value){
	LLOGD("http_add_header name:%s value:%s",name,value);
	
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
    for (size_t i = 0; i < tmplen; i++)
    {
        if (tmp[i] == '/') {
            if (i > 255) {
                LLOGI("host too long %s", http_ctrl->url);
                return -1;
            } 
            memcpy(tmphost, tmp, i);
            tmpuri = tmp + i;
            break;
        }
    }
	if (strlen(tmphost) < 1) {
        LLOGI("host not found %s", http_ctrl->url);
        return -1;
    }
    if (strlen(tmpuri) == 0) {
        tmpuri = "/";
    }
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
    LLOGD("tmphost:%s",tmphost);
	LLOGD("tmpuri:%s",tmpuri);
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

	LLOGD("http_ctrl->uri:%s",http_ctrl->uri);
	LLOGD("http_ctrl->host:%s",http_ctrl->host);
	LLOGD("http_ctrl->port:%d",http_ctrl->remote_port);
	return 0;
}

static int l_http_request(lua_State *L) {
	size_t client_cert_len, client_key_len, client_password_len;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	int adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (adapter_index < 0 || adapter_index >= NW_ADAPTER_QTY){
		return 0;
	}

	luat_http_ctrl_t *http_ctrl = (luat_http_ctrl_t *)luat_heap_malloc(sizeof(luat_http_ctrl_t));
	if (!http_ctrl){
		return 0;
	}
	memset(http_ctrl, 0, sizeof(luat_http_ctrl_t));
	http_ctrl->adapter_index = adapter_index;
	http_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!http_ctrl->netc){
		LLOGD("create fail");
		return 0;
	}
	network_init_ctrl(http_ctrl->netc, NULL, luat_lib_http_callback, http_ctrl);

	http_ctrl->netc->is_debug = 1;
	network_set_base_mode(http_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(http_ctrl->netc, 0);

	size_t len;
	const char *url = luaL_checklstring(L, 2, &len);
	http_ctrl->url = luat_heap_malloc(len + 1);
	memset(http_ctrl->url, 0, len + 1);
	memcpy(http_ctrl->url, url, len);

	LLOGD("http_ctrl->url:%s",http_ctrl->url);

	if (lua_istable(L, 3)){
		lua_pushstring(L, "method");
		if (LUA_TSTRING == lua_gettable(L, 3)) {
			const char *method = luaL_optlstring(L, -1, "GET", len);
			http_ctrl->method = luat_heap_malloc(len + 1);
			memset(http_ctrl->method, 0, len + 1);
			memcpy(http_ctrl->method, method, len);
			LLOGD("method:%s",http_ctrl->method);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "body");
		if (LUA_TSTRING == lua_gettable(L, 3)) {
			const char *body = luaL_checklstring(L, -1, len);
			http_ctrl->body = luat_heap_malloc(len + 1);
			memset(http_ctrl->body, 0, len + 1);
			memcpy(http_ctrl->body, body, len);
			LLOGD("body:%s",http_ctrl->body);
		}
		lua_pop(L, 1);
		
		lua_pushstring(L, "headers");
		if (LUA_TTABLE == lua_gettable(L, 3)) {
			lua_pushnil(L);
			while (lua_next(L, -2) != 0) {
				const char *name = lua_tostring(L, -2);
				const char *value = lua_tostring(L, -1);
				http_add_header(http_ctrl,name,value);
				lua_pop(L, 1);
			}
		}
		lua_pop(L, 1);


	}else{
		//关闭并释放
	}

	if (http_ctrl->is_tls){
		if (lua_isstring(L, 4)){
			client_cert = luaL_checklstring(L, 4, &client_cert_len);
		}
		if (lua_isstring(L, 5)){
			client_key = luaL_checklstring(L, 5, &client_key_len);
		}
		if (lua_isstring(L, 6)){
			client_password = luaL_checklstring(L, 6, &client_password_len);
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

	http_set_url(http_ctrl);
	
	if (!strncmp("GET", http_ctrl->method, strlen("GET"))) {
        // luat_http_get(http_ctrl);
    }
    else if (!strncmp("POST", http_ctrl->method, strlen("POST"))) {
        // luat_http_post(http_ctrl);
    }
    else {
        LLOGI("only GET/POST supported %s", http_ctrl->method);
        //关闭并释放
    }

	http_ctrl->ip_addr.is_ipv6 = 0xff;

	int ret = network_wait_link_up(http_ctrl->netc, 0);
	if (ret == 0){
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), http_ctrl->ip_addr.is_ipv6?NULL:&(http_ctrl->ip_addr), http_ctrl->remote_port, 0) < 0){
        	network_close(http_ctrl->netc, 0);
        return -1;
    	}
	}

	uint64_t id = luat_pushcwait(L);
	http_ctrl->idp = (uint64_t*)luat_heap_malloc(sizeof(uint64_t));
    memcpy(http_ctrl->idp, &id, sizeof(uint64_t));
    return 1;
}

#ifdef LUAT_USE_NETWORK

#include "rotable2.h"
static const rotable_Reg_t reg_http2[] =
{
	{"request",			ROREG_FUNC(l_http_request)},
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_http2( lua_State *L ) {
    luat_newlib2(L, reg_http2);
    return 1;
}

#else

#define LUAT_LOG_TAG "http2"
#include "luat_log.h"

#include "rotable2.h"
static const rotable_Reg_t reg_http2[] =
{
	{ NULL,             ROREG_INT(0)}
};
LUAMOD_API int luaopen_http2( lua_State *L ) {
    luat_newlib2(L, reg_http2);
	LLOGE("reg_http2 require network enable!!");
    return 1;
}
#endif


