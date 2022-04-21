
#include "luat_base.h"
#ifdef LUAT_USE_NETWORK
#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "platform_def.h"
#include "bsp_common.h"
#define LUAT_LOG_TAG "network"
#include "luat_log.h"
#include "ctype.h"
#define NW_LOCK		OS_SuspendTask(NULL)
#define NW_UNLOCK	OS_ResumeTask(NULL)

typedef struct
{
	network_adapter_info *opt;
	void *user_data;
	uint8_t *ctrl_busy;
	network_ctrl_t *ctrl_table;
}network_adapter_t;

static network_adapter_t prv_adapter_table[NW_ADAPTER_QTY];

static int32_t network_default_socket_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	uint32_t adapter_index =(uint32_t)param;
	if (adapter_index >= NW_ADAPTER_QTY) return -1;
	network_adapter_t *adapter = (network_adapter_t *)param;
	int i;
	network_ctrl_t *ctrl = NULL;
	NW_LOCK;
	if (event->ID > EV_NW_TIMEOUT)
	{
		ctrl = event->Param3;
		if (ctrl->task_handle)
		{
			platform_send_event(ctrl->task_handle, event->ID, event->Param1, event->Param2, event->Param3);
		}
		else
		{
			ctrl->user_callback(event, ctrl->user_data);
		}
	}
	else
	{
		for (i = 0; i < adapter->opt->max_socket_num; i++)
		{
			if (adapter->ctrl_busy[i])
			{
				ctrl = &adapter->ctrl_table[i];
				if (ctrl->task_handle)
				{
					platform_send_event(ctrl->task_handle, event->ID, event->Param1, event->Param2, event->Param3);
				}
				else
				{
					ctrl->user_callback(event, ctrl->user_data);
				}
			}
		}
	}
	NW_UNLOCK;
	return 0;
}

static int32_t network_default_timer_callback(void *data, void *param)
{
	platform_send_event(param, EV_NW_TIMEOUT, 0, 0, 0);
	return 0;
}

uint8_t network_string_is_ipv4(const char *string, uint32_t len)
{
	int i;
	for(i = 0; i < len; i++)
	{
		if (!isdigit(string[i]) && (string[i] != '.'))
		{
			return 0;
		}
	}
	return 1;
}

uint32_t network_string_to_ipv4(const char *string, uint32_t len)
{
	int i;
	int8_t Buf[4][4];
	CmdParam CP;
	PV_Union uIP;
	char temp[32];
	memset(Buf, 0, sizeof(Buf));
	CP.param_max_len = 4;
	CP.param_max_num = 4;
	CP.param_num = 0;
	CP.param_str = (int8_t *)Buf;
	memcpy(temp, string, len);
	temp[len] = 0;
	CmdParseParam(temp, &CP, '.');
	for(i = 0; i < 4; i++)
	{
		uIP.u8[i] = strtol(Buf[i], NULL, 10);
	}
//	DBG("%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
	return uIP.u32;
}

#define SWAP(x) ((((x) & (uint32_t)0x000000ffUL) << 24) | \
                     (((x) & (uint32_t)0x0000ff00UL) <<  8) | \
                     (((x) & (uint32_t)0x00ff0000UL) >>  8) | \
                     (((x) & (uint32_t)0xff000000UL) >> 24))

int network_string_to_ipv6(const char *string, luat_ip_addr_t *ip_addr)
{


  uint32_t addr_index, zero_blocks, current_block_index, current_block_value;
  const char *s;
  ip_addr->is_ipv6 = 0;
  /* Count the number of colons, to count the number of blocks in a "::" sequence
	 zero_blocks may be 1 even if there are no :: sequences */
  zero_blocks = 8;
  for (s = string; *s != 0; s++) {
	if (*s == ':') {
	  zero_blocks--;
	} else if (!isxdigit(*s)) {
	  break;
	}
  }

  /* parse each block */
  addr_index = 0;
  current_block_index = 0;
  current_block_value = 0;
  for (s = string; *s != 0; s++) {
	if (*s == ':') {
		if (current_block_index & 0x1) {
			ip_addr->ipv6_u32_addr[addr_index++] |= current_block_value;
		}
		else {
			ip_addr->ipv6_u32_addr[addr_index] = current_block_value << 16;
		}
	  current_block_index++;
	  current_block_value = 0;
	  if (current_block_index > 7) {
		/* address too long! */
		return 0;
	  }
	  if (s[1] == ':') {
		if (s[2] == ':') {
		  /* invalid format: three successive colons */
		  return 0;
		}
		s++;
		/* "::" found, set zeros */
		while (zero_blocks > 0) {
		  zero_blocks--;
		  if (current_block_index & 0x1) {
			addr_index++;
		  } else {
			  ip_addr->ipv6_u32_addr[addr_index] = 0;
		  }
		  current_block_index++;
		  if (current_block_index > 7) {
			/* address too long! */
			return 0;
		  }
		}
	  }
	} else if (isxdigit(*s)) {
	  /* add current digit */
	  current_block_value = (current_block_value << 4) +
		  (isxdigit(*s) ? (uint32_t)(*s - '0') :
		  (uint32_t)(10 + (isxdigit(*s) ? *s - 'a' : *s - 'A')));
	} else {
	  /* unexpected digit, space? CRLF? */
	  break;
	}
  }


	if (current_block_index & 0x1) {
		ip_addr->ipv6_u32_addr[addr_index++] |= current_block_value;
	}
	else {
		ip_addr->ipv6_u32_addr[addr_index] = current_block_value << 16;
	}

	/* convert to network byte order. */
	for (addr_index = 0; addr_index < 4; addr_index++) {
		ip_addr->ipv6_u32_addr[addr_index] = SWAP(ip_addr->ipv6_u32_addr[addr_index]);
	}



	if (current_block_index != 7) {

		return 0;
	}
	ip_addr->is_ipv6 = 1;
	return 1;

}

network_adapter_info *network_get_adapter(uint8_t adapter_index)
{
	return prv_adapter_table[adapter_index].opt;
}

int network_register_adapter(uint8_t adapter_index, network_adapter_info *info, void *user_data)
{
	prv_adapter_table[adapter_index].opt = info;
	prv_adapter_table[adapter_index].user_data = user_data;
	info->socket_set_callback(network_default_socket_callback, &prv_adapter_table[adapter_index], user_data);
	prv_adapter_table[adapter_index].ctrl_table = zalloc((info->max_socket_num) * sizeof(network_ctrl_t));
	prv_adapter_table[adapter_index].ctrl_busy = zalloc(info->max_socket_num);
}

void network_set_dns_server(uint8_t adapter_index, uint8_t server_index, luat_ip_addr_t *ip)
{
	network_adapter_t *adapter = &prv_adapter_table[adapter_index];
	adapter->opt->set_dns_server(server_index, ip, adapter->user_data);
}

/*
 * 申请一个network_ctrl
 */
network_ctrl_t *network_alloc_ctrl(uint8_t adapter_index)
{
	int i;
	network_ctrl_t *ctrl = NULL;
	network_adapter_t *adapter = &prv_adapter_table[adapter_index];
	NW_LOCK;
	for (i = 0; i < adapter->opt->max_socket_num; i++)
	{
		if (!adapter->ctrl_busy[i])
		{
			adapter->ctrl_busy[i] = 1;
			ctrl = &adapter->ctrl_table[i];
			break;
		}
	}
	if (i >= adapter->opt->max_socket_num) {LLOGE("adapter no more ctrl!");}
	NW_UNLOCK;
	return ctrl;
}
/*
 * 归还一个network_ctrl
 */
void network_release_ctrl(uint8_t adapter_index, network_ctrl_t *ctrl)
{
	int i;
	network_adapter_t *adapter = &prv_adapter_table[adapter_index];
	NW_LOCK;
	for (i = 0; i < adapter->opt->max_socket_num; i++)
	{
		if (&adapter->ctrl_table[i] == ctrl)
		{
			adapter->ctrl_busy[i] = 0;
			break;
		}
	}
	NW_UNLOCK;
	if (i >= adapter->opt->max_socket_num) {LLOGE("adapter index maybe error!, %d, %x", adapter, ctrl);}

}

void network_init_ctrl(network_ctrl_t *ctrl, uint8_t adapter_index, HANDLE task_handle, CBFuncEx_t callback, void *param)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	memset(ctrl, 0, sizeof(network_ctrl_t));
	ctrl->adapter_index = adapter_index;
	ctrl->task_handle = task_handle;
	ctrl->user_callback = callback;
	ctrl->user_data = param;
	ctrl->socket_id = -1;
	if (task_handle)
	{
		ctrl->timer = platform_create_timer(network_default_timer_callback, task_handle, NULL);
	}
}

void network_set_base_mode(network_ctrl_t *ctrl, uint8_t is_tcp)
{
	ctrl->is_tcp = is_tcp;
}

uint8_t network_check_ready(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->check_ready(adapter->user_data);
}

int network_create_soceket(network_ctrl_t *ctrl, uint8_t is_ipv6)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->socket_id = adapter->opt->create_soceket(ctrl->is_tcp, &ctrl->tag, ctrl->socket_param, is_ipv6, adapter->user_data);
	if (ctrl->socket_id < 0)
	{
		ctrl->tag = 0;
		return -1;
	}
	return 0;
}

int network_socket_connect(network_ctrl_t *ctrl, luat_ip_addr_t *remote_ip)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->is_server_mode = 0;
	return adapter->opt->socket_connect(ctrl->socket_id, ctrl->tag, ctrl->local_port, remote_ip, ctrl->remote_port, adapter->user_data);
}

int network_socket_listen(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	ctrl->is_server_mode = 1;
	return adapter->opt->socket_listen(ctrl->socket_id, ctrl->tag, ctrl->local_port, adapter->user_data);
}

//作为server接受一个client
//成功返回0，失败 < 0
int network_socket_accept(network_ctrl_t *ctrl, network_ctrl_t *accept_ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (adapter->opt->no_accept)
	{
		return 0;
	}
	accept_ctrl->socket_id = adapter->opt->socket_accept(ctrl->socket_id, ctrl->tag, &accept_ctrl->remote_ip, &accept_ctrl->remote_port, adapter->user_data);
	if (accept_ctrl->socket_id < 0)
	{
		return -1;
	}
	else
	{
		return 0;
	}
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
//成功返回0，失败 < 0
int network_socket_disconnect(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		return adapter->opt->socket_disconnect(ctrl->socket_id, ctrl->tag, adapter->user_data);
	}

}
//释放掉socket的控制权
//成功返回0，失败 < 0
int network_socket_close(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		return adapter->opt->socket_close(ctrl->socket_id, ctrl->tag, adapter->user_data);
	}

}
//强行释放掉socket的控制权
//成功返回0，失败 < 0
int network_socket_force_close(network_ctrl_t *ctrl)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	if (ctrl->socket_id >= 0)
	{
		adapter->opt->socket_force_close(ctrl->socket_id, adapter->user_data);
	}
	ctrl->socket_id = -1;
	return 0;
}
//tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
//udp时，只返回1个block数据，需要多次读直到没有数据为止
//成功返回实际读取的值，失败 < 0
int network_socket_receive(network_ctrl_t *ctrl,uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->socket_receive(ctrl->socket_id, ctrl->tag, buf, len, flags, remote_ip, remote_port, adapter->user_data);
}
//tcp时，不需要remote_ip和remote_port
//成功返回0，失败 < 0
int network_socket_send(network_ctrl_t *ctrl,const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->socket_send(ctrl->socket_id, ctrl->tag, buf, len, flags, remote_ip, remote_port, adapter->user_data);
}

int network_getsockopt(network_ctrl_t *ctrl, int level, int optname, void *optval, uint32_t *optlen)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->getsockopt(ctrl->socket_id, ctrl->tag, level, optname, optval, optlen, adapter->user_data);
}
int network_setsockopt(network_ctrl_t *ctrl, int level, int optname, const void *optval, uint32_t optlen)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->setsockopt(ctrl->socket_id, ctrl->tag, level, optname, optval, optlen, adapter->user_data);
}
//非posix的socket，用这个根据实际硬件设置参数
int network_user_cmd(network_ctrl_t *ctrl,  uint32_t cmd, uint32_t value)
{
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->user_cmd(ctrl->socket_id, ctrl->tag, cmd, value, adapter->user_data);
}

int network_dns(network_ctrl_t *ctrl, const char *url, uint32_t len, luat_ip_addr_t *remote_ip)
{
	if (network_string_is_ipv4(url, len))
	{
		remote_ip->is_ipv6 = 0;
		remote_ip->ipv4 = network_string_to_ipv4(url, len);
		return 1;
	}
	else
	{
		if (network_string_to_ipv6(url, remote_ip))
		{
			return 1;
		}
	}
	network_adapter_t *adapter = &prv_adapter_table[ctrl->adapter_index];
	return adapter->opt->dns(url, adapter->user_data);
}
#endif
