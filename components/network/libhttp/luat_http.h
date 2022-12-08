#ifndef LUAT_HTTP_H
#define LUAT_HTTP_H

#define HTTP_REQUEST_BUF_LEN_MAX 	(1024)
#define HTTP_RESP_HEADER_MAX_SIZE 	(4096)

#define HTTP_OK 			(0)
#define HTTP_ERROR_STATE 	(-1)
#define HTTP_ERROR_HEADER 	(-2)
#define HTTP_ERROR_BODY 	(-3)
#define HTTP_ERROR_CONNECT 	(-4)
#define HTTP_ERROR_CLOSE 	(-5)
#define HTTP_ERROR_RX 		(-6)
#define HTTP_ERROR_DOWNLOAD (-7)

typedef struct{
	network_ctrl_t *netc;		// http netc
	luat_ip_addr_t ip_addr;		// http ip
	uint8_t is_tls;             // 是否SSL
	const char *host; 			// http host
	uint16_t remote_port; 		// 远程端口号
	const char *url;			// url
	const char *uri;			// uri
	const char *method;			// method

	// 发送相关
	uint8_t request_message[HTTP_REQUEST_BUF_LEN_MAX];
	const char *req_header;
	const char *req_body;		//发送body
	size_t req_body_len;		//发送body长度

	uint8_t is_download;		//是否下载
	const char *dst;			//下载路径
	//解析相关
	http_parser  parser;
	http_parser_settings parser_settings;
	char* headers;
	uint32_t headers_len;		//headers缓存长度
	char* body;
	uint32_t body_len;			//body缓存长度

	// 响应相关
	// uint32_t resp_content_len;	//content 长度
	FILE* fd;					//下载 FILE
	uint32_t fd_writed;
	uint64_t idp;
	uint16_t timeout;
	uint8_t close_state;
}luat_http_ctrl_t;

#endif
