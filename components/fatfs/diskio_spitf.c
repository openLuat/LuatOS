/*-----------------------------------------------------------------------*/
/* Low level disk I/O module skeleton for FatFs     (C)ChaN, 2016        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#ifdef __LUATOS__
#include "lauxlib.h"
#endif
#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */
#ifdef __LUATOS__
#include "c_common.h"
#else
#if defined(LUAT_EC7XX_CSDK) || defined(CHIP_EC618) || defined (__SOC_BSP__)
#include "bsp_common.h"
#endif
#endif
#include "luat_rtos.h"
#include "luat_mcu.h"
#define LUAT_LOG_TAG "SPI_TF"
#include "luat_log.h"

//#define luat_spi_lock(x)
//#define luat_spi_unlock(x)

#define __SDHC_BLOCK_LEN__	(512)

#define CMD0	(0)			/* GO_IDLE_STATE */
#define CMD1	(1)			/* SEND_OP_COND */
#define CMD2	(2)
#define	ACMD41	(0x80+41)	/* SEND_OP_COND (SDC) */
#define CMD8	(8)			/* SEND_IF_COND */
#define CMD9	(9)			/* SEND_CSD */
#define CMD10	(10)		/* SEND_CID */
#define CMD12	(12)		/* STOP_TRANSMISSION */
#define CMD13	(13)		/* SEND_STATUS */
#define ACMD13	(0x80+13)	/* SD_STATUS (SDC) */
#define CMD16	(16)		/* SET_BLOCKLEN */
#define CMD17	(17)		/* READ_SINGLE_BLOCK */
#define CMD18	(18)		/* READ_MULTIPLE_BLOCK */
#define CMD23	(23)		/* SET_BLOCK_COUNT */
#define	ACMD23	(0x80+23)	/* SET_WR_BLK_ERASE_COUNT (SDC) */
#define CMD24	(24)		/* WRITE_BLOCK */
#define CMD25	(25)		/* WRITE_MULTIPLE_BLOCK */
#define CMD32	(32)		/* ERASE_ER_BLK_START */
#define CMD33	(33)		/* ERASE_ER_BLK_END */
#define CMD38	(38)		/* ERASE */
#define CMD55	(55)		/* APP_CMD */
#define CMD58	(58)		/* READ_OCR */

#define SD_CMD_GO_IDLE_STATE          0   /* CMD0 = 0x40  */
#define SD_CMD_SEND_OP_COND           1   /* CMD1 = 0x41  */
#define SD_CMD_SEND_IF_COND           8   /* CMD8 = 0x48  */
#define SD_CMD_SEND_CSD               9   /* CMD9 = 0x49  */
#define SD_CMD_SEND_CID               10  /* CMD10 = 0x4A */
#define SD_CMD_STOP_TRANSMISSION      12  /* CMD12 = 0x4C */
#define SD_CMD_SEND_STATUS            13  /* CMD13 = 0x4D */
#define SD_CMD_SET_BLOCKLEN           16  /* CMD16 = 0x50 */
#define SD_CMD_READ_SINGLE_BLOCK      17  /* CMD17 = 0x51 */
#define SD_CMD_READ_MULT_BLOCK        18  /* CMD18 = 0x52 */
#define SD_CMD_SET_BLOCK_COUNT        23  /* CMD23 = 0x57 */
#define SD_CMD_WRITE_SINGLE_BLOCK     24  /* CMD24 = 0x58 */
#define SD_CMD_WRITE_MULT_BLOCK       25  /* CMD25 = 0x59 */
#define SD_CMD_PROG_CSD               27  /* CMD27 = 0x5B */
#define SD_CMD_SET_WRITE_PROT         28  /* CMD28 = 0x5C */
#define SD_CMD_CLR_WRITE_PROT         29  /* CMD29 = 0x5D */
#define SD_CMD_SEND_WRITE_PROT        30  /* CMD30 = 0x5E */
#define SD_CMD_SD_ERASE_GRP_START     32  /* CMD32 = 0x60 */
#define SD_CMD_SD_ERASE_GRP_END       33  /* CMD33 = 0x61 */
#define SD_CMD_UNTAG_SECTOR           34  /* CMD34 = 0x62 */
#define SD_CMD_ERASE_GRP_START        35  /* CMD35 = 0x63 */
#define SD_CMD_ERASE_GRP_END          36  /* CMD36 = 0x64 */
#define SD_CMD_UNTAG_ERASE_GROUP      37  /* CMD37 = 0x65 */
#define SD_CMD_ERASE                  38  /* CMD38 = 0x66 */
#define SD_CMD_SD_APP_OP_COND         41  /* CMD41 = 0x69 */
#define SD_CMD_APP_CMD                55  /* CMD55 = 0x77 */
#define SD_CMD_READ_OCR               58  /* CMD55 = 0x79 */
#define SD_DEFAULT_BLOCK_SIZE (512)

#define SPI_TF_WRITE_TO_MS	((uint64_t)FATFS_WRITE_TO)
#define SPI_TF_READ_TO_MS	(100)

/* 多扇区读：一次 SPI 最多这么多个扇区，数据仍走 DMA。 */
#define SPITF_BULK_MAX_SECTORS 32u
/* 两个扇区之间允许的 0xFF 空档上限，含数据令牌 0xFE。 */
#define SPITF_BULK_GAP         16u
/* 寻找第一个数据令牌时，每次从线上读入的字节数。 */
#define SPITF_TOKEN_SCAN       32u

typedef struct
{
  uint8_t  Reserved1:2;               /* Reserved */
  uint16_t DeviceSize:12;             /* Device Size */
  uint8_t  MaxRdCurrentVDDMin:3;      /* Max. read current @ VDD min */
  uint8_t  MaxRdCurrentVDDMax:3;      /* Max. read current @ VDD max */
  uint8_t  MaxWrCurrentVDDMin:3;      /* Max. write current @ VDD min */
  uint8_t  MaxWrCurrentVDDMax:3;      /* Max. write current @ VDD max */
  uint8_t  DeviceSizeMul:3;           /* Device size multiplier */
} struct_v1;


typedef struct
{
  uint8_t  Reserved1:6;               /* Reserved */
  uint32_t DeviceSize:22;             /* Device Size */
  uint8_t  Reserved2:1;               /* Reserved */
} struct_v2;

/**
  * @brief  Card Specific Data: CSD Register
  */
typedef struct
{
  /* Header part */
  uint8_t  CSDStruct:2;            /* CSD structure */
  uint8_t  Reserved1:6;            /* Reserved */
  uint8_t  TAAC:8;                 /* Data read access-time 1 */
  uint8_t  NSAC:8;                 /* Data read access-time 2 in CLK cycles */
  uint8_t  MaxBusClkFrec:8;        /* Max. bus clock frequency */
  uint16_t CardComdClasses:12;      /* Card command classes */
  uint8_t  RdBlockLen:4;           /* Max. read data block length */
  uint8_t  PartBlockRead:1;        /* Partial blocks for read allowed */
  uint8_t  WrBlockMisalign:1;      /* Write block misalignment */
  uint8_t  RdBlockMisalign:1;      /* Read block misalignment */
  uint8_t  DSRImpl:1;              /* DSR implemented */

  /* v1 or v2 struct */
  union csd_version {
    struct_v1 v1;
    struct_v2 v2;
  } version;

  uint8_t  EraseSingleBlockEnable:1;  /* Erase single block enable */
  uint8_t  EraseSectorSize:7;         /* Erase group size multiplier */
  uint8_t  WrProtectGrSize:7;         /* Write protect group size */
  uint8_t  WrProtectGrEnable:1;       /* Write protect group enable */
  uint8_t  Reserved2:2;               /* Reserved */
  uint8_t  WrSpeedFact:3;             /* Write speed factor */
  uint8_t  MaxWrBlockLen:4;           /* Max. write data block length */
  uint8_t  WriteBlockPartial:1;       /* Partial blocks for write allowed */
  uint8_t  Reserved3:5;               /* Reserved */
  uint8_t  FileFormatGrouop:1;        /* File format group */
  uint8_t  CopyFlag:1;                /* Copy flag (OTP) */
  uint8_t  PermWrProtect:1;           /* Permanent write protection */
  uint8_t  TempWrProtect:1;           /* Temporary write protection */
  uint8_t  FileFormat:2;              /* File Format */
  uint8_t  Reserved4:2;               /* Reserved */
  uint8_t  crc:7;                     /* Reserved */
  uint8_t  Reserved5:1;               /* always 1*/

} SD_CSD;

/**
  * @brief  Card Identification Data: CID Register
  */
typedef struct
{
  uint8_t  ManufacturerID;       /* ManufacturerID */
  uint16_t OEM_AppliID;          /* OEM/Application ID */
  uint32_t ProdName1;            /* Product Name part1 */
  uint8_t  ProdName2;            /* Product Name part2*/
  uint8_t  ProdRev;              /* Product Revision */
  uint32_t ProdSN;               /* Product Serial Number */
  uint8_t  Reserved1;            /* Reserved1 */
  uint16_t ManufactDate;         /* Manufacturing Date */
  uint8_t  CID_CRC;              /* CID CRC */
  uint8_t  Reserved2;            /* always 1 */
} SD_CID;

/**
  * @brief SD Card information
  */
typedef struct
{
  SD_CSD Csd;
  SD_CID Cid;
  uint64_t CardCapacity;              /*!< Card Capacity */
  uint32_t LogBlockNbr;               /*!< Specifies the Card logical Capacity in blocks   */
  uint32_t CardBlockSize;             /*!< Card Block Size */
  uint32_t LogBlockSize;              /*!< Specifies logical block size in bytes           */
} SD_CardInfo;

typedef struct
{
	SD_CardInfo *Info;
	Buffer_Struct DataBuf;
	HANDLE locker;
	uint32_t Size;							//flash的大小KB
	uint32_t OCR;
	uint32_t SpiSpeed;
	uint8_t *TempData;
	uint16_t WriteWaitCnt;
	uint8_t CSPin;
	uint8_t SpiID;
	uint8_t SDHCState;
	uint8_t IsInitDone;
	uint8_t SDHCError;
	uint8_t SPIError;
	uint8_t ExternResult[64];
	uint8_t ExternLen;
	uint8_t SDSC;
	uint8_t ResetCnt;
	uint8_t CmdCnt;
	uint8_t ExtraClockNeeded; 		// 是否在发送命令前需要发送一个时钟: 0=no, 1=yes */
}luat_spitf_ctrl_t;

#define SPI_TF_WAIT(x) luat_rtos_task_sleep(x)

extern uint8_t FATFS_NO_CRC_CHECK;
extern uint16_t FATFS_WRITE_TO;
static luat_spitf_ctrl_t g_s_spitf;
/* 多扇区读的接收缓冲。第一次按需要申请，之后复用。 */
static uint8_t *s_spitf_bulk;
static uint32_t s_spitf_bulk_cap;
/* 与接收缓冲分开的 0xFF 发送缓冲，避免同一块内存同时收发。 */
static uint8_t *s_spitf_tx;
static uint32_t s_spitf_tx_cap;
/* 上一段为凑空档多时钟进来的尾巴，下一段从这里接着切。 */
static uint8_t s_spitf_carry[768];
static uint32_t s_spitf_carry_len;
/* 本次 CMD18 批量解析失败后，重试改走逐扇区读。下一次读盘会清掉。 */
static uint8_t s_spitf_force_slow;
static void luat_spitf_read_config(luat_spitf_ctrl_t *spitf);

static void luat_spitf_cs(luat_spitf_ctrl_t *spitf, uint8_t OnOff)
{
	uint8_t Temp[1] = {0xff};
	luat_gpio_set(spitf->CSPin, !OnOff);
	if (!OnOff)
	{
		luat_spi_send(spitf->SpiID, (const char *)Temp, 1);
	}

}
static uint8_t CRC7(uint8_t * chr, int cnt)
{
	int i,a;
	uint8_t crc,Data;
	crc=0;
	for (a=0;a<cnt;a++)
	{
	   Data=chr[a];
	   for (i=0;i<8;i++)
	   {
		crc <<= 1;

		if ((Data & 0x80)^(crc & 0x80))
		crc ^=0x09;
		Data <<= 1;
	   }
	}
	crc=(crc<<1)|1;
	return(crc);
}
extern void DBG_HexPrintf(void *Data, unsigned int len);
static int32_t luat_spitf_cmd(luat_spitf_ctrl_t *spitf, uint8_t Cmd, uint32_t Arg, uint8_t NeedStop)
{
	uint8_t i, TxLen, DummyLen;
	int32_t Result = -ERROR_OPERATION_FAILED;
	luat_spitf_cs(spitf, 1);
	if (spitf->ExtraClockNeeded)
	{
		uint8_t _dummy = 0xff;
		luat_spi_send(spitf->SpiID, (const char *)&_dummy, 1);
	}
	spitf->TempData[0] = 0x40|Cmd;
	BytesPutBe32(spitf->TempData + 1, Arg);
	spitf->TempData[5] = CRC7(spitf->TempData, 5);
	TxLen = 6 + spitf->CmdCnt;
	memset(spitf->TempData + 6, 0xff, TxLen - 6);

	spitf->SPIError = 0;
	spitf->SDHCError = 0;
	luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, TxLen, (char *)spitf->TempData, TxLen);

	for(i = 7; i < TxLen; i++)
	{
		if (spitf->TempData[i] != 0xff)
		{
//			LLOGE("find answer byte in %d", i);
			if (spitf->CmdCnt != (i + 1))
			{
				spitf->CmdCnt = i + 1;
				// LLOGI("find answer byte in %d", i);
			}

			spitf->SDHCState = spitf->TempData[i];
			if ((spitf->SDHCState == !spitf->IsInitDone) || !spitf->SDHCState)
			{
				Result = ERROR_NONE;
			}
			DummyLen = TxLen - i - 1;
			memcpy(spitf->ExternResult, &spitf->TempData[i + 1], DummyLen);
			spitf->ExternLen = DummyLen;
// 			if (spitf->SDHCState == 0xC1 || spitf->SDHCState == 0xC2)
// 			{
// 				LLOGE("SD response 0x%02x on CMD%d ARG 0x%08x SDSC=%d CmdCnt=%d", spitf->SDHCState, Cmd, Arg, spitf->SDSC, spitf->CmdCnt);
// 				DBG_HexPrintf(spitf->TempData, TxLen);
// 				if (spitf->ExternLen) DBG_HexPrintf(spitf->ExternResult, spitf->ExternLen);
// 			}
			/* 如果得到0xC1/0xC2且当前未使用额外时钟，则使用额外时钟重试一次（处理总线干扰，如CH390） */
			if ((spitf->SDHCState == 0xC1 || spitf->SDHCState == 0xC2) && !(spitf->ExtraClockNeeded))
			{
				LLOGD("Got 0x%02x, retrying CMD%d with extra clock to check for bus interference", spitf->SDHCState, Cmd);
				luat_spitf_cs(spitf, 0);
				luat_spitf_cs(spitf, 1);
				{
					uint8_t _dummy = 0xff;
					luat_spi_send(spitf->SpiID, (const char *)&_dummy, 1);
				}

				spitf->TempData[0] = 0x40|Cmd;
				BytesPutBe32(spitf->TempData + 1, Arg);
				spitf->TempData[5] = CRC7(spitf->TempData, 5);
				TxLen = 6 + spitf->CmdCnt;
				memset(spitf->TempData + 6, 0xff, TxLen - 6);
				luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, TxLen, (char *)spitf->TempData, TxLen);

				for (i = 7; i < TxLen; i++)
				{
					if (spitf->TempData[i] != 0xff)
					{
						spitf->SDHCState = spitf->TempData[i];
						DummyLen = TxLen - i - 1;
						memcpy(spitf->ExternResult, &spitf->TempData[i + 1], DummyLen);
						spitf->ExternLen = DummyLen;
						if ((spitf->SDHCState == !spitf->IsInitDone) || !spitf->SDHCState)
						{
							Result = ERROR_NONE;
						}
						break;
					}
				}
				if (spitf->SDHCState != 0xC1 && spitf->SDHCState != 0xC2)
				{
					spitf->ExtraClockNeeded = 1;
				}
			}
			break;
		}
	}
	if (NeedStop)
	{
		luat_spitf_cs(spitf, 0);
	}
	if (Result)
	{
		LLOGE("cmd %d arg %x result %d", Cmd, Arg, Result);
		DBG_HexPrintf(spitf->TempData, TxLen);
	}
	return Result;
}

static int32_t luat_spitf_read_reg(luat_spitf_ctrl_t *spitf, uint8_t *RegDataBuf, uint8_t DataLen)
{
	uint64_t OpEndTick;
	int Result = ERROR_NONE;
	uint16_t DummyLen;
	uint16_t i,offset;
	spitf->SPIError = 0;
	spitf->SDHCError = 0;
	OpEndTick = luat_mcu_tick64_ms() + SPI_TF_READ_TO_MS * 4;
	offset = 0;
	for(i = 0; i < spitf->ExternLen; i++)
	{
		if (spitf->ExternResult[i] != 0xff)
		{
			if (0xfe == spitf->ExternResult[i])
			{
				offset = 1;
			}
			else
			{
				LLOGD("no 0xfe find %d,%x",i,spitf->ExternResult[i]);
			}
			DummyLen = spitf->ExternLen - i - offset;
			memcpy(RegDataBuf, &spitf->ExternResult[i + offset], DummyLen);
			memset(RegDataBuf + DummyLen, 0xff, DataLen - DummyLen);
			luat_spi_transfer(spitf->SpiID, (const char *)(RegDataBuf + DummyLen), DataLen - DummyLen, (char *)(RegDataBuf + DummyLen), DataLen - DummyLen);
			goto SDHC_SPIREADREGDATA_DONE;
		}

	}
	while((luat_mcu_tick64_ms() < OpEndTick) && !spitf->SDHCError)
	{
		memset(spitf->TempData, 0xff, 40);
		luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, 40, (char *)spitf->TempData, 40);

		for(i = 0; i < 40; i++)
		{
			if (spitf->TempData[i] != 0xff)
			{
				if (0xfe == spitf->TempData[i])
				{
					offset = 1;
				}
				else
				{
					LLOGD("no 0xfe find %d,%x",i,spitf->TempData[i]);
				}
				DummyLen = 40 - i - offset;
				if (DummyLen >= DataLen)
				{
					memcpy(RegDataBuf, &spitf->TempData[i + offset], DataLen);
					goto SDHC_SPIREADREGDATA_DONE;
				}
				else
				{
					memcpy(RegDataBuf, &spitf->TempData[i + offset], DummyLen);
					memset(RegDataBuf + DummyLen, 0xff, DataLen - DummyLen);
					luat_spi_transfer(spitf->SpiID, (const char *)(RegDataBuf + DummyLen), DataLen - DummyLen, (char *)(RegDataBuf + DummyLen), DataLen - DummyLen);
					goto SDHC_SPIREADREGDATA_DONE;
				}
			}

		}
		SPI_TF_WAIT(1);
	}
	LLOGD("read config reg timeout!");
	Result = -ERROR_OPERATION_FAILED;
SDHC_SPIREADREGDATA_DONE:
	luat_spitf_cs(spitf, 0);
	return Result;
}


static int32_t luat_spitf_write_data(luat_spitf_ctrl_t *spitf)
{
	uint64_t OpEndTick;
	int Result = -ERROR_OPERATION_FAILED;
	uint16_t TxLen, DoneFlag, waitCnt;
	uint16_t i, crc16;
	spitf->SPIError = 0;
	spitf->SDHCError = 0;
	OpEndTick = luat_mcu_tick64_ms() + SPI_TF_WRITE_TO_MS;
	while( (spitf->DataBuf.Pos < spitf->DataBuf.MaxLen) && (luat_mcu_tick64_ms() < OpEndTick) )
	{
		spitf->TempData[0] = 0xff;
		spitf->TempData[1] = 0xff;
		//LLOGD("%u,%u", spitf->DataBuf.Pos, spitf->DataBuf.MaxLen);
		spitf->TempData[2] = 0xfc;
		memcpy(spitf->TempData + 3, spitf->DataBuf.Data + spitf->DataBuf.Pos * __SDHC_BLOCK_LEN__, __SDHC_BLOCK_LEN__);
		crc16 = CRC16Cal(spitf->DataBuf.Data + spitf->DataBuf.Pos * __SDHC_BLOCK_LEN__, __SDHC_BLOCK_LEN__, 0, CRC16_CCITT_GEN, 0);
		BytesPutBe16(spitf->TempData + 3 + __SDHC_BLOCK_LEN__, crc16);
		spitf->TempData[5 + __SDHC_BLOCK_LEN__] = 0xff;
		TxLen = 6 + __SDHC_BLOCK_LEN__;
		luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, TxLen, (char *)spitf->TempData, TxLen);
		if ((spitf->TempData[5 + __SDHC_BLOCK_LEN__] & 0x1f) != 0x05)
		{
			LLOGD("write data error! %d %02x", spitf->DataBuf.Pos, spitf->TempData[5 + __SDHC_BLOCK_LEN__]);
			spitf->SDHCError = 1;
			goto SDHC_SPIWRITEBLOCKDATA_DONE;
		}
		DoneFlag = 0;
		waitCnt = 0;
		while( (luat_mcu_tick64_ms() < OpEndTick) && !DoneFlag )
		{
			TxLen = spitf->WriteWaitCnt?spitf->WriteWaitCnt:80;
			memset(spitf->TempData, 0xff, TxLen);
			luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, TxLen, (char *)spitf->TempData, TxLen);
			for(i = 4; i < TxLen; i++)
			{
				if (spitf->TempData[i] == 0xff)
				{
					DoneFlag = 1;
					if ((i + waitCnt) < __SDHC_BLOCK_LEN__)
					{
						if ((i + waitCnt) != spitf->WriteWaitCnt)
						{
							spitf->WriteWaitCnt = i + waitCnt + 8;
						}
					}
					break;
				}
			}
			waitCnt += TxLen;
		}
		if (!DoneFlag)
		{
			LLOGD("write data timeout!");
			spitf->SDHCError = 1;
			goto SDHC_SPIWRITEBLOCKDATA_DONE;
		}
		spitf->DataBuf.Pos++;
		OpEndTick = luat_mcu_tick64_ms() + SPI_TF_WRITE_TO_MS;
	}
	Result = ERROR_NONE;
SDHC_SPIWRITEBLOCKDATA_DONE:
	spitf->TempData[0] = 0xfd;
	luat_spi_send(spitf->SpiID, (const char *)spitf->TempData, 1);

	OpEndTick = luat_mcu_tick64_ms() + SPI_TF_WRITE_TO_MS;
	DoneFlag = 0;
	while( (luat_mcu_tick64_ms() < OpEndTick) && !DoneFlag )
	{
		TxLen = 512;
		memset(spitf->TempData, 0xff, TxLen);
		luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, TxLen, (char *)spitf->TempData, TxLen);
		for(i = 4; i < TxLen; i++)
		{
			if (spitf->TempData[i] == 0xff)
			{
				DoneFlag = 1;
				break;
			}
		}
	}
	luat_spitf_cs(spitf, 0);
	return Result;
}

/*
 * 计算一个扇区数据的 CRC16-CCITT。
 * 结果与 CRC16Cal(src, 512, 0, CRC16_CCITT_GEN, 0) 相同，按字节查 256 项表。
 * 表在第一次调用时生成，之后重复使用。
 *
 * @param src 扇区数据，长度必须是 __SDHC_BLOCK_LEN__（512）。不含后面的 2 字节 CRC。
 * @return 该 512 字节的 CRC16。
 */
static uint16_t spitf_crc16_block(const uint8_t *src)
{
	static uint16_t tab[256];
	static uint8_t ready;
	uint16_t crc;
	uint16_t i;

	if (!ready)
	{
		for (i = 0; i < 256; i++)
		{
			uint16_t c = 0;
			uint8_t b = (uint8_t)i;
			int bit;
			for (bit = 8; bit > 0; bit--)
			{
				if (c & 0x8000)
				{
					c = (uint16_t)((c << 1) ^ CRC16_CCITT_GEN);
				}
				else
				{
					c = (uint16_t)(c << 1);
				}
				if (b & (1u << (bit - 1)))
				{
					c ^= CRC16_CCITT_GEN;
				}
			}
			tab[i] = c;
		}
		ready = 1;
	}
	crc = 0;
	for (i = 0; i < __SDHC_BLOCK_LEN__; i++)
	{
		crc = (uint16_t)((crc << 8) ^ tab[(crc >> 8) ^ src[i]]);
	}
	return crc;
}

/*
 * 在 CMD18 的数据阶段寻找第一个 0xFE 数据令牌。
 * 每次时钟读入 SPITF_TOKEN_SCAN 字节，最多扫 2048 字节。
 *
 * @param spitf      SD SPI 控制器，使用其中的 SpiID 和 TempData。
 * @param prefix     输出缓冲。令牌后面已经读进来的字节写到这里，容量至少 SPITF_TOKEN_SCAN。
 * @param prefix_len 输出这些字节的长度。令牌落在本次扫描的最后一个字节时为 0。
 * @return 0 找到令牌；-1 表示 SPI 传输失败，或扫满仍没有 0xFE。
 */
static int spitf_find_data_token(luat_spitf_ctrl_t *spitf, uint8_t *prefix, uint32_t *prefix_len)
{
	uint32_t scanned = 0;
	uint32_t i;

	*prefix_len = 0;
	while (scanned < 2048u)
	{
		memset(spitf->TempData, 0xff, SPITF_TOKEN_SCAN);
		if (luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, SPITF_TOKEN_SCAN,
				(char *)spitf->TempData, SPITF_TOKEN_SCAN) != (int)SPITF_TOKEN_SCAN)
		{
			return -1;
		}
		for (i = 0; i < SPITF_TOKEN_SCAN; i++)
		{
			if (spitf->TempData[i] == 0xfe)
			{
				*prefix_len = SPITF_TOKEN_SCAN - i - 1;
				if (*prefix_len)
				{
					memcpy(prefix, spitf->TempData + i + 1, *prefix_len);
				}
				return 0;
			}
		}
		scanned += SPITF_TOKEN_SCAN;
	}
	return -1;
}

/*
 * 保证一块堆缓冲的容量不小于 need。已有缓冲够用时不重新分配。
 * 第一次多扇区读会申请接收缓冲和发送缓冲，之后一直复用。
 *
 * @param buf  缓冲指针。分配成功后更新；失败时原来的指针保持不变。
 * @param cap  当前容量，单位字节。分配成功后更新为 need。
 * @param need 本次需要的字节数。
 * @return 0 容量已经够，或新缓冲分配成功；-1 堆申请失败。
 */
static int spitf_ensure_buf(uint8_t **buf, uint32_t *cap, uint32_t need)
{
	uint8_t *nb;
	if (need <= *cap)
	{
		return 0;
	}
	nb = (uint8_t *)luat_heap_malloc(need);
	if (nb == NULL)
	{
		return -1;
	}
	if (*buf)
	{
		luat_heap_free(*buf);
	}
	*buf = nb;
	*cap = need;
	return 0;
}

/*
 * 从当前 CMD18 数据流读出 n 个扇区。
 * 先定位数据令牌，再一次 DMA 把这一段时钟进来，在缓冲里切开每个扇区并核对 CRC16。
 * 为了对齐扇区间空档而多读进来的尾巴留在 s_spitf_carry，下一段从那里接着切。
 * 堆缓冲申请失败、令牌丢失或 CRC 不符时返回失败。调用方应发 CMD12，再改逐扇区读。
 *
 * @param spitf SD SPI 控制器。
 * @param n     本段扇区数，范围 1..SPITF_BULK_MAX_SECTORS。
 * @param base  目标地址，至少能放下 n * 512 字节的扇区数据，不含令牌和 CRC。
 * @return 0 这 n 个扇区已写入 base；-1 本段失败，线上位置不再可靠。
 */
static int spitf_read_bulk_chunk(luat_spitf_ctrl_t *spitf, uint32_t n, uint8_t *base)
{
	uint8_t prefix[SPITF_TOKEN_SCAN];
	uint32_t prefix_len = 0;
	uint32_t per = SPITF_BULK_GAP + 1u + 512u + 2u;
	uint32_t remain;
	uint32_t need;
	uint32_t i;
	uint32_t head;
	uint8_t *p;
	uint8_t *end;
	int first_needs_token;

	if (n == 0)
	{
		return -1;
	}
	if (s_spitf_carry_len == 0)
	{
		if (spitf_find_data_token(spitf, prefix, &prefix_len) != 0 || prefix_len > 512u)
		{
			return -1;
		}
		first_needs_token = 0;
	}
	else
	{
		if (s_spitf_carry_len > sizeof(s_spitf_carry))
		{
			return -1;
		}
		prefix_len = s_spitf_carry_len;
		first_needs_token = 1;
	}
	remain = (first_needs_token ? 0u : ((512u - prefix_len) + 2u)) + (n - (first_needs_token ? 0u : 1u)) * per + SPITF_BULK_GAP;
	if (remain < prefix_len && first_needs_token)
	{
		return -1;
	}
	if (first_needs_token && remain >= prefix_len)
	{
		remain -= prefix_len;
	}
	need = prefix_len + remain;
	if (spitf_ensure_buf(&s_spitf_bulk, &s_spitf_bulk_cap, need) != 0)
	{
		return -1;
	}
	if (prefix_len)
	{
		if (first_needs_token)
		{
			memcpy(s_spitf_bulk, s_spitf_carry, prefix_len);
			s_spitf_carry_len = 0;
		}
		else
		{
			memcpy(s_spitf_bulk, prefix, prefix_len);
		}
	}
	if (remain)
	{
		if (spitf_ensure_buf(&s_spitf_tx, &s_spitf_tx_cap, remain) != 0)
		{
			return -1;
		}
		memset(s_spitf_tx, 0xff, remain);
		if (luat_spi_transfer(spitf->SpiID, (const char *)s_spitf_tx, remain,
				(char *)(s_spitf_bulk + prefix_len), remain) != (int)remain)
		{
			return -1;
		}
	}

	p = s_spitf_bulk;
	end = s_spitf_bulk + need;
	for (i = 0; i < n; i++)
	{
		if (i > 0 || first_needs_token)
		{
			uint8_t *scan = p;
			uint8_t *limit = p + SPITF_BULK_GAP + 1u;
			if (limit > end)
			{
				limit = end;
			}
			while (scan < limit && *scan != 0xfe)
			{
				scan++;
			}
			if (scan >= limit || *scan != 0xfe)
			{
				return -1;
			}
			p = scan + 1;
		}
		if ((uint32_t)(end - p) < 514u)
		{
			return -1;
		}
		if (!FATFS_NO_CRC_CHECK)
		{
			uint16_t crc16 = spitf_crc16_block(p);
			uint16_t crc16_check = (uint16_t)(((uint16_t)p[512] << 8) | p[513]);
			if (crc16 != crc16_check)
			{
				LLOGD("crc16 error %04x %04x", crc16, crc16_check);
				return -1;
			}
		}
		memcpy(base + i * __SDHC_BLOCK_LEN__, p, __SDHC_BLOCK_LEN__);
		p += 514;
	}
	head = (uint32_t)(end - p);
	if (head > sizeof(s_spitf_carry))
	{
		return -1;
	}
	if (head)
	{
		memcpy(s_spitf_carry, p, head);
	}
	s_spitf_carry_len = head;
	return 0;
}

/*
 * 收完当前 CMD18 的数据阶段。命令本身已经由调用方发出。
 * 剩余扇区多于 1 个且没有强制慢路径时，按最多 32 个扇区一段批量读入，
 * CRC16 用查表。只剩 1 个扇区，或上一段批量失败后的重试，改为每个扇区
 * 三次 SPI：找 0xFE、读 512 字节、再读 2 字节 CRC，CRC 逐位计算。
 * 读到的扇区写入 spitf->DataBuf.Data，并推进 DataBuf.Pos。
 *
 * @param spitf SD SPI 控制器。DataBuf.MaxLen 是本次要读的扇区数，Pos 是已完成的个数。
 * @return ERROR_NONE 表示本次数据已收完。
 *         批量读失败时返回 -ERROR_OPERATION_FAILED，并置 s_spitf_force_slow。
 *         调用方应发 CMD12 结束这次 CMD18，再重试；重试会走逐扇区读。
 */
static int32_t luat_spitf_read_data(luat_spitf_ctrl_t *spitf)
{
	if (!s_spitf_force_slow && (spitf->DataBuf.MaxLen - spitf->DataBuf.Pos) > 1)
	{
		uint32_t left = spitf->DataBuf.MaxLen - spitf->DataBuf.Pos;
		spitf->SPIError = 0;
		spitf->SDHCError = 0;
		s_spitf_carry_len = 0;
		uint8_t *base = spitf->DataBuf.Data + spitf->DataBuf.Pos * __SDHC_BLOCK_LEN__;

		while (left)
		{
			uint32_t n = left > SPITF_BULK_MAX_SECTORS ? SPITF_BULK_MAX_SECTORS : left;
			if (spitf_read_bulk_chunk(spitf, n, base) != 0)
			{
				s_spitf_force_slow = 1;
				LLOGD("sd seq read fallback");
				return -ERROR_OPERATION_FAILED;
			}
			spitf->DataBuf.Pos += n;
			base += n * __SDHC_BLOCK_LEN__;
			left -= n;
		}
		return ERROR_NONE;
	}

	uint64_t OpEndTick;
	int Result = -ERROR_OPERATION_FAILED;
	uint16_t ReadLen, DummyLen, RemainingLen;
	uint16_t i, crc16, crc16_check;
	uint8_t *pBuf;
	spitf->SPIError = 0;
	spitf->SDHCError = 0;
	OpEndTick = luat_mcu_tick64_ms() + SPI_TF_READ_TO_MS;
	while( (spitf->DataBuf.Pos < spitf->DataBuf.MaxLen) && (luat_mcu_tick64_ms() < OpEndTick) )
	{

		DummyLen = (__SDHC_BLOCK_LEN__ >> 1);
		memset(spitf->TempData, 0xff, DummyLen);
//		LLOGD("read blocks %u,%u", spitf->DataBuf.Pos, spitf->DataBuf.MaxLen);
		luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, DummyLen, (char *)spitf->TempData, DummyLen);
		RemainingLen = 0;
		for(i = 0; i < DummyLen; i++)
		{
			if (spitf->TempData[i] == 0xfe)
			{
				ReadLen = (DummyLen - i - 1);
				RemainingLen = __SDHC_BLOCK_LEN__ - ReadLen;
				if (ReadLen)
				{
					memcpy(spitf->DataBuf.Data + spitf->DataBuf.Pos * __SDHC_BLOCK_LEN__, spitf->TempData + i + 1, ReadLen);
				}
//				LLOGD("read result %u,%u", ReadLen, RemainingLen);
				goto READ_REST_DATA;
			}
		}
		continue;
READ_REST_DATA:
		pBuf = spitf->DataBuf.Data + spitf->DataBuf.Pos * __SDHC_BLOCK_LEN__ + ReadLen;
		memset(pBuf, 0xff, RemainingLen);
		luat_spi_transfer(spitf->SpiID, (const char *)pBuf, RemainingLen, (char *)pBuf, RemainingLen);
		memset(spitf->TempData, 0xff, 2);
		luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, 2, (char *)spitf->TempData, 2);
		if (FATFS_NO_CRC_CHECK)
		{

		}
		else
		{
			crc16 = CRC16Cal(spitf->DataBuf.Data + spitf->DataBuf.Pos * __SDHC_BLOCK_LEN__, __SDHC_BLOCK_LEN__, 0, CRC16_CCITT_GEN, 0);
			crc16_check = BytesGetBe16(spitf->TempData);
			if (crc16 != crc16_check)
			{
				LLOGD("crc16 error %04x %04x", crc16, crc16_check);
				Result = ERROR_NONE;
				goto SDHC_SPIREADBLOCKDATA_DONE;
			}
		}
		spitf->DataBuf.Pos++;
		OpEndTick = luat_mcu_tick64_ms() + SPI_TF_READ_TO_MS;
	}
	Result = ERROR_NONE;

SDHC_SPIREADBLOCKDATA_DONE:
	return Result;
}

static void luat_spitf_init(luat_spitf_ctrl_t *spitf)
{
	uint64_t OpEndTick;
	if (!spitf->Info)
	{
		spitf->Info = luat_heap_malloc(sizeof(SD_CardInfo));
	}
	memset(spitf->Info, 0, sizeof(SD_CardInfo));
	if (!spitf->TempData)
	{
		spitf->TempData = luat_heap_malloc(__SDHC_BLOCK_LEN__ + 8);
	}
	luat_spi_change_speed(spitf->SpiID, 400000);
	spitf->ExtraClockNeeded = 0; /* default */
	spitf->IsInitDone = 0;
	spitf->SDHCState = 0xff;
	spitf->Info->CardCapacity = 0;
	spitf->WriteWaitCnt = 80;
	spitf->ResetCnt = 80;
	spitf->CmdCnt = 40;
	memset(spitf->TempData, 0xff, spitf->ResetCnt);
	luat_gpio_set(spitf->CSPin, 0);
	{
		/* SD reset 80 clock pulse (cs low)，msg-only：[SEND, RECV]
		 * 主路径 cmd/data 仍走旧 luat_spi_transfer（等待 PC vsd 状态机 msg 化）。
		 * TODO: msg-ize after PC vsd state-machine refactor */
		luat_spi_msg_t msgs[2] = {
			{ .mode = LUAT_SPI_MSG_SEND, .buff = spitf->TempData, .recv_buff = NULL, .len = spitf->ResetCnt },
			{ .mode = LUAT_SPI_MSG_RECV, .buff = spitf->TempData, .recv_buff = NULL, .len = spitf->ResetCnt },
		};
		// LLOGD("spitf reset trans_msgs SEND+RECV bus=%d len=%u", spitf->SpiID, (unsigned)spitf->ResetCnt);
		int r = luat_spi_trans_msgs(spitf->SpiID, msgs, 2);
		if (r < 0) {
			LLOGE("spitf reset trans_msgs failed rc=%d", r);
		}
	}
	luat_gpio_set(spitf->CSPin, 1);
	{
		/* SD idle 80 clock pulse (cs high) */
		luat_spi_msg_t msgs[2] = {
			{ .mode = LUAT_SPI_MSG_SEND, .buff = spitf->TempData, .recv_buff = NULL, .len = spitf->ResetCnt },
			{ .mode = LUAT_SPI_MSG_RECV, .buff = spitf->TempData, .recv_buff = NULL, .len = spitf->ResetCnt },
		};
		// LLOGD("spitf idle  trans_msgs SEND+RECV bus=%d len=%u", spitf->SpiID, (unsigned)spitf->ResetCnt);
		int r = luat_spi_trans_msgs(spitf->SpiID, msgs, 2);
		if (r < 0) {
			LLOGE("spitf idle  trans_msgs failed rc=%d", r);
		}
	}
	spitf->SDSC = 0;
	if (luat_spitf_cmd(spitf, CMD0, 0, 1))
	{
		goto INIT_DONE;
	}
	OpEndTick = luat_mcu_tick64_ms() + 3000;
	if (luat_spitf_cmd(spitf, CMD8, 0x1aa, 1))	//只支持2G以上的SDHC卡
	{
		LLOGD("tf cmd8 not support");
		spitf->SDSC = 1;
	}
WAIT_INIT_DONE:
	if (luat_mcu_tick64_ms() >= OpEndTick)
	{
		LLOGD("tf init timeout!");
		goto INIT_DONE;
	}
	if (luat_spitf_cmd(spitf, SD_CMD_APP_CMD, 0, 1))
	{
		goto INIT_DONE;
	}
	if (!spitf->SDSC)
	{
		if (luat_spitf_cmd(spitf, SD_CMD_SD_APP_OP_COND, 0x40000000, 1))
		{
			goto INIT_DONE;
		}
	}
	else
	{
		if (luat_spitf_cmd(spitf, SD_CMD_SD_APP_OP_COND, 0, 1))
		{
			goto INIT_DONE;
		}
	}
	spitf->IsInitDone = !spitf->SDHCState;
	if (!spitf->IsInitDone)
	{
		SPI_TF_WAIT(10);
		goto WAIT_INIT_DONE;
	}
	if (luat_spitf_cmd(spitf, CMD58, 0, 1))
	{
		goto INIT_DONE;
	}
	spitf->OCR = BytesGetBe32(spitf->ExternResult);
	luat_spi_change_speed(spitf->SpiID, spitf->SpiSpeed);
	luat_spitf_read_config(spitf);
	LLOGD("sdcard init OK OCR:0x%08x!", spitf->OCR);
	return;
INIT_DONE:
	if (!spitf->IsInitDone)
	{
		LLOGD("sdcard init fail!");
	}
	return;
}

static void luat_spitf_read_config(luat_spitf_ctrl_t *spitf)
{
	uint8_t CSD_Tab[18];
	SD_CSD* Csd = &spitf->Info->Csd;
	SD_CardInfo *pCardInfo = spitf->Info;
	uint64_t Temp;
	uint8_t flag_SDHC = (spitf->OCR & 0x40000000) >> 30;
	spitf->SDSC = !flag_SDHC;
	if (spitf->Info->CardCapacity) return;

	if (luat_spitf_cmd(spitf, CMD9, 0, 0))
	{
		goto READ_CONFIG_ERROR;
	}
	if (spitf->SDHCState)
	{
		goto READ_CONFIG_ERROR;
	}
	if (luat_spitf_read_reg(spitf, CSD_Tab, 18))
	{
		goto READ_CONFIG_ERROR;
	}
    /*************************************************************************
      CSD header decoding
    *************************************************************************/

    /* Byte 0 */
    Csd->CSDStruct = (CSD_Tab[0] & 0xC0) >> 6;
    Csd->Reserved1 =  CSD_Tab[0] & 0x3F;

    /* Byte 1 */
    Csd->TAAC = CSD_Tab[1];

    /* Byte 2 */
    Csd->NSAC = CSD_Tab[2];

    /* Byte 3 */
    Csd->MaxBusClkFrec = CSD_Tab[3];

    /* Byte 4/5 */
    Csd->CardComdClasses = (CSD_Tab[4] << 4) | ((CSD_Tab[5] & 0xF0) >> 4);
    Csd->RdBlockLen = CSD_Tab[5] & 0x0F;

    /* Byte 6 */
    Csd->PartBlockRead   = (CSD_Tab[6] & 0x80) >> 7;
    Csd->WrBlockMisalign = (CSD_Tab[6] & 0x40) >> 6;
    Csd->RdBlockMisalign = (CSD_Tab[6] & 0x20) >> 5;
    Csd->DSRImpl         = (CSD_Tab[6] & 0x10) >> 4;

    /*************************************************************************
      CSD v1/v2 decoding
    *************************************************************************/

    if(!flag_SDHC)
    {
		Csd->version.v1.Reserved1 = ((CSD_Tab[6] & 0x0C) >> 2);

		Csd->version.v1.DeviceSize =  ((CSD_Tab[6] & 0x03) << 10)
								  |  (CSD_Tab[7] << 2)
								  | ((CSD_Tab[8] & 0xC0) >> 6);
		Csd->version.v1.MaxRdCurrentVDDMin = (CSD_Tab[8] & 0x38) >> 3;
		Csd->version.v1.MaxRdCurrentVDDMax = (CSD_Tab[8] & 0x07);
		Csd->version.v1.MaxWrCurrentVDDMin = (CSD_Tab[9] & 0xE0) >> 5;
		Csd->version.v1.MaxWrCurrentVDDMax = (CSD_Tab[9] & 0x1C) >> 2;
		Csd->version.v1.DeviceSizeMul = ((CSD_Tab[9] & 0x03) << 1)
									 |((CSD_Tab[10] & 0x80) >> 7);
    }
    else
    {
		Csd->version.v2.Reserved1 = ((CSD_Tab[6] & 0x0F) << 2) | ((CSD_Tab[7] & 0xC0) >> 6);
		Csd->version.v2.DeviceSize= ((CSD_Tab[7] & 0x3F) << 16) | (CSD_Tab[8] << 8) | CSD_Tab[9];
		Csd->version.v2.Reserved2 = ((CSD_Tab[10] & 0x80) >> 8);
    }

    Csd->EraseSingleBlockEnable = (CSD_Tab[10] & 0x40) >> 6;
    Csd->EraseSectorSize   = ((CSD_Tab[10] & 0x3F) << 1)
                            |((CSD_Tab[11] & 0x80) >> 7);
    Csd->WrProtectGrSize   = (CSD_Tab[11] & 0x7F);
    Csd->WrProtectGrEnable = (CSD_Tab[12] & 0x80) >> 7;
    Csd->Reserved2         = (CSD_Tab[12] & 0x60) >> 5;
    Csd->WrSpeedFact       = (CSD_Tab[12] & 0x1C) >> 2;
    Csd->MaxWrBlockLen     = ((CSD_Tab[12] & 0x03) << 2)
                            |((CSD_Tab[13] & 0xC0) >> 6);
    Csd->WriteBlockPartial = (CSD_Tab[13] & 0x20) >> 5;
    Csd->Reserved3         = (CSD_Tab[13] & 0x1F);
    Csd->FileFormatGrouop  = (CSD_Tab[14] & 0x80) >> 7;
    Csd->CopyFlag          = (CSD_Tab[14] & 0x40) >> 6;
    Csd->PermWrProtect     = (CSD_Tab[14] & 0x20) >> 5;
    Csd->TempWrProtect     = (CSD_Tab[14] & 0x10) >> 4;
    Csd->FileFormat        = (CSD_Tab[14] & 0x0C) >> 2;
    Csd->Reserved4         = (CSD_Tab[14] & 0x03);
    Csd->crc               = (CSD_Tab[15] & 0xFE) >> 1;
    Csd->Reserved5         = (CSD_Tab[15] & 0x01);
#if 0
	if (luat_spitf_cmd(spitf, CMD10, 0, 0))
	{
		goto READ_CONFIG_ERROR;
	}
	if (spitf->SDHCState)
	{
		goto READ_CONFIG_ERROR;
	}
	if (luat_spitf_read_reg(Ctrl, CID_Tab, 18))
	{
		goto READ_CONFIG_ERROR;
	}
    /* Byte 0 */
    Cid->ManufacturerID = CID_Tab[0];

    /* Byte 1 */
    Cid->OEM_AppliID = CID_Tab[1] << 8;

    /* Byte 2 */
    Cid->OEM_AppliID |= CID_Tab[2];

    /* Byte 3 */
    Cid->ProdName1 = CID_Tab[3] << 24;

    /* Byte 4 */
    Cid->ProdName1 |= CID_Tab[4] << 16;

    /* Byte 5 */
    Cid->ProdName1 |= CID_Tab[5] << 8;

    /* Byte 6 */
    Cid->ProdName1 |= CID_Tab[6];

    /* Byte 7 */
    Cid->ProdName2 = CID_Tab[7];

    /* Byte 8 */
    Cid->ProdRev = CID_Tab[8];

    /* Byte 9 */
    Cid->ProdSN = CID_Tab[9] << 24;

    /* Byte 10 */
    Cid->ProdSN |= CID_Tab[10] << 16;

    /* Byte 11 */
    Cid->ProdSN |= CID_Tab[11] << 8;

    /* Byte 12 */
    Cid->ProdSN |= CID_Tab[12];

    /* Byte 13 */
    Cid->Reserved1 |= (CID_Tab[13] & 0xF0) >> 4;
    Cid->ManufactDate = (CID_Tab[13] & 0x0F) << 8;

    /* Byte 14 */
    Cid->ManufactDate |= CID_Tab[14];

    /* Byte 15 */
    Cid->CID_CRC = (CID_Tab[15] & 0xFE) >> 1;
    Cid->Reserved2 = 1;
#endif
    if(flag_SDHC)
    {
		pCardInfo->LogBlockSize = 512;
		pCardInfo->CardBlockSize = 512;
		Temp = 1024 * pCardInfo->LogBlockSize;
		pCardInfo->CardCapacity = (pCardInfo->Csd.version.v2.DeviceSize + 1) * Temp;
		pCardInfo->LogBlockNbr = (pCardInfo->Csd.version.v2.DeviceSize + 1) * 1024;
    }
    else
    {
		pCardInfo->CardCapacity = (pCardInfo->Csd.version.v1.DeviceSize + 1) ;
		pCardInfo->CardCapacity *= (1 << (pCardInfo->Csd.version.v1.DeviceSizeMul + 2));
		pCardInfo->LogBlockSize = 512;
		pCardInfo->CardBlockSize = 1 << (pCardInfo->Csd.RdBlockLen);
		pCardInfo->CardCapacity *= pCardInfo->CardBlockSize;
		pCardInfo->LogBlockNbr = (pCardInfo->CardCapacity) / (pCardInfo->LogBlockSize);
    }
    LLOGD("卡容量 %lluKB", pCardInfo->CardCapacity/1024);
	return;
READ_CONFIG_ERROR:
	spitf->IsInitDone = 0;
	spitf->SDHCError = 1;
	return;
}

static void luat_spitf_read_blocks(luat_spitf_ctrl_t *spitf, uint8_t *Buf, uint32_t StartLBA, uint32_t BlockNums)
{
	uint8_t Retry = 0;
	uint8_t error = 1;
	uint32_t address;
	Buffer_StaticInit(&spitf->DataBuf, Buf, BlockNums);
	s_spitf_force_slow = 0;
	if (spitf->SDSC)
	{
		if (luat_spitf_cmd(spitf, CMD16, 512, 1))
		{
			goto SDHC_SPIREADBLOCKS_ERROR;
		}
	}
SDHC_SPIREADBLOCKS_START:
	if (spitf->SDSC)
	{
		address = (StartLBA + spitf->DataBuf.Pos) * 512;
	}
	else
	{
		address = (StartLBA + spitf->DataBuf.Pos);
	}
	if (luat_spitf_cmd(spitf, CMD18, address, 0))
	{
		goto SDHC_SPIREADBLOCKS_CHECK;
	}
	if (luat_spitf_read_data(spitf))
	{
		luat_spitf_cmd(spitf, CMD12, 0, 1);
		goto SDHC_SPIREADBLOCKS_CHECK;
	}
	for (int i = 0; i < 3; i++)
	{
		if (!luat_spitf_cmd(spitf, CMD12, 0, 1))
		{
			error = 0;
			break;
		}
		else
		{
			spitf->SDHCError = 0;
			spitf->IsInitDone = 1;
			spitf->SDHCState = 0;
		}
	}
SDHC_SPIREADBLOCKS_CHECK:
	if (error)
	{
		LLOGD("read error %x,%u,%u",spitf->SDHCState, spitf->DataBuf.Pos, spitf->DataBuf.MaxLen);
		LLOGE("CMD returned 0x%02x StartLBA=%u address=0x%08x SDSC=%d", spitf->SDHCState, StartLBA, address, spitf->SDSC);
	}
	if (spitf->DataBuf.Pos != spitf->DataBuf.MaxLen)
	{
		Retry++;
		LLOGD("read retry %d,%u,%u,%u", Retry, StartLBA, spitf->DataBuf.Pos, spitf->DataBuf.MaxLen);
		if (Retry > 3)
		{

			spitf->SDHCError = 1;
			goto SDHC_SPIREADBLOCKS_ERROR;
		}
		else
		{
			spitf->SDHCError = 0;
			spitf->IsInitDone = 1;
			spitf->SDHCState = 0;
		}
		goto SDHC_SPIREADBLOCKS_START;
	}
	return;
SDHC_SPIREADBLOCKS_ERROR:
	LLOGD("read error!");
	spitf->IsInitDone = 0;
	spitf->SDHCError = 1;
	return;
}

static void luat_spitf_write_blocks(luat_spitf_ctrl_t *spitf, const uint8_t *Buf, uint32_t StartLBA, uint32_t BlockNums)
{
	uint8_t Retry = 0;
	uint8_t err_Retry = 0;
	uint32_t address;
	Buffer_StaticInit(&spitf->DataBuf, (void *)Buf, BlockNums);
	if (spitf->SDSC)
	{
		if (luat_spitf_cmd(spitf, CMD16, 512, 1))
		{
			goto SDHC_SPIWRITEBLOCKS_ERROR;
		}
	}
SDHC_SPIWRITEBLOCKS_START:
	if (spitf->SDSC)
	{
		address = (StartLBA + spitf->DataBuf.Pos) * 512;
	}
	else
	{
		address = (StartLBA + spitf->DataBuf.Pos);
	}
	if (luat_spitf_cmd(spitf, CMD25, address, 0))
	{
		LLOGE("CMD25 returned 0x%02x StartLBA=%u address=0x%08x SDSC=%d", spitf->SDHCState, StartLBA, address, spitf->SDSC);
		goto SDHC_SPIWRITEBLOCKS_ERROR;
	}
	if (luat_spitf_write_data(spitf))
	{
		goto SDHC_SPIWRITEBLOCKS_ERROR;
	}
	if (spitf->DataBuf.Pos != spitf->DataBuf.MaxLen)
	{
		Retry++;
		LLOGD("write retry %d", Retry);
		if (Retry > 3)
		{
			spitf->SDHCError = 1;
			goto SDHC_SPIWRITEBLOCKS_ERROR;
		}
		goto SDHC_SPIWRITEBLOCKS_START;
	}
	return;
SDHC_SPIWRITEBLOCKS_ERROR:
	luat_spitf_cs(spitf, 0);
	LLOGD("write error!");
	spitf->IsInitDone = 0;
	spitf->SDHCError = 1;
	return;
}

static uint8_t luat_spitf_is_ready(luat_spitf_ctrl_t *spitf)
{

	if (!spitf->SDHCState && spitf->IsInitDone)
	{
		return 1;
	}
	else
	{
		LLOGD("SDHC error, please reboot tf card");
		return 0;
	}
}

static DSTATUS luat_spitf_initialize(void* userdata)
{
	luat_mutex_lock(g_s_spitf.locker);
	luat_spi_lock(g_s_spitf.SpiID);
	luat_spitf_init(&g_s_spitf);
	luat_spi_unlock(g_s_spitf.SpiID);
	luat_mutex_unlock(g_s_spitf.locker);
	return luat_spitf_is_ready(&g_s_spitf)?0:STA_NOINIT;
}

static DSTATUS luat_spitf_status(void* userdata)
{
	return luat_spitf_is_ready(&g_s_spitf)?0:STA_NOINIT;

}

static DRESULT luat_spitf_read(void* userdata, uint8_t* buff, LBA_t sector, UINT count)
{
	luat_mutex_lock(g_s_spitf.locker);
	if (!luat_spitf_is_ready(&g_s_spitf))
	{
		luat_mutex_unlock(g_s_spitf.locker);
		return RES_NOTRDY;
	}
	luat_spi_lock(g_s_spitf.SpiID);
	luat_spitf_read_blocks(&g_s_spitf, buff, sector, count);
	luat_spi_unlock(g_s_spitf.SpiID);
	luat_mutex_unlock(g_s_spitf.locker);
	return luat_spitf_is_ready(&g_s_spitf)?RES_OK:RES_ERROR;
}

static DRESULT luat_spitf_write(void* userdata, const uint8_t* buff, LBA_t sector, UINT count)
{
	luat_mutex_lock(g_s_spitf.locker);
	if (!luat_spitf_is_ready(&g_s_spitf))
	{
		luat_mutex_unlock(g_s_spitf.locker);
		return RES_NOTRDY;
	}
	luat_spi_lock(g_s_spitf.SpiID);
	luat_spitf_write_blocks(&g_s_spitf, buff, sector, count);
	luat_spi_unlock(g_s_spitf.SpiID);
	luat_mutex_unlock(g_s_spitf.locker);
	return luat_spitf_is_ready(&g_s_spitf)?RES_OK:RES_ERROR;
}

static DRESULT luat_spitf_ioctl(void* userdata, uint8_t ctrl, void* buff)
{
	luat_mutex_lock(g_s_spitf.locker);
	if (!luat_spitf_is_ready(&g_s_spitf))
	{
		luat_mutex_unlock(g_s_spitf.locker);
		return RES_NOTRDY;
	}
	luat_spi_lock(g_s_spitf.SpiID);
	luat_spitf_read_config(&g_s_spitf);
	luat_spi_unlock(g_s_spitf.SpiID);
	luat_mutex_unlock(g_s_spitf.locker);
	switch (ctrl) {
		case CTRL_SYNC :		/* Make sure that no pending write process */
			return RES_OK;
			break;

		case GET_SECTOR_COUNT :	/* Get number of sectors on the disk (DWORD) */
			*(uint32_t*)buff = g_s_spitf.Info->LogBlockNbr;
			return RES_OK;
			break;

		case GET_BLOCK_SIZE :	/* Get erase block size in unit of sector (DWORD) */
			*(uint32_t*)buff = 128;
			return RES_OK;
			break;

		default:
			return RES_PARERR;
	}
	return RES_PARERR;
}


const block_disk_opts_t spitf_disk_opts = {
    .initialize = luat_spitf_initialize,
    .status = luat_spitf_status,
    .read = luat_spitf_read,
    .write = luat_spitf_write,
    .ioctl = luat_spitf_ioctl,
};

void luat_spi_set_sdhc_ctrl_default(
		block_disk_t *disk
)
{
	luat_fatfs_spi_t* userdata = disk->userdata;
	if (userdata->type && userdata->spi_device)
	{
		g_s_spitf.CSPin = userdata->spi_device->spi_config.cs;
		g_s_spitf.SpiID = userdata->spi_device->bus_id;
		g_s_spitf.SpiSpeed = userdata->fast_speed;
	}
	else
	{
		g_s_spitf.CSPin = userdata->spi_cs;
		g_s_spitf.SpiID = userdata->spi_id;
		g_s_spitf.SpiSpeed = userdata->fast_speed;
	}
	if (!g_s_spitf.locker)
	{
		g_s_spitf.locker = luat_mutex_create();
	}
	luat_heap_free(disk->userdata);
	disk->userdata = NULL;
	disk->opts = &spitf_disk_opts;
}

#ifndef LUAT_COMPILER_NOWEAK
__attribute__((weak)) void luat_spi_set_sdhc_ctrl(
		block_disk_t *disk)
{
	luat_spi_set_sdhc_ctrl_default(disk);
}
#else
void luat_spi_set_sdhc_ctrl(block_disk_t *disk);
#endif
static block_disk_t disk = {0};

DRESULT diskio_open_spitf(BYTE pdrv, luat_fatfs_spi_t* userdata) {
	// 暂时只支持单个fatfs实例
	disk.opts = &spitf_disk_opts;
	disk.userdata = userdata;
    luat_spi_set_sdhc_ctrl(&disk);
	return diskio_open(pdrv, &disk);
}

//static DWORD get_fattime() {
//	how to get?
//}

//--------------------------------------------------------------------------------------
