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

#define LUAT_LOG_TAG "fatfs"
#include "luat_log.h"

extern BYTE FATFS_DEBUG; // debug log, 0 -- disable , 1 -- enable

/*--------------------------------------------------------------------------

   Module Private Functions

---------------------------------------------------------------------------*/

/* MMC/SD command */
#define CMD0	(0)			/* GO_IDLE_STATE */
#define CMD1	(1)			/* SEND_OP_COND (MMC) */
#define	ACMD41	(0x80+41)	/* SEND_OP_COND (SDC) */
#define CMD8	(8)			/* SEND_IF_COND */
#define CMD9	(9)			/* SEND_CSD */
#define CMD10	(10)		/* SEND_CID */
#define CMD12	(12)		/* STOP_TRANSMISSION */
#define ACMD13	(0x80+13)	/* SD_STATUS (SDC) */
#define CMD16	(16)		/* SET_BLOCKLEN */
#define CMD17	(17)		/* READ_SINGLE_BLOCK */
#define CMD18	(18)		/* READ_MULTIPLE_BLOCK */
#define CMD23	(23)		/* SET_BLOCK_COUNT (MMC) */
#define	ACMD23	(0x80+23)	/* SET_WR_BLK_ERASE_COUNT (SDC) */
#define CMD24	(24)		/* WRITE_BLOCK */
#define CMD25	(25)		/* WRITE_MULTIPLE_BLOCK */
#define CMD32	(32)		/* ERASE_ER_BLK_START */
#define CMD33	(33)		/* ERASE_ER_BLK_END */
#define CMD38	(38)		/* ERASE */
#define CMD55	(55)		/* APP_CMD */
#define CMD58	(58)		/* READ_OCR */

#define SD_ACMD_SD_SEND_OP_COND		  41 /*!< ACMD41*/

/* MMC card type flags (MMC_GET_TYPE) */
#define CT_MMC3		0x01		/* MMC ver 3 */
#define CT_MMC4		0x02		/* MMC ver 4+ */
#define CT_MMC		0x03		/* MMC */
#define CT_SDC1		0x02		/* SDC ver 1 */
#define CT_SDC2		0x04		/* SDC ver 2+ */
#define CT_SDC		0x0C		/* SDC */
#define CT_BLOCK	0x10		/* Block addressing */


static volatile DSTATUS Stat = STA_NOINIT;	/* Physical drive status */

static
BYTE CardType = 0;			/* b0:MMC, b1:SDv1, b2:SDv2, b3:Block addressing */

#define dly_us luat_timer_us_delay
#define dly_ms luat_timer_mdelay

static void spitf_cs_low(luat_fatfs_spi_t* userdata){
	if(userdata->type == 1){
		luat_gpio_set(userdata->spi_device->spi_config.cs, 0);
	}else{
		luat_gpio_set(userdata->spi_cs, 0);
	}
}

static void spitf_cs_high(luat_fatfs_spi_t* userdata){
	if(userdata->type == 1){
		luat_gpio_set(userdata->spi_device->spi_config.cs, 1);
	}else{
		luat_gpio_set(userdata->spi_cs, 1);
	}
}

static void spitf_transfer(const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length,luat_fatfs_spi_t* userdata){
	if(userdata->type == 1){
		luat_spi_device_transfer(userdata->spi_device, send_buf, send_length, recv_buf, recv_length);
	}else{
		luat_spi_transfer(userdata->spi_id, send_buf, send_length, recv_buf, recv_length);
	}
}

static void spitf_send(const char *send_buf, size_t length,luat_fatfs_spi_t* userdata){
	if(userdata->type == 1){
		luat_spi_device_send(userdata->spi_device, send_buf, length);
	}else{
		luat_spi_send(userdata->spi_id, send_buf, length);
	}
}

static void spitf_recv(char *recv_buf, size_t length,luat_fatfs_spi_t* userdata){
	if(userdata->type == 1){
		luat_spi_device_recv(userdata->spi_device, recv_buf, length);
	}else{
		luat_spi_recv(userdata->spi_id, recv_buf, length);
	}
}

static uint8_t spitf_transfer_byte(uint8_t data,luat_fatfs_spi_t* userdata)
{
	uint8_t recv_buf;
	if(userdata->type == 1){
		luat_spi_device_transfer(userdata->spi_device, &data, 1, &recv_buf, 1);
	}else{
		luat_spi_transfer(userdata->spi_id, &data, 1, &recv_buf, 1);
	}
	return recv_buf;
}	  



static uint8_t spitf_crc7(uint8_t * buf, int cnt){
	int i,a;
	uint8_t crc,Data;
	crc=0;
	for (a=0;a<cnt;a++){
		Data=buf[a];
		for (i=0;i<8;i++){
		crc <<= 1;
		if ((Data & 0x80)^(crc & 0x80))
		crc ^=0x09;
		Data <<= 1;
		}
	}
	crc=(crc<<1)|1;
	return(crc);
}

static uint8_t spitf_send_cmd(uint8_t cmd, uint32_t arg, uint8_t cs_high,luat_fatfs_spi_t* userdata){
	uint32_t i = 0x00;
	uint8_t r1;
	spitf_cs_low(userdata);
	userdata->transfer_buf[0] = (cmd | 0x40); /*!< Construct byte 1 */
	userdata->transfer_buf[1] = (uint8_t)(arg >> 24); /*!< Construct byte 2 */
	userdata->transfer_buf[2] = (uint8_t)(arg >> 16); /*!< Construct byte 3 */
	userdata->transfer_buf[3] = (uint8_t)(arg >> 8); /*!< Construct byte 4 */
	userdata->transfer_buf[4] = (uint8_t)(arg); /*!< Construct byte 5 */
	userdata->transfer_buf[5] = spitf_crc7(userdata->transfer_buf,5); /*!< Construct CRC: byte 6 */
	userdata->transfer_buf[6] = 0xFF;
	spitf_send((const char *)(userdata->transfer_buf),7,userdata);

	for (size_t i = 0; i < 10; i++){
		spitf_recv(&r1, 1,userdata);
		if ((r1&0x80) == 0) break;
	}
	if (cs_high){
		spitf_cs_high(userdata);
		userdata->transfer_buf[0] = 0xFF; 
		spitf_send((const char *)(userdata->transfer_buf),1,userdata);
	}
	return r1;
}

/*-----------------------------------------------------------------------*/
/* Transmit bytes to the card (bitbanging)                               */
/*-----------------------------------------------------------------------*/

/* Exchange a byte */
static BYTE xchg_spi (
	BYTE dat,	/* Data to send */
	luat_fatfs_spi_t* userdata
)
{
	BYTE buff;
	spitf_transfer((const char *)&dat, 1, (char *)&buff, 1, userdata);
	return buff;
}



/*-----------------------------------------------------------------------*/
/* Wait for card ready                                                   */
/*-----------------------------------------------------------------------*/

static
int wait_ready (UINT wt,luat_fatfs_spi_t* userdata)	/* 1:OK, 0:Timeout */
{
	BYTE d;
	UINT tmr;

	for (tmr = wt; tmr; tmr--) {	/* Wait for ready in timeout of 500ms */
		d = xchg_spi(0xFF,userdata);
		if (d == 0xFF) break;
		dly_us(1000);
	}

	return (d == 0xFF) ? 1 : 0;
}



/*-----------------------------------------------------------------------*/
/* Deselect the card and release SPI bus                                 */
/*-----------------------------------------------------------------------*/

static
void spi_cs_deselect (luat_fatfs_spi_t* userdata)
{
	if(userdata->type == 1){
		// xchg_spi(userdata);
	}else{
		luat_gpio_set(userdata->spi_cs, 1);
		xchg_spi(0xFF,userdata);	/* Dummy clock (force DO hi-z for multiple slave SPI) */
	}
	
}



/*-----------------------------------------------------------------------*/
/* Select the card and wait for ready                                    */
/*-----------------------------------------------------------------------*/

static
int spi_cs_select (luat_fatfs_spi_t* userdata)	/* 1:OK, 0:Timeout */
{
	if(userdata->type == 1){
		xchg_spi(0xFF,userdata);
	}else{
		luat_gpio_set(userdata->spi_cs, 0);
		xchg_spi(0xFF,userdata);	/* Dummy clock (force DO enabled) */
	}
	
	if (wait_ready(500,userdata)) return 1;	/* Wait for card ready */

	spi_cs_deselect(userdata);
	return 0;			/* Failed */
}


/* Receive multiple byte */
static void rcvr_spi_multi (
	BYTE *buff,		/* Pointer to data buffer */
	UINT btr,		/* Number of bytes to receive (even number) */
	luat_fatfs_spi_t* userdata
)
{
	if(userdata->type == 1){
		luat_spi_device_recv(userdata->spi_device, (char*)buff, btr);
	}else{
		luat_spi_recv(userdata->spi_id, (char*)buff, btr);
	}
}

/* Send multiple byte */
static void xmit_spi_multi (
	const BYTE *buff,	/* Pointer to the data */
	UINT btx,			/* Number of bytes to send (even number) */
	luat_fatfs_spi_t* userdata
)
{
	if(userdata->type == 1){
		luat_spi_device_send(userdata->spi_device, (const char*)buff, btx);
	}else{
		luat_spi_send(userdata->spi_id, (const char*)buff, btx);
	}
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
	BYTE token;
	UINT tmr;


	for (tmr = 2000; tmr; tmr--) {	/* Wait for data packet in timeout of 100ms */
		token = xchg_spi(0xFF,userdata);
		if (token != 0xFF) break;
		dly_us(100);
	}
	if (token != 0xFE) return 0;		/* If not valid data token, return with error */

	rcvr_spi_multi(buff, btr, userdata);			/* Receive the data block into buffer */

	xchg_spi(0xFF,userdata);xchg_spi(0xFF,userdata);					/* Discard CRC */

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
	BYTE resp;
	if (!wait_ready(500,userdata)) return 0;

	xchg_spi(token, userdata);				/* Xmit a token */
	if (token != 0xFD) {		/* Is it data token? */
		xmit_spi_multi(buff, 512, userdata);	/* Data */
		xchg_spi(0xFF, userdata);xchg_spi(0xFF, userdata);/* Dummy CRC */
		resp = xchg_spi(0xFF, userdata);			/* Receive data response */
		if ((resp & 0x1F) != 0x05)	/* If not accepted, return with error */
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
	BYTE n, res;

	if (cmd & 0x80) {	/* ACMD<n> is the command sequense of CMD55-CMD<n> */
		cmd &= 0x7F;
		res = send_cmd(CMD55, 0, userdata);
		if (res > 1) return res;
	}

	/* Select the card and wait for ready except to stop multiple block read */
	if (cmd != CMD12) {
		spi_cs_deselect(userdata);
		if (!spi_cs_select(userdata)) return 0xFF;
	}

	/* Send a command packet */
	xchg_spi((0x40 | cmd),userdata);				/* Start + command index */
	xchg_spi((BYTE)(arg >> 24),userdata);		/* Argument[31..24] */
	xchg_spi((BYTE)(arg >> 16),userdata);		/* Argument[23..16] */
	xchg_spi((BYTE)(arg >> 8),userdata);			/* Argument[15..8] */
	xchg_spi((BYTE)arg,userdata);				/* Argument[7..0] */
	n = 0x01;							/* Dummy CRC + Stop */
	if (cmd == CMD0) n = 0x95;		/* (valid CRC for CMD0(0)) */
	if (cmd == CMD8) n = 0x87;		/* (valid CRC for CMD8(0x1AA)) */
	if (cmd == CMD8 || cmd == CMD10 || cmd == CMD17|| cmd == CMD24) n = 0xFF;
	xchg_spi(n,userdata);

	/* Receive command response */
	if (cmd == CMD12) xchg_spi(0xFF,userdata);	/* Skip a stuff byte when stop reading */
	n = 10;								/* Wait for a valid response in timeout of 10 attempts */
	do
		res = xchg_spi(0xFF,userdata);
	while ((res & 0x80) && --n);

	return res;			/* Return with the response value */
}



/*--------------------------------------------------------------------------

   Public Functions

---------------------------------------------------------------------------*/

static void FCLK_FAST(luat_fatfs_spi_t* userdata){
	if(userdata->type == 1){
		userdata->spi_device->spi_config.bandrate = userdata->fast_speed;
		luat_spi_device_config(userdata->spi_device);
	}else{
		luat_spi_t fatfs_spi_conf = {
			.id = userdata->spi_id,
			.cs = 255,
			.CPHA = 0,
			.CPOL = 0,
			.dataw = 8,
			.bandrate = userdata->fast_speed,
			.bit_dict = 1,
			.master = 1,
			.mode = 0,
		};
		luat_spi_setup(&fatfs_spi_conf);
	}
}

DSTATUS spitf_initialize (
	luat_fatfs_spi_t* userdata
)
{
	DSTATUS ret = 1;
	uint8_t r1 = 0;
	char buf[4] = {0xFF}; 

	CardType = 0;
	spitf_cs_high(userdata);
	for (uint8_t i = 0; i < 10; i++){
		spitf_send(&buf,1,userdata);
	} 
	r1 = spitf_send_cmd(CMD0, 0, 1,userdata);		/* Idle state */
	if (r1 != 0x01) return ret;

	r1 = spitf_send_cmd(CMD8, 0x1AA, 0,userdata); 

	if (r1 == 0x05){		// V1.0 or MMC
		// r1 = spitf_send_cmd(CMD1, 0, 1,userdata); 
		// if (r1 != 0x00) return ret;
	}else if(r1 == 0x01){	// V2.0
		LLOGD("card is V2.0");
		spitf_recv(buf, 4, userdata);
		if (buf[2] == 0x01 && buf[3] == 0xAA) {
			for (size_t i = 0; i < 2000; i++){
				r1 = spitf_send_cmd(CMD55,0, 1,userdata);
				if (r1 != 0x01) continue;
				r1 = spitf_send_cmd(SD_ACMD_SD_SEND_OP_COND,0x40000000, 1,userdata);
				if (r1 == 0x00) break;
				dly_us(1000);
			}
			if (r1 != 0x00) return ret;
			for (size_t i = 0; i < 1000; i++){
				r1 = spitf_send_cmd(CMD58,0, 0,userdata);
				if (r1 == 0x00) break;
				dly_us(1000);
			}
			if (r1 != 0x00) return ret;
			spitf_recv(buf, 4,userdata);
			CardType = (buf[0] & 0x40) ? CT_SDC2 | CT_BLOCK : CT_SDC2;	/* Card id SDv2 */
		}
	}

	// LLOGD("CardType:%d",CardType);
	spi_cs_deselect(userdata);

	if (CardType) {			/* OK */
		FCLK_FAST(userdata);			/* Set fast clock */
		Stat &= ~STA_NOINIT;	/* Clear STA_NOINIT flag */
	} else {			/* Failed */
		Stat = STA_NOINIT;
	}

	return Stat;
}


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
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/


DRESULT spitf_read (
	luat_fatfs_spi_t* userdata,
	BYTE *buff,			/* Pointer to the data buffer to store read data */
	DWORD sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	if (!count) return RES_PARERR;		/* Check parameter */
	if (spitf_status(userdata) & STA_NOINIT) return RES_NOTRDY;	/* Check if drive is ready */

	if (!(CardType & CT_BLOCK)) sector *= 512;	/* Convert LBA to byte address if needed */

	if (count == 1) {	/* Single sector read */
		if ((send_cmd(CMD17,  sector, userdata) == 0)	/* READ_SINGLE_BLOCK */
			&& rcvr_datablock(buff, 512, userdata)) {
			count = 0;
		}
	}
	else {				/* Multiple sector read */
		if (send_cmd(CMD18,  sector, userdata) == 0) {	/* READ_MULTIPLE_BLOCK */
			do {
				if (!rcvr_datablock(buff, 512, userdata)) break;
				buff += 512;
			} while (--count);
			send_cmd(CMD12, 0, userdata);				/* STOP_TRANSMISSION */
		}
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
	if (!count) return RES_PARERR;		/* Check parameter */
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
	DWORD st, ed, csize;
	LBA_t *dp;

	if (spitf_status(userdata) & STA_NOINIT) return RES_NOTRDY;	/* Check if card is in the socket */

	res = RES_ERROR;

	switch (ctrl) {
		case CTRL_SYNC :		/* Make sure that no pending write process */
			if (spi_cs_select(userdata)) res = RES_OK;
			break;

		case GET_SECTOR_COUNT :	/* Get number of sectors on the disk (DWORD) */
			if ((send_cmd(CMD9, 0, userdata) == 0) && rcvr_datablock(csd, 16, userdata)) {
				if ((csd[0] >> 6) == 1) {	/* SDC ver 2.00 */
					csize = csd[9] + ((WORD)csd[8] << 8) + ((DWORD)(csd[7] & 63) << 16) + 1;
					*(DWORD*)buff = csize << 10;
				} else {					/* SDC ver 1.XX or MMC */
					n = (csd[5] & 15) + ((csd[10] & 128) >> 7) + ((csd[9] & 3) << 1) + 2;
					csize = (csd[8] >> 6) + ((WORD)csd[7] << 2) + ((WORD)(csd[6] & 3) << 10) + 1;
					*(DWORD*)buff = csize << (n - 9);
				}
				res = RES_OK;
			}
			break;

		case GET_BLOCK_SIZE :	/* Get erase block size in unit of sector (DWORD) */
			if (CardType & CT_SDC2) {	/* SDC ver 2+ */
				if (send_cmd(ACMD13, 0, userdata) == 0) {	/* Read SD status */
					xchg_spi(0xFF, userdata);
					if (rcvr_datablock(csd, 16, userdata)) {				/* Read partial block */
						for (n = 64 - 16; n; n--) xchg_spi(0xFF, userdata);	/* Purge trailing data */
						*(DWORD*)buff = 16UL << (csd[10] >> 4);
						res = RES_OK;
					}
				}
			} else {					/* SDC ver 1 or MMC */
				if ((send_cmd(CMD9, 0, userdata) == 0) && rcvr_datablock(csd, 16, userdata)) {	/* Read CSD */
					if (CardType & CT_SDC1) {	/* SDC ver 1.XX */
						*(DWORD*)buff = (((csd[10] & 63) << 1) + ((WORD)(csd[11] & 128) >> 7) + 1) << ((csd[13] >> 6) - 1);
					} else {					/* MMC */
						*(DWORD*)buff = ((WORD)((csd[10] & 124) >> 2) + 1) * (((csd[11] & 3) << 3) + ((csd[11] & 224) >> 5) + 1);
					}
					res = RES_OK;
				}
			}
			break;

		case CTRL_TRIM :	/* Erase a block of sectors (used when _USE_ERASE == 1) */
			if (!(CardType & CT_SDC)) break;				/* Check if the card is SDC */
			if (disk_ioctl(0, MMC_GET_CSD, csd)) break;	/* Get CSD */
			if (!(csd[10] & 0x40)) break;					/* Check if ERASE_BLK_EN = 1 */
			dp = buff; st = (DWORD)dp[0]; ed = (DWORD)dp[1];	/* Load sector block */
			if (!(CardType & CT_BLOCK)) {
				st *= 512; ed *= 512;
			}
			if (send_cmd(CMD32, st, userdata) == 0 && send_cmd(CMD33, ed, userdata) == 0 && send_cmd(CMD38, 0, userdata) == 0 && wait_ready(30000,userdata)) {	/* Erase sector block */
				res = RES_OK;	/* FatFs does not check result of this command */
			}
			break;

		/* Following commands are never used by FatFs module */

		case MMC_GET_TYPE:		/* Get MMC/SDC type (BYTE) */
			*(BYTE*)buff = CardType;
			res = RES_OK;
			break;

		case MMC_GET_CSD:		/* Read CSD (16 bytes) */
			if (send_cmd(CMD9, 0, userdata) == 0 && rcvr_datablock((BYTE*)buff, 16, userdata)) {	/* READ_CSD */
				res = RES_OK;
			}
			break;

		case MMC_GET_CID:		/* Read CID (16 bytes) */
			if (send_cmd(CMD10, 0, userdata) == 0 && rcvr_datablock((BYTE*)buff, 16, userdata)) {	/* READ_CID */
				res = RES_OK;
			}
			break;

		case MMC_GET_OCR:		/* Read OCR (4 bytes) */
			if (send_cmd(CMD58, 0, userdata) == 0) {	/* READ_OCR */
				for (n = 0; n < 4; n++) *(((BYTE*)buff) + n) = xchg_spi(0xFF, userdata);
				res = RES_OK;
			}
			break;

		case MMC_GET_SDSTAT:	/* Read SD status (64 bytes) */
			if (send_cmd(ACMD13, 0, userdata) == 0) {	/* SD_STATUS */
				xchg_spi(0xFF, userdata);
				if (rcvr_datablock((BYTE*)buff, 64, userdata)) res = RES_OK;
			}
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

__attribute__((weak)) void luat_spi_set_sdhc_ctrl(
		block_disk_t *disk)
{

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

