#include "EPD_1in54_V3.h"
#include "Debug.h"
void lut_bw(void);

/******************************************************************************
function :	Software reset
parameter:
******************************************************************************/
static void EPD_1IN54_V3_Reset(void)
{
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(200);
    DEV_Digital_Write(EPD_RST_PIN, 0);
    DEV_Delay_ms(10);
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(200);
}

/******************************************************************************
function :	send command
parameter:
     Reg : Command register
******************************************************************************/
static void EPD_1IN54_V3_SendCommand(UBYTE Reg)
{
    DEV_Digital_Write(EPD_DC_PIN, 0);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(Reg);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

/******************************************************************************
function :	send data
parameter:
    Data : Write data
******************************************************************************/
static void EPD_1IN54_V3_SendData(UBYTE Data)
{
    DEV_Digital_Write(EPD_DC_PIN, 1);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(Data);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

/******************************************************************************
function :	Wait until the busy_pin goes LOW
parameter:
******************************************************************************/
static void EPD_1IN54_V3_ReadBusy(void)
{
    unsigned char count = 100;
    Debug("e-Paper busy\r\n");
    while(DEV_Digital_Read(EPD_BUSY_PIN) == 0) {      //0:BUSY,1:FREE
        if(!(count--))
        {
            Debug("error: e-Paper busy timeout!!!\r\n");
            break;
        }
        else
            DEV_Delay_ms(100);
    }
    Debug("e-Paper busy release\r\n");
}

/******************************************************************************
function :	Turn On Display full
parameter:
******************************************************************************/
static void EPD_1IN54_V3_TurnOnDisplay(void)
{
    EPD_1IN54_V3_SendCommand(0xE0);     //cascade setting
    EPD_1IN54_V3_SendData(0x01);

    EPD_1IN54_V3_SendCommand(0x12);     //DISPLAY REFRESH
    DEV_Delay_ms(100);          //!!!The delay here is necessary, 200uS at least!!!
    EPD_1IN54_V3_ReadBusy();
}

/******************************************************************************
function :	Turn On Display part
parameter:
******************************************************************************/
static void EPD_1IN54_V3_TurnOnDisplayPart(void)
{
    //不支持局刷好像
    EPD_1IN54_V3_TurnOnDisplay();
}

/******************************************************************************
function :	Initialize the e-Paper register
parameter:
******************************************************************************/
void EPD_1IN54_V3_Init(UBYTE mode)
{
    EPD_1IN54_V3_Reset();

    EPD_1IN54_V3_SendCommand(0x01); //power setting
    EPD_1IN54_V3_SendData(0xC7);
    EPD_1IN54_V3_SendData(0x00);
    EPD_1IN54_V3_SendData(0x0D);
    EPD_1IN54_V3_SendData(0x00);

    EPD_1IN54_V3_SendCommand(0x04);
    EPD_1IN54_V3_ReadBusy();

    EPD_1IN54_V3_SendCommand(0x00);     //panel setting
    EPD_1IN54_V3_SendData(0xDf);    //df-bw cf-r

    EPD_1IN54_V3_SendCommand(0X50);     //VCOM AND DATA INTERVAL SETTING
    EPD_1IN54_V3_SendData(0x77);    //WBmode:VBDF 17|D7 VBDW 97 VBDB 57   WBRmode:VBDF F7 VBDW 77 VBDB 37  VBDR B7

    EPD_1IN54_V3_SendCommand(0x30);     //PLL setting
    EPD_1IN54_V3_SendData(0x2A);

    EPD_1IN54_V3_SendCommand(0x61);     //resolution setting
    EPD_1IN54_V3_SendData(0xC8);
    EPD_1IN54_V3_SendData(0x00);
    EPD_1IN54_V3_SendData(0xC8);

    EPD_1IN54_V3_SendCommand(0x82);     //vcom setting
    EPD_1IN54_V3_SendData(0x0A);

    lut_bw();
}

//2s
const unsigned char EPD_1IN54_V3_lut_vcom0[] ={0x02  ,0x03 ,0x03 ,0x08 ,0x08 ,0x03 ,0x05 ,0x05 ,0x03 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 };
const unsigned char EPD_1IN54_V3_lut_w[] ={  0x42  ,0x43 ,0x03 ,0x48 ,0x88 ,0x03 ,0x85 ,0x08 ,0x03 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 };
const unsigned char EPD_1IN54_V3_lut_b[] ={  0x82  ,0x83 ,0x03 ,0x48 ,0x88 ,0x03 ,0x05 ,0x45 ,0x03 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 };
const unsigned char EPD_1IN54_V3_lut_g1[] ={ 0x82  ,0x83 ,0x03 ,0x48 ,0x88 ,0x03 ,0x05 ,0x45 ,0x03 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 };
const unsigned char EPD_1IN54_V3_lut_g2[] ={ 0x82  ,0x83 ,0x03 ,0x48 ,0x88 ,0x03 ,0x05 ,0x45 ,0x03 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 ,0x00 };
void lut_bw(void)
{
    unsigned int count;
    EPD_1IN54_V3_SendCommand(0x20);
    for(count=0;count<15;count++)
    {EPD_1IN54_V3_SendData(EPD_1IN54_V3_lut_vcom0[count]);}

    EPD_1IN54_V3_SendCommand(0x21);
    for(count=0;count<15;count++)
        {EPD_1IN54_V3_SendData(EPD_1IN54_V3_lut_w[count]);}

    EPD_1IN54_V3_SendCommand(0x22);
    for(count=0;count<15;count++)
        {EPD_1IN54_V3_SendData(EPD_1IN54_V3_lut_b[count]);}

    EPD_1IN54_V3_SendCommand(0x23);
    for(count=0;count<15;count++)
        {EPD_1IN54_V3_SendData(EPD_1IN54_V3_lut_g1[count]);}

    EPD_1IN54_V3_SendCommand(0x24);
    for(count=0;count<15;count++)
        {EPD_1IN54_V3_SendData(EPD_1IN54_V3_lut_g2[count]);}
}

/******************************************************************************
function :	Clear screen
parameter:
******************************************************************************/
void EPD_1IN54_V3_Clear(void)
{
    UWORD Width, Height;
    Width = (EPD_1IN54_V3_WIDTH % 8 == 0)? (EPD_1IN54_V3_WIDTH / 8 ): (EPD_1IN54_V3_WIDTH / 8 + 1);
    Height = EPD_1IN54_V3_HEIGHT*2;

    EPD_1IN54_V3_SendCommand(0x10);
    for (UWORD j = 0; j < Height; j++) {
        for (UWORD i = 0; i < Width; i++) {
            EPD_1IN54_V3_SendData(0XFF);
        }
    }
    EPD_1IN54_V3_TurnOnDisplay();
}

/******************************************************************************
function :	Sends the image buffer in RAM to e-Paper and displays
parameter:
******************************************************************************/
void EPD_1IN54_V3_Display(UBYTE *Image, UBYTE *Image2)
{
    UBYTE Temp = 0x00;
    UWORD Width, Height;
    Width = (EPD_1IN54_V3_WIDTH % 8 == 0)? (EPD_1IN54_V3_WIDTH / 8 ): (EPD_1IN54_V3_WIDTH / 8 + 1);
    Height = EPD_1IN54_V3_HEIGHT;

    UDOUBLE Addr = 0;
    EPD_1IN54_V3_SendCommand(0x10);
    for (UWORD j = 0; j < Height; j++) {
        for (UWORD i = 0; i < Width; i++) {
            Addr = i + j * Width;
            Temp = 0x00;
            for (int bit = 0; bit < 4; bit++) {
                if ((Image[Addr] & (0x80 >> bit)) != 0) {
                    Temp |= 0xC0 >> (bit * 2);
                }
            }
            EPD_1IN54_V3_SendData(Temp);
            Temp = 0x00;
            for (int bit = 4; bit < 8; bit++) {
                if ((Image[Addr] & (0x80 >> bit)) != 0) {
                    Temp |= 0xC0 >> ((bit - 4) * 2);
                }
            }
            EPD_1IN54_V3_SendData(Temp);
        }
    }
    EPD_1IN54_V3_TurnOnDisplay();
}

/******************************************************************************
function :	 The image of the previous frame must be uploaded, otherwise the
		        first few seconds will display an exception.
parameter:
******************************************************************************/
void EPD_1IN54_V3_DisplayPartBaseImage(UBYTE *Image)
{
    EPD_1IN54_V3_Display(Image, NULL);
}

/******************************************************************************
function :	Sends the image buffer in RAM to e-Paper and displays
parameter:
******************************************************************************/
void EPD_1IN54_V3_DisplayPart(UBYTE *Image)
{
    EPD_1IN54_V3_Display(Image, NULL);
}
/******************************************************************************
function :	Enter sleep mode
parameter:
******************************************************************************/
void EPD_1IN54_V3_Sleep(void)
{
    EPD_1IN54_V3_SendCommand(0x82);
    EPD_1IN54_V3_SendData(0x00);
    EPD_1IN54_V3_SendCommand(0x01);         //power setting
    EPD_1IN54_V3_SendData(0x02);        //gate switch to external
    EPD_1IN54_V3_SendData(0x00);
    EPD_1IN54_V3_SendData(0x00);
    EPD_1IN54_V3_SendData(0x00);
    DEV_Delay_ms(1500);
    EPD_1IN54_V3_SendCommand(0X02);   //deep sleep
    DEV_Delay_ms(100);
}
