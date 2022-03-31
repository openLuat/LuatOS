#include "luat_ymodem.h"
#include "luat_fs.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "ymodem"
#include "luat_log.h"

#define XMODEM_FLAG 'C'
#define XMODEM_SOH 0x01
#define XMODEM_STX 0x02
#define XMODEM_EOT 0x04
#define XMODEM_ACK 0x06
#define XMODEM_NAK 0x15
#define XMODEM_CAN 0x18
#define XMODEM_DATA_POS (3)
#define XMODEM_SOH_DATA_LEN (128)
#define XMODEM_STX_DATA_LEN (1024)

typedef struct
{
	char *save_path;
	const char *force_save_path;
	FILE* fd;
	uint32_t file_size;
	uint32_t write_size;
	uint16_t data_pos;
	uint16_t data_max;
	uint8_t state;
	uint8_t next_sn;
	uint8_t packet_data[XMODEM_STX_DATA_LEN + 8];
}ymodem_ctrlstruct;

static uint16_t CRC16_Cal(void *Data, uint16_t Len, uint16_t CRC16Last)
{
	uint16_t i;
	uint16_t CRC16 = CRC16Last;
	uint8_t *Src = (uint8_t *)Data;

	while (Len--)
	{
		for (i = 8; i > 0; i--)
		{
			if ((CRC16 & 0x8000) != 0)
			{
				CRC16 <<= 1;
				CRC16 ^= 0x1021;
			}
			else
			{
				CRC16 <<= 1;
			}
			if ((*Src&(1 << (i - 1))) != 0)
			{
				CRC16 ^= 0x1021;
			}
		}
		Src++;
	}
	return CRC16;
}

void *luat_ymodem_create_handler(const char *save_path, const char *force_save_path)
{
	ymodem_ctrlstruct *handler = luat_heap_malloc(sizeof(ymodem_ctrlstruct));
	if (handler)
	{
		memset(handler, 0, sizeof(ymodem_ctrlstruct));
		if (save_path)
		{
			handler->save_path = luat_heap_malloc(strlen(save_path) + 1);
			strcpy(handler->save_path, save_path);
		}
		if (force_save_path)
		{
			handler->force_save_path = luat_heap_malloc(strlen(force_save_path) + 1);
			strcpy((char*)handler->force_save_path, force_save_path);
		}


	}
	return handler;
}

int luat_ymodem_receive(void *handler, uint8_t *data, uint32_t len, uint8_t *ack, uint8_t *flag, uint8_t *file_ok, uint8_t *all_done)
{
	ymodem_ctrlstruct *ctrl = handler;
	uint16_t crc16_org, crc16;
	uint32_t i, NameEnd, LenEnd;
	char path[128];
	*file_ok = 0;
	*all_done = 0;
	*flag = 0;
	if (data)
	{
		if (data[0] == XMODEM_CAN)
		{
			luat_ymodem_reset(handler);
			*ack = XMODEM_ACK;
			*all_done = 1;
			return 0;
		}
	}

	switch (ctrl->state)
	{
	case 0:
		if (!data)
		{
			*ack = XMODEM_FLAG;
			return 0;
		}
		else
		{
			if ((ctrl->data_pos + len) >= (XMODEM_SOH_DATA_LEN + 5))
			{
				memcpy(&ctrl->packet_data[ctrl->data_pos], data, (XMODEM_SOH_DATA_LEN + 5) - ctrl->data_pos);
				if (ctrl->packet_data[0] != XMODEM_SOH || ctrl->packet_data[1] != 0x00 || ctrl->packet_data[2] != 0xff)
				{
					LLOGD("head %x %x %x", ctrl->packet_data[0], ctrl->packet_data[1], ctrl->packet_data[2]);
					goto DATA_RECIEVE_ERROR;
				}
				crc16_org = ctrl->packet_data[XMODEM_SOH_DATA_LEN + 3];
				crc16_org = (crc16_org << 8) + ctrl->packet_data[XMODEM_SOH_DATA_LEN + 4];
				crc16 = CRC16_Cal(&ctrl->packet_data[XMODEM_DATA_POS], XMODEM_SOH_DATA_LEN, 0);
				if (crc16 != crc16_org)
				{
					LLOGD("crc16 %x %x ", crc16, crc16_org);
					goto DATA_RECIEVE_ERROR;
				}
				else
				{
					if (!ctrl->packet_data[XMODEM_DATA_POS])
					{
						luat_ymodem_reset(handler);
						*ack = XMODEM_ACK;
						*all_done = 1;
						return 0;
					}
					NameEnd = NULL;
					for(i = XMODEM_DATA_POS; i < (XMODEM_SOH_DATA_LEN + 5); i++)
					{
						if (!ctrl->packet_data[i])
						{
							NameEnd = i;
							break;
						}
					}
					if (!NameEnd)
					{
						LLOGD("name end");
						goto DATA_RECIEVE_ERROR;
					}
					LenEnd = NULL;
					for(i = (NameEnd + 1); i < (XMODEM_SOH_DATA_LEN + 5); i++)
					{
						if (!ctrl->packet_data[i])
						{
							LenEnd = i;
							break;
						}
					}
					if (!LenEnd)
					{
						LLOGD("len end");
						goto DATA_RECIEVE_ERROR;
					}

					ctrl->file_size = strtol((const char*)&ctrl->packet_data[NameEnd + 1], NULL, 10);
					ctrl->write_size = 0;
					if (ctrl->force_save_path)
					{
						ctrl->fd = luat_fs_fopen(ctrl->force_save_path, "w");
						LLOGD("%s,%u,%x", ctrl->force_save_path, ctrl->file_size, ctrl->fd);
					}
					else
					{
						sprintf_(path, "%s%s", ctrl->save_path, &ctrl->packet_data[XMODEM_DATA_POS]);
						ctrl->fd = luat_fs_fopen(path, "w");
						LLOGD("%s,%u,%x", path, ctrl->file_size, ctrl->fd);
					}



					ctrl->state++;
					ctrl->next_sn = 0;
					ctrl->data_max = (XMODEM_STX_DATA_LEN + 5);
					*flag = XMODEM_FLAG;
					goto DATA_RECIEVE_OK;
				}
			}
			else
			{
				memcpy(&ctrl->packet_data[ctrl->data_pos], data, len);
				ctrl->data_pos += len;
			}
		}
		break;
	case 1:
		if (!ctrl->data_pos)
		{
			switch(data[0])
			{
			case XMODEM_STX:
				ctrl->data_max = (XMODEM_STX_DATA_LEN + 5);
				break;
			case XMODEM_SOH:
				ctrl->data_max = (XMODEM_SOH_DATA_LEN + 5);
				break;
			default:
				goto DATA_RECIEVE_ERROR;
				break;
			}
			memcpy(ctrl->packet_data, data, len);
			if (len >= ctrl->data_max) goto YMODEM_DATA_CHECK;
		}
		else
		{
			if ((ctrl->data_pos + len) >= ctrl->data_max)
			{
				memcpy(&ctrl->packet_data[ctrl->data_pos], data, ctrl->data_max - ctrl->data_pos);
YMODEM_DATA_CHECK:
				switch(ctrl->packet_data[0])
				{
				case XMODEM_SOH:
					if (ctrl->packet_data[1] != ctrl->next_sn || ctrl->packet_data[2] != (255 - ctrl->next_sn))
					{
						LLOGD("head %x %x %x", ctrl->packet_data[0], ctrl->packet_data[1], ctrl->packet_data[2]);
						goto DATA_RECIEVE_ERROR;
					}

					crc16_org = ctrl->packet_data[XMODEM_SOH_DATA_LEN + 3];
					crc16_org = (crc16_org << 8) + ctrl->packet_data[XMODEM_SOH_DATA_LEN + 4];
					crc16 = CRC16_Cal(&ctrl->packet_data[XMODEM_DATA_POS], XMODEM_SOH_DATA_LEN, 0);
					if (crc16 != crc16_org)
					{
						LLOGD("crc16 %x %x ", crc16, crc16_org);
						goto DATA_RECIEVE_ERROR;
					}
					LenEnd = ((ctrl->file_size - ctrl->write_size) > XMODEM_SOH_DATA_LEN)?XMODEM_SOH_DATA_LEN:(ctrl->file_size - ctrl->write_size);
					luat_fs_fwrite(ctrl->packet_data, LenEnd, 1, ctrl->fd);
					ctrl->write_size += LenEnd;
					goto DATA_RECIEVE_OK;
					break;
				case XMODEM_STX:
					if (ctrl->packet_data[1] != ctrl->next_sn || (ctrl->packet_data[2] != (255 - ctrl->next_sn)))
					{
						LLOGD("head %x %x %x", ctrl->packet_data[0], ctrl->packet_data[1], ctrl->packet_data[2]);
						goto DATA_RECIEVE_ERROR;
					}

					crc16_org = ctrl->packet_data[XMODEM_STX_DATA_LEN + 3];
					crc16_org = (crc16_org << 8) + ctrl->packet_data[XMODEM_STX_DATA_LEN + 4];
					crc16 = CRC16_Cal(&ctrl->packet_data[XMODEM_DATA_POS], XMODEM_STX_DATA_LEN, 0);
					if (crc16 != crc16_org)
					{
						LLOGD("crc16 %x %x ", crc16, crc16_org);
						goto DATA_RECIEVE_ERROR;
					}
					//写入
					LenEnd = ((ctrl->file_size - ctrl->write_size) > XMODEM_STX_DATA_LEN)?XMODEM_STX_DATA_LEN:(ctrl->file_size - ctrl->write_size);
					luat_fs_fwrite(ctrl->packet_data, LenEnd, 1, ctrl->fd);
					ctrl->write_size += LenEnd;
					goto DATA_RECIEVE_OK;
					break;
				default:
					if (ctrl->packet_data[1] != ctrl->next_sn || ctrl->packet_data[2] != ~ctrl->next_sn)
					{
						LLOGD("head %x %x %x", ctrl->packet_data[0], ctrl->packet_data[1], ctrl->packet_data[2]);
						goto DATA_RECIEVE_ERROR;
					}
					goto DATA_RECIEVE_OK;
				}
			}
			else
			{
				memcpy(&ctrl->packet_data[ctrl->data_pos], data, len);
				ctrl->data_pos += len;
			}
		}
		break;
	case 2:
		ctrl->state++;
		ctrl->data_pos = 0;
		*ack = XMODEM_NAK;
		return 0;

	case 3:
		if (data[0] == XMODEM_EOT)
		{
			ctrl->state = 0;
			*flag = XMODEM_FLAG;
			*ack = XMODEM_ACK;
			return 0;
		}
		else
		{
			goto DATA_RECIEVE_ERROR;
		}
		break;
	default:
		return -1;
	}
	*ack = 0;
	return 0;
DATA_RECIEVE_ERROR:
	ctrl->data_pos = 0;
	*ack = XMODEM_NAK;
	*flag = 0;
	*all_done = 0;
	return -1;
DATA_RECIEVE_OK:
	ctrl->data_pos = 0;
	ctrl->next_sn++;
	*ack = XMODEM_ACK;
	if (ctrl->file_size && (ctrl->write_size >= ctrl->file_size))
	{
		luat_fs_fclose(ctrl->fd);
		ctrl->fd = NULL;
		ctrl->state = 2;
		*file_ok = 1;
	}
	return 0;
}

void luat_ymodem_reset(void *handler)
{
	ymodem_ctrlstruct *ctrl = handler;
	ctrl->state = 0;
	ctrl->next_sn = 0;
	ctrl->file_size = 0;
	if (ctrl->fd) luat_fs_fclose(ctrl->fd);
	ctrl->fd = NULL;
}

void luat_ymodem_release(void *handler)
{
	ymodem_ctrlstruct *ctrl = handler;
	luat_ymodem_reset(handler);
	luat_heap_free(ctrl->save_path);
	luat_heap_free(handler);
}
