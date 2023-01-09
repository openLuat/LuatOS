
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

static luat_ftp_ctrl_t *ftp_ctrl = NULL;

static uint32_t luat_ftp_close(luat_ftp_ctrl_t *ftp_ctrl) {
	if (ftp_ctrl->cmd_netc){
		network_close(ftp_ctrl->cmd_netc,0);
		network_force_close_socket(ftp_ctrl->cmd_netc);
		network_release_ctrl(ftp_ctrl->cmd_netc);
		ftp_ctrl->cmd_netc = NULL;
	}
	if (ftp_ctrl->addr){
		luat_heap_free(ftp_ctrl->addr);
		ftp_ctrl->addr = NULL;
	}
	if (ftp_ctrl->username){
		luat_heap_free(ftp_ctrl->username);
		ftp_ctrl->username = NULL;
	}
	if (ftp_ctrl->password){
		luat_heap_free(ftp_ctrl->password);
		ftp_ctrl->password = NULL;
	}
	if (ftp_ctrl->remote_name){
		luat_heap_free(ftp_ctrl->remote_name);
		ftp_ctrl->remote_name = NULL;
	}
	if (ftp_ctrl->data_recv){
		luat_heap_free(ftp_ctrl->data_recv);
		ftp_ctrl->data_recv = NULL;
	}
	if (ftp_ctrl){
		luat_heap_free(ftp_ctrl);
		ftp_ctrl = NULL;
	}
	return 0;
}

static uint32_t luat_ftp_data_send(luat_ftp_ctrl_t *ftp_ctrl, uint8_t* send_data, uint32_t send_len) {
	if (send_len == 0)
		return 0;
	uint32_t tx_len = 0;
	LLOGD("luat_ftp_data_send data:%.*s",send_len,send_data);
	network_tx(ftp_ctrl->data_netc, send_data, send_len, 0, NULL, 0, &tx_len, 0);
	return tx_len;
}

static uint32_t luat_ftp_cmd_send(luat_ftp_ctrl_t *ftp_ctrl, uint8_t* send_data, uint32_t send_len,uint32_t timeout_ms) {
	if (send_len == 0)
		return 0;
	uint32_t tx_len = 0;
	LLOGD("luat_ftp_cmd_send data:%.*s",send_len,send_data);
	network_tx(ftp_ctrl->cmd_netc, send_data, send_len, 0, NULL, 0, &tx_len, timeout_ms);
	return tx_len;
}

static int luat_ftp_cmd_recv(luat_ftp_ctrl_t *ftp_ctrl,uint8_t *recv_data,uint32_t *recv_len,uint32_t timeout_ms){
	uint32_t total_len = 0;
	uint8_t is_break = 0,is_timeout = 0;
	int ret = network_wait_rx(ftp_ctrl->cmd_netc, timeout_ms, &is_break, &is_timeout);
	LLOGD("network_wait_rx ret:%d is_break:%d is_timeout:%d",ret,is_break,is_timeout);
	if (ret)
		return -1;
	if (is_timeout)
		return 1;
	else if (is_break)
		return 2;
	int result = network_rx(ftp_ctrl->cmd_netc, NULL, 0, 0, NULL, NULL, &total_len);
	if (0 == result){
		if (total_len>0){
next:
			result = network_rx(ftp_ctrl->cmd_netc, recv_data, total_len, 0, NULL, NULL, recv_len);
			LLOGD("result:%d recv_len:%d",result,*recv_len);
			LLOGD("recv_data:%.*s len:%d",total_len,recv_data,total_len);
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
}

static int32_t l_ftp_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
	LLOGD("l_ftp_callback arg1:%d arg2:%ld idp:%d",msg->arg1,msg->arg2,ftp_ctrl->idp);

	uint64_t idp = ftp_ctrl->idp;
	if (msg->arg1){
		switch (msg->arg2)
		{
		case FTP_QUEUE_LOGIN:
		case FTP_QUEUE_COMMAND:
		case FTP_QUEUE_PULL:
		case FTP_QUEUE_PUSH:
		case FTP_QUEUE_CLOSE:
			lua_pushlstring(L,ftp_ctrl->cmd_recv_data,strlen(ftp_ctrl->cmd_recv_data));
			luat_cbcwait(L, idp, 1);
			luat_ftp_close(ftp_ctrl);
			break;
		default:
			break;
		}
	}else{
		luat_cbcwait(L, idp, 0);
	}
	return 0;
}

static int32_t luat_lib_ftp_callback(void *data, void *param){
	OS_EVENT *event = (OS_EVENT *)data;
	luat_ftp_ctrl_t *ftp_ctrl =(luat_ftp_ctrl_t *)param;
	int ret = 0;
	LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	LLOGD("luat_lib_ftp_callback %d %d",event->ID & 0x0fffffff,event->Param1);
	if (event->Param1){
		LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
		LLOGE("luat_lib_ftp_callback ftp_ctrl close %d %d",event->ID & 0x0fffffff,event->Param1);
		network_force_close_socket(ftp_ctrl->data_netc);
		network_release_ctrl(ftp_ctrl->data_netc);
		return -1;
	}
	if (event->ID == EV_NW_RESULT_LINK){
		return 0;
	}else if(event->ID == EV_NW_RESULT_CONNECT){
		uint8_t ftp_event = FTP_QUEUE_DATA_CONNECT;
		luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &ftp_event, sizeof(uint8_t), 0);
	}else if(event->ID == EV_NW_RESULT_EVENT){
		uint32_t total_len = 0;
		uint32_t rx_len = 0;
		int result = network_rx(ftp_ctrl->data_netc, NULL, 0, 0, NULL, NULL, &total_len);
		// LLOGD("result:%d total_len:%d",result,total_len);
		if (0 == result){
			if (total_len>0){
				if (ftp_ctrl->data_recv){
					ftp_ctrl->data_recv = luat_heap_realloc(ftp_ctrl->data_recv,ftp_ctrl->data_recv_len+total_len+1);
					ftp_ctrl->data_recv_len += total_len;
				}else{
					ftp_ctrl->data_recv = luat_heap_malloc(total_len + 1);
					ftp_ctrl->data_recv_len = 0;
				}
				ftp_ctrl->data_recv[ftp_ctrl->data_recv_len+total_len] = 0x00;
next:
				result = network_rx(ftp_ctrl->data_netc, ftp_ctrl->data_recv, total_len, 0, NULL, NULL, &rx_len);
				LLOGD("result:%d rx_len:%d",result,rx_len);
				LLOGD("resp_buff:%.*s len:%d",total_len,ftp_ctrl->data_recv,total_len);
				if (result)
					goto next;
				if (rx_len == 0||result!=0) {
					network_close(ftp_ctrl->data_netc, 0);
					return -1;
				}
				
				LLOGD("ftp_ctrl->ftp_execute:%d",ftp_ctrl->ftp_execute);

				switch (ftp_ctrl->ftp_execute)
				{
				case FTP_QUEUE_PULL:
					if (ftp_ctrl->fd){
						luat_fs_fwrite(ftp_ctrl->data_recv, total_len, 1, ftp_ctrl->fd);
						luat_heap_free(ftp_ctrl->data_recv);
						ftp_ctrl->data_recv = NULL;
					}else{
						LLOGD("ftp fd error");
						luat_heap_free(ftp_ctrl->data_recv);
						network_close(ftp_ctrl->data_netc, 0);
						return -1;
					}
					break;
				
				default:
					break;
				}

			}
		}else{
			network_close(ftp_ctrl->data_netc, 0);
			return -1;
		}

	}else if(event->ID == EV_NW_RESULT_TX){
		uint8_t ftp_event = FTP_QUEUE_DATA_TX_DONE;
		luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &ftp_event, sizeof(uint8_t), 0);
		return 0;
	}else if(event->ID == EV_NW_RESULT_CLOSE){
		network_force_close_socket(ftp_ctrl->data_netc);
		network_release_ctrl(ftp_ctrl->data_netc);
		return 0;
	}
	ret = network_wait_event(ftp_ctrl->data_netc, NULL, 0, NULL);
	LLOGD("network_wait_event %d", ret);
	if (ret < 0){
		network_close(ftp_ctrl->data_netc, 0);
		return -1;
	}
    return 0;
}

static int luat_ftp_pasv_connect(luat_ftp_ctrl_t *ftp_ctrl,uint32_t timeout_ms){
	char h1[4]={0},h2[4]={0},h3[4]={0},h4[4]={0},p1[4]={0},p2[4]={0},data_addr[14]={0};
	uint8_t port1,port2;
	uint16_t data_port;	
	luat_ftp_cmd_send(ftp_ctrl, "PASV\r\n", strlen("PASV\r\n"),FTP_SOCKET_TIMEOUT);
	int ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
	if (ret){
		return -1;
	}else{
		LLOGD("luat_ftp_pasv_connect cmd_recv_data",ftp_ctrl->cmd_recv_data);
		if (memcmp(ftp_ctrl->cmd_recv_data, FTP_ENTER_PASSIVE, 3)){
			LLOGD("ftp pasv_connect wrong");
			return -1;
		}
	}
    char *temp = memchr(ftp_ctrl->cmd_recv_data, '(', strlen(ftp_ctrl->cmd_recv_data));
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
	snprintf_(data_addr, 14, "%s.%s.%s.%s",h1,h2,h3,h4);
	port1 = (uint8_t)atoi(p1);
	port2 = (uint8_t)atoi(p2);
	data_port = port1 * 256 + port2;
	LLOGD("data_addr:%s data_port:%d",data_addr,data_port);
	ftp_ctrl->data_netc = network_alloc_ctrl(ftp_ctrl->adapter_index);
	if (!ftp_ctrl->data_netc){
		LLOGE("data_netc create fail");
		return -1;
	}
	network_init_ctrl(ftp_ctrl->data_netc,NULL, luat_lib_ftp_callback, ftp_ctrl);
	network_set_base_mode(ftp_ctrl->data_netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(ftp_ctrl->data_netc, 0);
	network_deinit_tls(ftp_ctrl->data_netc);
	//下面仅测试使用 ftp_ctrl->addr 实际应使用 data_addr,但是要不要使用ftp_ctrl->addr兼容呢？
#ifdef LUAT_USE_LWIP
	if(network_connect(ftp_ctrl->data_netc, data_addr, strlen(data_addr), (0xff == ftp_ctrl->ip_addr.type)?NULL:&(ftp_ctrl->ip_addr), data_port, 0)<0){
#else
	if(network_connect(ftp_ctrl->data_netc, data_addr, strlen(data_addr), (0xff == ftp_ctrl->ip_addr.is_ipv6)?NULL:&(ftp_ctrl->ip_addr), data_port, 0)<0){
#endif
		LLOGE("ftp network_connect fail");
		network_close(ftp_ctrl->data_netc, 0);
		return -1;
	}
	LLOGD("ftp pasv_connect ok");
	return 0;
}

void ftp_task(void *param){
	int ret;
    uint8_t event;
	rtos_msg_t msg = {0};
    msg.handler = l_ftp_callback;
	msg.ptr = ftp_ctrl;
    while (1) {
        luat_rtos_queue_recv(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), LUAT_WAIT_FOREVER);
		msg.arg2 = event;
		switch (event)
		{
		case FTP_QUEUE_LOGIN:
			#ifdef LUAT_USE_LWIP
				if(network_connect(ftp_ctrl->cmd_netc, ftp_ctrl->addr, strlen(ftp_ctrl->addr), (0xff == ftp_ctrl->ip_addr.type)?NULL:&(ftp_ctrl->ip_addr), ftp_ctrl->port, FTP_SOCKET_TIMEOUT)){
			#else
				if(network_connect(ftp_ctrl->cmd_netc, ftp_ctrl->addr, strlen(ftp_ctrl->addr), (0xff == ftp_ctrl->ip_addr.is_ipv6)?NULL:&(ftp_ctrl->ip_addr), ftp_ctrl->port, FTP_SOCKET_TIMEOUT)){
			#endif
					LLOGE("ftp network_connect fail");
					network_close(ftp_ctrl->cmd_netc, 0);
					goto error;
				}

				ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto error;
				}else{
					if (memcmp(ftp_ctrl->cmd_recv_data, FTP_SERVICE_NEW_OK, 3)){
						LLOGD("ftp connect error");
						goto error;
					}
				}
				LLOGD("ftp connect ok");

				memset(ftp_ctrl->cmd_send_data,0,FTP_CMD_SEND_MAX);
				snprintf_(ftp_ctrl->cmd_send_data, FTP_CMD_SEND_MAX, "USER %s\r\n",ftp_ctrl->username);
				luat_ftp_cmd_send(ftp_ctrl, ftp_ctrl->cmd_send_data, strlen(ftp_ctrl->cmd_send_data),FTP_SOCKET_TIMEOUT);
				ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto error;
				}else{
					if (memcmp(ftp_ctrl->cmd_recv_data, FTP_USERNAME_OK, 3)){
						LLOGD("ftp username wrong");
						goto error;
					}
				}
				LLOGD("ftp username ok");
				
				memset(ftp_ctrl->cmd_send_data,0,FTP_CMD_SEND_MAX);
				snprintf_(ftp_ctrl->cmd_send_data, FTP_CMD_SEND_MAX, "PASS %s\r\n",ftp_ctrl->password);
				luat_ftp_cmd_send(ftp_ctrl, ftp_ctrl->cmd_send_data, strlen(ftp_ctrl->cmd_send_data),FTP_SOCKET_TIMEOUT);
				ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto error;
				}else{
					if (memcmp(ftp_ctrl->cmd_recv_data, FTP_LOGIN_OK, 3)){
						LLOGD("ftp login wrong");
						goto error;
					}
				}
				LLOGD("ftp login ok");
				msg.arg1 = 0;
				luat_msgbus_put(&msg, 0);
			break;
		case FTP_QUEUE_COMMAND:
			break;
		case FTP_QUEUE_PULL:
			if(luat_ftp_pasv_connect(ftp_ctrl,FTP_SOCKET_TIMEOUT)){
				LLOGD("ftp pasv_connect fail");
				goto error;
			}
			luat_rtos_queue_recv(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), FTP_SOCKET_TIMEOUT);
			if(event == FTP_QUEUE_DATA_CONNECT){
				memset(ftp_ctrl->cmd_send_data,0,FTP_CMD_SEND_MAX);
				LLOGD("ftp_ctrl->remote_name:%s",ftp_ctrl->remote_name);
				snprintf_(ftp_ctrl->cmd_send_data, FTP_CMD_SEND_MAX, "RETR %s\r\n",ftp_ctrl->remote_name);
				luat_ftp_cmd_send(ftp_ctrl, ftp_ctrl->cmd_send_data, strlen(ftp_ctrl->cmd_send_data),FTP_SOCKET_TIMEOUT);
			}else{
				goto error;
			}
			ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto error;
			}else{
				if (memcmp(ftp_ctrl->cmd_recv_data, FTP_FILE_STATUS_OK, 3)){
					LLOGD("ftp RETR wrong");
					goto error;
				}
			}
			ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto error;
			}else{
				if (memcmp(ftp_ctrl->cmd_recv_data, FTP_CLOSE_CONNECT, 3)){
					LLOGD("ftp RETR wrong");
					goto error;
				}
			}
			if (ftp_ctrl->fd){
				luat_fs_fclose(ftp_ctrl->fd);
				ftp_ctrl->fd = NULL;
			}
			msg.arg1 = 0;
			luat_msgbus_put(&msg, 0);

			break;
		case FTP_QUEUE_PUSH:
			if(luat_ftp_pasv_connect(ftp_ctrl,FTP_SOCKET_TIMEOUT)){
				LLOGD("ftp pasv_connect fail");
				goto error;
			}
			luat_rtos_queue_recv(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), FTP_SOCKET_TIMEOUT);
			if(event == FTP_QUEUE_DATA_CONNECT){
				memset(ftp_ctrl->cmd_send_data,0,FTP_CMD_SEND_MAX);
				snprintf_(ftp_ctrl->cmd_send_data, FTP_CMD_SEND_MAX, "APPE %s\r\n",ftp_ctrl->remote_name);
				luat_ftp_cmd_send(ftp_ctrl, ftp_ctrl->cmd_send_data, strlen(ftp_ctrl->cmd_send_data),FTP_SOCKET_TIMEOUT);
				ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto error;
				}else{
					if (memcmp(ftp_ctrl->cmd_recv_data, FTP_FILE_STATUS_OK, 3)){
						LLOGD("ftp APPE wrong");
						goto error;
					}
				}
			}else{
				goto error;
			}

			uint8_t* buff = luat_heap_malloc(PUSH_BUFF_SIZE);
			int offset = 0;
			while (1) {
				memset(buff, 0, PUSH_BUFF_SIZE);
				int len = luat_fs_fread(buff, sizeof(uint8_t), PUSH_BUFF_SIZE, ftp_ctrl->fd);
				if (len < 1)
					break;
				luat_ftp_data_send(ftp_ctrl, buff, len);
				offset += len;
			}
			luat_heap_free(buff);
			LLOGD("offset:%d file_size:%d",offset,ftp_ctrl->local_file_size);
			luat_rtos_queue_recv(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), FTP_SOCKET_TIMEOUT);
			if(event != FTP_QUEUE_DATA_TX_DONE){
				goto error;
			}
			LLOGD("ftp APPE ok");
			network_close(ftp_ctrl->data_netc, 0);
			ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
			if (ret){
				goto error;
			}else{
				if (memcmp(ftp_ctrl->cmd_recv_data, FTP_CLOSE_CONNECT, 3)){
					LLOGD("ftp STOR wrong");
					goto error;
				}
			}
			if (ftp_ctrl->fd){
				luat_fs_fclose(ftp_ctrl->fd);
				ftp_ctrl->fd = NULL;
			}
			msg.arg1 = 0;
			luat_msgbus_put(&msg, 0);
			break;
		case FTP_QUEUE_CLOSE:
				luat_ftp_cmd_send(ftp_ctrl, "QUIT\r\n", strlen("QUIT\r\n"),FTP_SOCKET_TIMEOUT);
				ret = luat_ftp_cmd_recv(ftp_ctrl,ftp_ctrl->cmd_recv_data,&ftp_ctrl->cmd_recv_len,FTP_SOCKET_TIMEOUT);
				if (ret){
					goto error;
				}else{
					if (memcmp(ftp_ctrl->cmd_recv_data, FTP_CLOSE_CONTROL, 3)){
						LLOGD("ftp QUIT wrong");
						goto error;
					}
				}
			break;
		default:
			break;
		}
	}
error:
	msg.arg1 = 1;
	luat_msgbus_put(&msg, 0);
	luat_rtos_task_delete(ftp_ctrl->ftp_task_handle);
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
@return int code
@return tabal headers
@return string body
@usage
ftp_login = ftp.login(ip_addr,port)
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
	// mbedtls_debug_set_threshold(4);
	if (ftp_ctrl){
		LLOGE("ftp_ctrl already created,please close first");
		goto error;
	}
	
	ftp_ctrl = (luat_ftp_ctrl_t *)luat_heap_malloc(sizeof(luat_ftp_ctrl_t));
	if (!ftp_ctrl){
		LLOGE("out of memory when malloc ftp_ctrl");
        goto error;
	}
	memset(ftp_ctrl, 0, sizeof(luat_ftp_ctrl_t));

	ftp_ctrl->adapter_index = luaL_optinteger(L, 1, network_get_last_register_adapter());
	if (ftp_ctrl->adapter_index < 0 || ftp_ctrl->adapter_index >= NW_ADAPTER_QTY){
		LLOGE("bad network adapter index %d", ftp_ctrl->adapter_index);
		goto error;
	}
	
	ftp_ctrl->cmd_netc = network_alloc_ctrl(ftp_ctrl->adapter_index);
	if (!ftp_ctrl->cmd_netc){
		LLOGE("cmd_netc create fail");
		goto error;
	}

	luat_rtos_task_create(&ftp_ctrl->ftp_task_handle, 2048, 50, "ftp", ftp_task, NULL, 0);
	network_init_ctrl(ftp_ctrl->cmd_netc,ftp_ctrl->ftp_task_handle, NULL, NULL);

	luat_rtos_queue_create(&ftp_ctrl->ftp_queue_handle, 10, sizeof(uint8_t));

	network_set_base_mode(ftp_ctrl->cmd_netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(ftp_ctrl->cmd_netc, 0);

	const char *addr = luaL_checklstring(L, 2, &addr_len);
	ftp_ctrl->addr = luat_heap_malloc(addr_len + 1);
	memset(ftp_ctrl->addr, 0, addr_len + 1);
	memcpy(ftp_ctrl->addr, addr, addr_len);

	ftp_ctrl->port = luaL_optinteger(L, 3, 21);

	username = luaL_optlstring(L, 4, "",&username_len);
	ftp_ctrl->username = luat_heap_malloc(username_len + 1);
	memset(ftp_ctrl->username, 0, username_len + 1);
	memcpy(ftp_ctrl->username, username, username_len);

	password = luaL_optlstring(L, 5, "",&password_len);
	ftp_ctrl->password = luat_heap_malloc(password_len + 1);
	memset(ftp_ctrl->password, 0, password_len + 1);
	memcpy(ftp_ctrl->password, password, password_len);

	// 加密相关
	if (lua_isboolean(L, 6)){
		ftp_ctrl->is_tls = lua_toboolean(L, 6);
	}

	if (lua_istable(L, 6)){
		ftp_ctrl->is_tls = 1;

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

	if (ftp_ctrl->is_tls){
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
		network_init_tls(ftp_ctrl->cmd_netc, (server_cert || client_cert)?2:0);
		if (server_cert){
			network_set_server_cert(ftp_ctrl->cmd_netc, (const unsigned char *)server_cert, server_cert_len+1);
		}
		if (client_cert){
			network_set_client_cert(ftp_ctrl->cmd_netc, client_cert, client_cert_len+1,
					client_key, client_key_len+1,
					client_password, client_password_len+1);
		}
	}else{
		network_deinit_tls(ftp_ctrl->cmd_netc);
	}

#ifdef LUAT_USE_LWIP
	ftp_ctrl->ip_addr.type = 0xff;
#else
	ftp_ctrl->ip_addr.is_ipv6 = 0xff;
#endif

	ftp_ctrl->idp = luat_pushcwait(L);
	uint8_t event = FTP_QUEUE_LOGIN;
	luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), 0);
    return 1;
error:
	LLOGE("ftp login fail");
	luat_ftp_close(ftp_ctrl);
    lua_pushinteger(L,FTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 0;
}

static int l_ftp_command(lua_State *L) {
	ftp_ctrl->idp = luat_pushcwait(L);
	if (!ftp_ctrl){
		LLOGE("please login first");
		goto error;
	}
	uint8_t event = FTP_QUEUE_COMMAND;
	luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), 0);
	return 1;
error:
	LLOGE("ftp command fail");
	luat_ftp_close(ftp_ctrl);
    lua_pushinteger(L,FTP_ERROR_FILE);
	luat_pushcwait_error(L,1);
	return 0;
}

static int l_ftp_pull(lua_State *L) {
	size_t len;
	ftp_ctrl->idp = luat_pushcwait(L);
	if (!ftp_ctrl){
		LLOGE("please login first");
		goto error;
	}
	const char * local_name = luaL_optlstring(L, 1, "",&len);
	luat_fs_remove(local_name);
	ftp_ctrl->fd = luat_fs_fopen(local_name, "wb+");
	if (ftp_ctrl->fd == NULL) {
		LLOGE("open download file fail %s", local_name);
		goto error;
	}
	ftp_ctrl->local_file_size = luat_fs_fsize(local_name);
	const char * remote_name = luaL_optlstring(L, 2, "",&len);
	ftp_ctrl->remote_name = luat_heap_malloc(len + 1);
	memset(ftp_ctrl->remote_name, 0, len + 1);
	memcpy(ftp_ctrl->remote_name, remote_name, len);
	ftp_ctrl->ftp_execute = FTP_QUEUE_PULL;
	uint8_t event = FTP_QUEUE_PULL;
	luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), 0);
	return 1;
error:
	LLOGE("ftp pull fail");
	luat_ftp_close(ftp_ctrl);
    lua_pushinteger(L,FTP_ERROR_FILE);
	luat_pushcwait_error(L,1);
	return 0;
}

static int l_ftp_push(lua_State *L) {
	size_t len;
	ftp_ctrl->idp = luat_pushcwait(L);
	if (!ftp_ctrl){
		LLOGE("please login first");
		goto error;
	}
	const char * local_name = luaL_optlstring(L, 1, "",&len);
	ftp_ctrl->fd = luat_fs_fopen(local_name, "rb");
	if (ftp_ctrl->fd == NULL) {
		LLOGE("open download file fail %s", local_name);
		goto error;
	}
	ftp_ctrl->local_file_size = luat_fs_fsize(local_name);
	const char * remote_name = luaL_optlstring(L, 2, "",&len);
	ftp_ctrl->remote_name = luat_heap_malloc(len + 1);
	memset(ftp_ctrl->remote_name, 0, len + 1);
	memcpy(ftp_ctrl->remote_name, remote_name, len);
	ftp_ctrl->ftp_execute = FTP_QUEUE_PUSH;
	uint8_t event = FTP_QUEUE_PUSH;
	luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), 0);
	return 1;
error:
	LLOGE("ftp push fail");
	luat_ftp_close(ftp_ctrl);
    lua_pushinteger(L,FTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 0;
}

static int l_ftp_close(lua_State *L) {
	ftp_ctrl->idp = luat_pushcwait(L);
	if (!ftp_ctrl){
		LLOGE("please login first");
		goto error;
	}
	uint8_t event = FTP_QUEUE_CLOSE;
	luat_rtos_queue_send(ftp_ctrl->ftp_queue_handle, &event, sizeof(uint8_t), 0);
	return 1;
error:
	LLOGE("ftp login fail");
	luat_ftp_close(ftp_ctrl);
    lua_pushinteger(L,FTP_ERROR_CONNECT);
	luat_pushcwait_error(L,1);
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_ftp[] =
{
	{"login",			ROREG_FUNC(l_ftp_login)},
	{"command",			ROREG_FUNC(l_ftp_command)},
	{"pull",			ROREG_FUNC(l_ftp_pull)},
	{"push",			ROREG_FUNC(l_ftp_push)},
	{"close",			ROREG_FUNC(l_ftp_close)},

    {"PWD",            	ROREG_INT(FTP_COMMAND_PWD)},

	{ NULL,             ROREG_INT(0)}
};

static const rotable_Reg_t reg_ftp_emtry[] =
{
	{ NULL,             ROREG_INT(0)}
};

LUAMOD_API int luaopen_ftp( lua_State *L ) {
#ifdef LUAT_USE_NETWORK
    luat_newlib2(L, reg_ftp);
#else
    luat_newlib2(L, reg_ftp_emtry);
	LLOGE("reg_ftp require network enable!!");
#endif
    return 1;
}
