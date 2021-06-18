#include "port.h"
#include "lcd_cfg.h"

const user_gpio_set_t lcd_common_rgb_gpio_list[LCD_PARA_QTY] = 
{
    {
        {0},           //POWER
    },
    {
        {0},           //PWM
    },
    {
        {0},           //BL
    },
    {
        {0},           //D0
        GPIO_PORTE,
        0,
        3,
    },
    {
        {0},           //D1
        GPIO_PORTE,
        1,
        3,
    },
    {
        {0},           //D2
        GPIO_PORTD,
        0,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        1,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        2,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        3,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        4,
        2,
    },

    {
        {1},
        GPIO_PORTD,
        5,
        2,
    },
    {
        {0},           //D8
        GPIO_PORTE,
        2,
        3,
    },
    {
        {0},           //D9
        GPIO_PORTE,
        3,
        3,
    },

    {
        {1},
        GPIO_PORTD,
        6,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        7,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        8,
        2,
    },

    {
        {1},
        GPIO_PORTD,
        9,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        10,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        11,
        2,
    },
    {
        {0},              //D16
        GPIO_PORTE,
        4,
        3,
    },
    {
        {0},               //D17
        GPIO_PORTE,
        5,
        3,
    },
    {
        {0},               //D18
        GPIO_PORTD,
        12,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        13,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        14,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        15,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        16,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        17,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        18,
        2,
    },

    {
        {1},
        GPIO_PORTD,
        19,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        20,
        2,
    },
    {
        {1},
        GPIO_PORTD,
        21,
        2,
    },
};

void LCD_common_rbg_cfg_panel_info(__panel_para_t * info)
{
    memset(info,0,sizeof(__panel_para_t));

    //屏的基本信息
    info->lcd_x                   = 800;
    info->lcd_y                   = 480;
    info->lcd_dclk_freq           = 33;  //MHz
    info->lcd_pwm_freq            = 1;  //KHz
    info->lcd_srgb                = 0x00202020;
    info->lcd_swap                = 0;
    
    //屏的接口配置信息
    info->lcd_if                  = 0;//0:HV , 1:8080 I/F, 2:TTL I/F, 3:LVDS
    
    //屏的HV模块相关信息
    info->lcd_hv_if               = 0;
    info->lcd_hv_hspw             = 0;
    info->lcd_hv_lde_iovalue      = 0;
    info->lcd_hv_lde_used         = 0;
    info->lcd_hv_smode            = 0;
    info->lcd_hv_syuv_if          = 0;
    info->lcd_hv_vspw             = 0;
        
    //屏的HV配置信息
    info->lcd_hbp           = 3;
    info->lcd_ht            = 960;
    info->lcd_vbp           = 3;
    info->lcd_vt            = (2 * 525);

    //屏的IO配置信息
    info->lcd_io_cfg0             = 0x00000000;
    info->lcd_io_cfg1             = 0x00000000;
    info->lcd_io_strength         = 0;

    //TTL屏幕的配置信息
    info->lcd_ttl_ckvd            = 0;
    info->lcd_ttl_ckvh            = 0;
    info->lcd_ttl_ckvt            = 0;
    info->lcd_ttl_datainv_en      = 0;
    info->lcd_ttl_datainv_sel     = 0;
    info->lcd_ttl_datarate        = 0;
    info->lcd_ttl_oehd            = 0;
    info->lcd_ttl_oehh            = 0;
    info->lcd_ttl_oevd            = 0;
    info->lcd_ttl_oevh            = 0;
    info->lcd_ttl_oevt            = 0;
    info->lcd_ttl_revd            = 0;
    info->lcd_ttl_revsel          = 0;
    info->lcd_ttl_sthd            = 0;
    info->lcd_ttl_sthh            = 0;
    info->lcd_ttl_stvdl           = 0;
    info->lcd_ttl_stvdp           = 0;
    info->lcd_ttl_stvh            = 0; 
        
    //cpu屏幕的配置信息
    info->lcd_frm 			 = 0;	//0: disable; 1: enable rgb666 dither; 2:enable rgb656 dither
}

void LCD_common_rbg_cfg_panel_info1(__panel_para_t * info)
{
    memset(info,0,sizeof(__panel_para_t));

    //屏的基本信息
    info->lcd_x                   = 1280;
    info->lcd_y                   = 720;
    info->lcd_dclk_freq           = 75;  //MHz
    info->lcd_pwm_freq            = 1;  //KHz
    info->lcd_srgb                = 0x00202020;
    info->lcd_swap                = 0;
    
    //屏的接口配置信息
    info->lcd_if                  = 0;//0:HV , 1:8080 I/F, 2:TTL I/F, 3:LVDS
    
    //屏的HV模块相关信息
    info->lcd_hv_if               = 0;
    info->lcd_hv_hspw             = 39;
    info->lcd_hv_lde_iovalue      = 0;
    info->lcd_hv_lde_used         = 0;
    info->lcd_hv_smode            = 0;
    info->lcd_hv_syuv_if          = 0;
    info->lcd_hv_vspw             = 4;
        
    //屏的HV配置信息
    info->lcd_hbp           = 259;
    info->lcd_ht            = 1649;
    info->lcd_vbp           = 25 -1;
    info->lcd_vt            = (1500);

    //屏的IO配置信息
    info->lcd_io_cfg0             = 0x00000000;
    info->lcd_io_cfg1             = 0x00000000;
    info->lcd_io_strength         = 0;

    //TTL屏幕的配置信息
    info->lcd_ttl_ckvd            = 0;
    info->lcd_ttl_ckvh            = 0;
    info->lcd_ttl_ckvt            = 0;
    info->lcd_ttl_datainv_en      = 0;
    info->lcd_ttl_datainv_sel     = 0;
    info->lcd_ttl_datarate        = 0;
    info->lcd_ttl_oehd            = 0;
    info->lcd_ttl_oehh            = 0;
    info->lcd_ttl_oevd            = 0;
    info->lcd_ttl_oevh            = 0;
    info->lcd_ttl_oevt            = 0;
    info->lcd_ttl_revd            = 0;
    info->lcd_ttl_revsel          = 0;
    info->lcd_ttl_sthd            = 0;
    info->lcd_ttl_sthh            = 0;
    info->lcd_ttl_stvdl           = 0;
    info->lcd_ttl_stvdp           = 0;
    info->lcd_ttl_stvh            = 0; 
        
    //cpu屏幕的配置信息
    info->lcd_frm 			 = 0;	//0: disable; 1: enable rgb666 dither; 2:enable rgb656 dither
}