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
