#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_i2c.h"
#include "luat_audio.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "es8311"
#include "luat_log.h"

#define ADC_VOLUME_GAIN 0xDF  //0xEF
#define DADC_GAIN 0x1A        //0x17
#define BCLK_DIV  0x13        //0x07

#define ES8311_ADDR  0x18

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

static uint8_t es8311_dacvol_bak,es8311_adcvol_bak;

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

static int es8311_mode_normal(luat_audio_codec_conf_t* conf,uint8_t selece){
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0x01);
        if (selece == LUAT_CODEC_MODE_ALL) 
            es8311_write_reg(conf,ES8311_GP_REG45,0x00);
        es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x3F);
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
            es8311_write_reg(conf,ES8311_SYSTEM_REG14,0x18);
        if (selece == LUAT_CODEC_MODE_ALL)
            es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0x00);
        else
            es8311_write_reg(conf,ES8311_SYSTEM_REG0E,0x02);

        if(selece != LUAT_CODEC_MODE_DAC)
            es8311_write_reg(conf,ES8311_ADC_REG17,es8311_adcvol_bak);
        if(selece != LUAT_CODEC_MODE_ADC)
            es8311_write_reg(conf,ES8311_DAC_REG32,es8311_dacvol_bak);
        luat_rtos_task_sleep(50);
        if(selece == LUAT_CODEC_MODE_ADC)
            es8311_write_reg(conf,ES8311_SDPOUT_REG0A,0x00);
    return 0;
}

static int es8311_mode_standby(luat_audio_codec_conf_t* conf,uint8_t selece){
    if(selece != LUAT_CODEC_MODE_ADC){
        es8311_dacvol_bak = es8311_read_reg(conf,ES8311_DAC_REG32);
        es8311_write_reg(conf,ES8311_DAC_REG32,0x00);
    }
    if(selece != LUAT_CODEC_MODE_DAC){
        es8311_adcvol_bak = es8311_read_reg(conf,ES8311_ADC_REG17);
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
        es8311_write_reg(conf,ES8311_SYSTEM_REG0D, 0xFA);
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
        es8311_write_reg(conf,ES8311_GP_REG45,0x01);
    }
    return 0;
}

static int es8311_mode_pwrdown(luat_audio_codec_conf_t* conf){
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
    luat_rtos_task_sleep(1);
    es8311_write_reg(conf,ES8311_RESET_REG00,0x1f);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x30);
    luat_rtos_task_sleep(1);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01,0x00);
    es8311_write_reg(conf,ES8311_GP_REG45,0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0D,0xfc);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02,0x00);
    return 0;
}

// mute
static uint8_t es8311_set_mute(luat_audio_codec_conf_t* conf,uint8_t enable){
    if (enable)  es8311_write_reg(conf,ES8311_DAC_REG31, 0x20);
    else es8311_write_reg(conf,ES8311_DAC_REG31, 0x00);
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
    // uint8_t i = 0;
	static int mclk = 0;
	static int switchflag = 0;
    switch(samplerate){
        case 8000:
			if (mclk == 0){
				mclk = 1;
			}
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, 0x08);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x44);
			if (switchflag == 0){
				switchflag = 1;
	            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x19);
	            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x19);
			}
            break;
        case 16000:
			if (mclk == 0){
				mclk = 1;
			}
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, 0x90);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
			if (switchflag == 0){
				switchflag = 1;
	            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x19);
	            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x19);
			}
            break;
        case 32000:
			if (mclk == 0){
				mclk = 1;
			}
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, 0x18);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x44);
			if (switchflag == 0){
				switchflag = 1;
	            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x19);
	            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x19);
			}
            break;
        case 44100:
			mclk = 0;
			switchflag = 0;
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, (0x03 << 3));
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x10);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x10);
            break;
        case 22050:
			mclk = 0;
			switchflag = 0;
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, (0x02 << 3));
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x10);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x10);
            break;
        case 11025:
			mclk = 0;			
			switchflag = 0;
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, (0x01 << 3));
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x10);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x10);
            break;
        case 48000:
			mclk = 0;		
			switchflag = 0;
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, (0x03 << 3));
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x10);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x10);
            break;
        case 24000:
			mclk = 0;		
			switchflag = 0;
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, (0x02 << 3));
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x10);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x10);
            break;
        case 12000:
			mclk = 0;			
			switchflag = 0;
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, (0x01 << 3));
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x10);
            es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x10);
            break;
        default:
            break;
    }
    return 0;
}

static int es8311_update_bits(luat_audio_codec_conf_t* conf,uint8_t reg, uint8_t mask, uint8_t val){
    uint8_t old, new;
    old = es8311_read_reg(conf,reg);
    new = (old & ~mask) | (val & mask);
    es8311_write_reg(conf,reg, new);
    return 0;
}

static int es8311_codec_samplebits(luat_audio_codec_conf_t* conf,uint8_t samplebits){
    if(samplebits != 8 && samplebits != 16 && samplebits != 24 && samplebits != 32){
        LLOGE("bit_width error!\n");
        return -1;
    }
    int wl;
    switch (samplebits)
    {
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
    es8311_update_bits(conf,ES8311_SDPIN_REG09,
                        ES8311_SDPIN_REG09_DACWL_MASK,
                        wl << ES8311_SDPIN_REG09_DACWL_SHIFT);
    es8311_update_bits(conf,ES8311_SDPOUT_REG0A,
                        ES8311_SDPOUT_REG0A_ADCWL_MASK,
                        wl << ES8311_SDPOUT_REG0A_ADCWL_SHIFT);
    return 0;
}

static int es8311_codec_channels(luat_audio_codec_conf_t* conf,uint8_t channels){
    return 0;
}

static int es8311_reg_init(luat_audio_codec_conf_t* conf){
    /* reset codec */
    es8311_write_reg(conf,ES8311_RESET_REG00, 0x1F);
    es8311_write_reg(conf,ES8311_GP_REG45, 0x00);

    luat_rtos_task_sleep(10);

    // es8311_write_reg(conf,ES8311_GPIO_REG44, 0x08);
    // luat_rtos_task_sleep(1);
    // es8311_write_reg(conf,ES8311_GPIO_REG44, 0x08);

    /* set ADC/DAC CLK */
    /* MCLK from BCLK  */
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01, 0x30);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG02, 0x90);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG03, 0x19);
    es8311_write_reg(conf,ES8311_ADC_REG16, 0x02);// bit5:0~non standard audio clock
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG04, 0x19);
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG05, 0x00);
	/*new cfg*/
	es8311_write_reg(conf,ES8311_CLK_MANAGER_REG06, BCLK_DIV);
	es8311_write_reg(conf,ES8311_CLK_MANAGER_REG07, 0x01);
	es8311_write_reg(conf,ES8311_CLK_MANAGER_REG08, 0xff);
    /* set system power up */
    es8311_write_reg(conf,ES8311_SYSTEM_REG0B, 0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0C, 0x00);
    es8311_write_reg(conf,ES8311_SYSTEM_REG10, 0x1F);
    es8311_write_reg(conf,ES8311_SYSTEM_REG11, 0x7F);
    /* chip powerup. slave mode */
    es8311_write_reg(conf,ES8311_RESET_REG00, 0x80);
    luat_rtos_task_sleep(50);

    /* power up analog */
    es8311_write_reg(conf,ES8311_SYSTEM_REG0D, 0x01);
    /* power up digital */
    es8311_write_reg(conf,ES8311_CLK_MANAGER_REG01, 0x3F);
    // SET ADC
    es8311_write_reg(conf,ES8311_SYSTEM_REG14, DADC_GAIN);
    // SET DAC
    es8311_write_reg(conf,ES8311_SYSTEM_REG12, 0x00);
    // ENABLE HP DRIVE
    es8311_write_reg(conf,ES8311_SYSTEM_REG13, 0x10);
    // SET ADC/DAC DATA FORMAT
    es8311_write_reg(conf,ES8311_SDPIN_REG09, 0x0c);
    es8311_write_reg(conf,ES8311_SDPOUT_REG0A, 0x0c);

    /* set normal power mode */
    es8311_write_reg(conf,ES8311_SYSTEM_REG0E, 0x02);
    es8311_write_reg(conf,ES8311_SYSTEM_REG0F, 0x44);
    // SET ADC
    /* set adc softramp */
    es8311_write_reg(conf,ES8311_ADC_REG15, 0x00);
    /* set adc hpf */
    es8311_write_reg(conf,ES8311_ADC_REG1B, 0x05);
    /* set adc hpf,ADC_EQ bypass */
    es8311_write_reg(conf,ES8311_ADC_REG1C, 0x65);
    /* set adc digtal vol */
    es8311_write_reg(conf,ES8311_ADC_REG17, ADC_VOLUME_GAIN);

    /* set dac softramp,disable DAC_EQ */
    es8311_write_reg(conf,ES8311_DAC_REG37, 0x08);
    es8311_write_reg(conf,ES8311_DAC_REG32, 0xBF);

    // /* set adc gain scale up */
    // es8311_write_reg(conf,ES8311_ADC_REG16, 0x24);
    // /* set adc alc maxgain */
    // es8311_write_reg(conf,ES8311_ADC_REG17, 0xBF);
    // /* adc alc disable,alc_winsize */
    // es8311_write_reg(conf,ES8311_ADC_REG18, 0x07);
    // /* set alc target level */
    // es8311_write_reg(conf,ES8311_ADC_REG19, 0xFB);
    // /* set adc_automute noise gate */
    // es8311_write_reg(conf,ES8311_ADC_REG1A, 0x03);
    // /* set adc_automute vol */
    // es8311_write_reg(conf,ES8311_ADC_REG1B, 0xEA);
    return 0;
}

static int es8311_codec_init(luat_audio_codec_conf_t* conf,uint8_t mode){
    uint8_t temp1 = 0, temp2 = 0, temp3 = 0;
    if (conf->pa_pin != -1){
        luat_gpio_mode(conf->pa_pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, !conf->pa_on_level);
        luat_gpio_set(conf->pa_pin, !conf->pa_on_level);
    }
    temp1 = es8311_read_reg(conf,ES8311_CHD1_REGFD);
    temp2 = es8311_read_reg(conf,ES8311_CHD2_REGFE);
    temp3 = es8311_read_reg(conf,ES8311_CHVER_REGFF);
    if(temp1 != 0x83 || temp2 != 0x11){
        LLOGE("codec err, id = 0x%x 0x%x ver = 0x%x", temp1, temp2, temp3);
        return -1;
    }
    es8311_reg_init(conf);
    switch (mode){
        case LUAT_CODEC_MODE_MASTER:
            es8311_write_reg(conf,ES8311_RESET_REG00, 0xC0);
            break;
        case LUAT_CODEC_MODE_SLAVE:
            es8311_write_reg(conf,ES8311_RESET_REG00, 0x80);
            break;
        default:
            break;
    }
    return 0;
}

static int es8311_codec_deinit(luat_audio_codec_conf_t* conf){

    return 0;
}

static void es8311_codec_pa(luat_audio_codec_conf_t* conf,uint8_t on){
    if (conf->pa_pin == LUAT_CODEC_PA_NONE) return;
	if (on){
        luat_rtos_task_sleep(conf->dummy_time_len);
        luat_gpio_set(conf->pa_pin, conf->pa_on_level);
        luat_rtos_task_sleep(conf->pa_delay_time);
	}else{	
        luat_gpio_set(conf->pa_pin, !conf->pa_on_level);
	}
}

static int es8311_codec_control(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data){
    switch (cmd){
        case LUAT_CODEC_MODE_NORMAL:
            es8311_mode_normal(conf,(uint8_t)data);
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

        case LUAT_CODEC_SET_RATE:
            es8311_codec_samplerate(conf,(uint16_t)data);
            break;
        case LUAT_CODEC_SET_BITS:
            es8311_codec_samplebits(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_SET_CHANNEL:
            es8311_codec_channels(conf,(uint8_t)data);
            break;
        case LUAT_CODEC_SET_PA:
            es8311_codec_pa(conf,(uint8_t)data);
            break;
        default:
            break;
    }
    return 0;
}

#define IS_DMIC             0
static int es8311_codec_start(luat_audio_codec_conf_t* conf){
    // uint8_t adcIface = 0, dacIface = 0;
    // dacIface = es8311_read_reg(conf,ES8311_SDPIN_REG09) & 0xBF;
    // adcIface = es8311_read_reg(conf,ES8311_SDPOUT_REG0A) & 0xBF;
    // adcIface &= ~(BIT(6));
    // dacIface &= ~(BIT(6));
    // es8311_write_reg(conf,ES8311_SDPIN_REG09,   dacIface);
    // es8311_write_reg(conf,ES8311_SDPOUT_REG0A,  adcIface);
    // es8311_write_reg(conf,ES8311_ADC_REG17,     0x88/*0xBF*/);
    // es8311_write_reg(conf,ES8311_SYSTEM_REG0E,  0x02);
    // es8311_write_reg(conf,ES8311_SYSTEM_REG12,  0x28/*0x00*/);
    // es8311_write_reg(conf,ES8311_SYSTEM_REG14,  0x18/*0x1A*/);
    // // pdm dmic enable or disable
    // int regv = 0;
    // if (IS_DMIC){
    //     regv = es8311_read_reg(conf,ES8311_SYSTEM_REG14);
    //     regv |= 0x40;
    //     es8311_write_reg(conf,ES8311_SYSTEM_REG14, regv);
    // }else{
    //     regv = es8311_read_reg(conf,ES8311_SYSTEM_REG14);
    //     regv &= ~(0x40);
    //     es8311_write_reg(conf,ES8311_SYSTEM_REG14, regv);
    // }
    // es8311_write_reg(conf,ES8311_SYSTEM_REG14, 0x18);  //add for debug
    // es8311_write_reg(conf,ES8311_SYSTEM_REG0D, 0x01);
    // es8311_write_reg(conf,ES8311_ADC_REG15, 0x00/*0x40*/);
    // es8311_write_reg(conf,ES8311_DAC_REG37, 0x48);
    // es8311_write_reg(conf,ES8311_GP_REG45, 0x00);
    // // set internal reference signal (ADCL + DACR)
    // es8311_write_reg(conf,ES8311_GPIO_REG44, 0x00/*0x50*/);
    es8311_codec_pa(conf,1);
    return 0;
}

static int es8311_codec_stop(luat_audio_codec_conf_t* conf){
    es8311_mode_standby(conf,LUAT_CODEC_MODE_ALL);
    es8311_codec_pa(conf,0);
    return 0;
}

luat_audio_codec_opts_t codec_opts_es8311 = {
    .name = "es8311",
    .init = es8311_codec_init,
    .deinit = es8311_codec_deinit,
    .control = es8311_codec_control,
    .start = es8311_codec_start,
    .stop = es8311_codec_stop,
};
































