/*
@module  ftp
@summary ftp 客户端
@version 1.0
@date    2022.09.05
@demo    ftp
@tag LUAT_USE_FTP
*/

#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#include "luat_ftp.h"

#define LUAT_LOG_TAG "ftp"
#include "luat_log.h"

#define FTP_DEBUG 0
#if FTP_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

enum
{
	FTP_REQ_LOGIN = 1,
	FTP_REQ_COMMAND 	,
	FTP_REQ_PULL 		,
	FTP_REQ_PUSH 		,
	FTP_REQ_CLOSE 	,


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
	const char *addr; 			// ftp addr
	const char *username; 		// ftp username
	const char *password; 		// ftp password
	const char *remote_name;//去掉？
    size_t upload_done_size;
	size_t local_file_size;
	uint8_t cmd_send_data[FTP_CMD_SEND_MAX];
	uint32_t cmd_send_len;
	uint8_t cmd_recv_data[FTP_CMD_RECV_MAX];
	uint32_t cmd_recv_len;
	uint16_t port; 				// 端口号
	uint8_t is_tls;             // 是否SSL
	uint8_t adapter_index;
	uint8_t data_netc_online;
	uint8_t data_netc_connecting;
}luat_ftp_network_t;

typedef struct{
	uint64_t idp;
	luat_rtos_task_handle task_handle;
	luat_ftp_network_t *network;
	FILE* fd;					//下载 FILE
	Buffer_Struct result_buffer;
	uint8_t is_run;
}luat_ftp_ctrl_t;


static luat_ftp_ctrl_t g_s_ftp;

static uint32_t luat_ftp_close(void) {
	if (!g_s_ftp.network) return 0;
	if (g_s_ftp.network->cmd_netc){
		if (network_close(g_s_ftp.network->cmd_netc,FTP_SOCKET_TIMEOUT) < 0)
		{
			network_force_close_socket(g_s_ftp.network->cmd_netc);
		}
		network_release_ctrl(g_s_ftp.network->cmd_netc);
		g_s_ftp.network->cmd_netc = NULL;
	}
	if (g_s_ftp.network->data_netc){
		network_force_close_socket(g_s_ftp.network->data_netc);
		network_release_ctrl(g_s_ftp.network->data_netc);
		g_s_ftp.network->data_netc = NULL;
	}
	if (g_s_ftp.network->addr){
		luat_heap_free(g_s_ftp.network->addr);
		g_s_ftp.network->addr = NULL;
	}
	if (g_s_ftp.network->username){
		luat_heap_free(g_s_ftp.network->username);
		g_s_ftp.network->username = NULL;
	}
	if (g_s_ftp.network->password){
		luat_heap_free(g_s_ftp.network->password);
		g_s_ftp.network->password = NULL;
	}
	if (g_s_ftp.network->remote_name){
		luat_heap_free(g_s_ftp.network->remote_name);
		g_s_ftp.network->remote_name = NULL;
	}
	luat_heap_free(g_s_ftp.network);
	g_s_ftp.network = NULL;
	return 0;
}

static uint32_t luat_ftp_data_send(luat_ftp_ctrl_t *ftp_ctrl, uint8_t* send_data, uint32_t send_len) {
	if (send_len == 0)
		return 0;
	uint32_t tx_len = 0;
	LLOGD("luat_ftp_data_send data:%d",send_len);
	network_tx(g_s_ftp.network->data_netc, send_data, send_len, 0, NULL, 0, &tx_len, 0);
	return tx_len;
}

static uint32_t luat_ftp_cmd_send(luat_ftp_ctrl_t *ftp_ctrl, uint8_t* send_data, uint32_t send_len,uint32_t timeout_ms) {
	if (send_len == 0)
		return 0;
	uint32_t tx_len = 0;
	LLOGD("luat_ftp_cmd_send data:%.*s",send_len,send_data);
	network_tx(g_s_ftp.network->cmd_netc, send_data, send_len, 0, NULL, 0, &tx_len, timeout_ms);
	return tx_len;
}

static int luat_ftp_cmd_recv(luat_ftp_ctrl_t *ftp_ctrl,uint8_t *recv_data,uint32_t *recv_len,uint32_t timeout_ms){
	uint32_t total_len = 0;
	uint8_t is_break = 0,is_timeout = 0;
	int ret = network_wait_rx(g_s_ftp.network->cmd_netc, timeout_ms, &is_break, &is_timeout);
	LLOGD("network_wait_rx ret:%d is_break:%d is_timeout:%d",ret,is_break,is_timeout);
	if (ret)
		return -1;
	if (is_timeout)
		return 1;
	else if (is_break)
		return 2;
	int result = network_rx(g_s_ftp.network->cmd_netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (0 == result){
		if (total_len>0){
next:
			result = network_rx(g_s_ftp.network->cmd_netc, recv_data, total_len, 0, NULL, NULL, recv_len);
			LLOGD("result:%d recv_len:%d",result,*recv_len);
			LLOGD("recv_data %.*s",total_len, recv_data);
			if (result)
				goto next;
			if (*recv_len == 0||result!=0) {
				return -1;
			}
			return 0;
		}
	}else{
		LLOGE("ftp network_rx fail");
		return -1;
	}
	return 0;
}

static int32_t l_ftp_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
	LLOGD("l_ftp_callback arg1:%d arg2:%d idp:%lld",msg->arg1,msg->arg2,g_s_ftp.idp);
	if (g_s_ftp.idp)
	{
		if (msg->arg1)
		{
			lua_pushboolean(L, 0);
		}
		else if (msg->arg2)
		{
			lua_pushlstring(L,(const char *)(g_s_ftp.result_buffer.Data),g_s_ftp.result_buffer.Pos);
		}
		else
		{
			lua_pushboolean(L, 1);
		}
		luat_cbcwait(L, g_s_ftp.idp, 1);
		g_s_ftp.idp = 0;
	}
	OS_DeInitBuffer(&g_s_ftp.result_buffer);
	if (g_s_ftp.fd){
		luat_fs_fclose(g_s_ftp.fd);
		g_s_ftp.fd = NULL;
	}
	return 0;
}

static int32_t luat_ftp_data_callback(void *data, void *param){
	OS_EVENT *event = (OS_EVENT *)data;
	uint8_t *rx_buffer;
	int ret = 0;
	uint32_t rx_len = 0;
	if (!g_s_ftp.network)
	{
		return 0;
	}
	// LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("luat_ftp_data_callback %d %d",event->ID - EV_NW_RESULT_BASE, event->Param1);
	if (event->Param1){
		if (EV_NW_RESULT_CONNECT == event->ID)
		{
			luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_CONNECT, 0xffffffff, 0, 0, LUAT_WAIT_FOREVER);
		}
		else
		{
			luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_CLOSED, 0, 0, 0, LUAT_WAIT_FOREVER);
		}
		return -1;
	}
	switch (event->ID)
	{
	case EV_NW_RESULT_TX:
		luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_TX_DONE, 0, 0, 0, LUAT_WAIT_FOREVER);
		break;
	case EV_NW_RESULT_EVENT:
		rx_buffer = luat_heap_malloc(4096);
		do
		{
			ret = network_rx(g_s_ftp.network->data_netc, rx_buffer, 4096, 0, NULL, NULL, &rx_len);
			if (!ret && rx_len > 0)
			{
				if (g_s_ftp.fd)
				{
					luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_WRITE_FILE, rx_buffer, rx_len, 0, LUAT_WAIT_FOREVER);
					rx_buffer = luat_heap_malloc(4096);
				}
				else
				{
					OS_BufferWrite(&g_s_ftp.result_buffer, rx_buffer, rx_len);
				}
			}
		} while (!ret && rx_len);
		luat_heap_free(rx_buffer);

		break;
	case EV_NW_RESULT_CLOSE:
		luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_CLOSED, 0, 0, 0, LUAT_WAIT_FOREVER);
		return 0;
		break;
	case EV_NW_RESULT_CONNECT:
		luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_CONNECT, 0, 0, 0, LUAT_WAIT_FOREVER);
		break;
	case EV_NW_RESULT_LINK:
		return 0;
	}

	ret = network_wait_event(g_s_ftp.network->data_netc, NULL, 0, NULL);
	if (ret < 0){
		network_close(g_s_ftp.network->data_netc, 0);
		return -1;
	}
    return 0;
}

static int32_t ftp_task_cb(void *pdata, void *param)
{
	OS_EVENT *event = pdata;
	uint8_t *rx_buffer;
	int ret = 0;
	uint32_t rx_len = 0;
	if (event->ID >= FTP_EVENT_LOGIN && event->ID <= FTP_EVENT_PUSH)
	{
		LLOGE("last cmd not finish, ignore %d,%u,%u,%x", event->ID - USER_EVENT_ID_START, event->Param1, event->Param2, param);
		return -1;
	}
	switch(event->ID)
	{
	case FTP_EVENT_DATA_WRITE_FILE:
		if (g_s_ftp.fd)
		{
			luat_fs_fwrite(event->Param1, event->Param2, 1, g_s_ftp.fd);
			luat_heap_free(event->Param1);
		}
		break;
	case FTP_EVENT_DATA_TX_DONE:
		g_s_ftp.network->upload_done_size = (size_t)g_s_ftp.network->data_netc->ack_size;
		if (g_s_ftp.network->upload_done_size >= g_s_ftp.network->local_file_size)
		{
			LLOGD("ftp data upload done!");
			network_close(g_s_ftp.network->data_netc, 0);
		}
		break;
	case FTP_EVENT_DATA_CONNECT:
		if (g_s_ftp.network->data_netc_connecting)
		{
			g_s_ftp.network->data_netc_connecting = 0;
			g_s_ftp.network->data_netc_online = !event->Param1;
		}
		break;
	case FTP_EVENT_DATA_CLOSED:
		LLOGD("ftp data channel close");
		g_s_ftp.network->data_netc_online = 0;
		if (g_s_ftp.network->data_netc)
		{
			network_force_close_socket(g_s_ftp.network->data_netc);
			network_release_ctrl(g_s_ftp.network->data_netc);
			g_s_ftp.network->data_netc = NULL;
		}
		break;
	case FTP_EVENT_CLOSE:
		g_s_ftp.is_run = 0;
		break;
	default:
//		LLOGE("ignore %x,%x,%x", event->ID, param, EV_NW_RESULT_EVENT);
		break;
	}
	return 0;
}

static int luat_ftp_pasv_connect(luat_ftp_ctrl_t *ftp_ctrl,uint32_t timeout_ms){
	char h1[4]={0},h2[4]={0},h3[4]={0},h4[4]={0},p1[4]={0},p2[4]={0},data_addr[20]={0};
	uint8_t port1,port2;
	uint16_t data_port;	
	luat_ftp_cmd_send(g_s_ftp.network, (uint8_t*)"PASV\r\n", strlen("PASV\r\n"),FTP_SOCKET_TIMEOUT);
	int ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		return -1;
	}else{
		LLOGD("luat_ftp_pasv_connect cmd_recv_data",g_s_ftp.network->cmd_recv_data);
		if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_ENTER_PASSIVE, 3)){
			LLOGD("ftp pasv_connect wrong");
			return -1;
		}
	}
    char *temp = memchr(g_s_ftp.network->cmd_recv_data, '(', strlen((const char *)(g_s_ftp.network->cmd_recv_data)));
    char *temp1 = memchr(temp+1, ',', strlen(temp)-1);
    memcpy(h1, temp+1, temp1-temp-1);
    char *temp2 = memchr(temp1+1, ',', strlen(temp1)-1);
    memcpy(h2, temp1+1, temp2-temp1-1);
    char *temp3 = memchr(temp2+1, ',', strlen(temp2)-1);
    memcpy(h3, temp2+1, temp3-temp2-1);
    char *temp4 = memchr(temp3+1, ',', strlen(temp3)-1);
    memcpy(h4, temp3+1, temp4-temp3-1);
    char *temp5 = memchr(temp4+1, ',', strlen(temp4)-1);
    memcpy(p1, temp4+1, temp5-temp4-1);
    char *temp6 = memchr(temp5+1, ')', strlen(temp5)-1);
    memcpy(p2, temp5+1, temp6-temp5-1);
	snprintf_(data_addr, 20, "%s.%s.%s.%s",h1,h2,h3,h4);
	port1 = (uint8_t)atoi(p1);
	port2 = (uint8_t)atoi(p2);
	data_port = port1 * 256 + port2;
	LLOGD("data_addr:%s data_port:%d",data_addr,data_port);
	if (g_s_ftp.network->data_netc)
	{
		LLOGE("data_netc already create");
		return -1;
	}
	g_s_ftp.network->data_netc = network_alloc_ctrl(g_s_ftp.network->adapter_index);
	if (!g_s_ftp.network->data_netc){
		LLOGE("data_netc create fail");
		return -1;
	}
	network_init_ctrl(g_s_ftp.network->data_netc,NULL, luat_ftp_data_callback, g_s_ftp.network);
	network_set_base_mode(g_s_ftp.network->data_netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(g_s_ftp.network->data_netc, 0);
	network_deinit_tls(g_s_ftp.network->data_netc);
	if(network_connect(g_s_ftp.network->data_netc, data_addr, strlen(data_addr), NULL, data_port, 0)<0){
		LLOGE("ftp data network connect fail");
		network_force_close_socket(g_s_ftp.network->data_netc);
		network_release_ctrl(g_s_ftp.network->data_netc);
		g_s_ftp.network->data_netc = NULL;
		return -1;
	}
	uint8_t is_timeout;
	OS_EVENT event;
	g_s_ftp.network->data_netc_connecting = 1;
	g_s_ftp.network->data_netc_online = 0;
	while(g_s_ftp.network->data_netc_connecting)
	{
		if (network_wait_event(g_s_ftp.network->cmd_netc, &event, timeout_ms, &is_timeout))
		{
			return -1;
		}
		if (is_timeout)
		{
			return -1;
		}
		if (event.ID)
		{
			ftp_task_cb(&event, NULL);
		}
		else
		{
        	if (g_s_ftp.network->cmd_netc->new_rx_flag)
        	{
        		network_rx(g_s_ftp.network->cmd_netc, g_s_ftp.network->cmd_recv_data, 1024, 0, NULL, NULL, &g_s_ftp.network->cmd_recv_len);
        		LLOGD("ftp cmd rx %.*s", g_s_ftp.network->cmd_recv_len, g_s_ftp.network->cmd_recv_data);
        	}
		}
	}
	if (g_s_ftp.network->data_netc_online)
	{
		LLOGD("ftp pasv_connect ok");
		return 0;
	}
	return -1;
}



static int ftp_login(void)
{
	int ret;
	if(network_connect(g_s_ftp.network->cmd_netc, g_s_ftp.network->addr, strlen(g_s_ftp.network->addr), NULL, g_s_ftp.network->port, FTP_SOCKET_TIMEOUT)){
		LLOGE("ftp network_connect fail");
		return -1;
	}
	ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		return -1;
	}else{
		if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_SERVICE_NEW_OK, 3)){
			LLOGE("ftp connect error");
			return -1;
		}
	}
	LLOGD("ftp connect ok");
	memset(g_s_ftp.network->cmd_send_data,0,FTP_CMD_SEND_MAX);
	snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "USER %s\r\n",g_s_ftp.network->username);
	luat_ftp_cmd_send(g_s_ftp.network, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
	ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		LLOGE("ftp username wrong");
		return -1;
	}else{
		if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_USERNAME_OK, 3)){
			LLOGE("ftp username wrong");
			return -1;
		}
	}
	LLOGD("ftp username ok");
	memset(g_s_ftp.network->cmd_send_data,0,FTP_CMD_SEND_MAX);
	snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "PASS %s\r\n",g_s_ftp.network->password);
	luat_ftp_cmd_send(g_s_ftp.network, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
	ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		LLOGE("ftp login wrong");
		return -1;
	}else{
		if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_LOGIN_OK, 3)){
			LLOGE("ftp login wrong");
			return -1;
		}
	}
	LLOGD("ftp login ok");
	return 0;
}

static void ftp_task(void *param){
	int ret;
	luat_rtos_task_handle task_handle = g_s_ftp.task_handle;
	OS_EVENT task_event;
	rtos_msg_t msg = {0};
	uint8_t is_timeout = 0;
	uint8_t is_online = 0;
	g_s_ftp.is_run = 1;
    msg.handler = l_ftp_callback;
	luat_rtos_event_recv(g_s_ftp.task_handle, FTP_EVENT_LOGIN, &task_event, NULL, LUAT_WAIT_FOREVER);
	if (ftp_login())
	{
		LLOGE("ftp login fail");
		luat_ftp_close();
		msg.arg1 = 1;
		luat_msgbus_put(&msg, 0);
		g_s_ftp.task_handle = NULL;
		luat_rtos_task_delete(task_handle);
		return;
	}
	else
	{
		msg.arg1 = 0;
		msg.arg2 = 0;
		luat_msgbus_put(&msg, 0);
	}
    while (g_s_ftp.is_run) {
    	is_timeout = 0;
    	ret = network_wait_event(g_s_ftp.network->cmd_netc, &task_event, 3600000, &is_timeout);
    	if (ret < 0)
    	{
    		LLOGE("ftp network error");
    		goto wait_event_and_out;
    	}
    	else if (is_timeout || !task_event.ID)
    	{
        	if (g_s_ftp.network->cmd_netc->new_rx_flag)
        	{
        		network_rx(g_s_ftp.network->cmd_netc, g_s_ftp.network->cmd_recv_data, 1024, 0, NULL, NULL, &ret);
        		LLOGD("ftp rx %dbyte", ret);
        	}
    		continue;
    	}
    	msg.arg1 = 0;
    	msg.arg2 = 0;
		switch (task_event.ID)
		{
		case FTP_EVENT_LOGIN:
			break;
		case FTP_EVENT_PULL:
			if (g_s_ftp.network->data_netc)
			{
				network_force_close_socket(g_s_ftp.network->data_netc);
				network_release_ctrl(g_s_ftp.network->data_netc);
				g_s_ftp.network->data_netc = NULL;
			}
			if(luat_ftp_pasv_connect(g_s_ftp.network,FTP_SOCKET_TIMEOUT)){
				LLOGE("ftp pasv_connect fail");
				goto operation_failed;
			}
			snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "RETR %s\r\n",g_s_ftp.network->remote_name);
			luat_ftp_cmd_send(g_s_ftp.network, g_s_ftp.network->cmd_send_data, strlen((const char *)g_s_ftp.network->cmd_send_data),FTP_SOCKET_TIMEOUT);
			ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto operation_failed;
			}else{

				if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_STATUS_OK, 3)){
					LLOGD("ftp RETR wrong");
					goto operation_failed;
				}
			}
			if (!g_s_ftp.network->data_netc_online)
			{
				g_s_ftp.network->cmd_recv_data[g_s_ftp.network->cmd_recv_len] = 0;
				LLOGD("ftp RETR maybe done!");
				if (strstr((const char *)(g_s_ftp.network->cmd_recv_data), "226 Transfer complete"))
				{
					LLOGD("ftp RETR ok!");
					if (g_s_ftp.fd){
						luat_fs_fclose(g_s_ftp.fd);
						g_s_ftp.fd = NULL;
					}
					luat_msgbus_put(&msg, 0);
					break;
				}
			}
			ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto operation_failed;
			}else{
				if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_CLOSE_CONNECT, 3)){
					LLOGD("ftp RETR wrong");
					goto operation_failed;
				}
			}
			if (g_s_ftp.fd){
				luat_fs_fclose(g_s_ftp.fd);
				g_s_ftp.fd = NULL;
			}
			luat_msgbus_put(&msg, 0);
			break;
		case FTP_EVENT_PUSH:
			if(luat_ftp_pasv_connect(g_s_ftp.network,FTP_SOCKET_TIMEOUT)){
				LLOGD("ftp pasv_connect fail");
				goto operation_failed;
			}

			memset(g_s_ftp.network->cmd_send_data,0,FTP_CMD_SEND_MAX);
			snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "STOR %s\r\n",g_s_ftp.network->remote_name);
			luat_ftp_cmd_send(g_s_ftp.network, g_s_ftp.network->cmd_send_data, strlen((const char *)g_s_ftp.network->cmd_send_data),FTP_SOCKET_TIMEOUT);
			ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto operation_failed;
			}else{
				if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_STATUS_OK, 3)){
					LLOGD("ftp STOR wrong");
					goto operation_failed;
				}
			}

			uint8_t* buff = luat_heap_malloc(PUSH_BUFF_SIZE);
			int offset = 0;
			g_s_ftp.network->upload_done_size = 0;
			while (1) {
				memset(buff, 0, PUSH_BUFF_SIZE);
				int len = luat_fs_fread(buff, sizeof(uint8_t), PUSH_BUFF_SIZE, g_s_ftp.fd);
				if (len < 1)
					break;
				luat_ftp_data_send(g_s_ftp.network, buff, len);
				offset += len;
			}
			luat_heap_free(buff);
			LLOGD("offset:%d file_size:%d",offset,g_s_ftp.network->local_file_size);
			ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (g_s_ftp.network->upload_done_size != g_s_ftp.network->local_file_size)
			{
				LLOGE("upload not finish !!! %d,%d", g_s_ftp.network->upload_done_size, g_s_ftp.network->local_file_size);
			}
			if (ret){
				goto operation_failed;
			}else{
				if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_CLOSE_CONNECT, 3)){
					LLOGD("ftp STOR wrong");
				}
			}
			if (g_s_ftp.fd){
				luat_fs_fclose(g_s_ftp.fd);
				g_s_ftp.fd = NULL;
			}
			luat_msgbus_put(&msg, 0);
			break;
		case FTP_EVENT_CLOSE:
			g_s_ftp.is_run = 0;
			break;
		case FTP_EVENT_COMMAND:
			OS_DeInitBuffer(&g_s_ftp.result_buffer);
			if(!memcmp(g_s_ftp.network->cmd_send_data, "LIST", 4))
			{
				if(luat_ftp_pasv_connect(g_s_ftp.network,FTP_SOCKET_TIMEOUT)){
					LLOGD("ftp pasv_connect fail");
					goto operation_failed;
				}
				luat_ftp_cmd_send(g_s_ftp.network, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
				ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto operation_failed;
				}else{
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_STATUS_OK, 3)){
						LLOGE("ftp LIST wrong");
						goto operation_failed;
					}
				}
				if (!g_s_ftp.network->data_netc_online)
				{
					g_s_ftp.network->cmd_recv_data[g_s_ftp.network->cmd_recv_len] = 0;
					LLOGD("ftp LIST maybe done!");
					if (strstr((const char *)(g_s_ftp.network->cmd_recv_data), FTP_CLOSE_CONNECT))
					{
						LLOGD("ftp LIST ok!");
						msg.arg2 = 1;
						luat_msgbus_put(&msg, 0);
						break;
					}
				}
				ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto operation_failed;
				}else{
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_CLOSE_CONNECT, 3)){
						LLOGE("ftp LIST wrong");
						goto operation_failed;
					}
				}
				msg.arg2 = 1;
				luat_msgbus_put(&msg, 0);
				break;
			}
			luat_ftp_cmd_send(g_s_ftp.network, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
			ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto operation_failed;
			}else{
				if (memcmp(g_s_ftp.network->cmd_send_data, "NOOP", 4)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_COMMAND_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "TYPE", 4)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_COMMAND_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "SYST", 4)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_SYSTEM_TYPE, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "PWD", 3)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_PATHNAME_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "MKD", 3)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_PATHNAME_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "CWD", 3)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_REQUESTED_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "CDUP", 4)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_REQUESTED_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "RMD", 3)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_REQUESTED_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if(memcmp(g_s_ftp.network->cmd_send_data, "DELE", 4)==0){
					if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_REQUESTED_OK, 3)){
						LLOGD("ftp COMMAND wrong");
					}
				}else if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_DATA_CON_FAIL, 3)==0){
					LLOGD("ftp need pasv_connect");


				}
			}
			OS_BufferWrite(&g_s_ftp.result_buffer, g_s_ftp.network->cmd_recv_data, g_s_ftp.network->cmd_recv_len);
			msg.arg2 = 1;
			luat_msgbus_put(&msg, 0);
			break;
		default:
			break;
		}
		continue;
operation_failed:
		msg.arg1 = 1;
		luat_msgbus_put(&msg, 0);
	}

	msg.arg1 = 0;
	msg.arg2 = 0;
	luat_ftp_cmd_send(g_s_ftp.network, (uint8_t*)"QUIT\r\n", strlen("QUIT\r\n"),FTP_SOCKET_TIMEOUT);
	ret = luat_ftp_cmd_recv(g_s_ftp.network,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		msg.arg1 = 1;
	}else{
		if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_CLOSE_CONTROL, 3)){
			LLOGE("ftp QUIT wrong");
			msg.arg1 = 1;
		}
	}
	OS_BufferWrite(&g_s_ftp.result_buffer, g_s_ftp.network->cmd_recv_data, g_s_ftp.network->cmd_recv_len);
	msg.arg2 = 1;
	luat_ftp_close();
	luat_msgbus_put(&msg, 0);
	g_s_ftp.task_handle = NULL;
	luat_rtos_task_delete(task_handle);
	return;
wait_event_and_out:
	while(1)
	{
		luat_rtos_event_recv(g_s_ftp.task_handle, 0, &task_event, NULL, LUAT_WAIT_FOREVER);
		if (task_event.ID >= FTP_EVENT_LOGIN && task_event.ID <= FTP_EVENT_CLOSE)
		{
			luat_ftp_close();
			msg.arg1 = 1;
			luat_msgbus_put(&msg, 0);
			g_s_ftp.task_handle = NULL;
			luat_rtos_task_delete(task_handle);
			return;
		}
	}
}

/*
FTP客户端
@api ftp.login(adapter,ip_addr,port,username,password)
@int 适配器序号, 只能是socket.ETH0, socket.STA, socket.AP,如果不填,会选择平台自带的方式,然后是最后一个注册的适配器
@string ip_addr 地址
@string port 端口,默认21
@string username 用户名
@string password 密码
@bool/table  是否为ssl加密连接,默认不加密,true为无证书最简单的加密，table为有证书的加密 <br>server_cert 服务器ca证书数据 <br>client_cert 客户端ca证书数据 <br>client_key 客户端私钥加密数据 <br>client_password 客户端私钥口令数据
@return bool/string 成功返回true 失败返回string
@usage
ftp_login = ftp.login(nil,"xxx")
*/
static int l_ftp_login(lua_State *L) {
	size_t server_cert_len,client_cert_len, client_key_len, client_password_len,addr_len,username_len,password_len;
	const char *server_cert = NULL;
	const char *client_cert = NULL;
	const char *client_key = NULL;
	const char *client_password = NULL;
	const char *username = NULL;
	const char *password = NULL;
	uint8_t is_timeout = 0;
	int result = 0;
	// mbedtls_debug_set_threshold(4);
	if (g_s_ftp.network){
		LLOGE("ftp already login, please close first");
		result = FTP_ERROR_STATE;
	    goto error;
	}
	
	g_s_ftp.network = (luat_ftp_network_t *)luat_heap_malloc(sizeof(luat_ftp_network_t));
	if (!g_s_ftp.network){
		LLOGE("out of memory when malloc g_s_ftp.network");
		result = FTP_ERROR_NO_MEM;
        goto error;
	}
	memset(g_s_ftp.network, 0, sizeof(luat_ftp_network_t));

	g_s_ftp.network->adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (g_s_ftp.network->adapter_index < 0 || g_s_ftp.network->adapter_index >= NW_ADAPTER_QTY){
		LLOGE("bad network adapter index %d", g_s_ftp.network->adapter_index);
		result = FTP_ERROR_STATE;
		goto error;
	}
	
	g_s_ftp.network->cmd_netc = network_alloc_ctrl(g_s_ftp.network->adapter_index);
	if (!g_s_ftp.network->cmd_netc){
		LLOGE("cmd_netc create fail");
		result = FTP_ERROR_NO_MEM;
		goto error;
	}

	luat_rtos_task_create(&g_s_ftp.task_handle, 2048, 40, "ftp", ftp_task, NULL, 16);
	network_init_ctrl(g_s_ftp.network->cmd_netc,g_s_ftp.task_handle, ftp_task_cb, NULL);
	network_set_base_mode(g_s_ftp.network->cmd_netc, 1, 30000, 0, 0, 0, 0);
	network_set_local_port(g_s_ftp.network->cmd_netc, 0);

	const char *addr = luaL_checklstring(L, 2, &addr_len);
	g_s_ftp.network->addr = luat_heap_malloc(addr_len + 1);
	memset(g_s_ftp.network->addr, 0, addr_len + 1);
	memcpy(g_s_ftp.network->addr, addr, addr_len);

	g_s_ftp.network->port = luaL_optinteger(L, 3, 21);

	username = luaL_optlstring(L, 4, "",&username_len);
	g_s_ftp.network->username = luat_heap_malloc(username_len + 1);
	memset(g_s_ftp.network->username, 0, username_len + 1);
	memcpy(g_s_ftp.network->username, username, username_len);

	password = luaL_optlstring(L, 5, "",&password_len);
	g_s_ftp.network->password = luat_heap_malloc(password_len + 1);
	memset(g_s_ftp.network->password, 0, password_len + 1);
	memcpy(g_s_ftp.network->password, password, password_len);

	// 加密相关
	if (lua_isboolean(L, 6)){
		g_s_ftp.network->is_tls = lua_toboolean(L, 6);
	}

	if (lua_istable(L, 6)){
		g_s_ftp.network->is_tls = 1;

		lua_pushstring(L, "server_cert");
		if (LUA_TSTRING == lua_gettable(L, 6)) {
			server_cert = luaL_checklstring(L, -1, &server_cert_len);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "client_cert");
		if (LUA_TSTRING == lua_gettable(L, 6)) {
			client_cert = luaL_checklstring(L, -1, &client_cert_len);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "client_key");
		if (LUA_TSTRING == lua_gettable(L, 6)) {
			client_key = luaL_checklstring(L, -1, &client_key_len);
		}
		lua_pop(L, 1);

		lua_pushstring(L, "client_password");
		if (LUA_TSTRING == lua_gettable(L, 6)) {
			client_password = luaL_checklstring(L, -1, &client_password_len);
		}
		lua_pop(L, 1);
	}

	if (g_s_ftp.network->is_tls){
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
		if (network_init_tls(g_s_ftp.network->cmd_netc, (server_cert || client_cert)?2:0)){
			result = FTP_ERROR_CLOSE;
			goto error;
		}
		
		if (server_cert){
			network_set_server_cert(g_s_ftp.network->cmd_netc, (const unsigned char *)server_cert, server_cert_len+1);
		}
		if (client_cert){
			network_set_client_cert(g_s_ftp.network->cmd_netc, (const unsigned char *)client_cert, client_cert_len+1,
					(const unsigned char *)client_key, client_key_len+1,
					(const unsigned char *)client_password, client_password_len+1);
		}
	}else{
		network_deinit_tls(g_s_ftp.network->cmd_netc);
	}

	network_set_ip_invaild(&g_s_ftp.network->ip_addr);

	g_s_ftp.idp = luat_pushcwait(L);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_LOGIN, 0, 0, 0, LUAT_WAIT_FOREVER);
    return 1;
error:
	LLOGE("ftp login fail");
	luat_ftp_close();
    lua_pushinteger(L, result);
	luat_pushcwait_error(L,1);
	return 1;
}

/*
FTP命令
@api ftp.command(cmd)
@string cmd 命令 目前支持:NOOP SYST TYPE PWD MKD CWD CDUP RMD DELE LIST
@return string 成功返回true 失败返回string
@usage
    print(ftp.command("NOOP").wait())
    print(ftp.command("SYST").wait())
    print(ftp.command("TYPE I").wait())
    print(ftp.command("PWD").wait())
    print(ftp.command("MKD QWER").wait())
    print(ftp.command("CWD /QWER").wait())
    print(ftp.command("CDUP").wait())
    print(ftp.command("RMD QWER").wait())
	print(ftp.command("DELE /1/12222.txt").wait())
*/
static int l_ftp_command(lua_State *L) {
	if (!g_s_ftp.network){
		LLOGE("please login first");
		goto error;
	}
	g_s_ftp.idp = luat_pushcwait(L);
	size_t len;
	const char *cmd = luaL_checklstring(L, 1, &len);
	if (memcmp(cmd, "NOOP", 4)==0){
		LLOGD("command: NOOP");
	}else if(memcmp(cmd, "SYST", 4)==0){
		LLOGD("command: SYST");
	}else if(memcmp(cmd, "MKD", 3)==0){
		LLOGD("command: MKD");
	}else if(memcmp(cmd, "CWD", 3)==0){
		LLOGD("command: CWD");
	}else if(memcmp(cmd, "CDUP", 4)==0){
		LLOGD("command: CDUP");
	}else if(memcmp(cmd, "RMD", 3)==0){
		LLOGD("command: RMD");
	}else if(memcmp(cmd, "PWD", 3)==0){
		LLOGD("command: RMD");
	}else if(memcmp(cmd, "DELE", 4)==0){
		LLOGD("command: DELE");
	}else if(memcmp(cmd, "TYPE", 4)==0){
		LLOGD("command: TYPE");
	}else if(memcmp(cmd, "LIST", 4)==0){
		LLOGD("command: LIST");
	}else{
		LLOGE("not support cmd:%s",cmd);
		lua_pushinteger(L,FTP_ERROR_FILE);
		luat_pushcwait_error(L,1);
		return 1;
	}
	memset(g_s_ftp.network->cmd_send_data,0,FTP_CMD_SEND_MAX);
	snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "%s\r\n",cmd);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_COMMAND, (uint32_t)g_s_ftp.idp, (uint32_t)(g_s_ftp.idp >> 32), 0, LUAT_WAIT_FOREVER);
	return 1;
error:
	LLOGE("ftp command fail");
    lua_pushinteger(L,FTP_ERROR_FILE);
	luat_pushcwait_error(L,1);
	return 1;
}

/*
FTP文件下载
@api ftp.pull(local_name,remote_name)
@string local_name 本地文件
@string remote_name 服务器文件
@return bool/string 成功返回true 失败返回string
@usage
ftp.pull("/1222.txt","/1222.txt").wait()
*/
static int l_ftp_pull(lua_State *L) {
	size_t len;
	if (!g_s_ftp.network){
		LLOGE("please login first");
		goto error;
	}
	g_s_ftp.idp = luat_pushcwait(L);
	const char * local_name = luaL_optlstring(L, 1, "",&len);
	luat_fs_remove(local_name);
	if (g_s_ftp.fd)
	{
		luat_fs_fclose(g_s_ftp.fd);
		g_s_ftp.fd = NULL;
	}
	g_s_ftp.fd = luat_fs_fopen(local_name, "wb+");
	if (g_s_ftp.fd == NULL) {
		LLOGE("open download file fail %s", local_name);
		goto error;
	}
	g_s_ftp.network->local_file_size = luat_fs_fsize(local_name);
	const char * remote_name = luaL_optlstring(L, 2, "",&len);
	if (g_s_ftp.network->remote_name) {
		luat_heap_free(g_s_ftp.network->remote_name);
		g_s_ftp.network->remote_name = NULL;
	}
	g_s_ftp.network->remote_name = luat_heap_malloc(len + 1);
	memset(g_s_ftp.network->remote_name, 0, len + 1);
	memcpy(g_s_ftp.network->remote_name, remote_name, len);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_PULL, 0, 0, 0, NULL);
	return 1;
error:
	LLOGE("ftp pull fail");
    lua_pushinteger(L,FTP_ERROR_FILE);
	luat_pushcwait_error(L,1);
	return 1;
}

/*
FTP文件上传
@api ftp.push(local_name,remote_name)
@string local_name 本地文件
@string remote_name 服务器文件
@return bool/string 成功返回true 失败返回string
@usage
ftp.push("/1222.txt","/1222.txt").wait()
*/
static int l_ftp_push(lua_State *L) {
	size_t len;
	if (!g_s_ftp.network){
		LLOGE("please login first");
		goto error;
	}
	g_s_ftp.idp = luat_pushcwait(L);
	const char * local_name = luaL_optlstring(L, 1, "",&len);
	if (g_s_ftp.fd)
	{
		luat_fs_fclose(g_s_ftp.fd);
		g_s_ftp.fd = NULL;
	}
	g_s_ftp.fd = luat_fs_fopen(local_name, "rb");
	if (g_s_ftp.fd == NULL) {
		LLOGE("open download file fail %s", local_name);
		goto error;
	}
	g_s_ftp.network->local_file_size = luat_fs_fsize(local_name);
	const char * remote_name = luaL_optlstring(L, 2, "",&len);
	if (g_s_ftp.network->remote_name) {
		luat_heap_free(g_s_ftp.network->remote_name);
		g_s_ftp.network->remote_name = NULL;
	}
	g_s_ftp.network->remote_name = luat_heap_malloc(len + 1);
	memset(g_s_ftp.network->remote_name, 0, len + 1);
	memcpy(g_s_ftp.network->remote_name, remote_name, len);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_PUSH, 0, 0, 0, LUAT_WAIT_FOREVER);
	return 1;
error:
	LLOGE("ftp push fail");
    lua_pushinteger(L,FTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 1;
}

/*
FTP客户端关闭
@api ftp.close()
@return bool/string 成功返回true 失败返回string
@usage
ftp.close().wait()
*/
static int l_ftp_close(lua_State *L) {
	if (!g_s_ftp.network){
		LLOGE("please login first");
		goto error;
	}
	g_s_ftp.idp = luat_pushcwait(L);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_CLOSE, 0, 0, 0, LUAT_WAIT_FOREVER);
	return 1;
error:
    lua_pushinteger(L,FTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 1;
}

#include "rotable2.h"
#ifdef LUAT_USE_NETWORK
static const rotable_Reg_t reg_ftp[] =
{
	{"login",			ROREG_FUNC(l_ftp_login)},
	{"command",			ROREG_FUNC(l_ftp_command)},
	{"pull",			ROREG_FUNC(l_ftp_pull)},
	{"push",			ROREG_FUNC(l_ftp_push)},
	{"close",			ROREG_FUNC(l_ftp_close)},

	{ NULL,             ROREG_INT(0)}
};
#else
static const rotable_Reg_t reg_ftp_emtry[] =
{
	{ NULL,             ROREG_INT(0)}
};
#endif

LUAMOD_API int luaopen_ftp( lua_State *L ) {
#ifdef LUAT_USE_NETWORK
    luat_newlib2(L, reg_ftp);
#else
    luat_newlib2(L, reg_ftp_emtry);
	LLOGE("reg_ftp require network enable!!");
#endif
    return 1;
}
