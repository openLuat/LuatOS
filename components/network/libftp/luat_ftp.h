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

enum
{
	FTP_COMMAND_SYST = 1,
	FTP_COMMAND_PULL 	,
	FTP_COMMAND_PUSH 	,
	FTP_COMMAND_CLOSE 	,
};

typedef struct{
	char *server_cert;
	char *client_cert;
	char *client_key;
	char *client_password;
}luat_ftp_tls_t;



uint32_t luat_ftp_release(void);
int luat_ftp_close(void);
int luat_ftp_login(uint8_t adapter,const char * ip_addr,uint16_t port,const char * username,const char * password,luat_ftp_tls_t* luat_ftp_tls);
int luat_ftp_command(const char * command);
int luat_ftp_pull(const char * local_name,const char * remote_name);
int luat_ftp_push(const char * local_name,const char * remote_name);

#endif
