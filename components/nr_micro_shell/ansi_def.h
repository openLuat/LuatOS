/**
 * @file      ansi_def.h
 * @author    Ji Youzhou
 * @version   V0.1
 * @date      11 June 2020
 * @brief     [brief]
 * *****************************************************************************
 * @attention
 * 
 * MIT License
 * 
 * Copyright (C) 2019 Ji Youzhou. or its affiliates.  All Rights Reserved.
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * 
 * Change Logs:
 * Date             Author              Notes
 * 2020-6-11        Ji Youzhou          first version
 * 
 */


/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __ansi_def_h
#define __ansi_def_h

#ifdef __cplusplus
extern "C"
{
#endif

/* Includes ------------------------------------------------------------------*/
#include "nr_micro_shell_config.h"

#define NR_ANSI_CTRL_MAX_LEN 20
#define NR_ANSI_MAX_EX_DATA_NUM 1

    enum
    {
        ANSI_ENABLE_SHOW,
        ANSI_DISABLE_SHOW
    };

    typedef struct nr_ansi_struct
    {
        short p;
        unsigned int counter;
        char current_line[NR_ANSI_LINE_SIZE];

        char combine_buf[NR_ANSI_CTRL_MAX_LEN];
        char cmd_num;
        char combine_state;
    } ansi_st;

    typedef void (*ansi_fun_t)(ansi_st *);

#define NR_ANSI_SET_TEXT(cmd) ((const char *)"\033["##cmd##"m") /** the form of set text font */

/** set the color of background */
#define NR_ANSI_BBLACK "40"
#define NR_ANSI_BRED "41"
#define NR_ANSI_BGREEN "42"
#define NR_ANSI_BGRAY "43"
#define NR_ANSI_BBLUE "44"
#define NR_ANSI_BPURPLE "45"
#define NR_ANSI_BAQUAM "46"
#define NR_ANSI_BWHITE "47"

/** set the color of character */
#define NR_ANSI_FBLACK "30"
#define NR_ANSI_FRED "31"
#define NR_ANSI_FGREEN "32"
#define NR_ANSI_FGRAY "33"
#define NR_ANSI_FBLUE "34"
#define NR_ANSI_FPURPLE "35"
#define NR_ANSI_FAQUAM "36"
#define NR_ANSI_FWHITE "37"

/** special effect */
#define NR_ANSI_NORMAL "0"
#define NR_ANSI_BRIGHT "1"
#define NR_ANSI_UNDERLINE "4"
#define NR_ANSI_FLASH "5"
#define NR_ANSI_INVERSE "7"
#define NR_ANSI_INVISABLE "8"

/****************************************************/

/** clear code */
#define NR_ANSI_CLEAR_RIGHT "\033[K"
#define NR_ANSI_CLEAR_LEFT "\033[1K"
#define NR_ANSI_CLEAR_WHOLE "\033[2K"

#define NR_ANSI_CLEAR_SCREEN "\033[2J"

#define NR_ANSI_HIDE_COURSER "\033[?25l"
#define NR_ANSI_SHOW_COURSER "\033[?25h"

#define NR_ANSI_SET_FONT(cmd) ((const char *)"\033["#cmd"I")
#define NR_ANSI_CLR_R_NCHAR(cmd) ((const char *)"\033["#cmd"X")
#define NR_ANSI_CLR_R_MV_L_NCHAR(cmd) ((const char *)"\033["#cmd"P")

/** move course code */
#define NR_ANSI_MV_L_N(n) ((const char *)"\033["#n"D")
#define NR_ANSI_MV_R_N(n) ((const char *)"\033["#n"C")

#define NR_ANSI_NORMAL "0"
#define NR_ANSI_SONG "1"
#define NR_ANSI_HEI "2"
#define NR_ANSI_KAI "3"

#ifdef __cplusplus
}
#endif

#endif
/******************* (C) COPYRIGHT 2019 Ji Youzhou *****END OF FILE*****************/
