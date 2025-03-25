#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_malloc.h"

uint8_t luat_crc8(const void *data, uint32_t len, uint8_t start, uint8_t poly, uint8_t is_reverse)
{
	uint32_t i;
	uint8_t CRC8 = start;
	uint8_t wTemp = poly;
	uint8_t *Src = (uint8_t *)data;
	if (is_reverse)
	{
		poly = 0;
		for (i = 0; i < 8; i++)
		{
			if (wTemp & (1 << (7 - i)))
			{
				poly |= 1 << i;
			}
		}
		while (len--)
		{

			CRC8 ^= *Src++;
			for (i = 0; i < 8; i++)
			{
				if ((CRC8 & 0x01))
				{
					CRC8 >>= 1;
					CRC8 ^= poly;
				}
				else
				{
					CRC8 >>= 1;
				}
			}
		}
	}
	else
	{
		while (len--)
		{

			CRC8 ^= *Src++;
			for (i = 8; i > 0; --i)
			{
				if ((CRC8 & 0x80))
				{
					CRC8 <<= 1;
					CRC8 ^= poly;
				}
				else
				{
					CRC8 <<= 1;
				}
			}
		}
	}
	return CRC8;
}

/************************************************************************/
/*  CRC16                                                                */
/************************************************************************/
uint16_t luat_crc16(const void *data, uint32_t len, uint16_t start, uint16_t poly, uint8_t is_reverse)
{
	uint32_t i;
	uint16_t CRC16 = start;
	uint16_t wTemp = poly;
	uint8_t *Src = (uint8_t *)data;
	if (is_reverse)
	{
		poly = 0;
		for (i = 0; i < 16; i++)
		{
			if (wTemp & (1 << (15 - i)))
			{
				poly |= 1 << i;
			}
		}
		while (len--)
		{
			for (i = 0; i < 8; i++)
			{
				if ((CRC16 & 0x0001) != 0)
				{
					CRC16 >>= 1;
					CRC16 ^= poly;
				}
				else
				{
					CRC16 >>= 1;
				}
				if ((*Src&(1 << i)) != 0)
				{
					CRC16 ^= poly;
				}
			}
			Src++;
		}
	}
	else
	{
		while (len--)
		{
			for (i = 8; i > 0; i--)
			{
				if ((CRC16 & 0x8000) != 0)
				{
					CRC16 <<= 1;
					CRC16 ^= poly;
				}
				else
				{
					CRC16 <<= 1;
				}
				if ((*Src&(1 << (i - 1))) != 0)
				{
					CRC16 ^= poly;
				}
			}
			Src++;
		}
	}

	return CRC16;
}


static uint32_t *luat_crc32_table;
static uint32_t luat_crc32_root;
/**
* @brief  反转数据
* @param  ref 需要反转的变量
* @param	ch 反转长度，多少位
* @retval N反转后的数据
*/
static unsigned long int prvReflect(unsigned long int ref, uint8_t ch)
{
	unsigned long int value = 0;
	unsigned long int i;
	for (i = 1; i < (unsigned long int)(ch + 1); i++)
	{
		if (ref & 1)
			value |= (unsigned long int)1 << (ch - i);
		ref >>= 1;
	}
	return value;
}

/**
* @brief  建立CRC32的查询表
* @param  Tab 表缓冲
* @param	Gen CRC32根
* @retval None
*/
static void prvCRC32_CreateTable(uint32_t *Tab, uint32_t Gen)
{
	uint32_t crc;
	uint32_t i, j, temp, t1, t2, flag;
	if (Tab[1] != 0)
		return;
	for (i = 0; i < 256; i++)
	{
		temp = prvReflect(i, 8);
		Tab[i] = temp << 24;
		for (j = 0; j < 8; j++)
		{
			flag = Tab[i] & 0x80000000;
			t1 = Tab[i] << 1;
			if (0 == flag)
			{
				t2 = 0;
			}
			else
			{
				t2 = Gen;
			}
			Tab[i] = t1 ^ t2;
		}
		crc = Tab[i];
		Tab[i] = prvReflect(crc, 32);
	}
}


/**
* @brief  计算buffer的crc校验码
* @param  CRC32_Table CRC32表
* @param  Buf 缓冲
* @param	Size 缓冲区长度
* @param	CRC32 初始CRC32值
* @retval 计算后的CRC32
*/
static uint32_t prvCRC32_Cal(uint32_t *CRC32_Table, const uint8_t *Buf, uint32_t Size, uint32_t CRC32Last)
{
	uint32_t i;
	for (i = 0; i < Size; i++)
	{
		CRC32Last = CRC32_Table[(CRC32Last ^ Buf[i]) & 0xff] ^ (CRC32Last >> 8);
	}
	return CRC32Last;
}

uint32_t luat_crc32(const void *data, uint32_t len, uint32_t start, uint32_t poly)
{
	if (!poly)
	{
		poly = 0x04C11DB7;
	}
	if (poly != luat_crc32_root)
	{
		luat_crc32_root = poly;
		if (!luat_crc32_table)
		{
			luat_crc32_table = luat_heap_malloc(1024);
		}
		prvCRC32_CreateTable(luat_crc32_table, luat_crc32_root);
	}
	return prvCRC32_Cal(luat_crc32_table, data, len, start);
}

// 仅追求数据的modbus crc16算法
// from https://github.com/LacobusVentura/MODBUS-CRC16/blob/master/README.md
// MIT协议
#ifndef LUAT_ATTR_METHOD_INRAM_CRC16
#define LUAT_ATTR_METHOD_INRAM_CRC16 
#endif
LUAT_ATTR_METHOD_INRAM_CRC16 static const uint16_t modbus_table[256] = {
	0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241,
	0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440,
	0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40,
	0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841,
	0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40,
	0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41,
	0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641,
	0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040,
	0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240,
	0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441,
	0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41,
	0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840,
	0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41,
	0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40,
	0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640,
	0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041,
	0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240,
	0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441,
	0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41,
	0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840,
	0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41,
	0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40,
	0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640,
	0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041,
	0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241,
	0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440,
	0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40,
	0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841,
	0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40,
	0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41,
	0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641,
	0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040 };

LUAT_ATTR_METHOD_INRAM_CRC16 uint16_t luat_crc16_modbus( const uint8_t *buf, uint32_t len)
{


	uint8_t xor = 0;
	uint16_t crc = 0xFFFF;

	while( len-- )
	{
		xor = (*buf++) ^ crc;
		crc >>= 8;
		crc ^= modbus_table[xor];
	}

	return crc;
}
