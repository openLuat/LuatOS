/**************************************************************************
 *              Copyright (C), AirM2M Tech. Co., Ltd.
 *
 * Name:    ucs2_to_gb2312.c
 * Author:  liweiqiang
 * Version: V0.1
 * Date:    2013/7/15
 *
 * Description:
 *          ucs2 ×ª»» gb2312
 **************************************************************************/

#include "stdio.h"
#include "errno.h"
#include "luat_base.h"
#define u16 uint16_t
#define u8 uint8_t

#include "ucs2_to_gb2312_table.h"

#include "ucs2_to_gb2312_offset.h"

const u8 number_of_bit_1[256] = 
{
    0x00, 0x01, 0x01, 0x02, 0x01, 0x02, 0x02, 0x03,
    0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04,
    0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
    0x01, 0x02, 0x02, 0x03, 0x02, 0x03, 0x03, 0x04,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
    0x02, 0x03, 0x03, 0x04, 0x03, 0x04, 0x04, 0x05,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06,
    0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
    0x03, 0x04, 0x04, 0x05, 0x04, 0x05, 0x05, 0x06, 
    0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
    0x04, 0x05, 0x05, 0x06, 0x05, 0x06, 0x06, 0x07,
    0x05, 0x06, 0x06, 0x07, 0x06, 0x07, 0x07, 0x08,
};

/* 0x4E00 <= ucs2 < 0xA000 */ 
static u16 get_ucs2_offset(u16 ucs2)
{
    u16   offset, page, tmp;
    u8    *mirror_ptr, ch;

    page = (ucs2>>8) - 0x4E;
    ucs2 &= 0xFF;

    tmp        = ucs2>>6; /* now 0 <= tmp < 4  */ 
    offset     = ucs2_index_table_4E00_9FFF[page][tmp];  
    mirror_ptr = (u8*)&ucs2_mirror_4E00_9FFF[page][tmp<<3]; /* [0, 8, 16, 24] */ 

    tmp = ucs2&0x3F; /* mod 64 */ 

    while(tmp >= 8)
    {
        offset += number_of_bit_1[*mirror_ptr];
        mirror_ptr++;
        tmp -= 8;
    }

    ch = *mirror_ptr;
    if(ch&(0x1<<tmp))
    {   /* Ok , this ucs2 can be covert to GB2312. */ 
        while(tmp) 
        { 
            if(ch&0x1)
            offset++;
            ch>>=1;
            tmp--;
        }
        return offset;
    }

    return (u16)(-1);
}

/*+\NEW\liweiqiang\2013.11.26\ÍêÉÆgb2312<->ucs2(ucs2be)±àÂë×ª»»*/
size_t iconv_ucs2_to_gb2312_endian(char **_inbuf, size_t *inbytesleft, char **_outbuf, size_t *outbytesleft, int endian)
{
    u16 offset, gb2312 = 0xA1A1; 
    u16 ucs2;
    size_t gb_length = 0;
    u16 *ucs2buf = (u16*)*_inbuf;
    char *outbuf = (char *)*_outbuf;
    size_t inlen = *inbytesleft/2;
    size_t outlen = *outbytesleft;
    size_t ret = 0;

    while(inlen > 0)
    {
        if(gb_length+2 > outlen)
        {
            errno = E2BIG;
            ret = -1;
            goto ucs2_to_gb2312_exit;
        }

        ucs2 = *ucs2buf++;

        if(endian == 1)
            ucs2 = (ucs2<<8)|(ucs2>>8);

        gb2312 = 0xA1A1;
        //End 7205
  
        if(0x80 > ucs2)
        {
            // can be convert to ASCII char
            *outbuf++ = (u8)ucs2;
            gb_length++;
        }
        else
        {
            if((0x4E00 <= ucs2) && (0xA000 > ucs2))
            {
                offset = get_ucs2_offset(ucs2);
                if((u16)(-1) != offset)
                {
                    gb2312 = ucs2_to_gb2312_table[offset];
                }
            }
            else
            {
                u16 u16count = sizeof(tab_UCS2_to_GBK)/4;
                u16 ui = 0;
                for(ui=0;ui<u16count;ui++)
                {
                    if(ucs2 == tab_UCS2_to_GBK[ui][0])
                    {
                        gb2312 = tab_UCS2_to_GBK[ui][1];
                    }
                }
                
            }
#if 0
            else
            {
                // Is chinese symbol ?
                // try search another table
                for( offset = 0; offset < 94 * 16; offset++ )
                {
                    if( ucs2 == gb2312_to_ucs2_table[ offset ] )
                    {
                        gb2312 = offset / 94 + 0xA0;             
                        gb2312 = (gb2312 << 8) + (offset % 94 + 0xA1);
                        break;
                    }
                }
            }
#endif
 
            *outbuf++ = (u8)(gb2312>>8);
            *outbuf++ = (u8)(gb2312);
            gb_length += 2;
        }
        
        inlen--;
    }

    if(inlen > 0)
    {
        errno = EINVAL;
        ret = -1;
    }

ucs2_to_gb2312_exit:
    *inbytesleft = inlen;
    *outbytesleft -= gb_length;

    return ret;
}

size_t iconv_ucs2_to_gb2312(char **_inbuf, size_t *inbytesleft, char **_outbuf, size_t *outbytesleft)
{
    return iconv_ucs2_to_gb2312_endian(_inbuf, inbytesleft, _outbuf, outbytesleft, 0);
}

size_t iconv_ucs2be_to_gb2312(char **_inbuf, size_t *inbytesleft, char **_outbuf, size_t *outbytesleft)
{
    return iconv_ucs2_to_gb2312_endian(_inbuf, inbytesleft, _outbuf, outbytesleft, 1);
}
/*-\NEW\liweiqiang\2013.11.26\ÍêÉÆgb2312<->ucs2(ucs2be)±àÂë×ª»»*/

