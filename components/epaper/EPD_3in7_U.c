#include "EPD_3in7_U.h"
#include "Debug.h"

//GC 0.9S
static const UBYTE EPD_3in7_U_lut_R20_GC[] =
{
    0x05,0x01,0x01,0x01,0x01,0x01,0x01,
    0x01,0x12,0x1C,0x01,0x01,0x01,0x01,
    0x01,0x20,0x20,0x20,0x01,0x01,0x01,
    0x01,0x08,0x12,0x05,0x05,0x01,0x02,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};							  
static const UBYTE EPD_3in7_U_lut_R21_GC[] =
{
    0x05,0x41,0x81,0x01,0x01,0x01,0x01,
    0x01,0x52,0x1C,0x01,0x01,0x01,0x01,
    0x01,0x20,0xA0,0x60,0x01,0x01,0x01,
    0x01,0x88,0x12,0x85,0x05,0x01,0x02,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};						 
static const UBYTE EPD_3in7_U_lut_R22_GC[] =
{
    0x05,0x41,0x81,0x01,0x01,0x01,0x01,
    0x01,0x52,0x1C,0x01,0x01,0x01,0x01,
    0x01,0x20,0xA0,0x60,0x01,0x01,0x01,
    0x01,0x88,0x12,0x85,0x05,0x01,0x02,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};
static const UBYTE EPD_3in7_U_lut_R23_GC[] =
{
    0x05,0x41,0x81,0x01,0x01,0x01,0x01,
    0x01,0x12,0x9C,0x01,0x01,0x01,0x01,
    0x01,0x60,0xA0,0x20,0x01,0x01,0x01,
    0x01,0x08,0x52,0x05,0x45,0x01,0x02,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};
static const UBYTE EPD_3in7_U_lut_R24_GC[] =
{
    0x05,0x41,0x81,0x01,0x01,0x01,0x01,
    0x01,0x12,0x9C,0x01,0x01,0x01,0x01,
    0x01,0x60,0xA0,0x20,0x01,0x01,0x01,
    0x01,0x08,0x52,0x05,0x45,0x01,0x02,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};


// DU 0.3s
static const UBYTE EPD_3in7_U_lut_R20_DU[] =
{
    0x01,0x16,0x16,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00
};							  
static const UBYTE EPD_3in7_U_lut_R21_DU[] =
{
    0x01,0x96,0x16,0x81,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00
};						 
static const UBYTE EPD_3in7_U_lut_R22_DU[] =
{
    0x01,0x96,0x16,0x81,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00
};
static const UBYTE EPD_3in7_U_lut_R23_DU[] =
{
    0x01,0x96,0x56,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00
};
static const UBYTE EPD_3in7_U_lut_R24_DU[] =
{
    0x01,0x96,0x56,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00
};

// 
static const UBYTE EPD_3in7_U_lut_vcom[] =
{
    0x05,0x14,0x14,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};

static const UBYTE EPD_3in7_U_lut_ww[] =
{
    0x05,0x54,0x94,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};

static const UBYTE EPD_3in7_U_lut_bw[] =
{
    0x05,0x54,0x94,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};

static const UBYTE EPD_3in7_U_lut_wb[] =
{	
    0x05,0x54,0x94,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};

static const UBYTE EPD_3in7_U_lut_bb[] =
{
    0x05,0x54,0x94,0x01,0x01,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01,
    0x01,0x00,0x00,0x00,0x00,0x01,0x01
};

unsigned char EPD_3in7_U_Flag = 0;

/******************************************************************************
function :	Software reset
parameter:
******************************************************************************/
void EPD_3in7_U_Reset(void)
{
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(200);
    DEV_Digital_Write(EPD_RST_PIN, 0);
    DEV_Delay_ms(2);
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(200);
}

/******************************************************************************
function :	send command
parameter:
     Reg : Command register
******************************************************************************/
void EPD_3in7_U_SendCommand(UBYTE Reg)
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
void EPD_3in7_U_SendData(UBYTE Data)
{
    DEV_Digital_Write(EPD_DC_PIN, 1);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(Data);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

/******************************************************************************
function :	Read Busy
parameter:
******************************************************************************/
void EPD_3in7_U_ReadBusy(void)
{
    EPD_Busy_WaitUntil(1,0);
    // Debug("e-Paper busy\r\n");
    // UBYTE busy;
    // do {
    //     busy = DEV_Digital_Read(EPD_BUSY_PIN);
    // } while(!busy);
    // DEV_Delay_ms(200);
    // Debug("e-Paper busy release\r\n");
}

/**
 * @brief 
 * 
 */
void EPD_3in7_U_lut(void)
{
    UBYTE count;
    EPD_3in7_U_SendCommand(0x20);        // vcom
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_vcom[count]);
    }
         
    EPD_3in7_U_SendCommand(0x21);        // ww --
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_ww[count]);
    }
        
    EPD_3in7_U_SendCommand(0x22);        // bw r
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_bw[count]);
    }
        
    EPD_3in7_U_SendCommand(0x23);        // wb w
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_bb[count]);
    }
        
    EPD_3in7_U_SendCommand(0x24);        // bb b
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_wb[count]);
    }
}

/**
 * @brief 
 * 
 */
void EPD_3in7_U_refresh(void)
{
    EPD_3in7_U_SendCommand(0x17);
    EPD_3in7_U_SendData(0xA5);
    EPD_3in7_U_ReadBusy();
    DEV_Delay_ms(200);
}

// LUT download
void EPD_3in7_U_lut_GC(void)
{
    UBYTE count;
    EPD_3in7_U_SendCommand(0x20);        // vcom
    for(count = 0; count < sizeof(EPD_3in7_U_lut_R20_GC) ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_R20_GC[count]);
    }
        
    EPD_3in7_U_SendCommand(0x21);        // red not use
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_R21_GC[count]);
    }
        
    EPD_3in7_U_SendCommand(0x24);        // bb b
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_R24_GC[count]);
    }
    
    if(EPD_3in7_U_Flag == 0)
    {
        EPD_3in7_U_SendCommand(0x22);    // bw r
        for(count = 0; count < sizeof(EPD_3in7_U_lut_R22_GC) ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R22_GC[count]);
        }
            
        EPD_3in7_U_SendCommand(0x23);    // wb w
        for(count = 0; count < 42 ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R23_GC[count]);
        }
            
        EPD_3in7_U_Flag = 1;
    }
        
    else
    {
        EPD_3in7_U_SendCommand(0x22);    // bw r
        for(count = 0; count < sizeof(EPD_3in7_U_lut_R23_GC) ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R23_GC[count]);
        }
            
        EPD_3in7_U_SendCommand(0x23);    // wb w
        for(count = 0; count < 42 ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R22_GC[count]);
        }
            
       EPD_3in7_U_Flag = 0;
    }
}

// LUT download        
void EPD_3in7_U_lut_DU(void)
{
    UBYTE count;
    EPD_3in7_U_SendCommand(0x20);      // vcom
    for(count = 0; count < sizeof(EPD_3in7_U_lut_R20_DU) ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_R20_DU[count]);
    }
        
    EPD_3in7_U_SendCommand(0x21);     // red not use
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_R21_DU[count]);
    }
        
    EPD_3in7_U_SendCommand(0x24);    // bb b
    for(count = 0; count < 42 ; count++)
    {
        EPD_3in7_U_SendData(EPD_3in7_U_lut_R24_DU[count]);
    }
    
    if(EPD_3in7_U_Flag == 0)
    {
        EPD_3in7_U_SendCommand(0x22);      // bw r
        for(count = 0; count < sizeof(EPD_3in7_U_lut_R22_DU) ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R22_DU[count]);
        }
            
        EPD_3in7_U_SendCommand(0x23);     // wb w
        for(count = 0; count < 42 ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R23_DU[count]);
        }
            
        EPD_3in7_U_Flag = 1;
    }
        
    else
    {
        EPD_3in7_U_SendCommand(0x22);    // bw r
        for(count = 0; count < sizeof(EPD_3in7_U_lut_R23_DU) ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R23_DU[count]);
        }
            
        EPD_3in7_U_SendCommand(0x23);   // wb w
        for(count = 0; count < 42 ; count++)
        {
            EPD_3in7_U_SendData(EPD_3in7_U_lut_R22_DU[count]);
        }
            
        EPD_3in7_U_Flag = 0;
    }
}  
            
    




/******************************************************************************
function :	Initialize the e-Paper register
parameter:
******************************************************************************/
void EPD_3in7_U_Init(UBYTE mode)
{
    EPD_3in7_U_Flag = 0;
    EPD_3in7_U_Reset();

    EPD_3in7_U_SendCommand(0x00);		// panel setting   PSR
    EPD_3in7_U_SendData(0xFF);			// RES1 RES0 REG KW/R     UD    SHL   SHD_N  RST_N	
    EPD_3in7_U_SendData(0x01);			// x x x VCMZ TS_AUTO TIGE NORG VC_LUTZ

    EPD_3in7_U_SendCommand(0x01);		// POWER SETTING   PWR
    EPD_3in7_U_SendData(0x03);			//  x x x x x x VDS_EN VDG_EN	
    EPD_3in7_U_SendData(0x10);			//  x x x VCOM_SLWE VGH[3:0]   VGH=20V, VGL=-20V	
    EPD_3in7_U_SendData(0x3F);			//  x x VSH[5:0]	VSH = 15V
    EPD_3in7_U_SendData(0x3F);			//  x x VSL[5:0]	VSL=-15V
    EPD_3in7_U_SendData(0x03);			//  OPTEN VDHR[6:0]  VHDR=6.4V
                                        // T_VDS_OFF[1:0] 00=1 frame; 01=2 frame; 10=3 frame; 11=4 frame
    EPD_3in7_U_SendCommand(0x06);		// booster soft start   BTST 
    EPD_3in7_U_SendData(0x37);			//  BT_PHA[7:0]  	
    EPD_3in7_U_SendData(0x3D);			//  BT_PHB[7:0]	
    EPD_3in7_U_SendData(0x3D);			//  x x BT_PHC[5:0]	

    EPD_3in7_U_SendCommand(0x60);		// TCON setting			TCON 
    EPD_3in7_U_SendData(0x22);			// S2G[3:0] G2S[3:0]   non-overlap = 12		

    EPD_3in7_U_SendCommand(0x82);		// VCOM_DC setting		VDCS 
    EPD_3in7_U_SendData(0x07);			// x  VDCS[6:0]	VCOM_DC value= -1.9v    00~3f,0x12=-1.9v

    EPD_3in7_U_SendCommand(0x30);			 
    EPD_3in7_U_SendData(0x09);		

    EPD_3in7_U_SendCommand(0xe3);		// power saving			PWS 
    EPD_3in7_U_SendData(0x88);			// VCOM_W[3:0] SD_W[3:0]

    EPD_3in7_U_SendCommand(0x61);		// resoultion setting 
    EPD_3in7_U_SendData(0xf0);			//  HRES[7:3] 0 0 0	
    EPD_3in7_U_SendData(0x01);			//  x x x x x x x VRES[8]	
    EPD_3in7_U_SendData(0xA0);			//  VRES[7:0]

    EPD_3in7_U_SendCommand(0x50);			
    EPD_3in7_U_SendData(0xB7);		
    // add for luatos
    EPD_3in7_U_display_NUM(EPD_3in7_U_WHITE);
    EPD_3in7_U_lut_GC();
    EPD_3in7_U_refresh();

    EPD_3in7_U_SendCommand(0x50);
    EPD_3in7_U_SendData(0x17);	
}


void EPD_3in7_U_display(UBYTE *Image, UBYTE *Image2)
{
    UWORD i;
    EPD_3in7_U_SendCommand(0x13);		     //Transfer new data
    for(i=0;i<(EPD_3in7_U_WIDTH*EPD_3in7_U_HEIGHT/8);i++)	     
    {
        EPD_3in7_U_SendData(*Image);
        Image++;
    }
    // add for luatos
    EPD_3in7_U_lut_GC();
    EPD_3in7_U_refresh();
}

void EPD_3in7_U_display_NUM(UBYTE NUM)
{
    UWORD row, column;
    // UWORD pcnt = 0;

    EPD_3in7_U_SendCommand(0x13);		     //Transfer new data

    for(column=0; column<EPD_3in7_U_HEIGHT; column++)   
    {
        for(row=0; row<EPD_3in7_U_WIDTH/8; row++)  
        {
            switch (NUM)
            {
                case EPD_3in7_U_WHITE:
                    EPD_3in7_U_SendData(0xFF);
                    break;  
                        
                case EPD_3in7_U_BLACK:
                    EPD_3in7_U_SendData(0x00);
                    break;  
                        
                case EPD_3in7_U_Source_Line:
                    EPD_3in7_U_SendData(0xAA);  
                    break;
                        
                case EPD_3in7_U_Gate_Line:
                    if(column%2)
                        EPD_3in7_U_SendData(0xff); //An odd number of Gate line  
                    else
                        EPD_3in7_U_SendData(0x00); //The even line Gate  
                    break;			
                        
                case EPD_3in7_U_Chessboard:
                    if(row>=(EPD_3in7_U_WIDTH/8/2)&&column>=(EPD_3in7_U_HEIGHT/2))
                        EPD_3in7_U_SendData(0xff);
                    else if(row<(EPD_3in7_U_WIDTH/8/2)&&column<(EPD_3in7_U_HEIGHT/2))
                        EPD_3in7_U_SendData(0xff);										
                    else
                        EPD_3in7_U_SendData(0x00);
                    break; 			
                        
                case EPD_3in7_U_LEFT_BLACK_RIGHT_WHITE:
                    if(row>=(EPD_3in7_U_WIDTH/8/2))
                        EPD_3in7_U_SendData(0xff);
                    else
                        EPD_3in7_U_SendData(0x00);
                    break;
                            
                case EPD_3in7_U_UP_BLACK_DOWN_WHITE:
                    if(column>=(EPD_3in7_U_HEIGHT/2))
                        EPD_3in7_U_SendData(0xFF);
                    else
                        EPD_3in7_U_SendData(0x00);
                    break;
                            
                case EPD_3in7_U_Frame:
                    if(column==0||column==(EPD_3in7_U_HEIGHT-1))
                        EPD_3in7_U_SendData(0x00);						
                    else if(row==0)
                        EPD_3in7_U_SendData(0x7F);
                    else if(row==(EPD_3in7_U_WIDTH/8-1))
                        EPD_3in7_U_SendData(0xFE);					
                    else
                        EPD_3in7_U_SendData(0xFF);
                    break; 					
                            
                case EPD_3in7_U_Crosstalk:
                    if((row>=(EPD_3in7_U_WIDTH/8/3)&&row<=(EPD_3in7_U_WIDTH/8/3*2)&&column<=(EPD_3in7_U_HEIGHT/3))||(row>=(EPD_3in7_U_WIDTH/8/3)&&row<=(EPD_3in7_U_WIDTH/8/3*2)&&column>=(EPD_3in7_U_HEIGHT/3*2)))
                        EPD_3in7_U_SendData(0x00);
                    else
                        EPD_3in7_U_SendData(0xFF);
                    break; 					
                            
                case EPD_3in7_U_Image:
                        //EPD_3in7_U_SendData(gImage_1[pcnt++]);
                    break;  
                                        
                default:
                    break;
            }
        }
    }	
}

/******************************************************************************
function :	Clear screen
parameter:
******************************************************************************/
void EPD_3in7_U_Clear(void)
{
    UWORD i;
    EPD_3in7_U_SendCommand(0x13);		     //Transfer new data
    for(i=0;i<(EPD_3in7_U_WIDTH*EPD_3in7_U_HEIGHT/8);i++)	     
    {
        EPD_3in7_U_SendData(0xFF);
    }
    EPD_3in7_U_lut_GC();
	EPD_3in7_U_refresh();
}

/******************************************************************************
function :	Enter sleep mode
parameter:
******************************************************************************/
void EPD_3in7_U_sleep(void)
{
    EPD_3in7_U_SendCommand(0X07);  	//deep sleep
    EPD_3in7_U_SendData(0xA5);
}



