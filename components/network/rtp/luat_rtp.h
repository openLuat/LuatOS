#ifndef __LUAT_RTP_H__
#define __LUAT_RTP_H__
#include "luat_base.h"
#if defined(__SOC_BSP__) || defined(LUAT_EC7XX_CSDK) || defined(CHIP_EC618) || defined(__AIR105_BSP__) || defined(CONFIG_SOC_8910) || defined(CONFIG_SOC_8850)
#include "bsp_common.h"
#endif
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
typedef struct
{
	union
	{
		struct
		{
			uint8_t version:2;
			uint8_t padding:1;
			uint8_t extension:1;
			uint8_t csrc_count:4;
		};
		uint8_t byte0;
	};
	union
	{
		struct
		{
			uint8_t maker:1;
			uint8_t payload_type:7;
		};
		uint8_t byte1;
	};
	uint16_t sn;
	uint32_t time_tamp;
	uint32_t ssrc;
	uint32_t csrc[];
}rtp_base_head_t;

typedef struct
{
	uint16_t profile_id;
	uint16_t length;
	uint8_t data[];
}rtp_extern_head_t;
/**
 * 从输入数据解析出RTP包头
 * @param input，输入数据首地址，必须是32bit对齐
 * @param input_len，输入数据长度
 * @param base_head，输出RTP包头
 * @param ccrc，返回ccrc数据的起始位置，如果有就是input+12，否则返回NULL
 * @return 成功返回已处理的字节数量，失败则<=0
 */
int luat_unpack_rtp_head(const uint32_t *input, uint32_t input_len, rtp_base_head_t *base_head, uint32_t **csrc);
/**
 * 从输入数据解析出RTP扩展包头
 * @param input，输入数据首地址，必须是32bit对齐，不能包含包头
 * @param input_len，输入数据长度
 * @param extern_head，输出RTP扩展包头
 * @param data，返回扩展数据的起始位置，如果有就是input+4，否则返回NULL
 * @return 成功返回已处理的字节数量，失败则<0
 */
int luat_unpack_rtp_extern_head(const uint32_t *input, uint32_t input_len, rtp_extern_head_t *extern_head, uint32_t **data);
/**
 * 打包RTP数据
 * @param base_head，RTP包头数据，连同CSRC，如果有的话
 * @param extern_head，RTP扩展包头数据
 * @param payload，有效数据
 * @param payload_len，有效数据长度
 * @param output，输出数据缓存
 * @param output_max_len，缓存区长度，必须有足够的长度，否则会失败
 * @return 成功返回最终数据长度，失败<=0
 */
int luat_pack_rtp(rtp_base_head_t *base_head, rtp_extern_head_t *extern_head, const void *payload, uint32_t payload_len, uint8_t *output, uint32_t output_max_len);
#endif
