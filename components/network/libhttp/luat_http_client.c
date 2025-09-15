
#include "luat_base.h"

#include "luat_rtos.h"
// #include "luat_msgbus.h"
#include "luat_debug.h"

#include "luat_mem.h"
#include "http_parser.h"


#include "luat_fota.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_str.h"

#include "luat_fs.h"
#include "luat_network_adapter.h"
#include "luat_http.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

extern void DBG_Printf(const char* format, ...);
extern void luat_http_client_onevent(luat_http_ctrl_t *http_ctrl, int error_code, int arg);
#undef LLOGD
#ifdef __LUATOS__
#define LLOGD(format, ...) do {if (http_ctrl->debug_onoff) {luat_log_log(LUAT_LOG_DEBUG, LUAT_LOG_TAG, format, ##__VA_ARGS__);}} while(0)
#else
#undef LLOGE
#undef LLOGI
#undef LLOGW
#define LLOGI(format, ...)
#define LLOGW(format, ...)
#ifdef LUAT_LOG_NO_NEWLINE
#define LLOGD(x,...)	do {if (http_ctrl->debug_onoff) {DBG_Printf("%s %d:"x, __FUNCTION__,__LINE__,##__VA_ARGS__);}} while(0)
#define LLOGE(x,...) DBG_Printf("%s %d:"x, __FUNCTION__,__LINE__,##__VA_ARGS__)
#else
#define LLOGD(x,...)	do {if (http_ctrl->debug_onoff) {DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##__VA_ARGS__);}} while(0)
#define LLOGE(x,...) DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##__VA_ARGS__)
#endif

#endif

#ifdef LUAT_USE_NETDRV
#include "luat_netdrv.h"
#include "luat_netdrv_event.h"
#endif

static void http_send_message(luat_http_ctrl_t *http_ctrl);
static int32_t luat_lib_http_callback(void *data, void *param);

int strncasecmp(const char *string1, const char *string2, size_t count);
int http_close(luat_http_ctrl_t *http_ctrl){
	LLOGD("http close %p", http_ctrl);
	if (http_ctrl->netc){
		network_close(http_ctrl->netc, 0);
		network_force_close_socket(http_ctrl->netc);
		network_release_ctrl(http_ctrl->netc);
		http_ctrl->netc = NULL;
	}
	if (http_ctrl->timeout_timer){
		luat_stop_rtos_timer(http_ctrl->timeout_timer);
		luat_release_rtos_timer(http_ctrl->timeout_timer);
    	http_ctrl->timeout_timer = NULL;
	}
	if (http_ctrl->host){
		luat_heap_free(http_ctrl->host);
		http_ctrl->host = NULL;
	}
	if (http_ctrl->request_line){
		luat_heap_free(http_ctrl->request_line);
		http_ctrl->request_line = NULL;
	}
	if (http_ctrl->req_header){
		luat_heap_free(http_ctrl->req_header);
		http_ctrl->req_header = NULL;
	}
	if (http_ctrl->req_body){
		luat_heap_free(http_ctrl->req_body);
		http_ctrl->req_body = NULL;
	}
	if (http_ctrl->luatos_mode) {
		if (http_ctrl->dst){
			luat_heap_free(http_ctrl->dst);
			http_ctrl->dst = NULL;
		}
		if (http_ctrl->headers){
			luat_heap_free(http_ctrl->headers);
			http_ctrl->headers = NULL;
		}
		if (http_ctrl->body){
			luat_heap_free(http_ctrl->body);
			http_ctrl->body = NULL;
		}
	}

	if (http_ctrl->req_auth) {
		luat_heap_free(http_ctrl->req_auth);
		http_ctrl->req_auth = NULL;
	}
	luat_heap_free(http_ctrl);
	return 0;
}

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK void luat_http_client_onevent(luat_http_ctrl_t *http_ctrl, int error_code, int arg){
    if (error_code == HTTP_OK){
        luat_http_cb http_cb = http_ctrl->http_cb;
        http_cb(HTTP_STATE_GET_BODY, NULL, 0, http_ctrl->http_cb_userdata); // 为了兼容老代码
        http_cb(HTTP_STATE_GET_BODY_DONE, (void *)((uint32_t)http_ctrl->parser.status_code), 0, http_ctrl->http_cb_userdata);
        http_ctrl->error_code = 0;
        http_ctrl->state = HTTP_STATE_DONE;
        luat_rtos_timer_stop(http_ctrl->timeout_timer);
    }
}
#endif

static void http_network_error(luat_http_ctrl_t *http_ctrl)
{
	if (!http_ctrl->netc)
	{
		LLOGE("http is free!!!");
		return;
	}
    luat_http_cb http_cb = http_ctrl->http_cb;
	if (++(http_ctrl->re_request_count))
	{
		if (http_ctrl->re_request_count >= http_ctrl->retry_cnt_max)
		{
			if (http_ctrl->error_code > 0)
			{
				http_ctrl->error_code = HTTP_ERROR_STATE;
			}
			http_cb(http_ctrl->error_code, NULL, 0, http_ctrl->http_cb_userdata);
			return;
		}
	}
	LLOGD("retry %d", http_ctrl->re_request_count);
	http_ctrl->state = HTTP_STATE_CONNECT;
	if (http_ctrl->timeout)
	{
		luat_start_rtos_timer(http_ctrl->timeout_timer, http_ctrl->timeout, 1);
	}
	else
	{
		luat_stop_rtos_timer(http_ctrl->timeout_timer);
	}

	if (network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), NULL, http_ctrl->remote_port, 0) < 0)
	{
		LLOGD("http can not connect!");
		http_ctrl->state = HTTP_STATE_IDLE;
		http_ctrl->error_code = HTTP_ERROR_CONNECT;
		network_close(http_ctrl->netc, 0);
		if (http_cb)
		{
			http_cb(http_ctrl->error_code, NULL, 0, http_ctrl->http_cb_userdata);
		}
		else
		{
			luat_debug_assert(__FUNCTION__, __LINE__, "http no cb");
		}
	}
}
static void http_network_close(luat_http_ctrl_t *http_ctrl)
{
	http_ctrl->state = HTTP_STATE_WAIT_CLOSE;
	luat_rtos_timer_stop(http_ctrl->timeout_timer);
	if (!network_close(http_ctrl->netc, 0))
	{
		http_network_error(http_ctrl);
	}
}



static void http_resp_error(luat_http_ctrl_t *http_ctrl, int error_code) {
	LLOGD("http_resp_error error_code:%d close_state:%d",error_code,http_ctrl->close_state);
#ifdef LUAT_USE_FOTA
	if (http_ctrl->isfota!=0 && error_code == HTTP_ERROR_FOTA){
		luat_fota_end(0);
		luat_http_client_onevent(http_ctrl, error_code, 0);
		return;
	}
#endif
	LLOGD("http_resp_error headers_complete:%d re_request_count:%d",http_ctrl->headers_complete,http_ctrl->re_request_count);
	if (http_ctrl->close_state == 0 && http_ctrl->headers_complete==1 && http_ctrl->re_request_count < http_ctrl->retry_cnt_max){
		#ifdef LUAT_USE_NETDRV
		luat_netdrv_fire_socket_event_netctrl(EV_NW_TIMEOUT, http_ctrl->netc, 3);
		#endif
		http_ctrl->re_request_count++;
		network_close(http_ctrl->netc, 0);
		network_force_close_socket(http_ctrl->netc);
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), NULL, http_ctrl->remote_port, 0) < 0){
			LLOGE("http_resp_error network_connect error");
			goto error;
		}
	}else if (http_ctrl->close_state==0){
		#ifdef LUAT_USE_NETDRV
		luat_netdrv_fire_socket_event_netctrl(EV_NW_TIMEOUT, http_ctrl->netc, 3);
		#endif
error:
		http_ctrl->close_state=1;
		luat_http_client_onevent(http_ctrl, error_code, 0);
	}
}

// body接收回调
static void luat_http_callback(luat_http_ctrl_t *http_ctrl){
	if (http_ctrl->http_cb && http_ctrl->luatos_mode){
		luat_http_client_onevent(http_ctrl, HTTP_CALLBACK, http_ctrl->body_len);
		LLOGD("luat_http_callback content_length:%ld body_len:%ld",http_ctrl->resp_content_len, http_ctrl->body_len);
    }
}

static int on_header_field(http_parser* parser, const char *at, size_t length){
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
    LLOGD("on_header_field:%.*s",length,at);
	if (http_ctrl->headers_complete){
		return 0;
	}

	if (http_ctrl->luatos_mode) {
		if(!strncasecmp(at, "Content-Length: ", 16) && http_ctrl->resp_content_len == 0){
			http_ctrl->resp_content_len = -1;
		}
		if (!http_ctrl->headers){
			http_ctrl->headers = luat_heap_malloc(length+2);
		}else{
			http_ctrl->headers = luat_heap_realloc(http_ctrl->headers,http_ctrl->headers_len+length+2);
		}
		memcpy(http_ctrl->headers+http_ctrl->headers_len,at,length);
		memcpy(http_ctrl->headers+http_ctrl->headers_len+length, ":", 1);
		http_ctrl->headers_len += length+1;
	} else {
		char temp[16] = {':'};
		http_ctrl->response_head_buffer.Pos = 0;
		OS_BufferWrite(&http_ctrl->response_head_buffer, (void*)at, length);
		OS_BufferWrite(&http_ctrl->response_head_buffer, temp, 1);
	}
    return 0;
}
	
static int on_header_value(http_parser* parser, const char *at, size_t length){

	char tmp[16] = {0};
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	LLOGD("on_header_value:%.*s",length,at);
	if (http_ctrl->headers_complete){
		if (!http_ctrl->luatos_mode) {
			LLOGD("state %d", http_ctrl->state);
		}
		return 0;
	}

	if (http_ctrl->luatos_mode) {
		if(http_ctrl->resp_content_len == -1){
			memcpy(tmp, at, length);
			http_ctrl->resp_content_len = atoi(tmp);
			LLOGD("http_ctrl->resp_content_len:%d",http_ctrl->resp_content_len);
		}
		http_ctrl->headers = luat_heap_realloc(http_ctrl->headers,http_ctrl->headers_len+length+3);
		memcpy(http_ctrl->headers+http_ctrl->headers_len,at,length);
		memcpy(http_ctrl->headers+http_ctrl->headers_len+length, "\r\n", 2);
		http_ctrl->headers_len += length+2;
	} else {
		OS_BufferWrite(&http_ctrl->response_head_buffer, (void *)at, length);
		OS_BufferWrite(&http_ctrl->response_head_buffer, tmp, 1);
		luat_http_cb http_cb = http_ctrl->http_cb;
		http_cb(HTTP_STATE_GET_HEAD, http_ctrl->response_head_buffer.Data, http_ctrl->response_head_buffer.Pos, http_ctrl->http_cb_userdata);
	}
    return 0;
}

static int on_headers_complete(http_parser* parser){
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
    LLOGD("on_headers_complete");
	if (http_ctrl->headers_complete){
		if (!http_ctrl->luatos_mode) {
			LLOGD("state %d", http_ctrl->state);
		}
		return 0;
	}
	if (http_ctrl->luatos_mode) {
		http_ctrl->headers[http_ctrl->headers_len] = 0x00;

		if (http_ctrl->is_download){
			luat_fs_remove(http_ctrl->dst);
			http_ctrl->fd = luat_fs_fopen(http_ctrl->dst, "w+");
			if (http_ctrl->fd == NULL) {
				LLOGE("open download file fail %s", http_ctrl->dst);
			}
		}
	#ifdef LUAT_USE_FOTA
		else if(http_ctrl->isfota){
			luat_fota_init(http_ctrl->address, http_ctrl->length, http_ctrl->spi_device, NULL, 0);
		}
	#endif
		http_ctrl->headers_complete = 1;
		luat_http_callback(http_ctrl);
	} else {
		if (http_ctrl->state != HTTP_STATE_GET_HEAD){
			LLOGE("http state error %d", http_ctrl->state);
			return 0;
		}
		if (!http_ctrl->context_len_vaild)
		{
			if (http_ctrl->parser.content_length != -1)
			{
				http_ctrl->context_len = http_ctrl->parser.content_length;
				http_ctrl->context_len_vaild = 1;
			}
			else
			{
				LLOGD("no content length, maybe chuck!");
			}
		}
		luat_http_cb http_cb = http_ctrl->http_cb;
		http_cb(HTTP_STATE_GET_HEAD, NULL, 0, http_ctrl->http_cb_userdata); // 为了兼容老代码
		http_cb(HTTP_STATE_GET_HEAD_DONE, (void *)((uint32_t)parser->status_code), 0, http_ctrl->http_cb_userdata);
		http_ctrl->state = HTTP_STATE_GET_BODY;
	}
    return 0;
}

static int on_body(http_parser* parser, const char *at, size_t length){
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	if (length > 512) {
		LLOGD("on_body first 512byte:%.*s",512,at);
	} else {
		LLOGD("on_body:%.*s",length,at);
	}

	LLOGD("on_body length:%d http_ctrl->body_len:%d status_code:%d",length,http_ctrl->body_len+length,parser->status_code);
	if (http_ctrl->luatos_mode) {
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
			if (length != luat_fs_fwrite(at, length, 1, http_ctrl->fd)) {
				LLOGE("err when fwrite %s", http_ctrl->dst);
				http_resp_error(http_ctrl, HTTP_ERROR_DOWNLOAD);
				return -1;
			}
		}
	#ifdef LUAT_USE_FOTA
		else if(http_ctrl->isfota && (parser->status_code == 200 || parser->status_code == 206)){
			if (luat_fota_write((uint8_t*)at, length) < 0){
				luat_fota_end(0);
				http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
				return -1;
			}
		}
	#endif

		else if(http_ctrl->is_post==0 && http_ctrl->zbuff_body!=NULL){
			if (http_ctrl->zbuff_body->len < http_ctrl->zbuff_body->used+length+1 ){
				void* tmpptr = luat_heap_realloc(http_ctrl->zbuff_body->addr,http_ctrl->zbuff_body->used+length+1);
				if (tmpptr == NULL) {
					LLOGE("out of memory when recv http body");
					http_resp_error(http_ctrl, HTTP_ERROR_DOWNLOAD);
					return -1;
				}
				http_ctrl->zbuff_body->addr = tmpptr;
			}
			memcpy(http_ctrl->zbuff_body->addr + http_ctrl->zbuff_body->used ,at,length);
			http_ctrl->zbuff_body->used += length;
		}

		else{
			if (!http_ctrl->body){
				http_ctrl->body = luat_heap_malloc(length+1);
				if (http_ctrl->body == NULL) {
					LLOGE("out of memory when recv http body");
					http_resp_error(http_ctrl, HTTP_ERROR_DOWNLOAD);
					return -1;
				}
			}else{
				void* tmpptr = luat_heap_realloc(http_ctrl->body,http_ctrl->body_len+length+1);
				if (tmpptr == NULL) {
					LLOGE("out of memory when recv http body");
					http_resp_error(http_ctrl, HTTP_ERROR_DOWNLOAD);
					return -1;
				}
				http_ctrl->body = tmpptr;
			}
			memcpy(http_ctrl->body+http_ctrl->body_len,at,length);
		}
		http_ctrl->body_len += length;
		luat_http_callback(http_ctrl);
	} else {
		if (http_ctrl->state != HTTP_STATE_GET_BODY){
			LLOGD("http state error %d", http_ctrl->state);
			return 0;
		}
		http_ctrl->body_len += length;
		luat_http_cb http_cb = http_ctrl->http_cb;
		if (at && length) {
			http_cb(HTTP_STATE_GET_BODY, (void *)at, length, http_ctrl->http_cb_userdata);
		}
	}
    return 0;
}

static int on_complete(http_parser* parser, luat_http_ctrl_t *http_ctrl){
    LLOGD("on_complete");
	// http_ctrl->body[http_ctrl->body_len] = 0x00;
	LLOGD("status_code:%d",parser->status_code);
	// LLOGD("content_length:%lld",parser->content_length);
	(void)parser;
	if (http_ctrl->luatos_mode) {
		if (http_ctrl->fd != NULL) {
			luat_fs_fclose(http_ctrl->fd);
			http_ctrl->fd = NULL;
			if (parser->status_code > 299 && http_ctrl->dst) {
				LLOGW("download fail, remove file %s", http_ctrl->dst);
				luat_fs_remove(http_ctrl->dst);
			}
		}
	#ifdef LUAT_USE_FOTA
		else if(http_ctrl->isfota){
			if (parser->status_code == 200 || parser->status_code == 206){
				parser->status_code = 200;
				int result = luat_fota_done();
				LLOGD("result1:%d",result);
				while (result>0){ // TODO 应该有超时机制
					luat_timer_mdelay(100);
					result = luat_fota_done();
				}
				LLOGD("result2:%d",result);
				if (result==0){
					if (luat_fota_end(1)){
						LLOGE("fota finish error");
						http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
						return -1;
					}
				}else{
					luat_fota_end(0);
					http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
					return -1;
				}
			}else{
				luat_fota_end(0);
				http_ctrl->close_state = 1;
				// network_close(http_ctrl->netc, 0);
				http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
				return -1;
			}
		}
	#endif
		// http_ctrl->close_state = 1;
		network_close(http_ctrl->netc, 0);
	}
	luat_http_client_onevent(http_ctrl, HTTP_OK, 0);
    return 0;
}

static int on_message_complete(http_parser* parser){
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
    LLOGD("on_message_complete");
	http_ctrl->close_state = 1;
	return 0;
}

static int on_chunk_header(http_parser* parser){
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	LLOGD("on_chunk_header");
	LLOGD("content_length:%lld",parser->content_length);
	// luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)parser->data;
	// http_ctrl->is_chunk = 1;
    return 0;
}

static const http_parser_settings parser_settings = {
	.on_header_field = on_header_field,
	.on_header_value = on_header_value,
	.on_headers_complete = on_headers_complete,
	.on_body = on_body,
	.on_message_complete = on_message_complete,
	.on_chunk_header = on_chunk_header
};


int luat_http_client_init(luat_http_ctrl_t* http_ctrl, int use_ipv6) {
	network_init_ctrl(http_ctrl->netc, NULL, luat_lib_http_callback, http_ctrl);

	network_set_base_mode(http_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(http_ctrl->netc, 0);
	if (use_ipv6) {
		LLOGI("enable ipv6 support for http request");
		network_connect_ipv6_domain(http_ctrl->netc, 1);
	}
	http_ctrl->luatos_mode = 1;
	return 0;
}


#define HTTP_SEND_LEN_MAX 		(4096)

static uint32_t http_send(luat_http_ctrl_t *http_ctrl, void* data, size_t len) {
	if (len == 0)
		return 0;
	uint32_t tx_len = 0;
	// LLOGD("http_send data:%.*s",len,data);
	network_tx(http_ctrl->netc, (uint8_t *)data, len, 0, NULL, 0, &tx_len, 0);
	return tx_len;
}

static void http_send_message(luat_http_ctrl_t *http_ctrl){
	// 发送请求行, 主要,这里都借用了resp_buff,但这并不会与resp冲突
	int result;
	http_send(http_ctrl, (uint8_t *)http_ctrl->request_line, strlen((char*)http_ctrl->request_line));
	// 判断自定义headers是否有host	
	if (http_ctrl->custom_host == 0) {
		result = snprintf_(http_ctrl->resp_buff, HTTP_RESP_BUFF_SIZE,  "Host: %s:%d\r\n", http_ctrl->host, http_ctrl->remote_port);
		http_send(http_ctrl, http_ctrl->resp_buff, result);
	}
	if (http_ctrl->luatos_mode) {

		if (http_ctrl->headers_complete){
			result = snprintf_(http_ctrl->resp_buff, HTTP_RESP_BUFF_SIZE,  "Range: bytes=%lu-\r\n", http_ctrl->body_len);
			http_send(http_ctrl, http_ctrl->resp_buff, result);
		}

		if (http_ctrl->req_auth) {
			http_send(http_ctrl, (uint8_t*)http_ctrl->req_auth, strlen((char*)http_ctrl->req_auth));
		}

		// 发送自定义头部
		if (http_ctrl->req_header){
			http_send(http_ctrl, (uint8_t*)http_ctrl->req_header, strlen((char*)http_ctrl->req_header));
		}

		// 结束头部
		http_send(http_ctrl, (uint8_t*)"\r\n", 2);
		// 发送body
		if (http_ctrl->req_body){
			if (http_ctrl->req_body_len > HTTP_SEND_LEN_MAX){
				http_send(http_ctrl, (uint8_t*)http_ctrl->req_body, HTTP_SEND_LEN_MAX);
				http_ctrl->tx_offset = HTTP_SEND_LEN_MAX;
			}else{
				http_send(http_ctrl, (uint8_t*)http_ctrl->req_body, http_ctrl->req_body_len);
				http_ctrl->tx_offset = 0;
			}
		}
		else if(http_ctrl->is_post==1 && http_ctrl->zbuff_body!=NULL){
			if (http_ctrl->zbuff_body->used > HTTP_SEND_LEN_MAX){
				http_send(http_ctrl, http_ctrl->zbuff_body->addr, HTTP_SEND_LEN_MAX);
				http_ctrl->tx_offset = HTTP_SEND_LEN_MAX;
			}else{
				http_send(http_ctrl, http_ctrl->zbuff_body->addr, http_ctrl->zbuff_body->used);
				http_ctrl->tx_offset = 0;
			}
		}
	} else {

		const char line[] = "Accept: application/octet-stream\r\n";
		http_ctrl->state = HTTP_STATE_SEND_HEAD;


		if (http_ctrl->data_mode && (http_ctrl->offset || http_ctrl->body_len)){
			result = snprintf_(http_ctrl->resp_buff, 320,  "Range: bytes=%lu-\r\n", (http_ctrl->offset + http_ctrl->body_len));
			LLOGD("get offset %u+%u", http_ctrl->offset, http_ctrl->body_len);
			http_send(http_ctrl, http_ctrl->resp_buff, result);
		}
	
		// 发送自定义头部
		if (http_ctrl->request_head_buffer.Data && http_ctrl->request_head_buffer.Pos){
			http_send(http_ctrl, http_ctrl->request_head_buffer.Data, http_ctrl->request_head_buffer.Pos);
		}
		if (http_ctrl->data_mode)
		{
			http_send(http_ctrl, (uint8_t *)line, sizeof(line) - 1);
		}
		// 结束头部
		http_send(http_ctrl, (uint8_t*)"\r\n", 2);
		// 发送body

		http_ctrl->state = HTTP_STATE_GET_HEAD;
	
		if (http_ctrl->is_post)
		{
			luat_http_cb http_cb = http_ctrl->http_cb;
			http_cb(HTTP_STATE_SEND_BODY_START, NULL, 0, http_ctrl->http_cb_userdata);
		}
	}
}

LUAT_RT_RET_TYPE luat_http_timer_callback(LUAT_RT_CB_PARAM){
	luat_http_ctrl_t * http_ctrl = (luat_http_ctrl_t *)param;
	if (http_ctrl->luatos_mode) {
		http_resp_error(http_ctrl, HTTP_ERROR_TIMEOUT);
	} else {
		if (http_ctrl->new_data)
		{
			http_ctrl->new_data = 0;
		}
		else
		{
			LLOGD("http timeout error!");
			http_ctrl->error_code = HTTP_ERROR_TIMEOUT;
			http_network_close(http_ctrl);
		}
	}
}

int32_t luat_lib_http_callback(void *data, void *param){
	OS_EVENT *event = (OS_EVENT *)data;
	luat_http_ctrl_t *http_ctrl =(luat_http_ctrl_t *)param;
	int ret = 0;
	if (!http_ctrl->luatos_mode) {
	    if (HTTP_STATE_IDLE == http_ctrl->state)
	    {
	        LLOGE("http state error %d", http_ctrl->state);
	        return 0;
	    }
	}

	//LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("luat_lib_http_callback %d %d %p",event->ID - EV_NW_RESULT_BASE,event->Param1, http_ctrl);
	if (event->Param1){
		//LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
		LLOGE("error event %08X %d host %s port %d",event->ID - EV_NW_RESULT_BASE, event->Param1, http_ctrl->netc->domain_name, http_ctrl->netc->remote_port);
		if (http_ctrl->luatos_mode) {
			http_resp_error(http_ctrl, event->ID == EV_NW_RESULT_CONNECT ? HTTP_ERROR_CONNECT : HTTP_ERROR_CLOSE);
		} else {
			http_ctrl->error_code = event->ID == EV_NW_RESULT_CONNECT ? HTTP_ERROR_CONNECT : HTTP_ERROR_CLOSE;
			http_network_error(http_ctrl);
		}
		return -1;
	}
    switch (event->ID)
    {
    case EV_NW_RESULT_EVENT:
    	if (!http_ctrl->luatos_mode) {
    		http_ctrl->new_data = 1;
    	}
		if (http_ctrl->is_pause){
			LLOGD("rx pause");
			break;
		}

		uint32_t total_len = 0;
		uint32_t rx_len = 0;
		while (1) {
			int result = network_rx(http_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
			if (result) {
				if (http_ctrl->luatos_mode) {
					http_resp_error(http_ctrl, HTTP_ERROR_RX);
				} else {
					http_ctrl->error_code = HTTP_ERROR_RX;
					http_network_error(http_ctrl);
				}
				return -1;
			}
			if (0 == total_len)
				break;
			if (http_ctrl->resp_buff_offset + total_len > (HTTP_RESP_BUFF_SIZE - 1)) {
				total_len = HTTP_RESP_BUFF_SIZE - 1 - http_ctrl->resp_buff_offset;
				if (total_len < 1) {
					// 能到这里的就是片段太长了
					// 要么header太长, 要么chunked太长,拒绝吧
					if (http_ctrl->luatos_mode) {
						http_resp_error(http_ctrl, HTTP_ERROR_RX);
					} else {
						http_ctrl->error_code = HTTP_ERROR_RX;
						http_network_error(http_ctrl);
					}
					return -1;
				}
			}
			result = network_rx(http_ctrl->netc, (uint8_t*)http_ctrl->resp_buff+http_ctrl->resp_buff_offset, total_len, 0, NULL, NULL, &rx_len);
			LLOGD("result:%d rx_len:%d",result,rx_len);
			if (rx_len == 0||result!=0) {
				if (http_ctrl->luatos_mode) {
					http_resp_error(http_ctrl, HTTP_ERROR_RX);
				} else {
					http_ctrl->error_code = HTTP_ERROR_RX;
					http_network_error(http_ctrl);
				}
				return -1;
			}
			http_ctrl->resp_buff_offset += rx_len;
			//LLOGD("resp_buff_offset:%d resp_buff:%s",http_ctrl->resp_buff_offset,http_ctrl->resp_buff);
			// uint8_t *tmp = (uint8_t*)http_ctrl->resp_buff;
			//LLOGD("resp buff %.*s", http_ctrl->resp_buff_offset, http_ctrl->resp_buff);
			if (0 == http_ctrl->resp_headers_done) {
				LLOGD("search headers, buff len %d", http_ctrl->resp_buff_offset);
				if (http_ctrl->resp_buff_offset > 4) {
					uint8_t *tmp = (uint8_t*)http_ctrl->resp_buff;
					size_t search = http_ctrl->resp_buff_offset;
					for (size_t i = 0; i < search; i++)
					{
						// \\r\\n\\r\\n
						// \\n\\n
						// \\r\\r
						if ((0x0D == tmp[i] &&  0x0A == tmp[i+1] &&  0x0D == tmp[i+2] &&  0x0A == tmp[i+3]) || 
							(0x0A == tmp[i] && 0x0A == tmp[i+1]) ||
							(0x0D == tmp[i] && 0x0D == tmp[i+1]) ){
							http_ctrl->resp_headers_done = 1;
							LLOGD("found headers end at %d", i);
							break;
						}
					}
				}
			}
			if (http_ctrl->resp_headers_done) {
				size_t nParseBytes = http_parser_execute(&http_ctrl->parser, &parser_settings, http_ctrl->resp_buff, http_ctrl->resp_buff_offset);
				LLOGD("nParseBytes %d resp_buff_offset %d", nParseBytes, http_ctrl->resp_buff_offset);
				if(http_ctrl->parser.http_errno) {
					LLOGW("http exit reason by errno: %d != HPE_OK!!!", http_ctrl->parser.http_errno);
					return 0;
				}
				if (http_ctrl->close_state) {
					http_ctrl->resp_buff_offset = 0;
					on_complete(&http_ctrl->parser, http_ctrl);
					return 0;
				}
				if (http_ctrl->resp_buff_offset <= nParseBytes) {
					http_ctrl->resp_buff_offset = 0;
				}
				else {
					memmove(http_ctrl->resp_buff, http_ctrl->resp_buff + nParseBytes, http_ctrl->resp_buff_offset - nParseBytes);
					http_ctrl->resp_buff_offset -= nParseBytes;
				}
			}
			else {
				LLOGD("wait headers %.*s", http_ctrl->resp_buff_offset, http_ctrl->resp_buff);
			}
			if (http_ctrl->close_state){
				return 0;
			}
		}

		break;
    case EV_NW_RESULT_TX:
    	if (http_ctrl->luatos_mode) {
			if (http_ctrl->tx_offset){
				if (http_ctrl->req_body){
					if (http_ctrl->req_body_len-http_ctrl->tx_offset > HTTP_SEND_LEN_MAX){
						http_send(http_ctrl, (uint8_t*)http_ctrl->req_body+http_ctrl->tx_offset, HTTP_SEND_LEN_MAX);
						http_ctrl->tx_offset += HTTP_SEND_LEN_MAX;
					}else{
						http_send(http_ctrl, (uint8_t*)http_ctrl->req_body+http_ctrl->tx_offset, http_ctrl->req_body_len-http_ctrl->tx_offset);
						http_ctrl->tx_offset = 0;
					}
				}
				else if(http_ctrl->is_post==1 && http_ctrl->zbuff_body!=NULL){
					if (http_ctrl->zbuff_body->used-http_ctrl->tx_offset > HTTP_SEND_LEN_MAX){
						http_send(http_ctrl, http_ctrl->zbuff_body->addr+http_ctrl->tx_offset, HTTP_SEND_LEN_MAX);
						http_ctrl->tx_offset += HTTP_SEND_LEN_MAX;
					}else{
						http_send(http_ctrl, http_ctrl->zbuff_body->addr+http_ctrl->tx_offset, http_ctrl->zbuff_body->used-http_ctrl->tx_offset);
						http_ctrl->tx_offset = 0;
					}
				}
			}
    	} else {
			if (http_ctrl->is_post){
				luat_http_cb http_cb = http_ctrl->http_cb;
				http_cb(HTTP_STATE_SEND_BODY, NULL, 0, http_ctrl->http_cb_userdata);
			}
			http_ctrl->state = HTTP_STATE_GET_HEAD;
    	}
		return 0;
    case EV_NW_RESULT_CONNECT:
		http_ctrl->resp_buff_offset = 0; // 复位resp缓冲区
		http_ctrl->resp_headers_done = 0;
		http_parser_init(&http_ctrl->parser, HTTP_RESPONSE);
		http_ctrl->parser.data = http_ctrl;

		// TODO header 保持原始数据,在lua回调时才导出数据
		// if (http_ctrl->resp_headers) {
		// 	luat_heap_free(http_ctrl->resp_headers);
		// 	http_ctrl->resp_headers = NULL;
		// }
		http_send_message(http_ctrl);
		return 0;
    case EV_NW_RESULT_CLOSE:
    	if (!http_ctrl->luatos_mode) {
			if (http_ctrl->error_code && (http_ctrl->state != HTTP_STATE_DONE))
			{
				LLOGD("http network closed");
				http_network_error(http_ctrl);
			}
			else
			{
				http_ctrl->state = HTTP_STATE_IDLE;
				luat_http_cb http_cb = http_ctrl->http_cb;
				http_cb(http_ctrl->state, NULL, 0, http_ctrl->http_cb_userdata);
			}
    	}
        return 0;
    case EV_NW_RESULT_LINK:
        return 0;
    default:
        break;
    }

    ret = network_wait_event(http_ctrl->netc, NULL, 0, NULL);
	if (ret < 0){
		LLOGE("network_wait_event %d", ret);
		if (http_ctrl->luatos_mode) {
			http_resp_error(http_ctrl, HTTP_ERROR_CLOSE);
		} else {
			http_ctrl->error_code = HTTP_ERROR_STATE;
			http_network_close(http_ctrl);
		}
		return -1;
	}
    return 0;
}


static void luat_http_dummy_cb(int status, void *data, uint32_t data_len, void *user_param) {;}
luat_http_ctrl_t* luat_http_client_create(luat_http_cb cb, void *user_param, int adapter_index)
{
	luat_http_ctrl_t *http_ctrl = luat_heap_malloc(sizeof(luat_http_ctrl_t));
	if (!http_ctrl) return NULL;
    memset(http_ctrl,0,sizeof(luat_http_ctrl_t));

	http_ctrl->timeout_timer = luat_create_rtos_timer(luat_http_timer_callback, http_ctrl, NULL);
	if (!http_ctrl->timeout_timer)
	{
		luat_heap_free(http_ctrl);
		LLOGE("no more timer");
		return NULL;
	}

	if (adapter_index >= 0)
	{
		http_ctrl->netc = network_alloc_ctrl(adapter_index);
	}
	else
	{
		http_ctrl->netc = network_alloc_ctrl(network_register_get_default());
	}
	if (!http_ctrl->netc)
	{
		luat_release_rtos_timer(http_ctrl->timeout_timer);
		luat_heap_free(http_ctrl);
		LLOGE("no more network ctrl");
		return NULL;
	}

	network_init_ctrl(http_ctrl->netc, NULL, luat_lib_http_callback, http_ctrl);
	network_set_base_mode(http_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(http_ctrl->netc, 0);
	http_ctrl->http_cb = cb?cb:luat_http_dummy_cb;
	http_ctrl->http_cb_userdata = user_param;
	http_ctrl->timeout = 15000;
	http_ctrl->retry_cnt_max = 0;
	http_ctrl->state = HTTP_STATE_IDLE;
	http_ctrl->debug_onoff = 0;
	http_ctrl->netc->is_debug = 0;
	return http_ctrl;
}


int luat_http_client_base_config(luat_http_ctrl_t* http_ctrl, uint32_t timeout, uint8_t debug_onoff, uint8_t re_request_count)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state)
	{
		LLOGE("http running, please stop and set");
		return -ERROR_PERMISSION_DENIED;
	}
	http_ctrl->timeout = timeout;
	http_ctrl->debug_onoff = debug_onoff;
	http_ctrl->netc->is_debug = debug_onoff;
	http_ctrl->retry_cnt_max = re_request_count;
	return 0;
}

int luat_http_client_ssl_config(luat_http_ctrl_t* http_ctrl, int mode, const char *server_cert, uint32_t server_cert_len,
		const char *client_cert, uint32_t client_cert_len,
		const char *client_cert_key, uint32_t client_cert_key_len,
		const char *client_cert_key_password, uint32_t client_cert_key_password_len)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state)
	{
		LLOGE("http running, please stop and set");
		return -ERROR_PERMISSION_DENIED;
	}

	if (mode < 0)
	{
		network_deinit_tls(http_ctrl->netc);
		return 0;
	}
	if (mode > 2)
	{
		return -ERROR_PARAM_INVALID;
	}
	int result;
	// network_init_tls(http_ctrl->netc, (server_cert || client_cert)?2:0);
	network_init_tls(http_ctrl->netc, 0);
	if (server_cert){
		result = network_set_server_cert(http_ctrl->netc, (const unsigned char *)server_cert, server_cert_len);
		if (result)
		{
			LLOGE("set server cert failed %d", result);
			return -ERROR_OPERATION_FAILED;
		}
	}
	if (client_cert){
		result = network_set_client_cert(http_ctrl->netc, (const unsigned char *)client_cert, client_cert_len,
				(const unsigned char *)client_cert_key, client_cert_key_len,
				(const unsigned char *)client_cert_key_password, client_cert_key_password_len);
		if (result)
		{
			LLOGE("set client cert failed %d", result);
			return -ERROR_OPERATION_FAILED;
		}
	}
	return 0;
}



int luat_http_client_clear(luat_http_ctrl_t *http_ctrl)
{
	OS_DeInitBuffer(&http_ctrl->request_head_buffer);
	return 0;
}


int luat_http_client_set_user_head(luat_http_ctrl_t *http_ctrl, const char *name, const char *value)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state)
	{
		LLOGE("http running, please stop and set");
		return -ERROR_PERMISSION_DENIED;
	}

	if (!http_ctrl->request_head_buffer.Data)
	{
		OS_InitBuffer(&http_ctrl->request_head_buffer, HTTP_RESP_BUFF_SIZE);
	}

	int ret = sprintf_((char *)http_ctrl->request_head_buffer.Data + http_ctrl->request_head_buffer.Pos, "%s:%s\r\n", name, value);
	if (ret > 0)
	{
		http_ctrl->request_head_buffer.Pos += ret;
		if (!strcmp("Host", name) || !strcmp("host", name))
		{
			http_ctrl->custom_host = 1;
		}
		return 0;
	}
	else
	{
		return -ERROR_OPERATION_FAILED;
	}
}


int luat_http_client_close(luat_http_ctrl_t *http_ctrl)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;

	LLOGD("user close http!");
	http_ctrl->state = HTTP_STATE_WAIT_CLOSE;
	http_ctrl->re_request_count = http_ctrl->retry_cnt_max;
	network_force_close_socket(http_ctrl->netc);
	luat_rtos_timer_stop(http_ctrl->timeout_timer);
	http_ctrl->state = HTTP_STATE_IDLE;
	http_ctrl->offset = 0;
	return 0;
}

int luat_http_client_destroy(luat_http_ctrl_t **p_http_ctrl)
{
	if (!p_http_ctrl) return -ERROR_PARAM_INVALID;
	luat_http_ctrl_t *http_ctrl = *p_http_ctrl;
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	LLOGD("user destroy http!");
	http_ctrl->state = HTTP_STATE_WAIT_CLOSE;

	OS_DeInitBuffer(&http_ctrl->request_head_buffer);
	OS_DeInitBuffer(&http_ctrl->response_head_buffer);
    http_close(http_ctrl);
	*p_http_ctrl = NULL;
	return 0;
}

int luat_http_client_get_status_code(luat_http_ctrl_t *http_ctrl)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	return http_ctrl->parser.status_code;
}

int luat_http_client_set_get_offset(luat_http_ctrl_t *http_ctrl, uint32_t offset)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state)
	{
		LLOGE("http running, stop and set!");
		return -ERROR_PERMISSION_DENIED;
	}
	http_ctrl->offset = offset;
	return 0;
}

int luat_http_client_pause(luat_http_ctrl_t *http_ctrl, uint8_t is_pause)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state != HTTP_STATE_GET_BODY)
	{
		LLOGE("http not recv body data, no use!");
		return -ERROR_PERMISSION_DENIED;
	}
	LLOGD("http pause state %d!", is_pause);
	http_ctrl->is_pause = is_pause;
	if (!http_ctrl->is_pause)
	{
		OS_EVENT event = {EV_NW_RESULT_EVENT, 0, 0, 0};
		luat_lib_http_callback(&event, http_ctrl);
	}
	return 0;
}

int luat_http_client_get_context_len(luat_http_ctrl_t *http_ctrl, uint32_t *len)
{
    if (http_ctrl->context_len_vaild)
    {
    	*len = http_ctrl->context_len;
    	return 0;
    }
    else
    {
        return -1;
    }
}

int luat_http_client_post_body(luat_http_ctrl_t *http_ctrl, void *data, uint32_t len)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state != HTTP_STATE_GET_HEAD)
	{
		return -ERROR_PERMISSION_DENIED;
	}
	http_send(http_ctrl, data, len);
	return 0;
}
int luat_http_client_start(luat_http_ctrl_t *http_ctrl, const char *url, uint8_t type, uint8_t ipv6, uint8_t data_mode)
{
	if (!http_ctrl) return -ERROR_PARAM_INVALID;
	if (http_ctrl->state)
	{
		LLOGE("http running, please stop and start");
		return -ERROR_PERMISSION_DENIED;
	}
	switch(type)
	{
	case 0:
	case 3:
		http_ctrl->is_post = 0;
		break;
	case 1:
	case 2:
		http_ctrl->is_post = 1;
		break;
	default:
		return -ERROR_PARAM_INVALID;
	}
    http_ctrl->luatos_mode = 0;
	http_ctrl->close_state = 0;
	http_ctrl->data_mode = data_mode;
	http_ctrl->re_request_count = 0;
	http_ctrl->body_len = 0;
	http_ctrl->remote_port = 0;
	http_ctrl->parser.status_code = 0;
	OS_ReInitBuffer(&http_ctrl->response_head_buffer, HTTP_HEADER_BASE_SIZE);
	network_connect_ipv6_domain(http_ctrl->netc, ipv6);

    if (http_ctrl->host)
    {
    	luat_heap_free(http_ctrl->host);
    	http_ctrl->host = NULL;
    }

    if (http_ctrl->request_line)
    {
    	luat_heap_free(http_ctrl->request_line);
    	http_ctrl->request_line = NULL;
    }

	char *tmp = (char *)url;
    if (!strncmp("https://", url, strlen("https://"))) {
        http_ctrl->is_tls = 1;
        tmp += strlen("https://");
    }
    else if (!strncmp("http://", url, strlen("http://"))) {
        http_ctrl->is_tls = 0;
        tmp += strlen("http://");
    }
    else {
        LLOGD("only http/https supported %s", url);
        return -ERROR_PARAM_INVALID;
    }

	int tmplen = strlen(tmp);
	if (tmplen < 5) {
        LLOGD("url too short %s", url);
        return -ERROR_PARAM_INVALID;
    }
	char tmphost[256] = {0};
    char *tmpuri = NULL;
    for (size_t i = 0; i < tmplen; i++){
        if (tmp[i] == '/') {
			if (i > 255) {
				LLOGD("host too long %s", url);
				return -ERROR_PARAM_INVALID;
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
        LLOGD("host not found %s", url);
        return -ERROR_PARAM_INVALID;
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
        LLOGD("out of memory when malloc host");
        return -ERROR_NO_MEMORY;
    }
    memcpy(http_ctrl->host, tmphost, strlen(tmphost) + 1);

	size_t linelen = strlen((char*)tmpuri) + 32;
    http_ctrl->request_line = luat_heap_malloc(linelen);
    if (http_ctrl->request_line == NULL) {
        LLOGD("out of memory when malloc url/request_line");
        return -ERROR_NO_MEMORY;
    }

    const char *me[4] = {
    		"GET","POST","PUT","DELETE"
    };
	snprintf_((char*)http_ctrl->request_line, 8192, "%s %s HTTP/1.1\r\n", me[type], tmpuri);

	if (http_ctrl->timeout)
	{
		luat_start_rtos_timer(http_ctrl->timeout_timer, http_ctrl->timeout, 1);
	}
	else
	{
		luat_stop_rtos_timer(http_ctrl->timeout_timer);
	}

	http_ctrl->state = HTTP_STATE_CONNECT;

    LLOGD("http connect %s:%d", http_ctrl->host, http_ctrl->remote_port);

    http_ctrl->error_code = HTTP_ERROR_CONNECT;
	http_ctrl->context_len_vaild = 0;
	http_ctrl->context_len = 0;
	if (network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), NULL, http_ctrl->remote_port, 0) < 0)
	{
		LLOGE("http can not connect!");
		network_close(http_ctrl->netc, 0);
		http_ctrl->state = HTTP_STATE_IDLE;
		return -1;
	}
	return 0;
}

int http_set_url(luat_http_ctrl_t *http_ctrl, const char* url, const char* method) {
	const char *tmp = url;
	if (strcmp("POST", method) != 0 && strcmp("GET", method) != 0 && strcmp("PUT", method) != 0){
		LLOGE("NOT SUPPORT %s",method);
		return -1;
	}
    if (!strncmp("https://", url, strlen("https://"))) {
        http_ctrl->is_tls = 1;
        tmp += strlen("https://");
    }
    else if (!strncmp("http://", url, strlen("http://"))) {
        http_ctrl->is_tls = 0;
        tmp += strlen("http://");
    }
    else {
        LLOGI("only http/https supported %s", url);
        return -1;
    }

	size_t tmplen = strlen(tmp);
	if (tmplen < 5) {
        LLOGI("url too short %s", url);
        return -1;
    }
	#define HOST_MAX_LEN (256)
	#define AUTH_MAX_LEN (128)
	char tmphost[HOST_MAX_LEN] = {0};
	char tmpauth[AUTH_MAX_LEN] = {0};
    const char *tmpuri = NULL;
    for (size_t i = 0; i < tmplen; i++){
        if (tmp[i] == '/') {
			if (i > 255) {
				LLOGI("host too long %s", url);
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
        LLOGI("host not found %s", url);
        return -1;
    }
    if (strlen(tmpuri) == 0) {
        tmpuri = "/";
    }
	// 先判断有无鉴权信息
	for (size_t i = 1; i < AUTH_MAX_LEN; i++){
		if (tmphost[i] == '@') {
			memcpy(tmpauth, tmphost, i);
			memmove(tmphost, tmphost + i + 1, strlen(tmphost) - i - 1);
			tmphost[strlen(tmphost) - i - 1] = 0x00;
			break;
		}
    }
    // LLOGD("tmphost:%s",tmphost);
	// LLOGD("tmpauth:%s", tmpauth);
	// LLOGD("tmpuri:%s",tmpuri);
	if(tmphost[0] != '[')
	{
		for (size_t i = 1; i < strlen(tmphost); i++){
			if (tmphost[i] == ':') {
				tmphost[i] = '\0';
				http_ctrl->remote_port = atoi(tmphost + i + 1);
				break;
			}
    	}
	}
	else
	{
		// ipv6地址
		uint16_t offset = 0;
		for (size_t i = 1; i < strlen(tmphost); i++){
			if (tmphost[i] == ']') {
				offset = i;
				break;
			}
	    }
		if (offset > 0) {
			for (size_t i = offset; i < strlen(tmphost); i++){
				if (tmphost[i] == ':') {
					tmphost[i] = '\0';
					http_ctrl->remote_port = atoi(tmphost + i + 1);
					break;
				}
		    }
			memmove(tmphost, tmphost + 1, offset - 1);
			tmphost[offset - 1] = 0x00;
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
	if (tmpauth[0]) {
		size_t tmplen = 0;
		http_ctrl->req_auth = luat_heap_malloc(strlen(tmpauth) * 2 + 64);
		if (http_ctrl->req_auth == NULL) {
        	LLOGE("out of memory when malloc auth");
        	return -1;
    	}
		memset(http_ctrl->req_auth, 0, strlen(tmpauth) * 2 + 64);
		memcpy(http_ctrl->req_auth, "Authorization: Basic ", strlen("Authorization: Basic "));
		luat_str_base64_encode((unsigned char *)http_ctrl->req_auth + strlen(http_ctrl->req_auth), 
			strlen(tmpauth) * 2, &tmplen, (const unsigned char *)tmpauth, strlen(tmpauth));
		memcpy(http_ctrl->req_auth + strlen(http_ctrl->req_auth), "\r\n", 2);
	}
    memcpy(http_ctrl->host, tmphost, strlen(tmphost) + 1);

	size_t linelen = strlen((char*)method) + strlen((char*)tmpuri) + 16;
    http_ctrl->request_line = luat_heap_malloc(linelen);
    if (http_ctrl->request_line == NULL) {
        LLOGE("out of memory when malloc url/request_line");
        return -1;
    }
	snprintf_((char*)http_ctrl->request_line, 8192, "%s %s HTTP/1.1\r\n", method, tmpuri);
	return 0;
}

int luat_http_client_start_luatos(luat_http_ctrl_t* http_ctrl) {
	http_ctrl->luatos_mode = 1;
	if(http_ctrl->timeout){
		http_ctrl->timeout_timer = luat_create_rtos_timer(luat_http_timer_callback, http_ctrl, NULL);
		luat_start_rtos_timer(http_ctrl->timeout_timer, http_ctrl->timeout, 0);
	}

	if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), NULL, http_ctrl->remote_port, 0) < 0){
		// network_close(http_ctrl->netc, 0);
		return -1;
	}
	return 0;
}

