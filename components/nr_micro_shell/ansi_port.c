/**
 * @file      ansi_port.c
 * @author    Ji Youzhou
 * @version   V0.1
 * @date      28 Oct 2019
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
 */

/* Includes ------------------------------------------------------------------*/
#include "ansi_port.h"
#include "ansi.h"
#include <stdio.h>
#include "nr_micro_shell.h"
#include <string.h>

// show string
void ansi_show_str(char *str, unsigned int len)
{
    unsigned int i;
    for (i = 0; i < len; i++)
    {
        ansi_show_char(str[i]);
    }
}

void nr_ansi_common_char_slover(ansi_st *ansi,char x)
{
	unsigned int i;
	
	if (ansi->counter < NR_ANSI_LINE_SIZE - 2)
    {
        if (ansi->p < ansi->counter)
        {
            for (i = ansi->counter; i > ansi->p; i--)
            {
                ansi->current_line[i] = ansi->current_line[i - 1];
            }
        }

        ansi->p++;
        ansi->counter++;

        ansi->current_line[ansi->p] = x;

        ansi->current_line[ansi->counter] = '\0';
		if(ansi->p+1 < ansi->counter)
		{
			shell_printf("\033[1@");
		}

        #ifndef NR_MICRO_SHELL_SIMULATOR	
        ansi_show_char(x);
        #endif	
    }
    else
    {
        ansi->counter = NR_ANSI_LINE_SIZE - 3;
        if (ansi->p >= ansi->counter)
        {
            ansi->p = ansi->counter - 1;
        }
        ansi->current_line[ansi->counter] = '\0';
    }
}

void nr_ansi_ctrl_common_slover(ansi_st *ansi)
{
    unsigned int i;
    for (i = 0; i < ansi->cmd_num; i++)
    {
        ansi_show_char((*(ansi->combine_buf + i)));
    }
}

// line break '\r' processing
void nr_ansi_in_enter(ansi_st *ansi)
{
#if NR_SHELL_END_OF_LINE == 1
	ansi->p = -1;
    ansi->counter = 0;

    nr_shell.cmd_his.index = nr_shell.cmd_his.len;
    ansi_show_char('\r');
    ansi_show_char('\n');
#else
    ansi_show_char('\r');
#endif
}

// line break '\n' processing
void nr_ansi_in_newline(ansi_st *ansi)
{
	ansi->p = -1;
    ansi->counter = 0;

    nr_shell.cmd_his.index = nr_shell.cmd_his.len;
#ifndef NR_MICRO_SHELL_SIMULATOR	
#if NR_SHELL_END_OF_LINE != 1
    ansi_show_char('\r');
    ansi_show_char('\n');
#else
    ansi_show_char('\n');
#endif
#endif
}

// Backspace '\b' processing
void nr_ansi_in_backspace(ansi_st *ansi)
{
    unsigned int i;

    if (ansi->p >= 0)
    {
        for (i = ansi->p; i < ansi->counter; i++)
        {
            ansi->current_line[i] = ansi->current_line[i + 1];
        }

        ansi->p--;
        ansi->counter--;

        ansi_show_char('\b');
#if NR_SHLL_FULL_ANSI == 1
        shell_printf(NR_ANSI_CLR_R_MV_L_NCHAR(1));
#endif
    }
}

// up key processing
void nr_ansi_in_up(ansi_st *ansi)
{
    if (nr_shell.cmd_his.index > 0)
    {
#if NR_SHLL_FULL_ANSI == 1
        shell_printf("\033[%dD", ansi->p + 1);
        shell_printf(NR_ANSI_CLEAR_RIGHT);
#else
        shell_printf("\r\n");
        shell_printf(nr_shell.user_name);
#endif

        shell_his_copy_queue_item(&nr_shell.cmd_his, nr_shell.cmd_his.index, ansi->current_line);
        ansi->counter = strlen(ansi->current_line);
        ansi->p = ansi->counter - 1;

        ansi_show_str(ansi->current_line, ansi->counter);
		
		nr_shell.cmd_his.index--;
        nr_shell.cmd_his.index = (nr_shell.cmd_his.index == 0) ? nr_shell.cmd_his.len : nr_shell.cmd_his.index;
    }
}

// down key processing
void nr_ansi_in_down(ansi_st *ansi)
{
    if (nr_shell.cmd_his.index > 0)
    {
#if NR_SHLL_FULL_ANSI == 1
        shell_printf("\033[%dD", ansi->p + 1);
        shell_printf(NR_ANSI_CLEAR_RIGHT);
#else
        shell_printf("\r\n");
        shell_printf(nr_shell.user_name);
#endif

        shell_his_copy_queue_item(&nr_shell.cmd_his, nr_shell.cmd_his.index, ansi->current_line);
        ansi->counter = strlen(ansi->current_line);
        ansi->p = ansi->counter - 1;

        ansi_show_str(ansi->current_line, ansi->counter);
		
		nr_shell.cmd_his.index++;
        nr_shell.cmd_his.index = (nr_shell.cmd_his.index > nr_shell.cmd_his.len) ? 1 : nr_shell.cmd_his.index;
    }
}

// left key <- processing
void nr_ansi_in_left(ansi_st *ansi)
{
    if (ansi->p > -1)
    {
        ansi->p--;
#if NR_SHLL_FULL_ANSI == 1
        shell_printf("\033[1D");
#endif
    }
}

// right key <- processing
void nr_ansi_in_right(ansi_st *ansi)
{
    if (ansi->p < (int)(ansi->counter - 1))
    {
        ansi->p++;
#if NR_SHLL_FULL_ANSI == 1
        shell_printf("\033[1C");
#endif
    }
}

// tab key processing
void nr_ansi_in_tab(ansi_st *ansi)
{
    unsigned char i;
    char *cmd;
    cmd = shell_cmd_complete(&nr_shell, ansi->current_line);
    if (cmd != NULL)
    {

        if (ansi->counter == 0)
        {
            shell_printf("\r\n");
            for (i = 0; nr_shell.static_cmd[i].fp != NULL; i++)
            {
                shell_printf("%s",nr_shell.static_cmd[i].cmd);
                shell_printf("\r\n");
            }

            shell_printf("%s",nr_shell.user_name);
        }
        else
        {
#if NR_SHLL_FULL_ANSI == 1
            shell_printf("\033[%dD", ansi->p + 1);
            shell_printf(NR_ANSI_CLEAR_RIGHT);
#else
            shell_printf("\r\n");
            shell_printf("%s",nr_shell.user_name);
#endif
            ansi->counter = strlen(cmd);
            ansi->p = ansi->counter - 1;
            strcpy(ansi->current_line, cmd);

            ansi_show_str(ansi->current_line, ansi->counter);
        }
    }
}

/*ansi delete*/
void nr_ansi_in__(ansi_st *ansi)
{
	unsigned int i;
	if(ansi->combine_buf[2] == '3')
	{
		for(i = ansi->p+1;i<ansi->counter;i++)
		{
			ansi->current_line[i] = ansi->current_line[i+1];
		}
		if((short)ansi->counter > ansi->p)
		{
			ansi->counter--;
#if NR_SHLL_FULL_ANSI == 1
			ansi_show_str("\033[1P",4);
#endif
		}
		
	}
}

/******************* (C) COPYRIGHT 2019 Ji Youzhou *****END OF FILE*****************/
