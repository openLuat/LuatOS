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
#include "luat_malloc.h"
#include "lauxlib.h"

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */
#include "c_common.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#define LUAT_LOG_TAG "SPI_TF"
#include "luat_log.h"


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

#define SPI_TF_WRITE_TO_MS	(100)
#define SPI_TF_READ_TO_MS	(100)

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
	uint8_t IsCRCCheck;
	uint8_t SDHCError;
	uint8_t SPIError;
	uint8_t ExternResult[8];
	uint8_t ExternLen;
	uint8_t SDSC;
}luat_spitf_ctrl_t;

#define SPI_TF_WAIT(x) luat_rtos_task_sleep(x)

static luat_spitf_ctrl_t g_s_spitf;
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
	uint64_t OpEndTick;
	uint8_t i, TxLen, DummyLen;
	int32_t Result = -ERROR_OPERATION_FAILED;
	luat_spitf_cs(spitf, 1);
	spitf->TempData[0] = 0x40|Cmd;
	BytesPutBe32(spitf->TempData + 1, Arg);
	spitf->TempData[5] = CRC7(spitf->TempData, 5);

	memset(spitf->TempData + 6, 0xff, 8);
	TxLen = 14;


	spitf->SPIError = 0;
	spitf->SDHCError = 0;
	luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, TxLen, (char *)spitf->TempData, TxLen);

	for(i = 7; i < TxLen; i++)
	{
		if (spitf->TempData[i] != 0xff)
		{
			spitf->SDHCState = spitf->TempData[i];
			if ((spitf->SDHCState == !spitf->IsInitDone) || !spitf->SDHCState)
			{
				Result = ERROR_NONE;
			}
			DummyLen = TxLen - i - 1;
			memcpy(spitf->ExternResult, &spitf->TempData[i + 1], DummyLen);
			spitf->ExternLen = DummyLen;
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
	uint16_t i,findResult,offset;
	spitf->SPIError = 0;
	spitf->SDHCError = 0;
	OpEndTick = luat_mcu_tick64_ms() + SPI_TF_READ_TO_MS * 4;
	findResult = 0;
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
	uint8_t *pBuf;
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

static int32_t luat_spitf_read_data(luat_spitf_ctrl_t *spitf)
{
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
//		if (spitf->IsCRCCheck)
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
	uint8_t i;
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
	spitf->IsInitDone = 0;
	spitf->SDHCState = 0xff;
	spitf->Info->CardCapacity = 0;
	spitf->WriteWaitCnt = 80;
	luat_gpio_set(spitf->CSPin, 0);
	luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, 40, (char *)spitf->TempData, 40);
	luat_gpio_set(spitf->CSPin, 1);
	memset(spitf->TempData, 0xff, 40);
	luat_spi_transfer(spitf->SpiID, (const char *)spitf->TempData, 40, (char *)spitf->TempData, 40);
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
	uint8_t CID_Tab[18];
	SD_CSD* Csd = &spitf->Info->Csd;
	SD_CID* Cid = &spitf->Info->Cid;
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
	uint32_t address;
	Buffer_StaticInit(&spitf->DataBuf, Buf, BlockNums);
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

static DSTATUS luat_spitf_initialize(luat_fatfs_spi_t* userdata)
{
	luat_mutex_lock(g_s_spitf.locker);
	luat_spitf_init(&g_s_spitf);
	luat_mutex_unlock(g_s_spitf.locker);
	return luat_spitf_is_ready(&g_s_spitf)?0:STA_NOINIT;
}

static DSTATUS luat_spitf_status(luat_fatfs_spi_t* userdata)
{
	return luat_spitf_is_ready(&g_s_spitf)?0:STA_NOINIT;
}

static DRESULT luat_spitf_read(luat_fatfs_spi_t* userdata, uint8_t* buff, uint32_t sector, uint32_t count)
{
	luat_mutex_lock(g_s_spitf.locker);
	if (!luat_spitf_is_ready(&g_s_spitf))
	{
		luat_mutex_unlock(g_s_spitf.locker);
		return RES_NOTRDY;
	}
	luat_spitf_read_blocks(&g_s_spitf, buff, sector, count);
	luat_mutex_unlock(g_s_spitf.locker);
	return luat_spitf_is_ready(&g_s_spitf)?RES_OK:RES_ERROR;
}

static DRESULT luat_spitf_write(luat_fatfs_spi_t* userdata, const uint8_t* buff, uint32_t sector, uint32_t count)
{
	luat_mutex_lock(g_s_spitf.locker);
	if (!luat_spitf_is_ready(&g_s_spitf))
	{
		luat_mutex_unlock(g_s_spitf.locker);
		return RES_NOTRDY;
	}
	luat_spitf_write_blocks(&g_s_spitf, buff, sector, count);
	luat_mutex_unlock(g_s_spitf.locker);
	return luat_spitf_is_ready(&g_s_spitf)?RES_OK:RES_ERROR;
}

static DRESULT luat_spitf_ioctl(luat_fatfs_spi_t* userdata, uint8_t ctrl, void* buff)
{
	luat_mutex_lock(g_s_spitf.locker);
	if (!luat_spitf_is_ready(&g_s_spitf))
	{
		luat_mutex_unlock(g_s_spitf.locker);
		return RES_NOTRDY;
	}
	luat_spitf_read_config(&g_s_spitf);
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

__attribute__((weak)) void luat_spi_set_sdhc_ctrl(
		block_disk_t *disk)
{
	luat_fatfs_spi_t* userdata = disk->userdata;
	if (userdata->type)
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
	g_s_spitf.locker = luat_mutex_create();
	luat_heap_free(disk->userdata);
	disk->userdata = NULL;
	disk->opts = &spitf_disk_opts;
}

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

