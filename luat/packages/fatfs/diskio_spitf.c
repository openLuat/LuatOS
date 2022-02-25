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
#include "lauxlib.h"

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

#define LUAT_LOG_TAG "luat.fatfs"
#include "luat_log.h"

// 与 diskio_spitf.c 对齐
typedef struct luat_fatfs_spi
{
	uint8_t type;
	uint8_t spi_id;
	uint8_t spi_cs;
	uint8_t nop;
	luat_spi_device_t * spi_device;
}luat_fatfs_spi_t;

extern BYTE FATFS_DEBUG; // debug log, 0 -- disable , 1 -- enable

/*--------------------------------------------------------------------------

   Module Private Functions

---------------------------------------------------------------------------*/

/* MMC/SD command (SPI mode) */
#define CMD0	(0)			/* GO_IDLE_STATE */
#define CMD1	(1)			/* SEND_OP_COND */
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


static
DSTATUS Stat = STA_NOINIT;	/* Disk status */

static
BYTE CardType;			/* b0:MMC, b1:SDv1, b2:SDv2, b3:Block addressing */


// static void dly_us(BYTE us) {
// 	if (us < 1) {
// 		return;
// 	}
// 	us += 999;
// 	luat_timer_mdelay(us/1000);
// }
#define dly_us luat_timer_us_delay

/*-----------------------------------------------------------------------*/
/* Transmit bytes to the card (bitbanging)                               */
/*-----------------------------------------------------------------------*/

static
void xmit_mmc (
	const BYTE* buff,	/* Data to be sent */
	UINT bc,				/* Number of bytes to send */
	luat_fatfs_spi_t* userdata
)
{
	#if 0
	BYTE d;


	do {
		d = *buff++;	/* Get a byte to be sent */
		if (d & 0x80) DI_H(); else DI_L();	/* bit7 */
		CK_H(); CK_L();
		if (d & 0x40) DI_H(); else DI_L();	/* bit6 */
		CK_H(); CK_L();
		if (d & 0x20) DI_H(); else DI_L();	/* bit5 */
		CK_H(); CK_L();
		if (d & 0x10) DI_H(); else DI_L();	/* bit4 */
		CK_H(); CK_L();
		if (d & 0x08) DI_H(); else DI_L();	/* bit3 */
		CK_H(); CK_L();
		if (d & 0x04) DI_H(); else DI_L();	/* bit2 */
		CK_H(); CK_L();
		if (d & 0x02) DI_H(); else DI_L();	/* bit1 */
		CK_H(); CK_L();
		if (d & 0x01) DI_H(); else DI_L();	/* bit0 */
		CK_H(); CK_L();
	} while (--bc);
	#endif
	if (FATFS_DEBUG)
		LLOGD("[FatFS]xmit_mmc bc=%d\r\n", bc);
	if(userdata->type == 1){
		luat_spi_device_send(userdata->spi_device, (char*)buff, bc);
	}else{
		luat_spi_send(userdata->spi_id, (const char*)buff, bc);
	}
	
}



/*-----------------------------------------------------------------------*/
/* Receive bytes from the card (bitbanging)                              */
/*-----------------------------------------------------------------------*/

static
void rcvr_mmc (
	BYTE *buff,	/* Pointer to read buffer */
	UINT bc,		/* Number of bytes to receive */
	luat_fatfs_spi_t* userdata
)
{
	#if 0
	BYTE r;


	DI_H();	/* Send 0xFF */

	do {
		r = 0;	 if (DO) r++;	/* bit7 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit6 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit5 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit4 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit3 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit2 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit1 */
		CK_H(); CK_L();
		r <<= 1; if (DO) r++;	/* bit0 */
		CK_H(); CK_L();
		*buff++ = r;			/* Store a received byte */
	} while (--bc);
	#endif
	//u8* buf2 = 0x00;
	//u8** buf = &buf2;
	// BYTE tmp[bc];
	
	// for(size_t i = 0; i < bc; i++)
	// {
	// 	tmp[i] = 0xFF;
	// }
	
	//DWORD t = luat_spi_transfer(userdata->spi_id, tmp, buff, bc);
	//s32 t = platform_spi_recv(0, buf, bc);
	if(userdata->type == 1){
		luat_spi_device_recv(userdata->spi_device, (char*)buff, bc);
	}else{
		luat_spi_recv(userdata->spi_id, (char*)buff, bc);
	}
		
	//memcpy(buff, buf2, bc);
	//if (FATFS_DEBUG)
	//	LLOGD("[FatFS]rcvr_mmc first resp byte=%02X, t=%d\r\n", buf2[0], t);
	//free(buf2);
}



/*-----------------------------------------------------------------------*/
/* Wait for card ready                                                   */
/*-----------------------------------------------------------------------*/

static
int wait_ready (luat_fatfs_spi_t* userdata)	/* 1:OK, 0:Timeout */
{
	BYTE d;
	UINT tmr;


	for (tmr = 5000; tmr; tmr--) {	/* Wait for ready in timeout of 500ms */
		rcvr_mmc(&d, 1, userdata);
		if (d == 0xFF) break;
		dly_us(100);
	}

	return tmr ? 1 : 0;
}



/*-----------------------------------------------------------------------*/
/* Deselect the card and release SPI bus                                 */
/*-----------------------------------------------------------------------*/

static
void spi_cs_deselect (luat_fatfs_spi_t* userdata)
{
	BYTE d;

	//CS_H();				/* Set CS# high */
	//platform_pio_op(0, 1 << userdata->spi_cs, 0);
	if(userdata->type == 1){
		// rcvr_mmc(&d, 1);
	}else{
		luat_gpio_set(userdata->spi_cs, 1);
		rcvr_mmc(&d, 1, userdata);	/* Dummy clock (force DO hi-z for multiple slave SPI) */
	}
	
}



/*-----------------------------------------------------------------------*/
/* Select the card and wait for ready                                    */
/*-----------------------------------------------------------------------*/

static
int spi_cs_select (luat_fatfs_spi_t* userdata)	/* 1:OK, 0:Timeout */
{
	BYTE d;

	//CS_L();				/* Set CS# low */
	//platform_pio_op(0, 1 << userdata->spi_cs, 1);
	if(userdata->type == 1){
		rcvr_mmc(&d, 1, userdata);
	}else{
		luat_gpio_set(userdata->spi_cs, 0);
		rcvr_mmc(&d, 1, userdata);	/* Dummy clock (force DO enabled) */
	}
	
	if (wait_ready(userdata)) return 1;	/* Wait for card ready */

	spi_cs_deselect(userdata);
	return 0;			/* Failed */
}



/*-----------------------------------------------------------------------*/
/* Receive a data packet from the card                                   */
/*-----------------------------------------------------------------------*/

static
int rcvr_datablock (	/* 1:OK, 0:Failed */
	BYTE *buff,			/* Data buffer to store received data */
	UINT btr,			/* Byte count */
	luat_fatfs_spi_t* userdata
)
{
	BYTE d[2];
	UINT tmr;


	for (tmr = 1000; tmr; tmr--) {	/* Wait for data packet in timeout of 100ms */
		rcvr_mmc(d, 1, userdata);
		if (d[0] != 0xFF) break;
		dly_us(100);
	}
	if (d[0] != 0xFE) return 0;		/* If not valid data token, return with error */

	rcvr_mmc(buff, btr, userdata);			/* Receive the data block into buffer */
	rcvr_mmc(d, 2, userdata);					/* Discard CRC */

	return 1;						/* Return with success */
}



/*-----------------------------------------------------------------------*/
/* Send a data packet to the card                                        */
/*-----------------------------------------------------------------------*/

static
int xmit_datablock (	/* 1:OK, 0:Failed */
	const BYTE *buff,	/* 512 byte data block to be transmitted */
	BYTE token,			/* Data/Stop token */
	luat_fatfs_spi_t* userdata
)
{
	BYTE d[2];


	if (!wait_ready(userdata)) return 0;

	d[0] = token;
	xmit_mmc(d, 1, userdata);				/* Xmit a token */
	if (token != 0xFD) {		/* Is it data token? */
		xmit_mmc(buff, 512, userdata);	/* Xmit the 512 byte data block to MMC */
		rcvr_mmc(d, 2, userdata);			/* Xmit dummy CRC (0xFF,0xFF) */
		rcvr_mmc(d, 1, userdata);			/* Receive data response */
		if ((d[0] & 0x1F) != 0x05)	/* If not accepted, return with error */
			return 0;
	}

	return 1;
}



/*-----------------------------------------------------------------------*/
/* Send a command packet to the card                                     */
/*-----------------------------------------------------------------------*/

static
BYTE send_cmd (		/* Returns command response (bit7==1:Send failed)*/
	BYTE cmd,		/* Command byte */
	DWORD arg,		/* Argument */
	luat_fatfs_spi_t* userdata
)
{
	BYTE n, d, buf[6];


	if (cmd & 0x80) {	/* ACMD<n> is the command sequense of CMD55-CMD<n> */
		cmd &= 0x7F;
		n = send_cmd(CMD55, 0, userdata);
		if (n > 1) return n;
	}

	/* Select the card and wait for ready except to stop multiple block read */
	if (cmd != CMD12) {
		spi_cs_deselect(userdata);
		if (!spi_cs_select(userdata)) return 0xFF;
	}

	/* Send a command packet */
	buf[0] = 0x40 | cmd;			/* Start + Command index */
	buf[1] = (BYTE)(arg >> 24);		/* Argument[31..24] */
	buf[2] = (BYTE)(arg >> 16);		/* Argument[23..16] */
	buf[3] = (BYTE)(arg >> 8);		/* Argument[15..8] */
	buf[4] = (BYTE)arg;				/* Argument[7..0] */
	n = 0x01;						/* Dummy CRC + Stop */
	if (cmd == CMD0) n = 0x95;		/* (valid CRC for CMD0(0)) */
	if (cmd == CMD8) n = 0x87;		/* (valid CRC for CMD8(0x1AA)) */
	buf[5] = n;
	xmit_mmc(buf, 6, userdata);

	/* Receive command response */
	if (cmd == CMD12) rcvr_mmc(&d, 1, userdata);	/* Skip a stuff byte when stop reading */
	n = 10;								/* Wait for a valid response in timeout of 10 attempts */
	do
		rcvr_mmc(&d, 1, userdata);
	while ((d & 0x80) && --n);

	return d;			/* Return with the response value */
}



/*--------------------------------------------------------------------------

   Public Functions

---------------------------------------------------------------------------*/


/*-----------------------------------------------------------------------*/
/* Get Disk Status                                                       */
/*-----------------------------------------------------------------------*/

DSTATUS spitf_status (
	luat_fatfs_spi_t* userdata
)
{
	//if (drv) return STA_NOINIT;

	return Stat;
}



/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/

DSTATUS spitf_initialize (
	luat_fatfs_spi_t* userdata
)
{
	BYTE n, ty, cmd, buf[4];
	UINT tmr;
	DSTATUS s;


	//if (drv) return RES_NOTRDY;

	//dly_us(10000);			/* 10ms */
	//CS_INIT(); CS_H();		/* Initialize port pin tied to CS */
	//CK_INIT(); CK_L();		/* Initialize port pin tied to SCLK */
	//DI_INIT();				/* Initialize port pin tied to DI */
	//DO_INIT();				/* Initialize port pin tied to DO */

	//luat_spi_close(userdata->spi_id);
	//luat_spi_setup(userdata->spi_id, 400*1000/*400khz*/, 0, 0, 8, 1, 1);

	spi_cs_deselect(userdata);

	for (n = 10; n; n--) rcvr_mmc(buf, 1, userdata);	/* Apply 80 dummy clocks and the card gets ready to receive command */

	ty = 0;
	if (send_cmd(CMD0, 0, userdata) == 1) {			/* Enter Idle state */
		if (send_cmd(CMD8, 0x1AA, userdata) == 1) {	/* SDv2? */
			rcvr_mmc(buf, 4, userdata);							/* Get trailing return value of R7 resp */
			if (buf[2] == 0x01 && buf[3] == 0xAA) {		/* The card can work at vdd range of 2.7-3.6V */
				for (tmr = 1000; tmr; tmr--) {			/* Wait for leaving idle state (ACMD41 with HCS bit) */
					if (send_cmd(ACMD41, 1UL << 30, userdata) == 0) break;
					dly_us(1000);
				}
				if (tmr && send_cmd(CMD58, 0, userdata) == 0) {	/* Check CCS bit in the OCR */
					rcvr_mmc(buf, 4, userdata);
					ty = (buf[0] & 0x40) ? CT_SD2 | CT_BLOCK : CT_SD2;	/* SDv2 */
				}
			}
		} else {							/* SDv1 or MMCv3 */
			if (send_cmd(ACMD41, 0, userdata) <= 1) 	{
				ty = CT_SD1; cmd = ACMD41;	/* SDv1 */
			} else {
				ty = CT_MMC; cmd = CMD1;	/* MMCv3 */
			}
			for (tmr = 1000; tmr; tmr--) {			/* Wait for leaving idle state */
				if (send_cmd(cmd, 0, userdata) == 0) break;
				dly_us(1000);
			}
			if (!tmr || send_cmd(CMD16, 512, userdata) != 0)	/* Set R/W block length to 512 */
				ty = 0;
		}
	}
	CardType = ty;
	s = ty ? 0 : STA_NOINIT;
	Stat = s;

	spi_cs_deselect(userdata);

	//luat_spi_close(userdata->spi_id);
	//spi.setup(id,0,0,8,400*1000,1)
	//luat_spi_setup(userdata->spi_id, 1000*1000/*1Mhz*/, 0, 0, 8, 1, 1);

	return s;
}



/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/

DRESULT spitf_read (
	luat_fatfs_spi_t* userdata,
	BYTE *buff,			/* Pointer to the data buffer to store read data */
	DWORD sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	BYTE cmd;


	if (spitf_status(userdata) & STA_NOINIT) return RES_NOTRDY;
	if (!(CardType & CT_BLOCK)) sector *= 512;	/* Convert LBA to byte address if needed */

	cmd = count > 1 ? CMD18 : CMD17;			/*  READ_MULTIPLE_BLOCK : READ_SINGLE_BLOCK */
	if (send_cmd(cmd, sector, userdata) == 0) {
		do {
			if (!rcvr_datablock(buff, 512, userdata)) break;
			buff += 512;
		} while (--count);
		if (cmd == CMD18) send_cmd(CMD12, 0, userdata);	/* STOP_TRANSMISSION */
	}
	spi_cs_deselect(userdata);

	return count ? RES_ERROR : RES_OK;
}



/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/

DRESULT spitf_write (
	luat_fatfs_spi_t* userdata,
	const BYTE *buff,	/* Pointer to the data to be written */
	DWORD sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	if (spitf_status(userdata) & STA_NOINIT) return RES_NOTRDY;
	if (!(CardType & CT_BLOCK)) sector *= 512;	/* Convert LBA to byte address if needed */

	if (count == 1) {	/* Single block write */
		if ((send_cmd(CMD24, sector, userdata) == 0)	/* WRITE_BLOCK */
			&& xmit_datablock(buff, 0xFE, userdata))
			count = 0;
	}
	else {				/* Multiple block write */
		if (CardType & CT_SDC) send_cmd(ACMD23, count, userdata);
		if (send_cmd(CMD25, sector, userdata) == 0) {	/* WRITE_MULTIPLE_BLOCK */
			do {
				if (!xmit_datablock(buff, 0xFC, userdata)) break;
				buff += 512;
			} while (--count);
			if (!xmit_datablock(0, 0xFD, userdata))	/* STOP_TRAN token */
				count = 1;
		}
	}
	spi_cs_deselect(userdata);

	return count ? RES_ERROR : RES_OK;
}


/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                               */
/*-----------------------------------------------------------------------*/

DRESULT spitf_ioctl (
	luat_fatfs_spi_t* userdata,
	BYTE ctrl,		/* Control code */
	void *buff		/* Buffer to send/receive control data */
)
{
	DRESULT res;
	BYTE n, csd[16];
	DWORD cs;


	if (spitf_status(userdata) & STA_NOINIT) return RES_NOTRDY;	/* Check if card is in the socket */

	res = RES_ERROR;
	switch (ctrl) {
		case CTRL_SYNC :		/* Make sure that no pending write process */
			if (spi_cs_select(userdata)) res = RES_OK;
			break;

		case GET_SECTOR_COUNT :	/* Get number of sectors on the disk (DWORD) */
			if ((send_cmd(CMD9, 0, userdata) == 0) && rcvr_datablock(csd, 16, userdata)) {
				if ((csd[0] >> 6) == 1) {	/* SDC ver 2.00 */
					cs = csd[9] + ((WORD)csd[8] << 8) + ((DWORD)(csd[7] & 63) << 16) + 1;
					*(DWORD*)buff = cs << 10;
				} else {					/* SDC ver 1.XX or MMC */
					n = (csd[5] & 15) + ((csd[10] & 128) >> 7) + ((csd[9] & 3) << 1) + 2;
					cs = (csd[8] >> 6) + ((WORD)csd[7] << 2) + ((WORD)(csd[6] & 3) << 10) + 1;
					*(DWORD*)buff = cs << (n - 9);
				}
				res = RES_OK;
			}
			break;

		case GET_BLOCK_SIZE :	/* Get erase block size in unit of sector (DWORD) */
			*(DWORD*)buff = 128;
			res = RES_OK;
			break;

		default:
			res = RES_PARERR;
	}

	spi_cs_deselect(userdata);

	return res;
}

// DSTATUS spitf_initialize (luat_fatfs_spi_t* userdata);
// DSTATUS ramdisk_status (luat_fatfs_spi_t* userdata);
// DRESULT ramdisk_read (luat_fatfs_spi_t* userdata, BYTE* buff, LBA_t sector, UINT count);
// DRESULT ramdisk_write (luat_fatfs_spi_t* userdata, const BYTE* buff, LBA_t sector, UINT count);
// DRESULT ramdisk_ioctl (luat_fatfs_spi_t* userdata, BYTE cmd, void* buff);

const block_disk_opts_t spitf_disk_opts = {
    .initialize = spitf_initialize,
    .status = spitf_status,
    .read = spitf_read,
    .write = spitf_write,
    .ioctl = spitf_ioctl,
};

static block_disk_t disk = {0};

DRESULT diskio_open_spitf(BYTE pdrv, luat_fatfs_spi_t* userdata) {
	// 暂时只支持单个fatfs实例
	disk.opts = &spitf_disk_opts;
    disk.userdata = userdata;
	return diskio_open(pdrv, &disk);
}

//static DWORD get_fattime() {
//	how to get?
//}

//--------------------------------------------------------------------------------------

