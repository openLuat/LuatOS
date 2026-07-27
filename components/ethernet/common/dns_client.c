
#include "luat_base.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_crypto.h"
#ifdef LUAT_USE_DNS
#include "luat_network_adapter.h"
#include "dns_def.h"
#include "ctype.h"
#undef malloc
#undef free
#include "platform_def.h"
#define dnsONE_QUESTION                 0x0001
#define dnsFLAG_QUERY_RESPONSE_BIT      0x8000
#define dnsFLAG_OPERATION_CODE_BITS     0x7800
#define dnsFLAG_TRUNCATION_BIT          0x0200
#define dnsFLAG_RESPONSE_CODE_BITS      0x000f
#define dnsOUTGOING_FLAGS               0x0100 /* Standard query. */
#define dnsTYPE_IPV4                    0x0001 /* A record (host address. */
#define dnsCLASS                        0x0001 /* IN */
#define dnsRX_FLAGS_MASK                0x800f /* The bits of interest in the flags field of incoming DNS messages. */
#define dnsEXPECTED_RX_FLAGS            0x8000 /* Should be a response, without any errors. */
#define dnsTYPE_IPV6                    0x001C
#define dnsNAME_IS_OFFSET               ( ( uint8_t ) 0xc0 )
#define MAX_DOMAIN_LEN 255
#define MAX_CHARACTER_NUM_PER_LABEL  63
#define DNS_TO_BASE (900)
#define DNS_TRY_MAX	(3)

#ifdef LUAT_USE_STD_STRING
extern void DBG_Printf(const char* format, ...);
#ifdef LUAT_LOG_NO_NEWLINE
#define DBG(x,y...)		DBG_Printf("%s %d:"x, __FUNCTION__,__LINE__,##y)
#define DBG_ERR(x,y...)		DBG_Printf("%s %d:"x, __FUNCTION__,__LINE__,##y)
#else
#define DBG(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
#define DBG_ERR(x,y...)		DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
#endif
#define LLOGD	DBG
#define LLOGI	DBG
#define LLOGE	DBG
#define LLOGW	DBG
#else
#define LUAT_LOG_TAG "DNS"
#include "luat_log.h"
#endif

typedef struct
{
	llist_head node;
	Buffer_Struct uri_buf;	//静态不用释放
	luat_dns_ip_result ip_result[MAX_DNS_IP];
	uint64_t timeout_ms;
	uint16_t session_id;
	uint8_t retry_cnt;
	uint8_t dns_cnt;
	uint8_t ip_nums;
	uint8_t is_done;
	uint8_t ipv6_mode;
	uint8_t is_ipv6;
	uint8_t ipv6_done;
}dns_process_t;

typedef struct xDNSMessage
{
    uint16_t usIdentifier;
    uint16_t usFlags;
    uint16_t usQuestions;
    uint16_t usAnswers;
    uint16_t usAuthorityRRs;
    uint16_t usAdditionalRRs;
}xDNSMessage_t;

static int32_t dns_find_process(void *pData, void *pParam)
{
	uint16_t session_id = (uint32_t)pParam;
	dns_process_t *process = (dns_process_t *)pData;
	if (process->session_id == session_id)
	{
		return LIST_FIND;
	}
	return LIST_PASS;
}

static uint16_t dns_get_session_id(dns_client_t *client)
{
	client->session_id++;
	if (!client->session_id)
	{
		client->session_id = 1;
	}
	return client->session_id;
}



static int32_t dns_skip_name_field(Buffer_Struct *buf)
{

	if (buf->Pos >= buf->MaxLen)
	{
		return -1;
	}
	if( ( buf->Data[buf->Pos] & dnsNAME_IS_OFFSET ) == dnsNAME_IS_OFFSET )
	{
		/* Jump over the two byte offset. */
		buf->Pos += sizeof( uint16_t );
	}
	else
	{
		/* pucByte points to the full name.  Walk over the string. */
		while( buf->Data[buf->Pos] != 0x00 )
		{
			/* The number of bytes to jump for each name section is stored in the byte
			before the name section. */
			buf->Pos += ( buf->Data[buf->Pos] + 1 );
			if (buf->Pos >= buf->MaxLen)
			{
				return -1;
			}
		}
		buf->Pos++;
	}
	if (buf->Pos >= buf->MaxLen)
	{
		return -1;
	}
	return 0;
}

static int32_t dns_set_result(void *pData, void *pParam)
{
	int i;
	dns_process_t *process = (dns_process_t *)pParam;
	luat_dns_require_t *require = (luat_dns_require_t *)pData;
	if (!require->result)
	{
		if (process->uri_buf.Pos == require->uri.Pos)
		{
			if (!memcmp(process->uri_buf.Data, require->uri.Data, require->uri.Pos))
			{
				require->result = -1;
				if (process->ip_nums)
				{
					for(i = 0; i < process->ip_nums; i++)
					{
						require->ip_result[i] = process->ip_result[i];
					}
					require->result = process->ip_nums;
				}
			}
		}
	}

	return LIST_PASS;
}

int32_t dns_get_ip(dns_client_t *client, Buffer_Struct *buf, uint16_t answer_num, dns_process_t *process)
{
	uint16_t i, usTemp;
	luat_ip_addr_t ip_addr = {0};

	uint32_t ttl;
	uint8_t error = 0;

	for(i = 0; i < answer_num; i++)
	{
		if (dns_skip_name_field(buf) != ERROR_NONE)
		{
			error = 1;
			goto NET_DNSGETIP_DONE;
		}
		// 记录固定部分(type/class/ttl/rdlength)至少10字节
		if ( (buf->Pos + 10) > buf->MaxLen)
		{
			error = 1;
			goto NET_DNSGETIP_DONE;
		}
		usTemp = BytesGetBe16(buf->Data + buf->Pos);
		switch (usTemp)
		{
		case dnsTYPE_IPV4:
			if ( (buf->Pos + 14) > buf->MaxLen)
			{
				error = 1;
				goto NET_DNSGETIP_DONE;
			}
			buf->Pos += 4;
			ttl = BytesGetBe32FromBuf(buf);
			if (!ttl)
			{
				LLOGW("ttl zero");
			}
			usTemp = BytesGetBe16FromBuf(buf);
			if ( (buf->Pos + usTemp) > buf->MaxLen)
			{
				error = 1;
				goto NET_DNSGETIP_DONE;
			}
			network_set_ip_ipv4(&ip_addr, BytesGetLe32(buf->Data + buf->Pos));
			buf->Pos += usTemp;
//			if (ttl > 0)
			{
				if (process && (process->ip_nums < MAX_DNS_IP))
				{
					//LLOGD("ipv4 result%d,%d.%d.%d.%d", process->ip_nums, pvUn.u8[0], pvUn.u8[1], pvUn.u8[2], pvUn.u8[3] );
					process->ip_result[process->ip_nums].ip = ip_addr;
					process->ip_result[process->ip_nums].ttl_end = ttl + ((uint32_t)(luat_mcu_tick64_ms()/1000));
					process->ip_nums++;
				}
			}
			break;
		case dnsTYPE_IPV6:
			if ( (buf->Pos + 14) > buf->MaxLen)
			{
				error = 1;
				goto NET_DNSGETIP_DONE;
			}
			buf->Pos += 4;
			ttl = BytesGetBe32FromBuf(buf);
			if (!ttl)
			{
				LLOGW("ttl zero");
			}
			usTemp = BytesGetBe16FromBuf(buf);
			if ( (buf->Pos + usTemp) > buf->MaxLen)
			{
				error = 1;
				goto NET_DNSGETIP_DONE;
			}
#ifdef LUAT_USE_LWIP
#if LWIP_IPV6
			memcpy(ip_addr.u_addr.ip6.addr, buf->Data + buf->Pos, sizeof( uint32_t ) * 4);
//			ip_addr.u_addr.ip6.zone = 0;
			ip_addr.type = IPADDR_TYPE_V6;
//			LLOGI("ipv6 result %s", ipaddr_ntoa(&ip_addr));
#endif
#else
			memcpy(ip_addr.ipv6_u8_addr, buf->Data + buf->Pos, sizeof( uint32_t ) * 4);
			ip_addr.is_ipv6 = 1;
#endif
			//if (ttl > 0)
			{
				if (process && (process->ip_nums < MAX_DNS_IP))
				{
					process->ip_result[process->ip_nums].ip = ip_addr;
					process->ip_result[process->ip_nums].ttl_end = ttl + ((uint32_t)(luat_mcu_tick64_ms()/1000));
					process->ip_nums++;
				}
			}
			buf->Pos += usTemp;
			break;
		default:
			//DBG("%04x",usTemp);
			buf->Pos += 8;
			usTemp = BytesGetBe16FromBuf(buf);
			if ( (buf->Pos + usTemp) > buf->MaxLen)
			{
				error = 1;
				goto NET_DNSGETIP_DONE;
			}
			buf->Pos += usTemp;
			//OS(Dump)(buf->Data + buf->Pos, usTemp);
			break;
		}
	}
NET_DNSGETIP_DONE:
	if (error)
	{

		return -1;
	}
	else
	{
		if (process)
		{
			if (process->ipv6_mode)
			{
				if (process->is_ipv6)
				{
					process->ipv6_done = 1;
					process->session_id = dns_get_session_id(client);
					process->is_ipv6 = 0;
					process->timeout_ms = 0;
					process->retry_cnt = 0;
					LLOGI("dns ipv6 done, now dns ipv4");
					return 0;
				}
			}
			process->is_done = 1;
			llist_traversal(&client->require_head, dns_set_result, process);
		}
		return 0;
	}


}



uint8_t dns_check_uri(const char *uri, uint32_t uri_len)
{
    uint32_t dot_num = 0;

    uint32_t i = 0;
    uint32_t label_len = 0;
    char uri_last = 0;

    if(uri ==NULL)
    {
        return 0;
    }

    if(uri_len == 0 || uri_len > MAX_DOMAIN_LEN)  //domain must less than 255
    {
         return 0;
    }

    if (!isalpha((int)uri[0])) // domain must start with a letter
    {
        return 0;
    }

    uri_last = uri[uri_len - 1];
    if (!isalnum((int)uri_last))//end with a letter or digit
    {
         return 0;
    }

    for(i = 0; i < uri_len ; i++)
    {
        if(!(isalnum((int)uri[i]) || uri[i]== '.' || uri[i] == '-'))//must a~z or A~Z or 0~9 or . or -
        {
            return 0;
        }

        if( uri [i] == '.')
        {
             dot_num++;
             if((label_len > MAX_CHARACTER_NUM_PER_LABEL) || (0 == label_len)) //Label must be 63 characters or less
                 return 0;
             label_len = 0;
        }
        else
        {
            label_len++;
        }
    }
    if((label_len > MAX_CHARACTER_NUM_PER_LABEL) || (0 == dot_num))//the last label must be 63 characters or less
        return 0;

    return 1;

}


int32_t dns_make(dns_client_t *client, dns_process_t *process, Buffer_Struct *out)
{
	xDNSMessage_t MsgHead;
    uint8_t *pucStart, *pucByte;
//    uint16_t usRecordType;
//    uint16_t usClass = BSP_Swap16(dnsCLASS);
	if (process->dns_cnt >= MAX_DNS_SERVER)
	{
		return -ERROR_PERMISSION_DENIED;
	}
	out->Pos = sizeof(xDNSMessage_t) + 6 + process->uri_buf.Pos;


	memset(&MsgHead, 0, sizeof(MsgHead));
	MsgHead.usIdentifier = BSP_Swap16(process->session_id);
	MsgHead.usFlags = BSP_Swap16(dnsOUTGOING_FLAGS);
	MsgHead.usQuestions = BSP_Swap16(dnsONE_QUESTION);
	memcpy(out->Data, &MsgHead, sizeof(MsgHead));

    pucStart = out->Data + sizeof( MsgHead );

    /* Leave a gap for the first length bytes. */
    pucByte = pucStart + 1;

    /* Copy in the host name. */
    memcpy( ( char * ) pucByte, process->uri_buf.Data, process->uri_buf.Pos );

    /* Mark the end of the string. */
    pucByte += process->uri_buf.Pos;
    *pucByte = 0x00;

    /* Walk the string to replace the '.' characters with byte counts.
    pucStart holds the address of the byte count.  Walking the string
    starts after the byte count position. */
    pucByte = pucStart;

    do
    {
        pucByte++;

        while( ( *pucByte != 0x00 ) && ( *pucByte != '.' ) )
        {
            pucByte++;
        }

        /* Fill in the byte count, then move the pucStart pointer up to
        the found byte position. */
        *pucStart = ( uint8_t ) ( ( uint32_t ) pucByte - ( uint32_t ) pucStart );
        ( *pucStart )--;

        pucStart = pucByte;

    } while( *pucByte != 0x00 );
    pucByte++;
    /* Finish off the record. */

    if (process->is_ipv6)
    {
    	BytesPutBe16(pucByte, dnsTYPE_IPV6);
    }
    else
    {
    	BytesPutBe16(pucByte, dnsTYPE_IPV4);
    }
    pucByte += sizeof( uint16_t );
    BytesPutBe16(pucByte, dnsCLASS);
	process->timeout_ms = luat_mcu_tick64_ms() + DNS_TO_BASE * (process->retry_cnt + 1);
    return ERROR_NONE;
}


static int32_t dns_check_process(void *pData, void *pParam)
{
	dns_process_t *process = (dns_process_t *)pData;
	Buffer_Struct *uri_buf = (Buffer_Struct *)pParam;
	if (uri_buf->Pos == process->uri_buf.Pos)
	{
		if (!memcmp(uri_buf->Data, process->uri_buf.Data, uri_buf->Pos))
		{
			return LIST_FIND;
		}
	}
	return LIST_PASS;
}

void dns_require(dns_client_t *client, const char *domain_name, uint32_t len, void *param)
{
	luat_dns_require_t *require = zalloc(sizeof(luat_dns_require_t));
	require->uri.Data = (uint8_t *)domain_name;
	require->uri.Pos = len;
	require->uri.MaxLen = len;
	require->param = param;
	dns_process_t *process = llist_traversal(&client->process_head, dns_check_process, &require->uri);
	// if no same proc
	if (!process)
	{
		process = zalloc(sizeof(dns_process_t));
		Buffer_StaticInit(&process->uri_buf, require->uri.Data, require->uri.Pos);
		process->uri_buf.Pos = require->uri.Pos;
		process->session_id = dns_get_session_id(client);
		llist_add_tail(&process->node, &client->process_head);
	}
	llist_add_tail(&require->node, &client->require_head);
}

void dns_require_ex(dns_client_t *client, const char *domain_name, void *param, uint8_t adapter_index)
{
	luat_dns_require_t *require = zalloc(sizeof(luat_dns_require_t));
	require->uri.Data = (uint8_t *)domain_name;
	require->uri.Pos = strlen(domain_name);
	require->uri.MaxLen = strlen(domain_name);
	require->param = param;
	require->adapter_index = adapter_index;
	dns_process_t *process = llist_traversal(&client->process_head, dns_check_process, &require->uri);
	// if no same proc
	if (!process)
	{
		process = zalloc(sizeof(dns_process_t));
		Buffer_StaticInit(&process->uri_buf, require->uri.Data, require->uri.Pos);
		process->uri_buf.Pos = require->uri.Pos;
		process->session_id = dns_get_session_id(client);
		llist_add_tail(&process->node, &client->process_head);
	}
	llist_add_tail(&require->node, &client->require_head);
}

void dns_require_ipv6(dns_client_t *client, const char *domain_name, void *param, uint8_t adapter_index, uint8_t is_ipv6)
{
	luat_dns_require_t *require = zalloc(sizeof(luat_dns_require_t));
	require->uri.Data = (uint8_t *)domain_name;
	require->uri.Pos = strlen(domain_name);
	require->uri.MaxLen = strlen(domain_name);
	require->param = param;
	require->adapter_index = adapter_index;
	dns_process_t *process = llist_traversal(&client->process_head, dns_check_process, &require->uri);
	// if no same proc
	if (!process)
	{
		process = zalloc(sizeof(dns_process_t));
		Buffer_StaticInit(&process->uri_buf, require->uri.Data, require->uri.Pos);
		process->uri_buf.Pos = require->uri.Pos;
		process->session_id = dns_get_session_id(client);
		process->ipv6_mode = is_ipv6;
		process->is_ipv6 = is_ipv6;
		llist_add_tail(&process->node, &client->process_head);
	}
	llist_add_tail(&require->node, &client->require_head);
}

static int32_t dns_clear_require(void *pData, void *pParam)
{
	luat_dns_require_t *require = (luat_dns_require_t *)pData;
	free(require->uri.Data);
	return LIST_DEL;
}


static int32_t dns_clear_process(void *pData, void *pParam)
{
	dns_process_t *process = (dns_process_t *)pData;
	if (pParam)
	{
		return process->is_done?LIST_DEL:LIST_PASS;
	}
	return LIST_DEL;
}


void dns_clear(dns_client_t *client)
{
//	uint64_t now_time = luat_mcu_tick64_ms();
	llist_traversal(&client->process_head, dns_clear_process, NULL);
	llist_traversal(&client->require_head, dns_clear_require, NULL);
}

// 校验应答question段的域名是否与该process查询的一致(RFC 1035 域名比较大小写不敏感),
// 并校验QTYPE/QCLASS。匹配则消耗掉name+qtype+qclass并返回0, 否则返回非0(不消耗或部分消耗, 调用方直接丢包)
static int32_t dns_check_question_name(Buffer_Struct *in, dns_process_t *process)
{
	uint32_t name_pos = in->Pos;	// 当前解码位置
	uint32_t return_pos = 0;		// 首次遇到压缩指针时应恢复到的位置
	uint8_t jumped = 0;
	uint8_t jump_cnt = 0;
	uint32_t uri_pos = 0;			// uri_buf(点分字符串)比较进度
	const uint8_t *uri = process->uri_buf.Data;
	uint32_t uri_len = process->uri_buf.Pos;

	for(;;)
	{
		uint8_t c;
		if (name_pos >= in->MaxLen)
		{
			return -1;
		}
		c = in->Data[name_pos];
		if ((c & dnsNAME_IS_OFFSET) == dnsNAME_IS_OFFSET)
		{
			// 压缩指针, 只允许回指且限制跳转次数, 防止死循环
			uint16_t offset;
			if (name_pos + 2 > in->MaxLen)
			{
				return -1;
			}
			offset = ((uint16_t)(c & 0x3f) << 8) | in->Data[name_pos + 1];
			if (!jumped)
			{
				return_pos = name_pos + 2;
				jumped = 1;
			}
			if (offset >= name_pos || ++jump_cnt > 8)
			{
				return -1;
			}
			name_pos = offset;
			continue;
		}
		if (c == 0x00)
		{
			// 名字结束
			if (!jumped)
			{
				return_pos = name_pos + 1;
			}
			break;
		}
		if ((c & 0xc0) || (name_pos + 1 + c > in->MaxLen))
		{
			return -1;
		}
		// 逐字节比较该label与uri中对应段(大小写不敏感)
		{
			uint8_t j;
			for (j = 0; j < c; j++)
			{
				uint8_t a, b;
				if (uri_pos >= uri_len)
				{
					return -1;
				}
				a = in->Data[name_pos + 1 + j];
				b = uri[uri_pos++];
				if (tolower(a) != tolower(b))
				{
					return -1;
				}
			}
			name_pos += 1 + c;
		}
		// label之间的分隔: uri中应是'.', 除非uri已恰好比较完
		if (uri_pos < uri_len)
		{
			if (uri[uri_pos] != '.')
			{
				return -1;
			}
			uri_pos++;
		}
	}
	if (uri_pos != uri_len)
	{
		// 应答名字比查询域名短
		return -1;
	}
	in->Pos = return_pos;
	if (in->Pos + 4 > in->MaxLen)
	{
		return -1;
	}
	// QTYPE必须与查询类型一致, QCLASS必须为IN
	{
		uint16_t qtype = BytesGetBe16(in->Data + in->Pos);
		uint16_t qclass = BytesGetBe16(in->Data + in->Pos + 2);
		uint16_t expect = process->is_ipv6 ? dnsTYPE_IPV6 : dnsTYPE_IPV4;
		if (qtype != expect || qclass != dnsCLASS)
		{
			return -1;
		}
	}
	in->Pos += 4;
	return 0;
}

static int32_t dns_find_need_tx_process(void *pData, void *pParam)
{
	dns_process_t *process = (dns_process_t *)pData;
	if (!process->is_done && (process->timeout_ms < luat_mcu_tick64_ms()))
	{
		return LIST_FIND;
	}
	return LIST_PASS;
}

void dns_run(dns_client_t *client, Buffer_Struct *in, Buffer_Struct *out, int *server_cnt)
{
	dns_process_t *process;
	int i;
	if (llist_empty(&client->process_head) && !llist_empty(&client->require_head))
	{
		dns_clear(client);
		if (client->is_run)
		{
			LLOGI("dns all done ,now stop");
		}
		client->is_run = 0;
		return;
	}
	if (in)
	{
		xDNSMessage_t MsgHead;
		while ( (in->Pos + sizeof(MsgHead)) < in->MaxLen)
		{
			memcpy(&MsgHead, in->Data + in->Pos, sizeof(MsgHead));
			MsgHead.usIdentifier = BSP_Swap16(MsgHead.usIdentifier);
			MsgHead.usFlags = BSP_Swap16(MsgHead.usFlags);
			in->Pos += sizeof(MsgHead);
			process = llist_traversal(&client->process_head, dns_find_process, (void *)((uint32_t)MsgHead.usIdentifier));
			if (process)
			{
				if ( MsgHead.usFlags & 0x8000)
				{
					MsgHead.usQuestions = BSP_Swap16(MsgHead.usQuestions);
					MsgHead.usAnswers = BSP_Swap16(MsgHead.usAnswers);
					MsgHead.usAuthorityRRs = BSP_Swap16(MsgHead.usAuthorityRRs);
					MsgHead.usAdditionalRRs = BSP_Swap16(MsgHead.usAdditionalRRs);

					if (!MsgHead.usQuestions)
					{
						// 标准查询的应答必须回显question, 否则无法校验归属, 丢弃
						LLOGW("response without question, drop");
						goto NET_DNS_RX_OUT;
					}
					for(i = 0; i < MsgHead.usQuestions; i++)
					{
						if (!i)
						{
							// 第1个question必须与本process查询的域名/类型一致, 否则视为串包或伪造应答, 丢弃
							if (dns_check_question_name(in, process))
							{
								LLOGW("question not match, drop");
								goto NET_DNS_RX_OUT;
							}
						}
						else
						{
							if (dns_skip_name_field(in) != ERROR_NONE)
							{
								goto NET_DNS_RX_OUT;
							}
							in->Pos += 4;
						}
						if (in->Pos >= in->MaxLen)
						{
							goto NET_DNS_RX_OUT;
						}
					}
					if (!(MsgHead.usFlags & 0x000f))
					{
						if (dns_get_ip(client, in, MsgHead.usAnswers, process))
						{
							goto NET_DNS_RX_OUT;
						}
					}
					else if ((MsgHead.usFlags & 0x000f) == 3)
					{
						// NXDOMAIN: 域名不存在是确定性结果, 立即失败, 不做无谓重试
						LLOGI("%.*s NXDOMAIN", process->uri_buf.Pos, process->uri_buf.Data);
						process->ip_nums = 0;
						process->is_done = 1;
						client->new_result = 1;
						llist_traversal(&client->require_head, dns_set_result, process);
						llist_del(&process->node);
						free(process);
						goto NET_DNS_RX_OUT;
					}
					else
					{
						// SERVFAIL/REFUSED等其他错误: 立即换下一台server, 不等重试超时
						LLOGW("%.*s rcode %d, try next dns server", process->uri_buf.Pos, process->uri_buf.Data, (MsgHead.usFlags & 0x000f));
						process->retry_cnt = 0;
						process->timeout_ms = 0;
						process->dns_cnt++;
						while((process->dns_cnt < MAX_DNS_SERVER) && !network_ip_is_vaild(&client->dns_server[process->dns_cnt]))
						{
							process->dns_cnt++;
						}
						if (process->dns_cnt >= MAX_DNS_SERVER)
						{
							LLOGE("%.*s all dns server failed", process->uri_buf.Pos, process->uri_buf.Data);
							process->ip_nums = 0;
							process->is_done = 1;
							client->new_result = 1;
							llist_traversal(&client->require_head, dns_set_result, process);
							llist_del(&process->node);
							free(process);
						}
						goto NET_DNS_RX_OUT;
					}

					if (dns_get_ip(client, in, MsgHead.usAuthorityRRs, NULL))
					{
						goto NET_DNS_RX_OUT;
					}

					if (dns_get_ip(client, in, MsgHead.usAdditionalRRs, NULL))
					{
						goto NET_DNS_RX_OUT;
					}
				}
				else
				{
					goto NET_DNS_RX_OUT;
				}

			}
		}
	}
	else if (out)
	{
NET_DNS_TX:

		process = llist_traversal(&client->process_head, dns_find_need_tx_process, NULL);
		if (!process)
		{
			goto NET_DNS_RX_OUT;
		}
		if (process->timeout_ms)
		{
			process->retry_cnt++;
			if (process->retry_cnt >= DNS_TRY_MAX)
			{
				process->retry_cnt = 0;
				if (process->ipv6_mode)
				{
					if (process->is_ipv6)
					{
						process->is_ipv6 = 0;
						goto NET_DNS_TX_IPV4;
					}
					else
					{
						if (process->ipv6_done && process->ip_nums)
						{
							LLOGD("get ipv6, no ipv4");
//							process->ip_nums = 0;
							process->is_done = 1;
							client->new_result = 1;
							llist_traversal(&client->require_head, dns_set_result, process);
							llist_del(&process->node);
							free(process);
							goto NET_DNS_TX;
						}
						else
						{
							process->is_ipv6 = 1;
						}
					}
				}

				process->dns_cnt++;
				if (process->dns_cnt >= MAX_DNS_SERVER)
				{
					LLOGE("no ipv6, no ipv4");
					process->ip_nums = 0;
					process->is_done = 1;
					client->new_result = 1;
					llist_traversal(&client->require_head, dns_set_result, process);
					llist_del(&process->node);
					free(process);
					goto NET_DNS_TX;
				}
			}
		}
NET_DNS_TX_IPV4:
		while(!network_ip_is_vaild(&client->dns_server[process->dns_cnt]))
		{
			process->dns_cnt++;
			if (process->dns_cnt >= MAX_DNS_SERVER)
			{
				LLOGE("no ipv6, no ipv4");
				process->ip_nums = 0;
				process->is_done = 1;
				client->new_result = 1;
				llist_traversal(&client->require_head, dns_set_result, process);
				llist_del(&process->node);
				free(process);
				goto NET_DNS_TX;
			}
		}
		LLOGD("%.*s state %d id %d ipv6 %d use dns server%d, try %d", process->uri_buf.Pos, process->uri_buf.Data, process->is_done, process->session_id, process->is_ipv6, process->dns_cnt, process->retry_cnt);
		process->is_done = 0;
		OS_InitBuffer(out, 512);
		dns_make(client, process, out);
		*server_cnt = process->dns_cnt;
	}

NET_DNS_RX_OUT:
	if (!llist_empty(&client->process_head))
	{
		llist_traversal(&client->process_head, dns_clear_process, (void *)1);
	}

	if (llist_empty(&client->process_head) && llist_empty(&client->require_head))
	{
		if (client->is_run)
		{
			LLOGI("dns all done ,now stop");
		}
		client->is_run = 0;
		return;
	}
	else
	{
		client->is_run = 1;
	}
	return ;
}

void dns_init_client(dns_client_t *client)
{
	int i;
	INIT_LLIST_HEAD(&client->process_head);
	INIT_LLIST_HEAD(&client->require_head);
	for(i = 0; i < MAX_DNS_SERVER; i++)
	{
		if (!client->is_static_dns[i])
		{
			network_set_ip_invaild(&client->dns_server[i]);
		}
	}
	// txid随机起点, 避免跨会话可预测(RFC 5452), 后续仍递增防同client内重复
	luat_crypto_trng((char*)&client->session_id, sizeof(client->session_id));
}

#endif


