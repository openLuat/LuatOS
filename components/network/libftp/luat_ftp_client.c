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
#include "luat_fs.h"
#include "luat_mem.h"

#include "luat_ftp.h"

#define LUAT_LOG_TAG "ftp"
#include "luat_log.h"


#undef LLOGD
#define LLOGD(format, ...) do {if (g_s_ftp.debug_onoff) {luat_log_log(LUAT_LOG_DEBUG, LUAT_LOG_TAG, format, ##__VA_ARGS__);}} while(0)


luat_ftp_ctrl_t g_s_ftp;

uint32_t luat_ftp_release(void) {
	if (!g_s_ftp.network) return 0;
	if (g_s_ftp.network->cmd_netc){
		network_force_close_socket(g_s_ftp.network->cmd_netc);
		network_release_ctrl(g_s_ftp.network->cmd_netc);
		g_s_ftp.network->cmd_netc = NULL;
	}
	if (g_s_ftp.network->data_netc){
		network_force_close_socket(g_s_ftp.network->data_netc);
		network_release_ctrl(g_s_ftp.network->data_netc);
		g_s_ftp.network->data_netc = NULL;
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
	uint32_t read_len;
	uint8_t is_break = 0,is_timeout = 0;
	int ret = network_wait_rx(g_s_ftp.network->cmd_netc, timeout_ms, &is_break, &is_timeout);
	LLOGD("luat_ftp_cmd_recv network_wait_rx ret:%d is_break:%d is_timeout:%d",ret,is_break,is_timeout);
	if (ret)
		return -1;
	if (is_timeout)
		return 1;
	else if (is_break)
		return 2;
	return network_rx(g_s_ftp.network->cmd_netc, recv_data, FTP_CMD_RECV_MAX, 0, NULL, NULL, recv_len);
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
	// LLOGD("event->ID %d LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",event->ID,EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
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
		rx_buffer = NULL;
		uint8_t tmpbuff[4];
		do
		{
			// 先读取长度
			ret = network_rx(g_s_ftp.network->data_netc, NULL, 0, 0, NULL, NULL, &rx_len);
			if (rx_len <= 0) {
				// 没数据? 那也读一次, 然后退出
				network_rx(g_s_ftp.network->data_netc, tmpbuff, 4, 0, NULL, NULL, &rx_len);
				break;
			}
			if (rx_len > 2048)
				rx_len = 2048;
			rx_buffer = luat_heap_malloc(rx_len);
			// 如果rx_buffer == NULL, 内存炸了
			if (rx_buffer == NULL) {
				LLOGE("out of memory when malloc ftp buff");
				network_close(g_s_ftp.network->data_netc, 0);
				return -1;
			}
			ret = network_rx(g_s_ftp.network->data_netc, rx_buffer, rx_len, 0, NULL, NULL, &rx_len);
			// LLOGD("luat_ftp_data_callback network_rx ret:%d rx_len:%d",ret,rx_len);
			if (!ret && rx_len > 0)
			{
				if (g_s_ftp.fd)
				{
					luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_DATA_WRITE_FILE, (uint32_t)rx_buffer, rx_len, 0, LUAT_WAIT_FOREVER);
					rx_buffer = NULL;
					continue;
				}
				else
				{
					OS_BufferWrite(&g_s_ftp.result_buffer, rx_buffer, rx_len);
				}
			}
			luat_heap_free(rx_buffer);
			rx_buffer = NULL;
		} while (!ret && rx_len);
		if (rx_buffer)
			luat_heap_free(rx_buffer);
		rx_buffer = NULL;
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
			luat_fs_fwrite((void*)event->Param1, event->Param2, 1, g_s_ftp.fd);
			luat_heap_free((void*)event->Param1);
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
	char h1[4]={0},h2[4]={0},h3[4]={0},h4[4]={0},p1[4]={0},p2[4]={0},data_addr[64]={0};
	uint8_t port1,port2;
	uint16_t data_port;	
	luat_ftp_cmd_send(&g_s_ftp, (uint8_t*)"PASV\r\n", strlen("PASV\r\n"),FTP_SOCKET_TIMEOUT);
//	g_s_ftp.data_transfer_done = 0;
	int ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		return -1;
	}else{
		LLOGD("luat_ftp_pasv_connect cmd_recv_data %s",g_s_ftp.network->cmd_recv_data);
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
	snprintf_(data_addr, 64, "%s.%s.%s.%s",h1,h2,h3,h4);
	port1 = (uint8_t)atoi(p1);
	port2 = (uint8_t)atoi(p2);
	data_port = port1 * 256 + port2;
	LLOGD("data_addr:%s data_port:%d",data_addr,data_port);
	if (memcmp(data_addr,"172.",4)==0||memcmp(data_addr,"192.",4)==0||memcmp(data_addr,"10.",3)==0||memcmp(data_addr,"127.0.0.1",9)==0||memcmp(data_addr,"169.254.0.0",11)==0||memcmp(data_addr,"169.254.0.16",12)==0){
		memset(data_addr,0,64);
		LLOGD("g_s_ftp.network->addr:%s",g_s_ftp.network->addr);
		memcpy(data_addr, g_s_ftp.network->addr, strlen(g_s_ftp.network->addr)+1);
	}
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
	ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
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
	luat_ftp_cmd_send(&g_s_ftp, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
	ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
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
	luat_ftp_cmd_send(&g_s_ftp, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
	ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
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

static void l_ftp_cb(FTP_SUCCESS_STATE_e state){
	if (g_s_ftp.network->ftp_cb){
		luat_ftp_cb_t ftp_cb = g_s_ftp.network->ftp_cb;
		ftp_cb(&g_s_ftp,state);
	}
#ifndef __LUATOS__
	OS_DeInitBuffer(&g_s_ftp.result_buffer);
#endif
}

static int find_newline(void)
{
	uint32_t pos = 0;
	while (pos < g_s_ftp.network->cmd_recv_len)
	{
		if(('\r' == g_s_ftp.network->cmd_recv_data[pos]) || ('\n' == g_s_ftp.network->cmd_recv_data[pos]))
		{
			return pos;
		}
		else
		{
			pos++;
		}
	}
	return -1;
}

static int pasv_recv(void)
{
	int ret;
	int pos;
	uint8_t rx_finish = 0;
	ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		return -1;
	}
	LLOGD("%.*s", g_s_ftp.network->cmd_recv_len, g_s_ftp.network->cmd_recv_data);
	g_s_ftp.network->cmd_recv_data[g_s_ftp.network->cmd_recv_len] = 0;
	if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_STATUS_OK, 3) && memcmp(g_s_ftp.network->cmd_recv_data, FTP_DATA_CON_OPEN, 3)){
		return -1;
	}
	pos = find_newline();
	if (pos >= 0)
	{
		memmove(g_s_ftp.network->cmd_recv_data, g_s_ftp.network->cmd_recv_data + pos, g_s_ftp.network->cmd_recv_len - pos);
		g_s_ftp.network->cmd_recv_len -= pos;
		g_s_ftp.network->cmd_recv_data[g_s_ftp.network->cmd_recv_len] = 0;
		if (strstr((const char *)(g_s_ftp.network->cmd_recv_data), FTP_CLOSE_CONNECT))
		{
			rx_finish = 1;
		}
	}
	while(!rx_finish && (g_s_ftp.network->data_netc_online || g_s_ftp.result_buffer.Pos))	//data通道未断开或者已经接收到数据了
	{
		ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
		if (ret < 0){
			LLOGD("rx error!%d", ret);
			return -1;
		} else if (!ret) {
			LLOGD("%.*s", g_s_ftp.network->cmd_recv_len, g_s_ftp.network->cmd_recv_data);
			if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_CLOSE_CONNECT, 3)){
				return -1;
			}
			else {
				rx_finish = 1;
			}
		}
	}
	if (!rx_finish) {	//没接收完就断开了
		LLOGD("???");
		return -1;
	}
	//等服务器关闭接收通道
	if (g_s_ftp.network->data_netc_online) {
		ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,1000);
		if (ret < 0) {
			return -1;
		}
	}
	//主动关闭掉接收
	if (g_s_ftp.network->data_netc_online && g_s_ftp.network->data_netc) {
		network_close(g_s_ftp.network->data_netc, 0);
	}
	return 0;
}

static void ftp_task(void *param){
	FTP_SUCCESS_STATE_e ftp_state = FTP_SUCCESS_NO_DATE;
	int ret;
	int count = 0;
	luat_rtos_task_handle task_handle = g_s_ftp.task_handle;
	OS_EVENT task_event;
	uint8_t is_timeout = 0;


	g_s_ftp.is_run = 1;
	luat_rtos_event_recv(g_s_ftp.task_handle, FTP_EVENT_LOGIN, &task_event, NULL, LUAT_WAIT_FOREVER);
	if (ftp_login()){
		LLOGE("ftp login fail");
		ftp_state = FTP_ERROR;
		l_ftp_cb(ftp_state);
		luat_ftp_release();
		g_s_ftp.task_handle = NULL;
		luat_rtos_task_delete(task_handle);
		return;
	}else{
		l_ftp_cb(ftp_state);
	}
    while (g_s_ftp.is_run) {
    	is_timeout = 0;
    	ret = network_wait_event(g_s_ftp.network->cmd_netc, &task_event, 3600000, &is_timeout);
    	if (ret < 0){    		
			LLOGE("ftp network error");
    		goto wait_event_and_out;
    	}else if (is_timeout || !task_event.ID){
        	if (g_s_ftp.network->cmd_netc->new_rx_flag){
        		network_rx(g_s_ftp.network->cmd_netc, g_s_ftp.network->cmd_recv_data, 1024, 0, NULL, NULL, &ret);
        		LLOGD("ftp rx %dbyte", ret);
        	}
    		continue;
    	}
    	ftp_state = FTP_SUCCESS_NO_DATE;
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
			if(luat_ftp_pasv_connect(&g_s_ftp,FTP_SOCKET_TIMEOUT)){
				LLOGE("ftp pasv_connect fail");
				goto operation_failed;
			}
			snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "RETR %s\r\n",g_s_ftp.network->remote_name);
			luat_ftp_cmd_send(&g_s_ftp, g_s_ftp.network->cmd_send_data, strlen((const char *)g_s_ftp.network->cmd_send_data),FTP_SOCKET_TIMEOUT);
			if (pasv_recv()) goto operation_failed;
			if (g_s_ftp.fd){
				luat_fs_fclose(g_s_ftp.fd);
				g_s_ftp.fd = NULL;
			}
			l_ftp_cb(ftp_state);
			break;
		case FTP_EVENT_PUSH:
			if(luat_ftp_pasv_connect(&g_s_ftp,FTP_SOCKET_TIMEOUT)){
				LLOGD("ftp pasv_connect fail");
				goto operation_failed;
			}

			memset(g_s_ftp.network->cmd_send_data,0,FTP_CMD_SEND_MAX);
			snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "STOR %s\r\n",g_s_ftp.network->remote_name);
			luat_ftp_cmd_send(&g_s_ftp, g_s_ftp.network->cmd_send_data, strlen((const char *)g_s_ftp.network->cmd_send_data),FTP_SOCKET_TIMEOUT);
			ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto operation_failed;
			}else{
				LLOGD("%.*s", g_s_ftp.network->cmd_recv_len, g_s_ftp.network->cmd_recv_data);
				if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_FILE_STATUS_OK, 3) && memcmp(g_s_ftp.network->cmd_recv_data, FTP_DATA_CON_OPEN, 3)){
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
				luat_ftp_data_send(&g_s_ftp, buff, len);
				offset += len;
			}
			luat_heap_free(buff);
			LLOGD("offset:%d file_size:%d",offset,g_s_ftp.network->local_file_size);
			ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
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
			while (count<3 && g_s_ftp.network->data_netc_online!=0){
				luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT/3);
				count++;
			}
			if (g_s_ftp.fd){
				luat_fs_fclose(g_s_ftp.fd);
				g_s_ftp.fd = NULL;
			}
			l_ftp_cb(ftp_state);
			break;
		case FTP_EVENT_CLOSE:
			g_s_ftp.is_run = 0;
			break;
		case FTP_EVENT_COMMAND:
			OS_DeInitBuffer(&g_s_ftp.result_buffer);
			if(!memcmp(g_s_ftp.network->cmd_send_data, "LIST", 4))
			{
				if(luat_ftp_pasv_connect(&g_s_ftp,FTP_SOCKET_TIMEOUT)){
					LLOGD("ftp pasv_connect fail");
					goto operation_failed;
				}
				luat_ftp_cmd_send(&g_s_ftp, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
				if (pasv_recv()) goto operation_failed;
				ftp_state = FTP_SUCCESS_DATE;
				l_ftp_cb(ftp_state);
				break;
			}
			luat_ftp_cmd_send(&g_s_ftp, g_s_ftp.network->cmd_send_data, strlen((const char *)(g_s_ftp.network->cmd_send_data)),FTP_SOCKET_TIMEOUT);
			ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
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
			ftp_state = FTP_SUCCESS_DATE;
			l_ftp_cb(ftp_state);
			break;
		default:
			break;
		}
		continue;
operation_failed:
		if (g_s_ftp.fd){
			luat_fs_fclose(g_s_ftp.fd);
			g_s_ftp.fd = NULL;
		}
		ftp_state = FTP_ERROR;
		l_ftp_cb(ftp_state);
	}
	ftp_state = FTP_SUCCESS_NO_DATE;
	luat_ftp_cmd_send(&g_s_ftp, (uint8_t*)"QUIT\r\n", strlen("QUIT\r\n"),FTP_SOCKET_TIMEOUT);
	ret = luat_ftp_cmd_recv(&g_s_ftp,g_s_ftp.network->cmd_recv_data,&g_s_ftp.network->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		ftp_state = FTP_ERROR;
	}else{
		if (memcmp(g_s_ftp.network->cmd_recv_data, FTP_CLOSE_CONTROL, 3)){
			LLOGE("ftp QUIT wrong");
			ftp_state = FTP_ERROR;
		}
	}
	OS_BufferWrite(&g_s_ftp.result_buffer, g_s_ftp.network->cmd_recv_data, g_s_ftp.network->cmd_recv_len);
	if (ftp_state == FTP_SUCCESS_NO_DATE) ftp_state = FTP_SUCCESS_DATE;
	l_ftp_cb(ftp_state);
	luat_ftp_release();
	g_s_ftp.task_handle = NULL;
	luat_rtos_task_delete(task_handle);
	return;
wait_event_and_out:
	while(1)
	{
		luat_rtos_event_recv(g_s_ftp.task_handle, 0, &task_event, NULL, LUAT_WAIT_FOREVER);
		if (task_event.ID >= FTP_EVENT_LOGIN && task_event.ID <= FTP_EVENT_CLOSE)
		{
			luat_ftp_release();
			ftp_state = FTP_ERROR;
			l_ftp_cb(ftp_state);
			g_s_ftp.task_handle = NULL;
			luat_rtos_task_delete(task_handle);
			return;
		}
	}
}


int luat_ftp_login(uint8_t adapter,const char * ip_addr,uint16_t port,const char * username,const char * password,luat_ftp_tls_t* luat_ftp_tls,luat_ftp_cb_t ftp_cb){
	if (g_s_ftp.network){
		LLOGE("ftp already login, please close first");
		return FTP_ERROR_STATE;
	}
	g_s_ftp.network = (luat_ftp_network_t *)luat_heap_malloc(sizeof(luat_ftp_network_t));
	if (!g_s_ftp.network){
		LLOGE("out of memory when malloc g_s_ftp.network");
		return FTP_ERROR_NO_MEM;
	}
	memset(g_s_ftp.network, 0, sizeof(luat_ftp_network_t));
	if (ftp_cb){
		g_s_ftp.network->ftp_cb = ftp_cb;
	}
	g_s_ftp.network->adapter_index = adapter;
	if (g_s_ftp.network->adapter_index >= NW_ADAPTER_QTY){
		LLOGE("bad network adapter index %d", g_s_ftp.network->adapter_index);
		return FTP_ERROR_STATE;
	}
	g_s_ftp.network->cmd_netc = network_alloc_ctrl(g_s_ftp.network->adapter_index);
	if (!g_s_ftp.network->cmd_netc){
		LLOGE("cmd_netc create fail");
		return FTP_ERROR_NO_MEM;
	}
	g_s_ftp.network->port = port;
	if (strlen(ip_addr) > 0 && strlen(ip_addr) < 64)
		memcpy(g_s_ftp.network->addr, ip_addr, strlen(ip_addr) + 1);
	if (strlen(username) > 0 && strlen(username) < 64)
		memcpy(g_s_ftp.network->username, username, strlen(username) + 1);
	if (strlen(password) > 0 && strlen(password) < 64)
		memcpy(g_s_ftp.network->password, password, strlen(password) + 1);
	if (luat_ftp_tls == NULL){
		network_deinit_tls(g_s_ftp.network->cmd_netc);
	}else{
		if (network_init_tls(g_s_ftp.network->cmd_netc, (luat_ftp_tls->server_cert || luat_ftp_tls->client_cert)?2:0)){
			return FTP_ERROR_CLOSE;
		}
		if (luat_ftp_tls->server_cert){
			network_set_server_cert(g_s_ftp.network->cmd_netc, (const unsigned char *)luat_ftp_tls->server_cert, strlen(luat_ftp_tls->server_cert)+1);
		}
		if (luat_ftp_tls->client_cert){
			network_set_client_cert(g_s_ftp.network->cmd_netc, (const unsigned char *)luat_ftp_tls->client_cert, strlen(luat_ftp_tls->client_cert)+1,
					(const unsigned char *)luat_ftp_tls->client_key, strlen(luat_ftp_tls->client_key)+1,
					(const unsigned char *)luat_ftp_tls->client_password, strlen(luat_ftp_tls->client_password)+1);
		}
	}
	network_set_ip_invaild(&g_s_ftp.network->ip_addr);
	int result = luat_rtos_task_create(&g_s_ftp.task_handle, 2*1024, 10, "ftp", ftp_task, NULL, 16);
	if (result) {
		LLOGE("创建ftp task失败!! %d", result);
		return result;
	}
	network_init_ctrl(g_s_ftp.network->cmd_netc,g_s_ftp.task_handle, ftp_task_cb, NULL);
	network_set_base_mode(g_s_ftp.network->cmd_netc, 1, 30000, 0, 0, 0, 0);
	network_set_local_port(g_s_ftp.network->cmd_netc, 0);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_LOGIN, 0, 0, 0, LUAT_WAIT_FOREVER);
	return 0;
}

int luat_ftp_command(const char * command){
	if (!g_s_ftp.network){
		LLOGE("please login first");
		return -1;
	}
	if (memcmp(command, "NOOP", 4)==0){
		LLOGD("command: NOOP");
	}else if(memcmp(command, "SYST", 4)==0){
		LLOGD("command: SYST");
	}else if(memcmp(command, "MKD", 3)==0){
		LLOGD("command: MKD");
	}else if(memcmp(command, "CWD", 3)==0){
		LLOGD("command: CWD");
	}else if(memcmp(command, "CDUP", 4)==0){
		LLOGD("command: CDUP");
	}else if(memcmp(command, "RMD", 3)==0){
		LLOGD("command: RMD");
	}else if(memcmp(command, "PWD", 3)==0){
		LLOGD("command: RMD");
	}else if(memcmp(command, "DELE", 4)==0){
		LLOGD("command: DELE");
	}else if(memcmp(command, "TYPE", 4)==0){
		LLOGD("command: TYPE");
	}else if(memcmp(command, "LIST", 4)==0){
		LLOGD("command: LIST");
	}else{
		LLOGE("not support cmd:%s",command);
		return -1;
	}
	memset(g_s_ftp.network->cmd_send_data,0,FTP_CMD_SEND_MAX);
	snprintf_((char *)(g_s_ftp.network->cmd_send_data), FTP_CMD_SEND_MAX, "%s\r\n",command);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_COMMAND, 0, 0, 0, 0);
	return 0;
}

int luat_ftp_pull(const char * local_name,const char * remote_name){
	if (!g_s_ftp.network){
		LLOGE("please login first");
		return -1;
	}
	luat_fs_remove(local_name);
	if (g_s_ftp.fd)
	{
		luat_fs_fclose(g_s_ftp.fd);
		g_s_ftp.fd = NULL;
	}
	g_s_ftp.fd = luat_fs_fopen(local_name, "wb+");
	if (g_s_ftp.fd == NULL) {
		LLOGE("open download file fail %s", local_name);
		return -1;
	}
	g_s_ftp.network->local_file_size = luat_fs_fsize(local_name);
	memcpy(g_s_ftp.network->remote_name, remote_name, strlen(remote_name) + 1);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_PULL, 0, 0, 0, 0);
	return 0;
}

int luat_ftp_close(void){
	if (!g_s_ftp.network){
		LLOGE("please login first");
		return -1;
	}
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_CLOSE, 0, 0, 0, LUAT_WAIT_FOREVER);
	return 0;
}

int luat_ftp_push(const char * local_name,const char * remote_name){
	if (!g_s_ftp.network){
		LLOGE("please login first");
		return -1;
	}
	if (g_s_ftp.fd)
	{
		luat_fs_fclose(g_s_ftp.fd);
		g_s_ftp.fd = NULL;
	}
	g_s_ftp.fd = luat_fs_fopen(local_name, "rb");
	if (g_s_ftp.fd == NULL) {
		LLOGE("open download file fail %s", local_name);
		return -1;
	}
	g_s_ftp.network->local_file_size = luat_fs_fsize(local_name);
	memcpy(g_s_ftp.network->remote_name, remote_name, strlen(remote_name) + 1);
	luat_rtos_event_send(g_s_ftp.task_handle, FTP_EVENT_PUSH, 0, 0, 0, LUAT_WAIT_FOREVER);
	return 0;
}

void luat_ftp_debug(uint8_t on_off) {g_s_ftp.debug_onoff = on_off;}
