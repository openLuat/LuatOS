#ifndef LUAT_HTTP_H
#define LUAT_HTTP_H
#include "luat_network_adapter.h"
#include "luat_spi.h"
#include "luat_fota.h"
#ifdef __LUATOS__
#include "luat_zbuff.h"
#else
typedef enum {
    LUAT_HEAP_AUTO_DUMMY,
    LUAT_HEAP_SRAM_DUMMY,
    LUAT_HEAP_PSRAM_DUMMY,
} LUAT_HEAP_TYPE;//只是为了占位，不要使用
typedef struct luat_zbuff {
	LUAT_HEAP_TYPE type; //内存类型
    uint8_t* addr;      //数据存储的地址
    size_t len;       //实际分配空间的长度
    union {
    	size_t cursor;    //目前的指针位置，表明了处理了多少数据
    	size_t used;	//已经保存的数据量，表明了存了多少数据
    };

    uint32_t width; //宽度
    uint32_t height;//高度
    uint8_t bit;    //色深度
} luat_zbuff_t;
#endif


#if defined(AIR101) || defined(AIR103)
// #define HTTP_REQ_HEADER_MAX_SIZE 	(2048)
#define HTTP_RESP_BUFF_SIZE 		(2048)
#else
// #define HTTP_REQ_HEADER_MAX_SIZE 	(8192)
#define HTTP_RESP_BUFF_SIZE 		(8192)
#endif
#define HTTP_HEADER_BASE_SIZE 	(1024)
#include "http_parser.h"

#define HTTP_CALLBACK 		(1)
// #define HTTP_RE_REQUEST_MAX (3)
#define HTTP_TIMEOUT 		(5*60*1000) // 10分钟

/**
 * @defgroup luatos_HTTP  HTTP(S)相关接口
 * @{
 */
enum{
	HTTP_STATE_IDLE,
	HTTP_STATE_CONNECT,
	HTTP_STATE_SEND_HEAD,
	HTTP_STATE_SEND_BODY_START,
	HTTP_STATE_SEND_BODY,
	HTTP_STATE_GET_HEAD,
    HTTP_STATE_GET_HEAD_DONE,
	HTTP_STATE_GET_BODY,
    HTTP_STATE_GET_BODY_DONE,
	HTTP_STATE_DONE,
	HTTP_STATE_WAIT_CLOSE,
};

enum{
	HTTP_OK = 0,
    HTTP_ERROR_STATE 	= -1,
    HTTP_ERROR_HEADER 	= -2,
    HTTP_ERROR_BODY 	= -3,
    HTTP_ERROR_CONNECT 	= -4,
    HTTP_ERROR_CLOSE 	= -5,
    HTTP_ERROR_RX 		= -6,
    HTTP_ERROR_DOWNLOAD = -7,
    HTTP_ERROR_TIMEOUT  = -8,
    HTTP_ERROR_FOTA  	= -9,
};



/*
 * http运行过程的回调函数
 * status >=0 表示运行状态，看HTTP_STATE_XXX <0说明出错停止了，==0表示结束了
 * data 在获取响应阶段，会回调head数据，如果为NULL，则head接收完成了。如果设置了data_mode，body数据也直接回调。
 * data_len 数据长度，head接收时，每行会多加一个\0，方便字符串处理
 * user_param 用户自己的参数
 */
typedef void (*luat_http_cb)(int status, void *data, uint32_t data_len, void *user_param);

#define HTTP_GET_DATA 		(2)
#define HTTP_POST_DATA 		(1)


typedef struct{
	network_ctrl_t *netc;		// http netc
	http_parser  parser;	    //解析相关
	char *host; 			/**< http host，需要释放 */
	char* request_line;	/**< 需要释放，http请求的首行数据*/
	uint16_t remote_port; 		/**< 远程端口号 */
	uint8_t is_tls;             // 是否SSL
	uint8_t custom_host;        /**< 是否自定义Host了*/
	uint8_t custom_connection;        /**< 是否自定义Host了*/
	uint8_t is_post;
	uint8_t re_request_count;
	void* timeout_timer;			/**< timeout_timer 定时器*/
	uint32_t timeout;
	uint32_t tx_offset;
	// 发送相关
	char *req_header;
	char *req_body;				//发送body
	size_t req_body_len;		//发送body长度
    char *req_auth;
	void* http_cb;				/**< http 回调函数 */
	void* http_cb_userdata;				/**< http 回调函数用户传参*/
	uint8_t is_pause;
	uint8_t debug_onoff;
    uint8_t headers_complete;
    uint8_t close_state;
	char resp_buff[HTTP_RESP_BUFF_SIZE];
	size_t resp_buff_offset;
	size_t resp_headers_done;
	uint32_t body_len;			//body缓存长度

#ifdef LUAT_USE_FOTA
	//OTA相关
	uint8_t isfota;				//是否为ota下载
	uint32_t address;			
	uint32_t length;		
	luat_spi_device_t* spi_device;
#endif
	//下载相关
	uint8_t is_download;		//是否下载
	char *dst;			//下载路径
	// http_parser_settings parser_settings;
	char* headers;
	uint32_t headers_len;		//headers缓存长度
	char* body;

	// 响应相关
	int32_t resp_content_len;	//content 长度
	FILE* fd;					//下载 FILE
	luat_ip_addr_t ip_addr;		// http ip
	uint64_t idp;
	luat_zbuff_t *zbuff_body;

	Buffer_Struct request_head_buffer;	/**<存放用户自定义的请求head数据*/
	Buffer_Struct response_head_buffer;	/**<接收到的head数据缓存，回调给客户后就销毁了*/
	int error_code;
	uint32_t offset;
	uint32_t context_len;
	uint8_t retry_cnt_max;		/**<最大重试次数*/
	uint8_t state;
	uint8_t data_mode;
	uint8_t new_data;
	uint8_t context_len_vaild;
	uint8_t luatos_mode;
	// TCP连接是否已经关闭
	uint8_t tcp_closed;
	uint8_t http_body_is_finally;
	// 终态通知是否已发出(防重复上报)
	uint8_t finished;

	uint32_t idg;
}luat_http_ctrl_t;

//下面2个API是luatos内部使用，csdk不使用
int luat_http_client_init(luat_http_ctrl_t* http, int ipv6);
int luat_http_client_start_luatos(luat_http_ctrl_t* http);

#ifdef __LUATOS__
/**
 * luatos 模式下 http 客户端 -> lua 绑定 的跨线程通知消息(自包含)。
 * 所有权约定:
 *   1. 消息及其 headers/body 由生产者(网络回调线程)分配; luat_msgbus_put 成功后
 *      生产者不得再触碰, 由消费者(VM 线程)处理完后调用 luat_http_msg_free 释放
 *   2. 投递失败时由生产者调用 luat_http_msg_free 释放
 *   3. 消息绝不携带 luat_http_ctrl_t(指针也不带), 消费时机与 ctrl 生命周期无关,
 *      从根上避免多核平台上 luatos 与 lwip 对 http_ctrl 竞争 free
 */
typedef struct luat_http_msg {
	uint32_t idg;                /* 会话标识, 仅用于日志/排查 */
	int32_t  event;              /* HTTP_CALLBACK / 0(HTTP_OK) / HTTP_ERROR_xxx */
	int32_t  arg;                /* HTTP_CALLBACK 时为 body_len */
	int32_t  status_code;        /* parser.status_code 快照 */
	int32_t  resp_content_len;   /* 进度回调需要 */
	uint32_t body_len;           /* 响应长度快照 */
	uint64_t idp;                /* luat_pushcwait 返回的 token, 原样带回 */
	int32_t  http_cb;            /* lua registry ref, 0 表示无 */
	int32_t  http_cb_userdata;
	uint8_t  is_download;
	uint8_t  isfota;
	uint8_t  zbuff_mode;         /* 响应写入了用户 zbuff, 无 body 指针 */
	uint8_t  download_ok;        /* 终态: 下载完成且文件保留 */
	uint8_t  debug_onoff;
	char    *headers;            /* 终态: 所有权移交给消费者, 可为 NULL */
	uint32_t headers_len;
	char    *body;               /* 终态: 所有权移交给消费者, 可为 NULL */
} luat_http_msg_t;

void luat_http_msg_free(luat_http_msg_t *msg);
/* 通知入口: 返回 0 表示投递成功(消息所有权移交消费端); 非 0 表示投递失败(已由生产端释放)。
 * 强符号在 luat_lib_http.c(投递 msgbus), 弱符号在 luat_http_client.c(直接释放) */
int luat_http_client_onevent(luat_http_msg_t *msg);
/* 终态交付失败的兜底通知: 只带 idg/error 的轻量消息, 由 VM 线程完成 cwait/解除引用并负责
 * close, 避免 Lua 侧永久挂起。强符号在 luat_lib_http.c, 弱符号在 luat_http_client.c(空实现) */
void luat_http_fail_notify(uint32_t idg, int error_code);
#endif

/**
 * @brief 创建一个http客户端
 *
 * @param cb http运行过程回调函数
 * @param user_param 回调时用户自己的参数
 * @param adapter_index 网卡适配器，不清楚的写-1，系统自动分配
 * @return 成功返回客户端地址，失败返回NULL
 */
/* 注意: 该 API 是"同步 C 回调"风格(luatos_mode=0), 定时器仍持 http_ctrl 裸指针,
 * 仅适用于调用方自管生命周期、单线程回调的场景; 不要与 luat_http_client_start_luatos 混用 */
luat_http_ctrl_t* luat_http_client_create(luat_http_cb cb, void *user_param, int adapter_index);
/**
 * @brief http客户端的通用配置，创建客户端时已经有默认配置，可以不配置
 *
 * @param http_ctrl 客户端
 * @param timeout 单次数据传输超时时间，单位ms
 * @param debug_onoff 是否开启调试打印，开启后会占用一点系统资源
 * @param retry_cnt 因传输异常而重传的最大次数
 * @return 成功返回0，其他值失败
 */
int luat_http_client_base_config(luat_http_ctrl_t* http_ctrl, uint32_t timeout, uint8_t debug_onoff, uint8_t retry_cnt);
/**
 * @brief 客户端SSL配置，只有访问https才需要配置
 *
 * @param http_ctrl 客户端
 * @param mode <0 关闭SSL功能，并忽略后续参数; 0忽略证书验证过程，大部分https应用就可以这个配置，后续证书配置可以都写NULL和0; 2强制证书验证，后续证书相关参数必须写对
 * @param server_cert 服务器证书字符串，结尾必须有0，如果不忽略证书验证，这个必须有
 * @param server_cert_len 服务器证书数据长度，长度包含结尾的0，也就是strlen(server_cert) + 1
 * @param client_cert 客户端证书字符串，结尾必须有0，双向认证才有，一般金融行业可能会用
 * @param client_cert_len 客户端证书数据长度，长度包含结尾的0
 * @param client_cert_key 客户端证书私钥字符串，结尾必须有0，双向认证才有，一般金融行业可能会用
 * @param client_cert_key_len 客户端证书私钥数据长度，长度包含结尾的0
 * @param client_cert_key_password 客户端证书私钥密码字符串，结尾必须有0，双向认证才有，如果私钥没有密码保护，则不需要
 * @param client_cert_key_password_len 客户端证书私钥密码数据长度，长度包含结尾的0
 * @return 成功返回0，其他值失败
 */
int luat_http_client_ssl_config(luat_http_ctrl_t* http_ctrl, int mode, const char *server_cert, uint32_t server_cert_len,
		const char *client_cert, uint32_t client_cert_len,
		const char *client_cert_key, uint32_t client_cert_key_len,
		const char *client_cert_key_password, uint32_t client_cert_key_password_len);

/**
 * @brief 清空用户设置的POST数据和request head参数
 *
 * @param http_ctrl 客户端
 * @return 成功返回0，其他值失败
 */

int luat_http_client_clear(luat_http_ctrl_t *http_ctrl);

/**
 * @brief 设置一条用户的request head参数，Content-Length一般不需要，在设置POST的body时自动生成
 *
 * @param http_ctrl 客户端
 * @param name head参数的name
 * @param value head参数的value
 * @return 成功返回0，其他值失败
 */
int luat_http_client_set_user_head(luat_http_ctrl_t *http_ctrl, const char *name, const char *value);


/**
 * @brief 启动一个http请求
 *
 * @param http_ctrl 客户端
 * @param url http请求完整的url，如果有转义字符需要提前转义好
 * @param type 请求类型，0 get 1 post 2 put 3 delete
 * @param ipv6 是否存在IPV6的服务器
 * @param data_mode 大数据模式，接收数据超过1KB的时候，必须开启。开启后请求头里自动加入"Accept: application/octet-stream\r\n"
 * @return 成功返回0，其他值失败
 */
int luat_http_client_start(luat_http_ctrl_t *http_ctrl, const char *url, uint8_t type, uint8_t ipv6, uint8_t continue_mode);
/**
 * @brief 停止当前的http请求，调用后不再有http回调了
 *
 * @param http_ctrl 客户端
 * @return 成功返回0，其他值失败
 */

int luat_http_client_close(luat_http_ctrl_t *http_ctrl);
/**
 * @brief 完全释放掉当前的http客户端
 *
 * @param p_http_ctrl 客户端指针的地址
 * @return 成功返回0，其他值失败
 */
int luat_http_client_destroy(luat_http_ctrl_t **p_http_ctrl);

/**
 * @brief POST请求时发送body数据，如果数据量比较大，可以在HTTP_STATE_SEND_BODY回调里分次发送
 *
 * @param http_ctrl 客户端
 * @param data body数据
 * @param len body数据长度
 * @return 成功返回0，其他值失败
 */
int luat_http_client_post_body(luat_http_ctrl_t *http_ctrl, void *data, uint32_t len);
/**
 * @brief http获取状态码
 *
 * @param http_ctrl 客户端
 * @return 状态码
 */
int luat_http_client_get_status_code(luat_http_ctrl_t *http_ctrl);
/**
 * @brief http客户端设置暂停
 *
 * @param http_ctrl 客户端
 * @param is_pause 是否暂停
 * @return 成功返回0，其他值失败
 */
int luat_http_client_pause(luat_http_ctrl_t *http_ctrl, uint8_t is_pause);
/**
 * @brief GET请求时要求服务器从offset位置开始传输数据，谨慎使用
 *
 * @param http_ctrl 客户端
 * @param offset 偏移位置
 * @return 成功返回0，其他值失败
 */
int luat_http_client_set_get_offset(luat_http_ctrl_t *http_ctrl, uint32_t offset);
/**
 * @brief 获取context length
 *
 * @param http_ctrl 客户端
 * @param len context length值
 * @return 成功返回0，其他值失败或者是chunk编码
 */
int luat_http_client_get_context_len(luat_http_ctrl_t *http_ctrl, uint32_t *len);

uint32_t luat_http_idg_register(luat_http_ctrl_t *http_ctrl);

luat_http_ctrl_t* luat_http_idg_get(uint32_t idg);

/* 原子认领: 一次临界区内 get+unreg, 成功返回 ctrl 并摘除注册, 之后该 idg 一律查不到。
 * 供 close/释放路径防重复释放(竞争 free 防线) */
luat_http_ctrl_t* luat_http_idg_claim(uint32_t idg);

int luat_http_idg_unreg(uint32_t idg);
/** @}*/
#endif

