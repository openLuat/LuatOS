#include "luat_base.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#if 1
#include "luat_network_adapter.h"
#include "dhcp_def.h"
#define LUAT_LOG_TAG "DHCP"
#include "luat_log.h"
#define DHCP_OPTION_138 138

// DHCP超时和重传配置
#define DHCP_MIN_LEASE_SEC 60
#define DHCP_RETRY_BASE_MS 1000
#define DHCP_RETRY_MAX_MS 8000
#define DHCP_RENEW_TIMEOUT_MS 2500
#define DHCP_REBIND_TIMEOUT_MS 2500
#define DHCP_SELECT_ACK_TIMEOUT_MS 1900
#define DHCP_MAX_SELECT_RETRIES 3


//extern void DBG_Printf(const char* format, ...);
//extern void DBG_HexPrintf(void *Data, unsigned int len);
//#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

void make_ip4_dhcp_msg_base(dhcp_client_info_t *dhcp, uint16_t flag, Buffer_Struct *out)
{
	uint16_t escape_time = 0;
	if (dhcp->last_tx_time)
	{
		escape_time = (luat_mcu_tick64_ms() - dhcp->last_tx_time) / 1000;
	}
	// 确保缓冲区至少能容纳DHCP基本消息(236) + magic(4) + 选项空间
	if (out->MaxLen < DHCP_MSG_LEN + 4 + 64) {
		LLOGE("buffer too small for DHCP message");
		return;
	}
	BytesPut8ToBuf(out, DHCP_BOOTREQUEST);
	BytesPut8ToBuf(out, DHCP_HTYPE_ETH);
	BytesPut8ToBuf(out, 6);
	BytesPut8ToBuf(out, 0);
	BytesPutBe32ToBuf(out, dhcp->xid);
	BytesPutBe16ToBuf(out, escape_time);
	BytesPutBe16ToBuf(out, flag);
	BytesPutLe32ToBuf(out, dhcp->ip);
	BytesPutLe32ToBuf(out, 0);
	BytesPutLe32ToBuf(out, 0);
	BytesPutLe32ToBuf(out, 0);
	OS_BufferWrite(out, dhcp->mac, 6);
	// 使用OS_BufferWrite确保安全，填充chaddr剩余10字节 + sname(64) + file(128)
	uint8_t zeros[202] = {0}; // 10 + 64 + 128
	OS_BufferWrite(out, zeros, sizeof(zeros));
	BytesPutBe32ToBuf(out, DHCP_MAGIC_COOKIE);
}

void ip4_dhcp_msg_add_bytes_option(uint8_t id, uint8_t *data, uint8_t len, Buffer_Struct *out)
{
	BytesPut8ToBuf(out, id);
	BytesPut8ToBuf(out, len);
	OS_BufferWrite(out, data, len);
}

void ip4_dhcp_msg_add_client_id_option(uint8_t id, uint8_t *data, uint8_t len, Buffer_Struct *out)
{
	BytesPut8ToBuf(out, id);
	BytesPut8ToBuf(out, len + 1);
	BytesPut8ToBuf(out, 1);
	OS_BufferWrite(out, data, len);
}

void ip4_dhcp_msg_add_ip_option(uint8_t id, uint32_t ip, Buffer_Struct *out)
{
	BytesPut8ToBuf(out, id);
	BytesPut8ToBuf(out, 4);
	// 保持与系统内部IP存储格式一致（小端序）
	// 该系统所有IP读取都用BytesGetLe32，写入也需要用Le32保持一致
	BytesPutLe32ToBuf(out, ip);
}

void ip4_dhcp_msg_add_integer_option(uint8_t id, uint8_t len, uint32_t value, Buffer_Struct *out)
{
	BytesPut8ToBuf(out, id);
	BytesPut8ToBuf(out, len);
	switch (len)
	{
	case 1:
		BytesPut8ToBuf(out, value);
		break;
	case 2:
		BytesPutBe16ToBuf(out, value);
		break;
	default:
		BytesPutBe32ToBuf(out, value);
		break;
	}
}

void make_ip4_dhcp_discover_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out)
{
	uint8_t dhcp_discover_request_options[] = {
			  DHCP_OPTION_SUBNET_MASK,
			  DHCP_OPTION_ROUTER,
			  DHCP_OPTION_BROADCAST,
			  DHCP_OPTION_SERVER_ID,
			  DHCP_OPTION_LEASE_TIME,
			  DHCP_OPTION_IP_TTL,
	};
	out->Pos = 0;
	dhcp->xid++;
	make_ip4_dhcp_msg_base(dhcp, 0x8000, out);
	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_DISCOVER, out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_PARAMETER_REQUEST_LIST, dhcp_discover_request_options, sizeof(dhcp_discover_request_options), out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, (uint8_t*)dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, (uint8_t*)dhcp->mac, 6, out);
	BytesPut8ToBuf(out, 0xff);
	// DHCP选项无需强制4字节对齐，避免产生冗余填充
}

void make_ip4_dhcp_select_msg(dhcp_client_info_t *dhcp, uint16_t flag, Buffer_Struct *out)
{
	uint8_t dhcp_discover_request_options[] = {
			  DHCP_OPTION_SUBNET_MASK,
			  DHCP_OPTION_ROUTER,
			  DHCP_OPTION_DNS_SERVER,
			  15,
			  31,33,43,44,46,47,
			  DHCP_OPTION_SERVER_ID,
			  DHCP_OPTION_LEASE_TIME,
			  119,121,249,252
			  //DHCP_OPTION_138,
	  };
	out->Pos = 0;
	// 构造FQDN(Option 81): Flags(1) + RCode1(1) + RCode2(1) + Hostname
	uint8_t full_name[96] = {0};
	make_ip4_dhcp_msg_base(dhcp, flag, out);
	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_REQUEST, out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, (uint8_t*)dhcp->mac, 6, out);
	ip4_dhcp_msg_add_ip_option(DHCP_OPTION_REQUESTED_IP, dhcp->temp_ip, out);
	if (dhcp->server_ip)
	{
		ip4_dhcp_msg_add_ip_option(DHCP_OPTION_SERVER_ID, dhcp->server_ip, out);
	}
	// HOSTNAME（长度限制避免超过255）
	{
		size_t name_len = strlen(dhcp->name);
		if (name_len > 63) name_len = 63; // 常见实现对主机名长度做限制
		ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, (uint8_t*)dhcp->name, (uint8_t)name_len, out);
		// FQDN: Flags=0x01（服务器进行更新），RCode1=0，RCode2=0
		full_name[0] = 0x01;
		full_name[1] = 0x00;
		full_name[2] = 0x00;
		memcpy(full_name + 3, (uint8_t*)dhcp->name, name_len);
		ip4_dhcp_msg_add_bytes_option(81, full_name, (uint8_t)(name_len + 3), out);
	}
	// Vendor Class已移除（原"MSFT 5.0"），避免服务器施加Windows特定策略
	// 如有需要，可根据实际平台配置添加
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_PARAMETER_REQUEST_LIST, dhcp_discover_request_options, sizeof(dhcp_discover_request_options), out);
	BytesPut8ToBuf(out, 0xff);
}

//void make_ip4_dhcp_info_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out)
//{
//	uint8_t dhcp_discover_request_options[] = {
//			  DHCP_OPTION_SUBNET_MASK,
//			  DHCP_OPTION_ROUTER,
//			  DHCP_OPTION_BROADCAST,
//			  DHCP_OPTION_SERVER_ID,
//			  DHCP_OPTION_LEASE_TIME,
//			  DHCP_OPTION_DNS_SERVER,
//			  DHCP_OPTION_IP_TTL,
//			  DHCP_OPTION_138,
//	  };
//	out->Pos = 0;
//	dhcp->xid++;
//	make_ip4_dhcp_msg_base(dhcp, 0x8000, out);
//	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_INFORM, out);
//	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, (uint8_t*)dhcp->name, strlen(dhcp->name), out);
//	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, (uint8_t*)dhcp->mac, 6, out);
//	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_PARAMETER_REQUEST_LIST, dhcp_discover_request_options, sizeof(dhcp_discover_request_options), out);
//	BytesPut8ToBuf(out, 0xff);
//}

void make_ip4_dhcp_decline_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out)
{

	out->Pos = 0;
	dhcp->xid++;
	make_ip4_dhcp_msg_base(dhcp, 0, out);
	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_DECLINE, out);
	ip4_dhcp_msg_add_ip_option(DHCP_OPTION_REQUESTED_IP, dhcp->temp_ip, out);
	ip4_dhcp_msg_add_ip_option(DHCP_OPTION_SERVER_ID, dhcp->server_ip, out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, (uint8_t*)dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, (uint8_t*)dhcp->mac, 6, out);
	BytesPut8ToBuf(out, 0xff);
}

int analyze_ip4_dhcp(dhcp_client_info_t *dhcp, Buffer_Struct *in)
{
	int ack = 0;
	uint64_t lease_time;
	if (in->Data[0] != DHCP_BOOTREPLY)
	{
		LLOGD("head error");
		return -1;
	}
	if (BytesGetBe32(&in->Data[DHCP_MSG_LEN]) != DHCP_MAGIC_COOKIE)
	{
		LLOGD("cookie error");
		return -2;
	}
	// 基本类型校验：HTYPE=ETH(1)，HLEN=6
	if (in->Data[1] != DHCP_HTYPE_ETH || in->Data[2] != 6)
	{
		LLOGD("htype/hlen error %d/%d", in->Data[1], in->Data[2]);
		return -1;
	}

	if (BytesGetBe32(&in->Data[4]) != dhcp->xid)
	{
		// LLOGD("xid error %x,%x", BytesGetBe32(&in->Data[4]), dhcp->xid);
		if (BytesGetBe32(&in->Data[4]) == (dhcp->xid - 1))
		{
			LLOGD("maybe get same ack, drop %x,%x", BytesGetBe32(&in->Data[4]), dhcp->xid);
			return 0;
		}
		LLOGD("xid error %x,%x not for us, drop", BytesGetBe32(&in->Data[4]), dhcp->xid);
		return -3;
	}
	if (memcmp(dhcp->mac, &in->Data[28], 6))
	{
		LLOGD("mac error");
		return -4;
	}
	dhcp->temp_ip = BytesGetLe32(&in->Data[16]);
	LLOGD("find ip %x %d.%d.%d.%d", dhcp->temp_ip, in->Data[16], in->Data[17], in->Data[18], in->Data[19]);


	in->Pos = DHCP_OPTIONS_OFS;
	while (in->Pos < in->MaxLen)
	{
__CHECK:
		// 边界检查，确保能读取type/len
		if (in->Pos + 1 >= in->MaxLen)
			break;
		uint8_t opt = in->Data[in->Pos];
		uint8_t len = in->Data[in->Pos + 1];
		if (opt == DHCP_OPTION_PAD)
		{
			in->Pos++;
			goto __CHECK;
		}
		if (opt == DHCP_OPTION_END)
		{
			return ack;
		}
		if (in->Pos + 2 + len > in->MaxLen)
		{
			LLOGW("option overflow opt=%d len=%d pos=%d", opt, len, in->Pos);
			break;
		}
		switch(opt)
		{
		case DHCP_OPTION_MESSAGE_TYPE:
			ack = in->Data[in->Pos + 2];
			break;
		case DHCP_OPTION_SERVER_ID:
			dhcp->server_ip = BytesGetLe32(&in->Data[in->Pos + 2]);
			break;
		case DHCP_OPTION_LEASE_TIME:
			if (DHCP_ACK == ack)
			{
				dhcp->lease_time = BytesGetBe32(&in->Data[in->Pos + 2]);
				if (dhcp->lease_time < DHCP_MIN_LEASE_SEC)
				{
					LLOGW("lease time too short %d, set to %d", dhcp->lease_time, DHCP_MIN_LEASE_SEC);
					dhcp->lease_time = DHCP_MIN_LEASE_SEC;
				}
				lease_time = dhcp->lease_time;
				lease_time *= 1000;
				dhcp->lease_end_time = luat_mcu_tick64_ms() + lease_time;
				// 默认按比例，若后续解析到T1/T2会覆盖
				dhcp->lease_p1_time = dhcp->lease_end_time - (lease_time >> 1);
				dhcp->lease_p2_time = dhcp->lease_end_time - (lease_time >> 3);
			}
			break;

		case DHCP_OPTION_SUBNET_MASK:
			dhcp->submask = BytesGetLe32(&in->Data[in->Pos + 2]);
			break;
		case DHCP_OPTION_ROUTER:
			dhcp->gateway = BytesGetLe32(&in->Data[in->Pos + 2]);
			break;
		case DHCP_OPTION_DNS_SERVER:
			{
				// 解析所有DNS，每4字节一个地址
				uint8_t count = len / 4;
				for (uint8_t i = 0; i < count && i < 2; i++)
				{
					uint32_t addr = BytesGetLe32(&in->Data[in->Pos + 2 + i * 4]);
					dhcp->dns_server[i] = addr;
				}
				for (uint8_t i = count; i < 2; i++) dhcp->dns_server[i] = 0;
			}
			break;
		case 58: // Renewal Time (T1)
			if (DHCP_ACK == ack && len == 4)
			{
				uint64_t t1 = BytesGetBe32(&in->Data[in->Pos + 2]);
				if (t1 < DHCP_MIN_LEASE_SEC) t1 = DHCP_MIN_LEASE_SEC;
				dhcp->lease_p1_time = luat_mcu_tick64_ms() + t1 * 1000;
				LLOGD("T1(Renew)=%llu sec", t1);
			}
			break;
		case 59: // Rebinding Time (T2)
			if (DHCP_ACK == ack && len == 4)
			{
				uint64_t t2 = BytesGetBe32(&in->Data[in->Pos + 2]);
				if (t2 < DHCP_MIN_LEASE_SEC) t2 = DHCP_MIN_LEASE_SEC;
				dhcp->lease_p2_time = luat_mcu_tick64_ms() + t2 * 1000;
				LLOGD("T2(Rebind)=%llu sec", t2);
			}
			break;
		default:
			//LLOGD("jump %d,%d", in->Data[in->Pos], in->Data[in->Pos+1]);
			break;
		}
		in->Pos += 2 + len;
	}
	return ack;
}

int ip4_dhcp_run(dhcp_client_info_t *dhcp, Buffer_Struct *in, Buffer_Struct *out, uint32_t *remote_ip)
{
	uint16_t flag = 0x8000;
	*remote_ip = 0xffffffff;
	int result = 0;
	uint64_t tnow = luat_mcu_tick64_ms();
	LLOGD("dhcp state %d tnow %lld p1 %lld p2 %lld", dhcp->state, tnow, dhcp->lease_p1_time, dhcp->lease_p2_time);
	if (in)
	{
		result = analyze_ip4_dhcp(dhcp, in);
		LLOGD("result %d", result);
		if (result > 0)
		{
			if (result == DHCP_NAK)
			{
				dhcp->state = DHCP_STATE_DISCOVER;
				dhcp->temp_ip = 0;
				dhcp->server_ip = 0;
				dhcp->submask = 0;
				dhcp->gateway = 0;
				dhcp->ip = 0;
				dhcp->last_tx_time = 0;
				dhcp->lease_p1_time = 0;
				dhcp->lease_p2_time = 0;
				dhcp->weak_temp_ip = 0;
				dhcp->weak_server_ip = 0;
			}
		}
		else
		{
			return -1;
		}
	}
//	LLOGD("%d,%d", dhcp->state, result);
	switch(dhcp->state)
	{
	case DHCP_STATE_WAIT_LEASE_P1:
		if (tnow >= dhcp->lease_p1_time)
		{
			flag = 0;
			*remote_ip = dhcp->server_ip;
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P1_ACK:
		if (in && (result == DHCP_ACK))
		{
			LLOGD("lease p1 renew ip ok");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
			break;
		}
		if (tnow >= (dhcp->last_tx_time + DHCP_RENEW_TIMEOUT_MS))
		{
			LLOGD("lease p1 renew timeout, enter rebind phase");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P2;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P2:
		if (tnow >= dhcp->lease_p2_time)
		{
			LLOGD("lease p2 rebind time reached, broadcast request");
			// Rebind阶段使用广播，不指定server_ip
			flag = 0x8000;
			*remote_ip = 0xffffffff;
			dhcp->state = DHCP_STATE_WAIT_LEASE_P2_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P2_ACK:
		if (in && (result == DHCP_ACK))
		{
			LLOGD("lease p2 rebind ip ok");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
			break;
		}
		if (tnow >= (dhcp->last_tx_time + DHCP_REBIND_TIMEOUT_MS))
		{
			LLOGD("lease p2 rebind timeout, wait for lease expiry");
			dhcp->state = DHCP_STATE_WAIT_LEASE_END;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_END:
		if (tnow >= dhcp->lease_end_time)
		{
			LLOGD("lease expired, restart from discover");
			dhcp->state = DHCP_STATE_DISCOVER;
			dhcp->temp_ip = 0;
			dhcp->server_ip = 0;
			dhcp->ip = 0;
			dhcp->last_tx_time = 0;
			dhcp->discover_cnt = 0;
			// 下一轮循环会触发DISCOVER
		}
		break;
//	case DHCP_STATE_WAIT_REQUIRE_ACK:
//		if (in && (result == DHCP_ACK))
//		{
//			LLOGD("require ip ok");
//			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
//			break;
//		}
//		if (luat_mcu_tick64_ms() >= (dhcp->last_tx_time + 2500))
//		{
//			LLOGD("require ip long time no ack");
//			OS_ReInitBuffer(out, 512);
//			make_ip4_dhcp_discover_msg(dhcp, out);
//			dhcp->last_tx_time = luat_mcu_tick64_ms();
//			dhcp->discover_cnt = 0;
//			dhcp->state = DHCP_STATE_WAIT_OFFER;
//		}
//		break;
	case DHCP_STATE_DISCOVER:
		LLOGD("dhcp discover %02X%02X%02X%02X%02X%02X", (uint8_t)dhcp->mac[0], (uint8_t)dhcp->mac[1], (uint8_t)dhcp->mac[2], (uint8_t)dhcp->mac[3], (uint8_t)dhcp->mac[4], (uint8_t)dhcp->mac[5]);
		OS_ReInitBuffer(out, 512);
		make_ip4_dhcp_discover_msg(dhcp, out);
		dhcp->last_tx_time = luat_mcu_tick64_ms();
		dhcp->state = DHCP_STATE_WAIT_OFFER;
		break;
	case DHCP_STATE_WAIT_OFFER:
		if (in && (result == DHCP_OFFER))
		{
			LLOGD("got offer, send request");
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			dhcp->wait_selec_ack_cnt = 0;
			goto DHCP_NEED_REQUIRE;
		}
		// 指数退避：1s, 2s, 4s, 8s...
		{
			uint32_t backoff = DHCP_RETRY_BASE_MS << dhcp->discover_cnt;
			if (backoff > DHCP_RETRY_MAX_MS) backoff = DHCP_RETRY_MAX_MS;
			if (tnow >= (dhcp->last_tx_time + backoff))
			{
				LLOGD("no offer after %ums, resend discover (retry %d)", backoff, dhcp->discover_cnt);
				dhcp->discover_cnt++;
				OS_ReInitBuffer(out, 512);
				make_ip4_dhcp_discover_msg(dhcp, out);
				dhcp->last_tx_time = luat_mcu_tick64_ms();
			}
		}
		break;
	case DHCP_STATE_WAIT_SELECT_ACK:
		if (in && (result == DHCP_ACK))
		{
			dhcp->ip = dhcp->temp_ip;
			dhcp->state = DHCP_STATE_CHECK;
			dhcp->weak_temp_ip = 0;
			dhcp->weak_server_ip = 0;
			LLOGD("DHCP acquired IP %d.%d.%d.%d", 
				(dhcp->ip) & 0xFF, (dhcp->ip >> 8) & 0xFF, 
				(dhcp->ip >> 16) & 0xFF, (dhcp->ip >> 24) & 0xFF);
			break;
		}
		if (dhcp->wait_selec_ack_cnt >= DHCP_MAX_SELECT_RETRIES)
		{
			LLOGD("select request timeout after %d retries", dhcp->wait_selec_ack_cnt);
			if ((dhcp->weak_temp_ip == dhcp->temp_ip) && (dhcp->weak_server_ip == dhcp->server_ip))
			{
				LLOGW("same offer repeated, assume server issue, accept IP");
				dhcp->ip = dhcp->temp_ip;
				dhcp->state = DHCP_STATE_CHECK;
				dhcp->weak_temp_ip = 0;
				dhcp->weak_server_ip = 0;
				break;
			}
			else
			{
				dhcp->weak_temp_ip = dhcp->temp_ip;
				dhcp->weak_server_ip = dhcp->server_ip;
			}
			// 重新DISCOVER
			OS_ReInitBuffer(out, 512);
			make_ip4_dhcp_discover_msg(dhcp, out);
			dhcp->last_tx_time = luat_mcu_tick64_ms();
			dhcp->discover_cnt = 0;
			dhcp->state = DHCP_STATE_WAIT_OFFER;
		}
		else
		{
			if (tnow >= (dhcp->last_tx_time + DHCP_SELECT_ACK_TIMEOUT_MS * (dhcp->wait_selec_ack_cnt + 1)))
			{
				dhcp->wait_selec_ack_cnt++;
				LLOGD("select request no ack, retry %d", dhcp->wait_selec_ack_cnt);
				goto DHCP_NEED_REQUIRE;
			}
		}
		break;
	case DHCP_STATE_REQUIRE:
	case DHCP_STATE_SELECT:
		dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
		goto DHCP_NEED_REQUIRE;
		break;
	case DHCP_STATE_CHECK:
		break;
	case DHCP_STATE_DECLINE:
		dhcp->weak_temp_ip = 0;
		dhcp->weak_server_ip = 0;
		flag = 0;
		*remote_ip = dhcp->server_ip;
		OS_ReInitBuffer(out, 512);
		make_ip4_dhcp_decline_msg(dhcp, out);
		dhcp->last_tx_time = luat_mcu_tick64_ms();
		dhcp->state = DHCP_STATE_DISCOVER;

		break;
	case DHCP_STATE_NOT_WORK:
		break;
	}
	return 0;
DHCP_NEED_REQUIRE:
	OS_ReInitBuffer(out, 512);
	make_ip4_dhcp_select_msg(dhcp, flag, out);
	dhcp->last_tx_time = luat_mcu_tick64_ms();
	return 0;
}

#endif
