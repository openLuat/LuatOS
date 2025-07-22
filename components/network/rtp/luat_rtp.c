#include "luat_rtp.h"

int luat_unpack_rtp_head(const uint32_t *input, uint32_t input_len, rtp_base_head_t *base_head,, uint32_t **csrc)
{
	if (input_len < 12) return -ERROR_PARAM_OVERFLOW;
	Buffer_Struct buf = {0};
	buf.Data = (uint8_t *)input;
	base_head->byte0 = buf.Data[0];
	if (base_head->version != 2)
	{
		return -ERROR_PARAM_INVALID;
	}
	base_head->byte1 = buf.Data[1];
	buf.Pos = 2;
	base_head->sn = BytesGetBe16FromBuf(&buf);
	base_head->time_tamp = BytesGetBe32FromBuf(&buf);
	base_head->ssrc = BytesGetBe32FromBuf(&buf);
	if (base_head->csrc_count)
	{
		*csrc = (uint32_t *)(&input[3]);
		uint32_t t = base_head->csrc_count;
		buf.Pos += t * 4;
	}
	else
	{
		*csrc = NULL;
	}
	if (buf.Pos > input_len)
	{
		return -ERROR_BUFFER_FULL;
	}
	return buf.Pos;
}

int luat_unpack_rtp_extern_head(const uint32_t *input, uint32_t input_len, rtp_extern_head_t *extern_head, uint32_t **data)
{
	if (input_len < 4) return -ERROR_PARAM_OVERFLOW;
	Buffer_Struct buf = {0};
	buf.Data = (uint8_t *)input;
	extern_head->profile_id = BytesGetBe16FromBuf(&buf);
	extern_head->length = BytesGetBe16FromBuf(&buf);
	if (extern_head->length)
	{
		*data = (uint32_t *)(&input[1]);
		uint32_t t = extern_head->length;
		buf.Pos += t * 4;
	}
	else
	{
		*data = NULL;
	}
	if (buf.Pos > input_len)
	{
		return -ERROR_BUFFER_FULL;
	}
	return buf.Pos;
}

int luat_pack_rtp(rtp_base_head_t *base_head, rtp_extern_head_t *extern_head, const void *payload, uint32_t payload_len, uint8_t *output, uint32_t output_max_len)
{
	uint32_t t1 = base_head->csrc_count;
	uint32_t t2 = 0;
	t1 = t1 * 4 + 12;
	if (extern_head)
	{
		t2 = extern_head->length;
		t1 += t2 * 4 + 4;
	}
	if ((t1 + payload_len) > output_max_len)
	{
		return -ERROR_BUFFER_FULL;
	}
	Buffer_Struct buf = {0};
	buf.Data = output;
	buf.MaxLen = output_max_len;
	if (extern_head)
	{
		base_head->extension = 1;
	}
	BytesPut8ToBuf(&buf, base_head->byte0);
	BytesPut8ToBuf(&buf, base_head->byte1);
	BytesPutBe16ToBuf(&buf, base_head->sn);
	BytesPutBe32ToBuf(&buf, base_head->time_tamp);
	BytesPutBe32ToBuf(&buf, base_head->ssrc);
	if (base_head->csrc_count)
	{
		for(int i = 0; i < base_head->csrc_count; i++)
		{
			BytesPutBe32ToBuf(&buf, base_head->csrc[i]);
		}
	}
	if (extern_head)
	{
		BytesPutBe16ToBuf(&buf, extern_head->profile_id);
		BytesPutBe16ToBuf(&buf, extern_head->length);
		if (extern_head->length)
		{
			BytesPut8ToBuf(&buf, extern_head->data, extern_head->length * 4);
		}
	}
	BytesPut8ToBuf(&buf, payload, payload_len);
	return buf.Pos;
}
