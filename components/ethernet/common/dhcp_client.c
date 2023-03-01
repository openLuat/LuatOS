#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#ifdef LUAT_USE_DHCP
#include "luat_network_adapter.h"
#include "dhcp_def.h"
#define LUAT_LOG_TAG "DHCP"
#include "luat_log.h"
#define DHCP_OPTION_138 138


//extern void DBG_Printf(const char* format, ...);
//extern void DBG_HexPrintf(void *Data, unsigned int len);
//#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

void make_ip4_dhcp_msg_base(dhcp_client_info_t *dhcp, uint16_t flag, Buffer_Struct *out)
{
	dhcp->xid++;
	BytesPut8ToBuf(out, DHCP_BOOTREQUEST);
	BytesPut8ToBuf(out, DHCP_HTYPE_ETH);
	BytesPut8ToBuf(out, 6);
	BytesPut8ToBuf(out, 0);
	BytesPutBe32ToBuf(out, dhcp->xid);
	BytesPutBe16ToBuf(out, 0);
	BytesPutBe16ToBuf(out, flag);
	BytesPutLe32ToBuf(out, dhcp->ip);
	BytesPutLe32ToBuf(out, 0);
	BytesPutLe32ToBuf(out, 0);
	BytesPutLe32ToBuf(out, 0);
	OS_BufferWrite(out, dhcp->mac, 6);
	memset(out->Data + out->Pos, 0, 10 + 64 + 128);
	out->Pos += 10 + 64 + 128;
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
	make_ip4_dhcp_msg_base(dhcp, 0x8000, out);
	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_DISCOVER, out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_PARAMETER_REQUEST_LIST, dhcp_discover_request_options, sizeof(dhcp_discover_request_options), out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, (uint8_t*)dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, (uint8_t*)dhcp->mac, 6, out);
	BytesPut8ToBuf(out, 0xff);
	if (out->Pos < (DHCP_MSG_LEN + 72))
	{
		out->Pos = (DHCP_MSG_LEN + 72);
	}
	else
	{
		out->Pos = (out->Pos + (4 - 1)) & (~(4 - 1));
	}
}

void make_ip4_dhcp_select_msg(dhcp_client_info_t *dhcp, uint16_t flag, Buffer_Struct *out)
{
	uint8_t dhcp_discover_request_options[] = {
			  DHCP_OPTION_SUBNET_MASK,
			  DHCP_OPTION_ROUTER,
			  DHCP_OPTION_BROADCAST,
			  DHCP_OPTION_SERVER_ID,
			  DHCP_OPTION_LEASE_TIME,
			  DHCP_OPTION_DNS_SERVER,
			  DHCP_OPTION_IP_TTL,
			  DHCP_OPTION_138,
	  };
	out->Pos = 0;
	make_ip4_dhcp_msg_base(dhcp, flag, out);
	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_REQUEST, out);
	ip4_dhcp_msg_add_ip_option(DHCP_OPTION_REQUESTED_IP, dhcp->temp_ip, out);
	if (!flag)
	{
		ip4_dhcp_msg_add_ip_option(DHCP_OPTION_SERVER_ID, dhcp->server_ip, out);
	}
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_PARAMETER_REQUEST_LIST, dhcp_discover_request_options, sizeof(dhcp_discover_request_options), out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, (uint8_t*)dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, (uint8_t*)dhcp->mac, 6, out);
	BytesPut8ToBuf(out, 0xff);
}

void make_ip4_dhcp_decline_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out)
{

	out->Pos = 0;
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

	if (BytesGetBe32(&in->Data[4]) != dhcp->xid)
	{
		LLOGD("xid error %x,%x", BytesGetBe32(&in->Data[4]), dhcp->xid);
		if (BytesGetBe32(&in->Data[4]) == (dhcp->xid - 1))
		{
			LLOGD("maybe get same ack, drop");
			return 0;
		}
		LLOGD("xid error %x,%x", BytesGetBe32(&in->Data[4]), dhcp->xid);
		return -3;
	}
	dhcp->xid++;
	if (memcmp(dhcp->mac, &in->Data[28], 6))
	{
		LLOGD("mac error");
		return -4;
	}
	dhcp->temp_ip = BytesGetLe32(&in->Data[16]);
	LLOGD("find ip %x", dhcp->temp_ip);
	in->Pos = DHCP_OPTIONS_OFS;
	while (in->Pos < in->MaxLen)
	{
__CHECK:
		switch(in->Data[in->Pos])
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
				lease_time = dhcp->lease_time;
				lease_time *= 1000;
				dhcp->lease_end_time = luat_mcu_tick64_ms() + lease_time;
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
			dhcp->dns_server[0] = BytesGetLe32(&in->Data[in->Pos + 2]);
			dhcp->dns_server[1] = (in->Data[in->Pos + 1] >= 8)?BytesGetLe32(&in->Data[in->Pos + 6]):0;
			break;
		case DHCP_OPTION_PAD:
			in->Pos++;
			goto __CHECK;
			break;
		case DHCP_OPTION_END:
			return ack;
		default:
			LLOGD("jump %d,%d", in->Data[in->Pos], in->Data[in->Pos+1]);
			break;
		}
		in->Pos += 2 + in->Data[in->Pos+1];
	}
	return ack;
}

int ip4_dhcp_run(dhcp_client_info_t *dhcp, Buffer_Struct *in, Buffer_Struct *out, uint32_t *remote_ip)
{
	uint16_t flag = 0x8000;
	*remote_ip = 0xffffffff;
	int result = 0;
	LLOGD("dhcp state %d", dhcp->state);
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
		if (luat_mcu_tick64_ms() >= dhcp->lease_p1_time)
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
			LLOGD("lease p1 require ip ok");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
			break;
		}
		if (luat_mcu_tick64_ms() >= (dhcp->last_tx_time + 2500))
		{
			LLOGD("lease p1 require ip long time no ack");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P2;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P2:
		if (luat_mcu_tick64_ms() >= dhcp->lease_p2_time)
		{
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P2_ACK:
		if (in && (result == DHCP_ACK))
		{
			LLOGD("lease p2 require ip ok");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
			break;
		}
		if (luat_mcu_tick64_ms() >= (dhcp->last_tx_time + 2500))
		{
			LLOGD("lease p2 require ip long time no ack");
			dhcp->state = DHCP_STATE_WAIT_LEASE_END;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_END:
		if (luat_mcu_tick64_ms() >= dhcp->lease_end_time)
		{
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			goto DHCP_NEED_REQUIRE;
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
		LLOGD("dhcp discover");
		OS_ReInitBuffer(out, 512);
		make_ip4_dhcp_discover_msg(dhcp, out);
		dhcp->last_tx_time = luat_mcu_tick64_ms();
		dhcp->state = DHCP_STATE_WAIT_OFFER;
		break;
	case DHCP_STATE_WAIT_OFFER:
		if (in && (result == DHCP_OFFER))
		{
			LLOGD("select offer, wait ack");
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		if (luat_mcu_tick64_ms() >= (dhcp->last_tx_time + (dhcp->discover_cnt * 500) + 900))
		{
			LLOGD("long time no offer, resend");
			dhcp->discover_cnt++;
			OS_ReInitBuffer(out, 512);
			make_ip4_dhcp_discover_msg(dhcp, out);
			dhcp->last_tx_time = luat_mcu_tick64_ms();
		}
		break;
	case DHCP_STATE_WAIT_SELECT_ACK:
		if (in && (result == DHCP_ACK))
		{
//			LLOGD("need check ip %x,%x,%x,%x", dhcp->temp_ip, dhcp->submask, dhcp->gateway, dhcp->server_ip);
			dhcp->ip = dhcp->temp_ip;
			dhcp->state = DHCP_STATE_CHECK;
			LLOGD("DHCP get ip ready");
			break;
		}
		if (luat_mcu_tick64_ms() >= (dhcp->last_tx_time + (dhcp->discover_cnt * 500) + 1100))
		{
			LLOGD("select ip long time no ack");
			OS_ReInitBuffer(out, 512);
			make_ip4_dhcp_discover_msg(dhcp, out);
			dhcp->last_tx_time = luat_mcu_tick64_ms();
			dhcp->discover_cnt = 0;
			dhcp->state = DHCP_STATE_WAIT_OFFER;
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
