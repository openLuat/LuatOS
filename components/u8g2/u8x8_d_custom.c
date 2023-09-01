/*

  u8x8_d_custom.c

  Universal 8bit Graphics Library (https://github.com/olikraus/u8g2/)
  
*/


#include "luat_u8g2.h"
#include "luat_timer.h"

static luat_u8g2_conf_t* conf = NULL;
/*
(24)
(21), (0xae)
(21), (0xd5), (22), (0x80)
(21), (0xa8), (22), (0x3f)
(21), (0xd3), (22), (0x00)
(21), (0x40)
(21), (0x8d), (22), (0x14)
(21), (0x20), (22), (0x00)
(21), (0xa1)
(21), (0xc8)
(21), (0xda), (22), (0x12)
(21), (0x81), (22), (0xcf)
(21), (0xd9), (22), (0xf1)
(21), (0xdb), (22), (0x40)
(21), (0x2e)
(21), (0xa4)
(21), (0xa6)
(25)
(0xff)
*/

/* more or less generic setup of all these small OLEDs */
// static const uint8_t u8x8_d_custom_noname_init_seq[] = {
    
//   U8X8_START_TRANSFER(),             	/* enable chip, delay is part of the transfer start */
  
  
//   U8X8_C(0x0ae),		                /* display off */
//   U8X8_CA(0x0d5, 0x080),		/* clock divide ratio (0x00=1) and oscillator frequency (0x8) */
//   U8X8_CA(0x0a8, 0x03f),		/* multiplex ratio */
//   U8X8_CA(0x0d3, 0x000),		/* display offset */
//   U8X8_C(0x040),		                /* set display start line to 0 */
//   U8X8_CA(0x08d, 0x014),		/* [2] charge pump setting (p62): 0x014 enable, 0x010 disable, SSD1306 only, should be removed for SH1106 */
//   U8X8_CA(0x020, 0x000),		/* horizontal addressing mode */
  
//   U8X8_C(0x0a1),				/* segment remap a0/a1*/
//   U8X8_C(0x0c8),				/* c0: scan dir normal, c8: reverse */
//   // Flipmode
//   // U8X8_C(0x0a0),				/* segment remap a0/a1*/
//   // U8X8_C(0x0c0),				/* c0: scan dir normal, c8: reverse */
  
//   U8X8_CA(0x0da, 0x012),		/* com pin HW config, sequential com pin config (bit 4), disable left/right remap (bit 5) */

//   U8X8_CA(0x081, 0x0cf), 		/* [2] set contrast control */
//   U8X8_CA(0x0d9, 0x0f1), 		/* [2] pre-charge period 0x022/f1*/
//   U8X8_CA(0x0db, 0x040), 		/* vcomh deselect level */  
//   // if vcomh is 0, then this will give the biggest range for contrast control issue #98
//   // restored the old values for the noname constructor, because vcomh=0 will not work for all OLEDs, #116
  
//   U8X8_C(0x02e),				/* Deactivate scroll */ 
//   U8X8_C(0x0a4),				/* output ram to display */
//   U8X8_C(0x0a6),				/* none inverted normal display mode */
    
//   U8X8_END_TRANSFER(),             	/* disable chip */
//   U8X8_END()             			/* end of sequence */
// };

static const uint8_t u8x8_d_custom_noname_flip0_seq[] = {
  U8X8_START_TRANSFER(),             	/* enable chip, delay is part of the transfer start */
  U8X8_C(0x0a1),				/* segment remap a0/a1*/
  U8X8_C(0x0c8),				/* c0: scan dir normal, c8: reverse */
  U8X8_END_TRANSFER(),             	/* disable chip */
  U8X8_END()             			/* end of sequence */
};

static const uint8_t u8x8_d_custom_noname_flip1_seq[] = {
  U8X8_START_TRANSFER(),             	/* enable chip, delay is part of the transfer start */
  U8X8_C(0x0a0),				/* segment remap a0/a1*/
  U8X8_C(0x0c0),				/* c0: scan dir normal, c8: reverse */
  U8X8_END_TRANSFER(),             	/* disable chip */
  U8X8_END()             			/* end of sequence */
};

static uint8_t u8x8_d_custom_generic(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr)
{
  uint8_t x, c;
  uint8_t *ptr;

  switch(msg)
  {
    /* handled by the calling function
    case U8X8_MSG_DISPLAY_SETUP_MEMORY:
      u8x8_d_helper_display_setup_memory(u8x8, &u8x8_custom_noname_display_info);
      break;
    */
    /* handled by the calling function
    case U8X8_MSG_DISPLAY_INIT:
      u8x8_d_helper_display_init(u8x8);
      u8x8_cad_SendSequence(u8x8, u8x8_d_custom_noname_init_seq);    
      break;
    */
    case U8X8_MSG_DISPLAY_SET_POWER_SAVE:
      if ( arg_int == 0 ){
        u8x8_cad_StartTransfer(u8x8);
        u8x8_cad_SendCmd(u8x8, conf->wakecmd);
        u8x8_cad_EndTransfer(u8x8);
      }
      else{
        u8x8_cad_StartTransfer(u8x8);
        u8x8_cad_SendCmd(u8x8, conf->sleepcmd);
        u8x8_cad_EndTransfer(u8x8);
      }
      break;
    case U8X8_MSG_DISPLAY_SET_FLIP_MODE:
      if ( arg_int == 0 )
      {
        u8x8_cad_SendSequence(u8x8, u8x8_d_custom_noname_flip0_seq);
        u8x8->x_offset = u8x8->display_info->default_x_offset;
      }
      else
      {
        u8x8_cad_SendSequence(u8x8, u8x8_d_custom_noname_flip1_seq);
        u8x8->x_offset = u8x8->display_info->flipmode_x_offset;
      }
      break;
#ifdef U8X8_WITH_SET_CONTRAST
    case U8X8_MSG_DISPLAY_SET_CONTRAST:
      u8x8_cad_StartTransfer(u8x8);
      u8x8_cad_SendCmd(u8x8, 0x081 );
      u8x8_cad_SendArg(u8x8, arg_int );	/* ssd1306 has range from 0 to 255 */
      u8x8_cad_EndTransfer(u8x8);
      break;
#endif
    case U8X8_MSG_DISPLAY_DRAW_TILE:
      u8x8_cad_StartTransfer(u8x8);
      x = ((u8x8_tile_t *)arg_ptr)->x_pos;    
      x *= 8;
      x += u8x8->x_offset;
    
      u8x8_cad_SendCmd(u8x8, 0x040 );	/* set line offset to 0 */
    
      u8x8_cad_SendCmd(u8x8, 0x010 | (x>>4) );
      u8x8_cad_SendArg(u8x8, 0x000 | ((x&15)));					/* probably wrong, should be SendCmd */
      u8x8_cad_SendArg(u8x8, 0x0b0 | (((u8x8_tile_t *)arg_ptr)->y_pos));	/* probably wrong, should be SendCmd */

    
      do
      {
        c = ((u8x8_tile_t *)arg_ptr)->cnt;
        ptr = ((u8x8_tile_t *)arg_ptr)->tile_ptr;
        u8x8_cad_SendData(u8x8, c*8, ptr); 	/* note: SendData can not handle more than 255 bytes */
        /*
        do
        {
          u8x8_cad_SendData(u8x8, 8, ptr);
          ptr += 8;
          c--;
        } while( c > 0 );
        */
        arg_int--;
      } while( arg_int > 0 );
      
      u8x8_cad_EndTransfer(u8x8);
      break;
    default:
      return 0;
  }
  return 1;
}

static u8x8_display_info_t u8x8_custom_noname_display_info =
{
  /* chip_enable_level = */ 0,
  /* chip_disable_level = */ 1,
  
  /* post_chip_enable_wait_ns = */ 20,
  /* pre_chip_disable_wait_ns = */ 10,
  /* reset_pulse_width_ms = */ 100, 	/* SSD1306: 3 us */
  /* post_reset_wait_ms = */ 100, /* far east OLEDs need much longer setup time */
  /* sda_setup_time_ns = */ 50,		/* SSD1306: 15ns, but cycle time is 100ns, so use 100/2 */
  /* sck_pulse_width_ns = */ 50,	/* SSD1306: 20ns, but cycle time is 100ns, so use 100/2, AVR: below 70: 8 MHz, >= 70 --> 4MHz clock */
  /* sck_clock_hz = */ 8000000UL,	/* since Arduino 1.6.0, the SPI bus speed in Hz. Should be  1000000000/sck_pulse_width_ns */
  /* spi_mode = */ 0,		/* active high, rising edge */
  /* i2c_bus_clock_100kHz = */ 4,
  /* data_setup_time_ns = */ 40,
  /* write_pulse_width_ns = */ 150,	/* SSD1306: cycle time is 300ns, so use 300/2 = 150 */
  // /* tile_width = */ 16,
  // /* tile_height = */ 8,
  /* default_x_offset = */ 0,
  /* flipmode_x_offset = */ 0
  // /* pixel_width = */ 128,
  // /* pixel_height = */ 64
};

uint8_t u8x8_d_custom_noname(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr)
{
  uint32_t cmd = 0;
  if ( u8x8_d_custom_generic(u8x8, msg, arg_int, arg_ptr) != 0 )
    return 1;
  luat_u8g2_custom_t* u8g2_custom = NULL;
  printf("u8x8_d_custom_noname msg:%d\n",msg);
  switch(msg)
  {
    case U8X8_MSG_DISPLAY_INIT:
      conf = (luat_u8g2_conf_t*)u8x8->user_ptr;
      u8x8_custom_noname_display_info.pixel_width = conf->w;
      u8x8_custom_noname_display_info.pixel_height = conf->h;
      u8x8_custom_noname_display_info.tile_width = conf->w/8;
      u8x8_custom_noname_display_info.tile_height = conf->h/8;
      u8x8_d_helper_display_init(u8x8);
      // printf("conf w:%d h:%d\n",conf->w,conf->h);
      // u8x8_cad_SendSequence(u8x8, u8x8_d_custom_noname_init_seq);    
      u8g2_custom = (luat_u8g2_custom_t*)conf->userdata;
      u8x8_cad_StartTransfer(u8x8);
      for (size_t i = 0; i < u8g2_custom->init_cmd_count; i++){
        cmd = u8g2_custom->initcmd[i];
        switch(((cmd >> 16) & 0xFF)) {
            case 0x0000 :
                u8x8->cad_cb(u8x8, U8X8_MSG_CAD_SEND_CMD, (uint8_t)(cmd & 0xFF), NULL);
                break;
            case 0x0001 :
                luat_timer_mdelay(cmd & 0xFF);
                break;
            case 0x0002 :
                u8x8->cad_cb(u8x8, U8X8_MSG_CAD_SEND_CMD, (uint8_t)(cmd & 0xFF), NULL);
                break;
            case 0x0003 :
                u8x8->cad_cb(u8x8, U8X8_MSG_CAD_SEND_CMD, (uint8_t)(cmd & 0xFF), NULL);
                break;
            default:
                break;
        }
      }
      u8x8_cad_EndTransfer(u8x8);
      break;
    case U8X8_MSG_DISPLAY_SETUP_MEMORY:
      u8x8_d_helper_display_setup_memory(u8x8, &u8x8_custom_noname_display_info);
      break;
    default:
      return 0;
  }
  return 1;
}


