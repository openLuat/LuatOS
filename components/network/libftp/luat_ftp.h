#ifndef LUAT_FTP_H
#define LUAT_FTP_H

#define FTP_CMD_SEND_MAX 		(128)
#define FTP_CMD_RECV_MAX 		(1024)
#define PUSH_BUFF_SIZE 			(4096)
#define FTP_SOCKET_TIMEOUT 		(30000)

#define FTP_OK 					(0)
#define FTP_ERROR_STATE 		(-1)
#define FTP_ERROR_HEADER 		(-2)
#define FTP_ERROR_BODY 			(-3)
#define FTP_ERROR_CONNECT 		(-4)
#define FTP_ERROR_CLOSE 		(-5)
#define FTP_ERROR_RX 			(-6)
#define FTP_ERROR_DOWNLOAD 		(-7)
#define FTP_ERROR_FILE			(-8)
#define FTP_ERROR_NO_MEM 		(-9)
#define FTP_ERROR_NETWORK 		(-10)
#define FTP_RX_TIMEOUT 			(-6)

#define FTP_RESTART_MARKER 		"110" //Restart marker reply.
#define FTP_SERVICE_MIN_OK 		"120" //Service ready in nnn minutes.
#define FTP_DATA_CON_OPEN 		"125" //Data connection already open; transfer starting.
#define FTP_FILE_STATUS_OK 		"150" //File status okay; about to open data connection.
#define FTP_COMMAND_OK 			"200" //Command okay.
#define FTP_COM_NOT_IMP 		"202" //Command not implemented, superfluous at this site.
#define FTP_SYSTEM_STATUS 		"211" //System status, or system help reply.
#define FTP_DIRECTORY_STATUS 	"212" //Directory status.
#define FTP_FILE_STATUS 		"213" //File status.
#define FTP_HELP_MESSAGE 		"214" //Help message.
#define FTP_SYSTEM_TYPE 		"215" //NAME system type.
#define FTP_SERVICE_NEW_OK 		"220" //Service ready for new user.
#define FTP_CLOSE_CONTROL 		"221" //Service closing control connection.
#define FTP_CLOSE_CONNECT 		"226" //Closing data connection.
#define FTP_ENTER_PASSIVE 		"227" //Entering Passive Mode (h1,h2,h3,h4,p1,p2).
#define FTP_LOGIN_OK 			"230" //User logged in, proceed.
#define FTP_FILE_REQUESTED_OK 	"250" //Requested file action okay, completed.
#define FTP_PATHNAME_OK 		"257" //"PATHNAME" created.
#define FTP_USERNAME_OK			"331" //User name okay, need password.
#define FTP_DATA_CON_FAIL		"425" //Can't open data connection.

typedef enum{
	FTP_ERROR 			,
	FTP_SUCCESS_NO_DATE ,
	FTP_SUCCESS_DATE 	,
}FTP_SUCCESS_STATE_e;

enum{
	FTP_COMMAND_SYST = 1,
	FTP_COMMAND_PULL 	,
	FTP_COMMAND_PUSH 	,
	FTP_COMMAND_CLOSE 	,
};

enum{
	FTP_REQ_LOGIN = 1	,
	FTP_REQ_COMMAND 	,
	FTP_REQ_PULL 		,
	FTP_REQ_PUSH 		,
	FTP_REQ_CLOSE 		,

	FTP_EVENT_LOGIN = USER_EVENT_ID_START + FTP_REQ_LOGIN,
	FTP_EVENT_COMMAND 	,
	FTP_EVENT_PULL 		,
	FTP_EVENT_PUSH 		,
	FTP_EVENT_CLOSE 	,
	FTP_EVENT_DATA_CONNECT 	,
	FTP_EVENT_DATA_TX_DONE 	,
	FTP_EVENT_DATA_WRITE_FILE 	,
	FTP_EVENT_DATA_CLOSED 	,
};

typedef struct{
	network_ctrl_t *cmd_netc;		// ftp netc
	network_ctrl_t *data_netc;	// ftp data_netc
	luat_ip_addr_t ip_addr;		// ftp ip
	char addr[64]; 			// ftp addr
	char username[64]; 		// ftp username
	char password[64]; 		// ftp password
	char remote_name[64];//去掉？
    size_t upload_done_size;
	size_t local_file_size;
	uint8_t cmd_send_data[FTP_CMD_SEND_MAX];
	uint32_t cmd_send_len;
	uint8_t cmd_recv_data[FTP_CMD_RECV_MAX];
	uint32_t cmd_recv_len;
	uint16_t port; 				// 端口号
	uint8_t adapter_index;
	uint8_t data_netc_online;
	uint8_t data_netc_connecting;
	void* ftp_cb;			/**< mqtt 回调函数*/
}luat_ftp_network_t;

typedef struct{
	luat_rtos_task_handle task_handle;
	luat_ftp_network_t *network;
	FILE* fd;					//下载 FILE
	Buffer_Struct result_buffer;
	uint8_t is_run;
}luat_ftp_ctrl_t;

typedef struct{
	const char *server_cert;
	const char *client_cert;
	const char *client_key;
	const char *client_password;
}luat_ftp_tls_t;

typedef void (*luat_ftp_cb_t)(luat_ftp_ctrl_t *luat_ftp_ctrl, FTP_SUCCESS_STATE_e event);

uint32_t luat_ftp_release(void);
int luat_ftp_close(void);
int luat_ftp_login(uint8_t adapter,const char * ip_addr,uint16_t port,const char * username,const char * password,luat_ftp_tls_t* luat_ftp_tls,luat_ftp_cb_t ftp_cb);
int luat_ftp_command(const char * command);
int luat_ftp_pull(const char * local_name,const char * remote_name);
int luat_ftp_push(const char * local_name,const char * remote_name);

#endif
