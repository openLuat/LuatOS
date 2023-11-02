#include "luat_base.h"
#include "stdlib.h"
#include "luat_ymodem.h"
#ifdef __LUATOS__
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#else
#include "luat_malloc.h"
#endif
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
#ifdef __LUATOS__
	char *save_path;
	const char *force_save_path;
	FILE* fd;
#else
	luat_ymodem_callback cb;
#endif
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
#ifdef __LUATOS__
void *luat_ymodem_create_handler(const char *save_path, const char *force_save_path)
#else
void *luat_ymodem_create_handler(luat_ymodem_callback cb)
#endif
{
	ymodem_ctrlstruct *handler = luat_heap_malloc(sizeof(ymodem_ctrlstruct));
	if (handler)
	{
		memset(handler, 0, sizeof(ymodem_ctrlstruct));
#ifdef __LUATOS__
		if (save_path)
		{
			if (save_path[strlen(save_path)-1] == '/'){
				handler->save_path = luat_heap_malloc(strlen(save_path) + 1);
				strcpy(handler->save_path, save_path);
				handler->save_path[strlen(save_path)] = 0;
			}else{
				handler->save_path = luat_heap_malloc(strlen(save_path) + 2);
				strcpy(handler->save_path, save_path);
				handler->save_path[strlen(save_path)] = '/';
				handler->save_path[strlen(save_path)+1] = 0;
			}
		}
		if (force_save_path)
		{
			handler->force_save_path = luat_heap_malloc(strlen(force_save_path) + 1);
			strcpy((char*)handler->force_save_path, force_save_path);
		}
#else
		handler->cb = cb;
#endif

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
	*ack = 0;
	*flag = 0;

	switch (ctrl->state)
	{
	case 0:
		if (!data || !len)
		{
			*ack = XMODEM_FLAG;
			return 0;
		}
		else
		{
			if (ctrl->data_pos > 0)
			{

			}
			else
			{
				switch(data[0])
				{
				case XMODEM_STX:
					ctrl->data_max = XMODEM_STX_DATA_LEN;
					break;
				case XMODEM_SOH:
					ctrl->data_max = XMODEM_SOH_DATA_LEN;
					break;
				case XMODEM_CAN:
					luat_ymodem_reset(handler);
					*ack = XMODEM_ACK;
					*all_done = 1;
					return 0;
				default:
					goto DATA_RECIEVE_ERROR;
					break;
				}
			}
			if ((ctrl->data_pos + len) >= (ctrl->data_max + 5))
			{
				//memcpy(&ctrl->packet_data[ctrl->data_pos], data, (XMODEM_SOH_DATA_LEN + 5) - ctrl->data_pos);
				memcpy(&ctrl->packet_data[ctrl->data_pos], data, (ctrl->data_max + 5) - ctrl->data_pos);
				//if (ctrl->packet_data[0] != XMODEM_SOH || ctrl->packet_data[1] != 0x00 || ctrl->packet_data[2] != 0xff)
				if (ctrl->packet_data[1] != 0x00 || ctrl->packet_data[2] != 0xff)
				{
					LLOGD("head %x %x %x", ctrl->packet_data[0], ctrl->packet_data[1], ctrl->packet_data[2]);
					goto DATA_RECIEVE_ERROR;
				}
				//crc16_org = ctrl->packet_data[XMODEM_SOH_DATA_LEN + 3];
				//crc16_org = (crc16_org << 8) + ctrl->packet_data[XMODEM_SOH_DATA_LEN + 4];
				//crc16 = CRC16_Cal(&ctrl->packet_data[XMODEM_DATA_POS], XMODEM_SOH_DATA_LEN, 0);
				crc16_org = ctrl->packet_data[ctrl->data_max + 3];
				crc16_org = (crc16_org << 8) + ctrl->packet_data[ctrl->data_max + 4];
				crc16 = CRC16_Cal(&ctrl->packet_data[XMODEM_DATA_POS], ctrl->data_max, 0);
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
						*flag = 0;
						*ack = XMODEM_ACK;
						*all_done = 1;
						return 0;
					}
					NameEnd = 0;
					//for(i = XMODEM_DATA_POS; i < (XMODEM_SOH_DATA_LEN + 5); i++)
					for(i = XMODEM_DATA_POS; i < (ctrl->data_max + 5); i++)
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
					LenEnd = 0;
					//for(i = (NameEnd + 1); i < (XMODEM_SOH_DATA_LEN + 5); i++)
					for(i = (NameEnd + 1); i < (ctrl->data_max + 5); i++)
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
#ifdef __LUATOS__
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
#else
					ctrl->cb(&ctrl->packet_data[XMODEM_DATA_POS], 0);
					ctrl->cb(NULL, ctrl->file_size);
#endif


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
		if (!data || !len)
		{
			return 0;
		}
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
			case XMODEM_CAN:
				luat_ymodem_reset(handler);
				*ack = XMODEM_ACK;
				*all_done = 1;
				return 0;
			default:
				LLOGD("%x", data[0]);
				goto DATA_RECIEVE_ERROR;
				break;
			}
			memcpy(ctrl->packet_data, data, len);
			ctrl->data_pos += len;
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
						LLOGD("head %x %x %x,%d", ctrl->packet_data[0], ctrl->packet_data[1], ctrl->packet_data[2],ctrl->next_sn);
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
#ifdef __LUATOS__
					luat_fs_fwrite(ctrl->packet_data+3, LenEnd, 1, ctrl->fd);
#else
					ctrl->cb(ctrl->packet_data+3, LenEnd);
#endif
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
#ifdef __LUATOS__
					luat_fs_fwrite(ctrl->packet_data+3, LenEnd, 1, ctrl->fd);
#else
					ctrl->cb(ctrl->packet_data+3, LenEnd);
#endif
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
		if (!data || !len)
		{
			return 0;
		}
		switch(data[0])
		{
		case XMODEM_EOT:
			ctrl->state++;
			ctrl->data_pos = 0;
			*flag = 0;
			*ack = XMODEM_NAK;
#ifdef __LUATOS__
			if (ctrl->fd) luat_fs_fclose(ctrl->fd);
			ctrl->fd = NULL;
#else
			ctrl->cb(NULL, 0);
#endif
			break;
		case XMODEM_CAN:
			luat_ymodem_reset(handler);
			*ack = XMODEM_ACK;
			*all_done = 1;
			return 0;
		default:
			goto DATA_RECIEVE_ERROR;
		}
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
#ifdef __LUATOS__
		luat_fs_fclose(ctrl->fd);
		ctrl->fd = NULL;
#else

#endif
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
#ifdef __LUATOS__
	if (ctrl->fd) luat_fs_fclose(ctrl->fd);
	ctrl->fd = NULL;
#else
	ctrl->cb(NULL, 0);
#endif
}

void luat_ymodem_release(void *handler)
{
	ymodem_ctrlstruct *ctrl = handler;
	luat_ymodem_reset(handler);
#ifdef __LUATOS__
	luat_heap_free(ctrl->save_path);
#endif
	luat_heap_free(handler);
}
