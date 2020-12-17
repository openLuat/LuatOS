/**************************************************************************
 *              Copyright (C), AirM2M Tech. Co., Ltd.
 *
 * Name:    iconv.c
 * Author:  liweiqiang
 * Version: V0.1
 * Date:    2013/7/15
 *
 * Description:
 *          字符编码转换
 **************************************************************************/

#include <string.h>
#include "iconv.h"
#include "prv_iconv.h"

typedef struct builtin_iconv_map_tag
{
    const char      *from;
    const char      *to;
    const iconv_fct fct;
}builtin_iconv_map;

static const builtin_iconv_map iconv_map[] =
{
    {"ucs2",    "gb2312",   iconv_ucs2_to_gb2312},
/*+\NEW\liweiqiang\2013.11.26\完善gb2312<->ucs2(ucs2be)编码转换*/
    {"ucs2be",  "gb2312",   iconv_ucs2be_to_gb2312},
    {"gb2312",  "ucs2",     iconv_gb2312_to_ucs2},
    {"gb2312",  "ucs2be",   iconv_gb2312_to_ucs2be},
/*-\NEW\liweiqiang\2013.11.26\完善gb2312<->ucs2(ucs2be)编码转换*/
/*+\NEW\liweiqiang\2013.7.19\增加utf8<->ucs2,ucs2be编码转换*/
    {"utf8",    "ucs2",     iconv_utf8_to_ucs2},
    {"utf8",    "ucs2be",   iconv_utf8_to_ucs2be},
    {"ucs2",    "utf8",     iconv_ucs2_to_utf8},
    {"ucs2be",    "utf8",     iconv_ucs2be_to_utf8},
/*-\NEW\liweiqiang\2013.7.19\增加utf8<->ucs2,ucs2be编码转换*/
};

iconv_t iconv_open (const char *__tocode, const char *__fromcode)
{
    size_t i;

    for(i = 0; i < sizeof(iconv_map)/sizeof(iconv_map[0]); i++)
    {
        if(strcmp(iconv_map[i].from, __fromcode) == 0 &&
            strcmp(iconv_map[i].to, __tocode) == 0)
        {
            return (iconv_t)&iconv_map[i];
        }
    }

    return (iconv_t)-1;
}

size_t iconv (iconv_t __cd, char ** __inbuf,
		     size_t * __inbytesleft,
		     char ** __outbuf,
		     size_t * __outbytesleft)
{
    builtin_iconv_map *_map_cd = (builtin_iconv_map *)__cd;

    if(__inbuf == NULL || *__inbuf == NULL)
        return (size_t)-1;

    if(_map_cd < &iconv_map[0] &&
        _map_cd > &iconv_map[sizeof(iconv_map)/sizeof(iconv_map[0])])
        return (size_t)-1;

    return _map_cd->fct(__inbuf, __inbytesleft, __outbuf, __outbytesleft);
}

int iconv_close (iconv_t __cd)
{
    return 0;
}

