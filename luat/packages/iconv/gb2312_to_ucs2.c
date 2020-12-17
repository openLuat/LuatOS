/**************************************************************************
 *              Copyright (C), AirM2M Tech. Co., Ltd.
 *
 * Name:    gb2312_to_ucs2.c
 * Author:  liweiqiang
 * Version: V0.1
 * Date:    2013/11/26
 *
 * Description:
 *          gb2312 ×ª»» ucs2
 **************************************************************************/

#include "stdio.h"
#include "errno.h"
#include "luat_base.h"

#include "gb2312_to_ucs2_table.h"

#define u16 uint16_t
#define u8 uint8_t

size_t iconv_gb2312_to_ucs2_endian(char **_inbuf, size_t *inbytesleft, char **_outbuf, size_t *outbytesleft, int endian)
{
    u16 offset,gb2312;
    char *gbbuf = *_inbuf;
    u16 *ucs2buf = (u16*)*_outbuf;
    u16 ucs2;
    size_t ucs2len = 0;
    size_t inlen = *inbytesleft;
    size_t outlen = *outbytesleft;
    size_t ret = 0;
    
    while(inlen > 0)
    {
        if(ucs2len+2 > outlen)
        {
            errno = E2BIG;
            ret = -1;
            goto gb2312_to_ucs2_exit;
        }

        gb2312 = *gbbuf++;

        if(gb2312 < 0x80)
        {
            ucs2 = gb2312;
            inlen--;
        }
        else if(inlen >= 2)
        {
            gb2312 = (gb2312<<8) + ((*gbbuf++)&0x00ff);
            inlen -= 2;
            
            offset = ((gb2312>>8) - 0xA0)*94/*(0xFE-0xA1+1)*/ + ((gb2312&0x00ff) - 0xA1);
            ucs2 = gb2312_to_ucs2_table[offset];
        }
        else
        {
            break;
        }

        if(endian == 1)
            ucs2 = (ucs2<<8)|(ucs2>>8);

        *ucs2buf++ = ucs2;
        ucs2len += 2;
    }

    if(inlen > 0)
    {
        errno = EINVAL;
        ret = -1;
    }

gb2312_to_ucs2_exit:
    *_inbuf = gbbuf;

    *inbytesleft = inlen;
    *outbytesleft -= ucs2len;

    return ret;
}

size_t iconv_gb2312_to_ucs2(char **_inbuf, size_t *inbytesleft, char **_outbuf, size_t *outbytesleft)
{
    return iconv_gb2312_to_ucs2_endian(_inbuf, inbytesleft, _outbuf, outbytesleft, 0);
}

size_t iconv_gb2312_to_ucs2be(char **_inbuf, size_t *inbytesleft, char **_outbuf, size_t *outbytesleft)
{
    return iconv_gb2312_to_ucs2_endian(_inbuf, inbytesleft, _outbuf, outbytesleft, 1);
}
