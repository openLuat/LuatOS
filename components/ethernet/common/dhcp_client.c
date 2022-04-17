#include "luat_base.h"
#ifdef LUAT_USE_DHCP
#include "dhcp_def.h"
#include "bsp_common.h"
extern void DBG_Printf(const char* format, ...);
extern void DBG_HexPrintf(void *Data, unsigned int len);
#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

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
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, dhcp->mac, 6, out);
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
			  DHCP_OPTION_IP_TTL,
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
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, dhcp->mac, 6, out);
	BytesPut8ToBuf(out, 0xff);
}

void make_ip4_dhcp_decline_msg(dhcp_client_info_t *dhcp, Buffer_Struct *out)
{

	out->Pos = 0;
	make_ip4_dhcp_msg_base(dhcp, 0, out);
	ip4_dhcp_msg_add_integer_option(DHCP_OPTION_MESSAGE_TYPE, DHCP_OPTION_MESSAGE_TYPE_LEN, DHCP_DECLINE, out);
	ip4_dhcp_msg_add_ip_option(DHCP_OPTION_REQUESTED_IP, dhcp->temp_ip, out);
	ip4_dhcp_msg_add_ip_option(DHCP_OPTION_SERVER_ID, dhcp->server_ip, out);
	ip4_dhcp_msg_add_bytes_option(DHCP_OPTION_HOSTNAME, dhcp->name, strlen(dhcp->name), out);
	ip4_dhcp_msg_add_client_id_option(DHCP_OPTION_CLIENT_ID, dhcp->mac, 6, out);
	BytesPut8ToBuf(out, 0xff);
}

int analyze_ip4_dhcp(dhcp_client_info_t *dhcp, Buffer_Struct *in)
{
	int ack;
	uint64_t lease_time;
	if (in->Data[0] != DHCP_BOOTREPLY)
	{
		DBG("!");
		return -1;
	}
	if (BytesGetBe32(&in->Data[DHCP_MSG_LEN]) != DHCP_MAGIC_COOKIE)
	{
		DBG("!");
		return -2;
	}
	if (BytesGetBe32(&in->Data[4]) != dhcp->xid)
	{
		DBG("!");
		return -3;
	}
	if (memcmp(dhcp->mac, &in->Data[28], 6))
	{
		DBG("!");
		return -4;
	}
	dhcp->temp_ip = BytesGetLe32(&in->Data[16]);
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
				dhcp->lease_end_time = GetSysTickMS() + lease_time;
				dhcp->lease_p1_time = dhcp->lease_end_time - (lease_time >> 1);
				dhcp->lease_p2_time = dhcp->lease_end_time - (lease_time >> 3);
			}
			break;
		case DHCP_OPTION_PAD:
			in->Pos++;
			goto __CHECK;
			break;
		case DHCP_OPTION_END:
			return ack;
		case DHCP_OPTION_SUBNET_MASK:
			dhcp->submask = BytesGetLe32(&in->Data[in->Pos + 2]);
			break;
		case DHCP_OPTION_ROUTER:
			dhcp->gateway = BytesGetLe32(&in->Data[in->Pos + 2]);
			break;
		default:
//			DBG("jump %d,%d", in->Data[in->Pos], in->Data[in->Pos+1]);
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
	int result;
	if (in)
	{
		result = analyze_ip4_dhcp(dhcp, in);

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
//	DBG("%d,%d", dhcp->state, result);
	switch(dhcp->state)
	{
	case DHCP_STATE_WAIT_LEASE_P1:
		if (GetSysTickMS() >= dhcp->lease_p1_time)
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
			DBG("lease p1 require ip ok");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
			break;
		}
		if (GetSysTickMS() >= (dhcp->last_tx_time + 2500))
		{
			DBG("lease p1 require ip long time no ack");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P2;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P2:
		if (GetSysTickMS() >= dhcp->lease_p2_time)
		{
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_P2_ACK:
		if (in && (result == DHCP_ACK))
		{
			DBG("lease p2 require ip ok");
			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
			break;
		}
		if (GetSysTickMS() >= (dhcp->last_tx_time + 2500))
		{
			DBG("lease p2 require ip long time no ack");
			dhcp->state = DHCP_STATE_WAIT_LEASE_END;
		}
		break;
	case DHCP_STATE_WAIT_LEASE_END:
		if (GetSysTickMS() >= dhcp->lease_end_time)
		{
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		break;
//	case DHCP_STATE_WAIT_REQUIRE_ACK:
//		if (in && (result == DHCP_ACK))
//		{
//			DBG("require ip ok");
//			dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
//			break;
//		}
//		if (GetSysTickMS() >= (dhcp->last_tx_time + 2500))
//		{
//			DBG("require ip long time no ack");
//			OS_ReInitBuffer(out, 512);
//			make_ip4_dhcp_discover_msg(dhcp, out);
//			dhcp->last_tx_time = GetSysTickMS();
//			dhcp->discover_cnt = 0;
//			dhcp->state = DHCP_STATE_WAIT_OFFER;
//		}
//		break;
	case DHCP_STATE_DISCOVER:

		OS_ReInitBuffer(out, 512);
		make_ip4_dhcp_discover_msg(dhcp, out);
		dhcp->last_tx_time = GetSysTickMS();
		dhcp->state = DHCP_STATE_WAIT_OFFER;
		break;
	case DHCP_STATE_WAIT_OFFER:
		if (in && (result == DHCP_OFFER))
		{
			dhcp->state = DHCP_STATE_WAIT_SELECT_ACK;
			goto DHCP_NEED_REQUIRE;
		}
		if (GetSysTickMS() >= (dhcp->last_tx_time + (dhcp->discover_cnt * 500) + 900))
		{
			DBG("long time no offer, resend");
			dhcp->discover_cnt++;
			OS_ReInitBuffer(out, 512);
			make_ip4_dhcp_discover_msg(dhcp, out);
			dhcp->last_tx_time = GetSysTickMS();
		}
		break;
	case DHCP_STATE_WAIT_SELECT_ACK:
		if (in && (result == DHCP_ACK))
		{
//			DBG("need check ip %x,%x,%x,%x", dhcp->temp_ip, dhcp->submask, dhcp->gateway, dhcp->server_ip);
			dhcp->ip = dhcp->temp_ip;
			dhcp->state = DHCP_STATE_CHECK;
			break;
		}
		if (GetSysTickMS() >= (dhcp->last_tx_time + (dhcp->discover_cnt * 500) + 1100))
		{
			DBG("select ip long time no ack");
			OS_ReInitBuffer(out, 512);
			make_ip4_dhcp_discover_msg(dhcp, out);
			dhcp->last_tx_time = GetSysTickMS();
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
		dhcp->last_tx_time = GetSysTickMS();
		dhcp->state = DHCP_STATE_DISCOVER;
		break;
	case DHCP_STATE_NOT_WORK:
		break;
	}
	return 0;
DHCP_NEED_REQUIRE:
	OS_ReInitBuffer(out, 512);
	make_ip4_dhcp_select_msg(dhcp, flag, out);
	dhcp->last_tx_time = GetSysTickMS();
	return 0;
}

#endif
