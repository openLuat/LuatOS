
#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
// #include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "http_parser.h"
#include "luat_spi.h"
#include "luat_http.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

#define HTTP_DEBUG 0
#if HTTP_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

static void http_send_message(luat_http_ctrl_t *http_ctrl);
int32_t luat_lib_http_callback(void *data, void *param);
void luat_http_client_onevent(luat_http_ctrl_t *http_ctrl, int arg1, int arg2);

int http_close(luat_http_ctrl_t *http_ctrl){
	LLOGD("http close %p", http_ctrl);
	if (http_ctrl->netc){
		network_force_close_socket(http_ctrl->netc);
		network_release_ctrl(http_ctrl->netc);
		http_ctrl->netc = NULL;
	}
	if (http_ctrl->timeout_timer){
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
	luat_heap_free(http_ctrl);
	return 0;
}

static void http_resp_error(luat_http_ctrl_t *http_ctrl, int error_code) {
	LLOGD("http_resp_error error_code:%d close_state:%d",error_code,http_ctrl->close_state);
#ifdef LUAT_USE_FOTA
	if (http_ctrl->isfota){
		luat_fota_end(0);
		if (http_ctrl->parser.status_code){
			error_code = 0;
		}
		luat_http_client_onevent(http_ctrl, error_code, 0);
	}
#endif
	if (http_ctrl->close_state == 0 && http_ctrl->headers_complete && http_ctrl->re_request_count < HTTP_RE_REQUEST_MAX){
		http_ctrl->re_request_count++;
		if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), NULL, http_ctrl->remote_port, 0) < 0){
			goto error;
		}
	}else if (http_ctrl->close_state==0){
error:
		http_ctrl->close_state=1;
		network_close(http_ctrl->netc, 0);
		luat_http_client_onevent(http_ctrl, error_code, 0);
	}
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
#ifdef LUAT_USE_FOTA
	else if(http_ctrl->isfota){
		luat_fota_init(http_ctrl->address, http_ctrl->length, http_ctrl->spi_device, NULL, 0);
	}
#endif
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
	}
#ifdef LUAT_USE_FOTA
	else if(http_ctrl->isfota && parser->status_code == 200){
		if (luat_fota_write((uint8_t*)at, length) < 0){
			luat_fota_end(0);
			http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
			return -1;
		}
	}
#endif
	else{
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
#ifdef LUAT_USE_FOTA
	else if(http_ctrl->isfota){
		if (parser->status_code == 200){
			int result = luat_fota_done();
			while (result>0){
				luat_timer_mdelay(100);
				result = luat_fota_done();
			}
			if (result==0){
				luat_fota_end(1);
			}else{
				luat_fota_end(0);
				http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
				return -1;
			}
		}else{
			luat_fota_end(0);
			http_ctrl->close_state = 1;
			network_close(http_ctrl->netc, 0);
			http_resp_error(http_ctrl, HTTP_ERROR_FOTA);
			return -1;
		}
	}
#endif
	LLOGD("status_code:%d",parser->status_code);
	LLOGD("content_length:%lld",parser->content_length);
	http_ctrl->close_state = 1;
	network_close(http_ctrl->netc, 0);
	luat_http_client_onevent(http_ctrl, HTTP_OK, 0);
    return 0;
}

static int on_chunk_header(http_parser* parser){
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


    http_parser_init(&http_ctrl->parser, HTTP_RESPONSE);
	http_ctrl->parser.data = http_ctrl;
	return 0;
}


static uint32_t http_send(luat_http_ctrl_t *http_ctrl, uint8_t* data, size_t len) {
	if (len == 0)
		return 0;
	uint32_t tx_len = 0;
	LLOGD("http_send data:%.*s",len,data);
	network_tx(http_ctrl->netc, data, len, 0, NULL, 0, &tx_len, 0);
	return tx_len;
}

static void http_send_message(luat_http_ctrl_t *http_ctrl){
	uint32_t tx_len = 0;
	// 发送请求行, 主要,这里都借用了resp_buff,但这并不会与resp冲突
	http_send(http_ctrl, http_ctrl->request_line, strlen((char*)http_ctrl->request_line));
	// 判断自定义headers是否有host
	if (http_ctrl->custom_host == 0) {
		snprintf_((char*)http_ctrl->resp_buff, HTTP_RESP_BUFF_SIZE,  "Host: %s\r\n", http_ctrl->host);
		http_send(http_ctrl, (uint8_t*)http_ctrl->resp_buff, strlen((char*)http_ctrl->resp_buff));
	}

	if (http_ctrl->headers_complete){
		snprintf_((char*)http_ctrl->resp_buff, HTTP_RESP_BUFF_SIZE,  "Range: bytes=%d-\r\n", http_ctrl->body_len+1);
		http_send(http_ctrl, (uint8_t*)http_ctrl->resp_buff, strlen((char*)http_ctrl->resp_buff));
	}
	
	// 发送自定义头部
	if (http_ctrl->req_header){
		http_send(http_ctrl, (uint8_t*)http_ctrl->req_header, strlen((char*)http_ctrl->req_header));
	}

	// 结束头部
	http_send(http_ctrl, (uint8_t*)"\r\n", 2);
	// 发送body
	if (http_ctrl->req_body){
		http_send(http_ctrl, (uint8_t*)http_ctrl->req_body, http_ctrl->req_body_len);
	}
}

LUAT_RT_RET_TYPE luat_http_timer_callback(LUAT_RT_CB_PARAM){
	luat_http_ctrl_t * http_ctrl = (luat_http_ctrl_t *)param;
	http_resp_error(http_ctrl, HTTP_ERROR_TIMEOUT);
}

int32_t luat_lib_http_callback(void *data, void *param){
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
		http_ctrl->resp_buff_offset = 0; // 复位resp缓冲区
		http_ctrl->resp_headers_done = 0;
		// TODO header 保持原始数据,在lua回调时才导出数据
		// if (http_ctrl->resp_headers) {
		// 	luat_heap_free(http_ctrl->resp_headers);
		// 	http_ctrl->resp_headers = NULL;
		// }
		http_send_message(http_ctrl);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t total_len = 0;
		uint32_t rx_len = 0;
		while (1) {
			int result = network_rx(http_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
			if (result) {
				http_resp_error(http_ctrl, HTTP_ERROR_RX);
				return -1;
			}
			if (0 == total_len)
				break;
			if (http_ctrl->resp_buff_offset + total_len > (HTTP_RESP_BUFF_SIZE - 1)) {
				total_len = HTTP_RESP_BUFF_SIZE - 1 - http_ctrl->resp_buff_offset;
				if (total_len < 1) {
					// 能到这里的就是片段太长了
					// 要么header太长, 要么chunked太长,拒绝吧
					http_resp_error(http_ctrl, HTTP_ERROR_RX);
					return -1;
				}
			}
			result = network_rx(http_ctrl->netc, (uint8_t*)http_ctrl->resp_buff, total_len, 0, NULL, NULL, &rx_len);
			LLOGD("result:%d rx_len:%d",result,rx_len);
			if (rx_len == 0||result!=0) {
				http_resp_error(http_ctrl, HTTP_ERROR_RX);
				return -1;
			}
			http_ctrl->resp_buff_offset += rx_len;
			// LLOGDUMP(http_ctrl->resp_buff, http_ctrl->resp_buff_offset);
			uint8_t *tmp = (uint8_t*)http_ctrl->resp_buff;
			// LLOGD("resp buff %.*s", http_ctrl->resp_buff_offset, http_ctrl->resp_buff);
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
				int nParseBytes = http_parser_execute(&http_ctrl->parser, &parser_settings, http_ctrl->resp_buff, http_ctrl->resp_buff_offset);
				LLOGD("nParseBytes %d resp_buff_offset %d", nParseBytes, http_ctrl->resp_buff_offset);
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

int http_set_url(luat_http_ctrl_t *http_ctrl, const char* url, const char* method) {
	char *tmp = url;
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

	int tmplen = strlen(tmp);
	if (tmplen < 5) {
        LLOGI("url too short %s", url);
        return -1;
    }
	char tmphost[256] = {0};
    char *tmpuri = NULL;
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

	size_t linelen = strlen((char*)method) + strlen((char*)tmpuri) + 16;
    http_ctrl->request_line = luat_heap_malloc(linelen);
    if (http_ctrl->request_line == NULL) {
        LLOGE("out of memory when malloc url/request_line");
        return -1;
    }
	snprintf_((char*)http_ctrl->request_line, 8192, "%s %s HTTP/1.1\r\n", method, tmpuri);
	return 0;
}

int luat_http_client_start(luat_http_ctrl_t* http_ctrl) {
	if(http_ctrl->timeout){
		http_ctrl->timeout_timer = luat_create_rtos_timer(luat_http_timer_callback, http_ctrl, NULL);
		luat_start_rtos_timer(http_ctrl->timeout_timer, http_ctrl->timeout, 0);
	}

	if(network_connect(http_ctrl->netc, http_ctrl->host, strlen(http_ctrl->host), NULL, http_ctrl->remote_port, 0) < 0){
		network_close(http_ctrl->netc, 0);
		return -1;
	}
	return 0;
}

