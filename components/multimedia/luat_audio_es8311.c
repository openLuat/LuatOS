#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_i2c.h"
#include "luat_audio.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "es8311"
#include "luat_log.h"

#define ES8311_ADDR                     0x18

#define MCLK_DIV_FRE                    256
#define ES8311_MCLK_SOURCE              0       //是否硬件没接MCLK需要用SCLK当作MCLK,一般不用,除非引脚非常不够要省引脚
#define ES8311_DMIC_SEL                 0       //DMIC选择:默认选择关闭0,打开为1
#define ES8311_LINSEL_SEL		        1       //0 – no input selection  1 – select Mic1p-Mic1n 2 – select Mic2p-Mic2n 3 – select both pairs of Mic1 and Mic2
#define ES8311_ADC_PGA_GAIN		        8       //ADC模拟增益:(选择范围0~10),具体对应关系见相应DS说明
#define ES8311_ADC2DAC_SEL              0	    //LOOP选择:内部ADC数据给到DAC自回环输出:默认选择关闭0,打开为1
#define ES8311_DAC_HP_ON	            0	    //输出负载开启HP驱动:默认选择关闭0,打开为1
#define ES8311_VDDA_3V3			        0x00
#define ES8311_VDDA_1V8			        0x01
#define ES8311_VDDA_VOLTAGE		        ES8311_VDDA_3V3    //模拟电压选择为3V3还是1V8,需要和实际硬件匹配,默认选择3V3

/* ES8311_REGISTER NAME_REG_REGISTER ADDRESS */
#define ES8311_RESET_REG00              0x00  /*reset digital,csm,clock manager etc.*/
/* Clock Scheme Register definition */
#define ES8311_CLK_MANAGER_REG01        0x01 /* select clk src for mclk, enable clock for codec */
#define ES8311_CLK_MANAGER_REG02        0x02 /* clk divider and clk multiplier */
#define ES8311_CLK_MANAGER_REG03        0x03 /* adc fsmode and osr  */
#define ES8311_CLK_MANAGER_REG04        0x04 /* dac osr */
#define ES8311_CLK_MANAGER_REG05        0x05 /* clk divier for adc and dac */
#define ES8311_CLK_MANAGER_REG06        0x06 /* bclk inverter and divider */
#define ES8311_CLK_MANAGER_REG07        0x07 /* tri-state, lrck divider */
#define ES8311_CLK_MANAGER_REG08        0x08 /* lrck divider */
#define ES8311_SDPIN_REG09              0x09 /* dac serial digital port */
#define ES8311_SDPIN_REG09_DACWL_MASK   (7 << 2)
#define ES8311_SDPIN_REG09_DACWL_SHIFT  2
#define ES8311_SDPOUT_REG0A             0x0A /* adc serial digital port */
#define ES8311_SDPOUT_REG0A_ADCWL_MASK  (7 << 2)
#define ES8311_SDPOUT_REG0A_ADCWL_SHIFT 2
#define ES8311_SYSTEM_REG0B             0x0B /* system */
#define ES8311_SYSTEM_REG0C             0x0C /* system */
#define ES8311_SYSTEM_REG0D             0x0D /* system, power up/down */
#define ES8311_SYSTEM_REG0E             0x0E /* system, power up/down */
#define ES8311_SYSTEM_REG0F             0x0F /* system, low power */
#define ES8311_SYSTEM_REG10             0x10 /* system */
#define ES8311_SYSTEM_REG11             0x11 /* system */
#define ES8311_SYSTEM_REG12             0x12 /* system, Enable DAC */
#define ES8311_SYSTEM_REG13             0x13 /* system */
#define ES8311_SYSTEM_REG14             0x14 /* system, select DMIC, select analog pga gain */
#define ES8311_ADC_REG15                0x15 /* ADC, adc ramp rate, dmic sense */
#define ES8311_ADC_REG16                0x16 /* ADC */
#define ES8311_ADC_REG17                0x17 /* ADC, volume */
#define ES8311_ADC_REG18                0x18 /* ADC, alc enable and winsize */
#define ES8311_ADC_REG19                0x19 /* ADC, alc maxlevel */
#define ES8311_ADC_REG1A                0x1A /* ADC, alc automute */
#define ES8311_ADC_REG1B                0x1B /* ADC, alc automute, adc hpf s1 */
#define ES8311_ADC_REG1C                0x1C /* ADC, equalizer, hpf s2 */
#define ES8311_DAC_REG31                0x31 /* DAC, mute */
#define ES8311_DAC_REG32                0x32 /* DAC, volume */
#define ES8311_DAC_REG33                0x33 /* DAC, offset */
#define ES8311_DAC_REG34                0x34 /* DAC, drc enable, drc winsize */
#define ES8311_DAC_REG35                0x35 /* DAC, drc maxlevel, minilevel */
#define ES8311_DAC_REG37                0x37 /* DAC, ramprate */
#define ES8311_GPIO_REG44               0x44 /* GPIO, dac2adc for test */
#define ES8311_GP_REG45                 0x45 /* GP CONTROL */
#define ES8311_CHD1_REGFD               0xFD /* CHIP ID1 */
#define ES8311_CHD2_REGFE               0xFE /* CHIP ID2 */
#define ES8311_CHVER_REGFF              0xFF /* VERSION */
#define ES8311_CHD1_REGFD               0xFD /* CHIP ID1 */
#define ES8311_MAX_REGISTER             0xFF

//static uint8_t es8311_dacvol_bak=0,es8311_adcvol_bak=0;

typedef struct{
    uint32_t mclk;          // mclk frequency
    uint32_t rate;          // sample rate
    uint8_t preDiv;         // the pre divider with range from 1 to 8
    uint8_t preMulti;       // the pre multiplier with x1, x2, x4 and x8 selection
    uint8_t adcDiv;         // adcclk divider
    uint8_t dacDiv;         // dacclk divider
    uint8_t fsMode;         // double speed or single speed, =0, ss, =1, ds
    uint8_t lrckH;          // adclrck divider and daclrck divider
    uint8_t lrckL;
    uint8_t bclkDiv;        // sclk divider
    uint8_t adcOsr;         // adc osr
    uint8_t dacOsr;         // dac osr
}es8311_codec_div_t;

// codec hifi mclk clock divider coefficients
static const es8311_codec_div_t es8311_codec_div[] =
{
    //mclk     rate   preDiv  mult  adcDiv dacDiv fsMode lrch  lrcl  bckdiv adcOsr dacOsr
    // 8k
    {12288000, 8000 , 0x06,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {18432000, 8000 , 0x03,    0x02, 0x03,   0x03,   0x00,   0x05, 0xff, 0x18,  0x10,   0x20},
    {16384000, 8000 , 0x08,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {8192000 , 8000 , 0x04,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {6144000 , 8000 , 0x03,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {4096000 , 8000 , 0x02,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {3072000 , 8000 , 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {2048000 , 8000 , 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {1536000 , 8000 , 0x03,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},
    {1024000 , 8000 , 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04,  0x10,   0x20},

    // 16k
    {12288000, 16000, 0x03,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {18432000, 16000, 0x03,    0x02, 0x03,   0x03,   0x00,   0x02, 0xff, 0x0c, 0x10,    0x20},
    {16384000, 16000, 0x04,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {8192000 , 16000, 0x02,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {6144000 , 16000, 0x03,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {4096000 , 16000, 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {3072000 , 16000, 0x03,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {2048000 , 16000, 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {1536000 , 16000, 0x03,    0x08, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},
    {1024000 , 16000, 0x01,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x20},

    // 22.05k
    {11289600, 22050, 0x02,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {5644800 , 22050, 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {2822400 , 22050, 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {1411200 , 22050, 0x01,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},

    // 32k
    {12288000, 32000, 0x03,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {18432000, 32000, 0x03,    0x04, 0x03,   0x03,   0x00,   0x02, 0xff, 0x0c, 0x10,    0x10},
    {16384000, 32000, 0x02,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {8192000 , 32000, 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {6144000 , 32000, 0x03,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {4096000 , 32000, 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {3072000 , 32000, 0x03,    0x08, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {2048000 , 32000, 0x01,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {1536000 , 32000, 0x03,    0x08, 0x01,   0x01,   0x01,   0x00, 0x7f, 0x02, 0x10,    0x10},
    {1024000 , 32000, 0x01,    0x08, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},

    // 44.1k
    {11289600, 44100, 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {5644800 , 44100, 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {2822400 , 44100, 0x01,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {1411200 , 44100, 0x01,    0x08, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},

    // 48k
    {12288000, 48000, 0x01,    0x01, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {18432000, 48000, 0x03,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {6144000 , 48000, 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {3072000 , 48000, 0x01,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {1536000 , 48000, 0x01,    0x08, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},

    // 96k
    {12288000, 96000, 0x01,    0x02, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {18432000, 96000, 0x03,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {6144000 , 96000, 0x01,    0x04, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {3072000 , 96000, 0x01,    0x08, 0x01,   0x01,   0x00,   0x00, 0xff, 0x04, 0x10,    0x10},
    {1536000 , 96000, 0x01,    0x08, 0x01,   0x01,   0x01,   0x00, 0x7f, 0x02, 0x10,    0x10},
};

static int es8311_get_coeff(uint32_t mclk, uint32_t rate){
    for (int i = 0; i < (sizeof(es8311_codec_div) / sizeof(es8311_codec_div[0])); i++) {
        if (es8311_codec_div[i].rate == rate && es8311_codec_div[i].mclk == mclk)
            return i;
    }
    return -1;
}

static void es8311_write_reg(luat_audio_codec_conf_t* conf,uint8_t addr, uint8_t data){
    uint8_t temp[] = {addr,data};
    luat_i2c_send(conf->i2c_id, ES8311_ADDR, temp, 2 , 1);
	luat_rtos_task_sleep(1);
}

static uint8_t es8311_read_reg(luat_audio_codec_conf_t* conf,uint8_t addr){
	uint8_t temp=0;
    luat_i2c_send(conf->i2c_id, ES8311_ADDR, &addr, 1 , 0);
    luat_i2c_recv(conf->i2c_id, ES8311_ADDR, &temp, 1);
	return temp;
}

static int es8311_mode_resume(luat_audio_codec_conf_t* conf,uint8_t selece){
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0x01);
        if (selece == LUAT_CODEC_MODE_ALL) 
            es8311_write_reg(conf,ES8311_GP_REG45,0x00);
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x3F + (ES8311_MCLK_SOURCE<<7));
        es8311_write_reg(conf,ES8311_RESET_REG00,0x80);
        luat_rtos_task_sleep(1);
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0x01);
        if (selece == LUAT_CODEC_MODE_ALL) 
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02,0x00);
        es8311_write_reg(conf,ES8311_DAC_REG37,0x08);
        if (selece == LUAT_CODEC_MODE_ALL)
            es8311_write_reg(conf,ES8311_ADC_REG15,0x40);
        else
            es8311_write_reg(conf,ES8311_ADC_REG15,0x00);
        if(selece != LUAT_CODEC_MODE_ADC)
            es8311_write_reg(conf,ES8311_SYSTEM_REG12,0x00);
        if(selece != LUAT_CODEC_MODE_DAC)
            es8311_write_reg(conf,ES8311_SYSTEM_REG14,(ES8311_DMIC_SEL<<6) + (ES8311_LINSEL_SEL<<4) + ES8311_ADC_PGA_GAIN);
        if (selece == LUAT_CODEC_MODE_ALL)
            es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0x00);
        else
            es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0x02);
//        if(selece != LUAT_CODEC_MODE_DAC)
//            es8311_write_reg(conf,ES8311_ADC_REG17,es8311_adcvol_bak);
//        if(selece != LUAT_CODEC_MODE_ADC)
//            es8311_write_reg(conf,ES8311_DAC_REG32,es8311_dacvol_bak);
//        luat_rtos_task_sleep(50);
        if(selece == LUAT_CODEC_MODE_ADC)
            es8311_write_reg(conf,ES8311_SDPOUT_REG0A,0x00);
    return 0;
}

static int es8311_mode_standby(luat_audio_codec_conf_t* conf,uint8_t selece){
    if(selece != LUAT_CODEC_MODE_ADC){
        //es8311_dacvol_bak = es8311_read_reg(conf,ES8311_DAC_REG32);
        es8311_write_reg(conf,ES8311_DAC_REG32,0x00);
    }
    if(selece != LUAT_CODEC_MODE_DAC){
        //es8311_adcvol_bak = es8311_read_reg(conf,ES8311_ADC_REG17);
        es8311_write_reg(conf,ES8311_ADC_REG17,0x00);
    }
    if(selece == LUAT_CODEC_MODE_ADC){
        es8311_write_reg(conf,ES8311_SDPOUT_REG0A,0x40);
        es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0x7f);
        es8311_write_reg(conf,ES8311_SYSTEM_REG14,0x00);
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0x31);
    }else if(selece == LUAT_CODEC_MODE_DAC){
        es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0x0F);
        es8311_write_reg(conf,ES8311_SYSTEM_REG12,0x02);
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0x09);
    }else{
        es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0xFF);
        es8311_write_reg(conf,ES8311_SYSTEM_REG12,0x02);
        es8311_write_reg(conf,ES8311_SYSTEM_REG14,0x00);
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D, 0xFA);//0xF9
    }
    es8311_write_reg(conf,ES8311_ADC_REG15, 0x00);
    es8311_write_reg(conf,ES8311_DAC_REG37, 0x08);
    if(selece == LUAT_CODEC_MODE_ADC){
        es8311_write_reg(conf,ES8311_RESET_REG00,0x82);
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x35);
    }else if(selece == LUAT_CODEC_MODE_DAC){
        es8311_write_reg(conf,ES8311_RESET_REG00, 0x81);
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x3a);
    }else{
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02,0x10);
        es8311_write_reg(conf,ES8311_RESET_REG00,0x00);
        es8311_write_reg(conf,ES8311_RESET_REG00,0x1F);
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x30);
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x00);
        es8311_write_reg(conf,ES8311_GP_REG45,0x01);
    }
    return 0;
}

static int es8311_mode_pwrdown(luat_audio_codec_conf_t* conf){
    luat_audio_play_blank(conf->multimedia_id, 1);

	//es8311_dacvol_bak = es8311_read_reg(conf,ES8311_DAC_REG32);
	//es8311_adcvol_bak = es8311_read_reg(conf,ES8311_ADC_REG17);
    es8311_write_reg(conf,ES8311_DAC_REG32,0x00);
    es8311_write_reg(conf,ES8311_ADC_REG17,0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0xff);
    es8311_write_reg(conf,ES8311_SYSTEM_REG12,0x02);
    es8311_write_reg(conf,ES8311_SYSTEM_REG14,0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0xf9);
    es8311_write_reg(conf,ES8311_ADC_REG15,0x00);
    es8311_write_reg(conf,ES8311_DAC_REG37,0x08);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02,0x10);
    es8311_write_reg(conf,ES8311_RESET_REG00,0x00);
    es8311_write_reg(conf,ES8311_RESET_REG00,0x1f);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x30);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x00);
    es8311_write_reg(conf,ES8311_GP_REG45,0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0xfc);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02,0x00);
    luat_rtos_task_sleep(50);
    luat_audio_play_blank(conf->multimedia_id, 0);
    return 0;
}

// mute
static uint8_t es8311_set_mute(luat_audio_codec_conf_t* conf,uint8_t enable){
    es8311_write_reg(conf,ES8311_DAC_REG31, enable?0x20:0x00);
	return 0;
}

static uint8_t es8311_get_mute(luat_audio_codec_conf_t* conf){
    uint8_t reg = es8311_read_reg(conf,ES8311_DAC_REG31);
	return (reg & 0x20) >> 5;
}

// voice_vol
static uint8_t es8311_set_voice_vol(luat_audio_codec_conf_t* conf,uint8_t vol){
    if(vol < 0 || vol > 100) return -1;
	es8311_write_reg(conf,ES8311_DAC_REG32,(uint8_t)(vol * 2550 / 1000));
	return 0;
}

static uint8_t es8311_get_voice_vol(luat_audio_codec_conf_t* conf){
    uint8_t reg = es8311_read_reg(conf,ES8311_DAC_REG32);
	return reg * 1000 / 2550;
}

// mic_vol
static uint8_t es8311_set_mic_vol(luat_audio_codec_conf_t* conf,uint8_t vol){
    if(vol < 0 || vol > 100) return -1;
	es8311_write_reg(conf,ES8311_ADC_REG17,(uint8_t)(vol * 2550 / 1000));
	return 0;
}

static uint8_t es8311_get_mic_vol(luat_audio_codec_conf_t* conf){
    uint8_t reg = es8311_read_reg(conf,ES8311_ADC_REG17);
	return reg * 1000 / 2550;
}


static int es8311_codec_samplerate(luat_audio_codec_conf_t* conf,uint16_t samplerate){
    if(samplerate != 8000 && samplerate != 16000 && samplerate != 32000 &&
        samplerate != 11025 && samplerate != 22050 && samplerate != 44100 &&
        samplerate != 12000 && samplerate != 24000 && samplerate != 48000)
    {
        LLOGE("samplerate error! samplerate:%d\n",samplerate);
        return -1;
    }
    int coeff = es8311_get_coeff(samplerate * MCLK_DIV_FRE, samplerate);
    if (coeff < 0){
    	LLOGE("Unable to configure sample rate %dHz with %dHz MCLK", samplerate, samplerate * MCLK_DIV_FRE);
        return -1;
    }
    uint8_t reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG02) & 0x07;
    reg |= (es8311_codec_div[coeff].preDiv - 1) << 5;
    uint8_t datmp = 0;
    switch (es8311_codec_div[coeff].preMulti){
        case 1:
            datmp = 0;
            break;
        case 2:
            datmp = 1;
            break;
        case 4:
            datmp = 2;
            break;
        case 8:
            datmp = 3;
            break;
        default:
            break;
    }

    reg |= (datmp) << 3;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, reg);

    reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG05) & 0x00;
    reg |= (es8311_codec_div[coeff].adcDiv - 1) << 4;
    reg |= (es8311_codec_div[coeff].dacDiv - 1) << 0;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, reg);

    reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG03) & 0x80;
    reg |= es8311_codec_div[coeff].fsMode << 6;
    reg |= es8311_codec_div[coeff].adcOsr << 0;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, reg);

    reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG04) & 0x80;
    reg |= es8311_codec_div[coeff].dacOsr << 0;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, reg);

    reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG07) & 0xC0;
    reg |= es8311_codec_div[coeff].lrckH << 0;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG07, reg);

    reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG08) & 0x00;
    reg |= es8311_codec_div[coeff].lrckL << 0;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG08, reg);

    reg = es8311_read_reg(conf,ES8311_CLK_MANAGER_REG06) & 0xE0;
    if (es8311_codec_div[coeff].bclkDiv < 19)
        reg |= (es8311_codec_div[coeff].bclkDiv - 1) << 0;
    else
        reg |= (es8311_codec_div[coeff].bclkDiv) << 0;
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG06, reg);
    return 0;
}

static int es8311_set_format(luat_audio_codec_conf_t* conf,uint8_t format){
    // only support I2S format now
    uint8_t dacIface = es8311_read_reg(conf,ES8311_SDPIN_REG09);
    uint8_t adcIface = es8311_read_reg(conf,ES8311_SDPOUT_REG0A);
    dacIface &= 0xFC;
    adcIface &= 0xFC;
    es8311_write_reg(conf,ES8311_SDPIN_REG09, dacIface);
    es8311_write_reg(conf,ES8311_SDPOUT_REG0A, adcIface);
    return 0;
}

static int es8311_codec_samplebits(luat_audio_codec_conf_t* conf,uint8_t samplebits){
    if(samplebits != 8 && samplebits != 16 && samplebits != 24 && samplebits != 32){
        LLOGE("bit_width error!\n");
        return -1;
    }
    int wl;
    switch (samplebits){
        case 16:
            wl = 3;
            break;
        case 18:
            wl = 2;
            break;
        case 20:
            wl = 1;
            break;
        case 24:
            wl = 0;
            break;
        case 32:
            wl = 4;
            break;
        default:
            return -1;
    }
    uint8_t dac_iface = es8311_read_reg(conf,ES8311_SDPIN_REG09);
    uint8_t adc_iface = es8311_read_reg(conf,ES8311_SDPOUT_REG0A);
    dac_iface |= wl << ES8311_SDPIN_REG09_DACWL_SHIFT;
    adc_iface |= wl << ES8311_SDPOUT_REG0A_ADCWL_SHIFT;
    es8311_write_reg(conf,ES8311_SDPIN_REG09, dac_iface);
    es8311_write_reg(conf,ES8311_SDPOUT_REG0A, adc_iface);
    return 0;
}

static int es8311_codec_channels(luat_audio_codec_conf_t* conf,uint8_t channels){
    return 0;
}

static inline void es8311_reset(luat_audio_codec_conf_t* conf){
    es8311_write_reg(conf,ES8311_RESET_REG00, 0x1F);
    es8311_write_reg(conf,ES8311_RESET_REG00, 0x80);
    luat_rtos_task_sleep(1);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0D, 0x01);
}

static int es8311_codec_init(luat_audio_codec_conf_t* conf,uint8_t mode){
    luat_audio_power(conf->multimedia_id,1);
    luat_rtos_task_sleep(50);
    luat_audio_conf_t* audio_conf = luat_audio_get_config(conf->multimedia_id);
    uint8_t temp1 = es8311_read_reg(conf,ES8311_CHD1_REGFD);
    uint8_t temp2 = es8311_read_reg(conf,ES8311_CHD2_REGFE);
    uint8_t temp3 = es8311_read_reg(conf,ES8311_CHVER_REGFF);
    if(temp1 != 0x83 || temp2 != 0x11){
        LLOGE("codec err, id = 0x%x 0x%x ver = 0x%x", temp1, temp2, temp3);
        return -1;
    }
    /* reset codec */
    es8311_reset(conf);
    // BCLK/LRCK pullup on
    es8311_write_reg(conf,ES8311_GP_REG45, 0x00);
    /* power up digital */
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01, 0x30);

    // SET SDP in and SDP out mute
    es8311_write_reg(conf,ES8311_SDPIN_REG09, (es8311_read_reg(conf,ES8311_SDPIN_REG09) & 0xBF));
    es8311_write_reg(conf,ES8311_SDPOUT_REG0A, (es8311_read_reg(conf,ES8311_SDPOUT_REG0A) & 0xBF));

    es8311_write_reg(conf,ES8311_SYSTEM_REG0B, 0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0C, 0x00);
    if (audio_conf)
        es8311_write_reg(conf,ES8311_SYSTEM_REG10, (0x1C*ES8311_DAC_HP_ON) + (0x60 * (audio_conf->voltage ? ES8311_VDDA_1V8 : ES8311_VDDA_3V3)) + 0x03);
    else
        es8311_write_reg(conf,ES8311_SYSTEM_REG10, (0x1C*ES8311_DAC_HP_ON) + (0x60 * ES8311_VDDA_VOLTAGE) + 0x03);
    es8311_write_reg(conf,ES8311_SYSTEM_REG11, 0x7F);	

    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x3F + (ES8311_MCLK_SOURCE<<7));

    es8311_write_reg(conf,ES8311_RESET_REG00, 0X80+(mode<<6));
    luat_rtos_task_sleep(1);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0D, 0x01);

    es8311_write_reg(conf,ES8311_SYSTEM_REG14,(ES8311_DMIC_SEL<<6) + (ES8311_LINSEL_SEL<<4) + ES8311_ADC_PGA_GAIN);
    es8311_write_reg(conf,ES8311_SYSTEM_REG12, 0x28);
    es8311_write_reg(conf,ES8311_SYSTEM_REG13, 0x00 + (ES8311_DAC_HP_ON<<4));

    /* set normal power mode */
    es8311_write_reg(conf,ES8311_SYSTEM_REG0E, 0x02);

    es8311_write_reg(conf,ES8311_SYSTEM_REG0F, 0x44);
    // start up vmid normal speed charge
    es8311_write_reg(conf,ES8311_ADC_REG15, 0x00);
    /* set adc hpf */
    es8311_write_reg(conf,ES8311_ADC_REG1B, 0x0A);
    /* set adc hpf,ADC_EQ bypass */
    es8311_write_reg(conf,ES8311_ADC_REG1C, 0x6A);
    /* set dac softramp,disable DAC_EQ */
    es8311_write_reg(conf,ES8311_DAC_REG37, 0x08);
    // set internal reference signal (ADC + DAC)
    es8311_write_reg(conf,ES8311_GPIO_REG44, (ES8311_ADC2DAC_SEL<<7));
    // adc vol
    //es8311_write_reg(conf,ES8311_ADC_REG17, es8311_adcvol_bak);
    // dac vol
    //es8311_write_reg(conf,ES8311_DAC_REG32, es8311_dacvol_bak);
    return 0;
}

static int es8311_codec_deinit(luat_audio_codec_conf_t* conf){
    return 0;
}

static int es8311_codec_control(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data){
    switch (cmd){
        case LUAT_CODEC_MODE_RESUME:
            es8311_mode_resume(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_MODE_STANDBY:
            es8311_mode_standby(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_MODE_PWRDOWN:
            es8311_mode_pwrdown(conf);
            break;
        case LUAT_CODEC_SET_MUTE:
            es8311_set_mute(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_GET_MUTE:
            return es8311_get_mute(conf);
            break;
        case LUAT_CODEC_SET_VOICE_VOL:
            es8311_set_voice_vol(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_GET_VOICE_VOL:
            return es8311_get_voice_vol(conf);
            break;
        case LUAT_CODEC_SET_MIC_VOL:
            es8311_set_mic_vol(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_GET_MIC_VOL:
            return es8311_get_mic_vol(conf);
            break;
        case LUAT_CODEC_SET_FORMAT:
            es8311_set_format(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_SET_RATE:
            es8311_codec_samplerate(conf,(uint16_t)data);
            break;
        case LUAT_CODEC_SET_BITS:
            es8311_codec_samplebits(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_SET_CHANNEL:
            es8311_codec_channels(conf,(uint8_t)data);
            break;
        default:
            break;
    }
    return 0;
}

static int es8311_codec_start(luat_audio_codec_conf_t* conf){
    es8311_mode_resume(conf,LUAT_CODEC_MODE_ALL);
//    luat_audio_pa(conf->multimedia_id,1, 0);
    return 0;
}

static int es8311_codec_stop(luat_audio_codec_conf_t* conf){
//    luat_audio_pa(conf->multimedia_id,0, 0);
    es8311_mode_standby(conf,LUAT_CODEC_MODE_ALL);
    return 0;
}

const luat_audio_codec_opts_t codec_opts_es8311 = {
    .name = "es8311",
    .init = es8311_codec_init,
    .deinit = es8311_codec_deinit,
    .control = es8311_codec_control,
    .start = es8311_codec_start,
    .stop = es8311_codec_stop,
};
































