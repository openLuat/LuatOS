#ifndef LUAT_FTP_H
#define LUAT_FTP_H

enum
{
	FTP_QUEUE_LOGIN = 1	,
	FTP_QUEUE_COMMAND 	,
	FTP_QUEUE_PULL 		,
	FTP_QUEUE_PUSH 		,
	FTP_QUEUE_CLOSE 	,
	FTP_QUEUE_DATA_CONNECT 	,
	FTP_QUEUE_DATA_TX_DONE 	,
};

enum
{
	FTP_COMMAND_PWD = 1	,
	FTP_COMMAND_SYST 	,
	FTP_COMMAND_PULL 	,
	FTP_COMMAND_PUSH 	,
	FTP_COMMAND_CLOSE 	,
};

#define FTP_OK 				(0)
#define FTP_ERROR_STATE 	(-1)
#define FTP_ERROR_HEADER 	(-2)
#define FTP_ERROR_BODY 		(-3)
#define FTP_ERROR_CONNECT 	(-4)
#define FTP_ERROR_CLOSE 	(-5)
#define FTP_ERROR_RX 		(-6)
#define FTP_ERROR_DOWNLOAD 	(-7)
#define FTP_ERROR_FILE		(-8)

#define FTP_RX_TIMEOUT 		(-6)

#define FTP_SOCKET_TIMEOUT 		(30000)

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
#define FTP_USERNAME_OK			"331" //User name okay, need password.

#define FTP_CMD_SEND_MAX 	(128)
#define FTP_CMD_RECV_MAX 	(1024)
#define PUSH_BUFF_SIZE 		(4096)

typedef struct{
	uint64_t idp;
	int adapter_index;
	network_ctrl_t *cmd_netc;		// ftp netc
	network_ctrl_t *data_netc;	// ftp data_netc
	luat_ip_addr_t ip_addr;		// ftp ip
	uint8_t is_tls;             // 是否SSL
	const char *addr; 			// ftp addr
	uint16_t port; 				// 端口号
	const char *username; 		// ftp username
	const char *password; 		// ftp password

	uint8_t ftp_execute;             // 
	const char *remote_name;
	
    luat_rtos_task_handle ftp_task_handle;
    luat_rtos_queue_t ftp_queue_handle;

	FILE* fd;					//下载 FILE
	size_t local_file_size;
	uint8_t *data_recv;
	uint32_t data_recv_len;

	uint8_t cmd_send_data[FTP_CMD_SEND_MAX];
	uint32_t cmd_send_len;
	uint8_t cmd_recv_data[FTP_CMD_RECV_MAX];
	uint32_t cmd_recv_len;
}luat_ftp_ctrl_t;

#endif
