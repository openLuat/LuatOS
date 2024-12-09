/**
 * @file      ansi.c
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

/* Includes ------------------------------------------------------------------ */
#include "ansi.h"
#include <stdio.h>

ansi_st nr_ansi;

const char nr_ansi_in_cmd[] = {'m', 'I', 'A', 'B', 'C', 'D', 'X', 'K', 'M', 'P', 'J', '@', 'L', 'l', 'h', 'n', 'H', 's', 'u', '~','\0'};
void (*const nr_ansi_in_cmd_fun[])(ansi_st *) =
    {
        nr_ansi_in_m_function,
        nr_ansi_in_I_function,
        nr_ansi_in_A_function,
        nr_ansi_in_B_function,
        nr_ansi_in_C_function,
        nr_ansi_in_D_function,
        nr_ansi_in_X_function,
        nr_ansi_in_K_function,
        nr_ansi_in_M_function,
        nr_ansi_in_P_function,
        nr_ansi_in_J_function,
        nr_ansi_in_at_function,
        nr_ansi_in_L_function,
        nr_ansi_in_l_function,
        nr_ansi_in_h_function,
        nr_ansi_in_n_function,
        nr_ansi_in_H_function,
        nr_ansi_in_s_function,
        nr_ansi_in_u_function,
		nr_ansi_in___function,
	};

const char nr_ansi_in_special_symbol[] = {'\b', '\n', '\r', '\t', '\0'};
void (*const nr_ansi_in_special_symbol_fun[])(ansi_st *) =
    {
        nr_ansi_in_bsb_function,
        nr_ansi_in_bsn_function,
        nr_ansi_in_bsr_function,
        nr_ansi_in_bst_function};

int ansi_search_char(char x, const char *buf)
{
    int i = 0;
    for (i = 0; (buf[i] != x) && (buf[i] != '\0'); i++)
        ;
    if (buf[i] != '\0')
    {
        return i;
    }
    else
    {
        return -1;
    }
}

enum
{
    ANSI_NO_CTRL_CHAR,
	ANSI_MAYBE_CTRL_CHAR,
    ANSI_WAIT_CTRL_CHAR_END,
};

void ansi_init(ansi_st *ansi)
{
    ansi->counter = 0;
    ansi->p = -1;

    ansi->current_line[ansi->counter] = '\0';

    ansi->cmd_num = 0;
    ansi->combine_state = ANSI_NO_CTRL_CHAR;
}

void ansi_clear_current_line(ansi_st *ansi)
{
    ansi->counter = 0;
    ansi->p = -1;

    ansi->current_line[ansi->counter] = '\0';
}

char ansi_get_char(char x, ansi_st *ansi)
{
    int cmd_id = -1;

    if (ansi->combine_state == ANSI_NO_CTRL_CHAR)
    {
        cmd_id = ansi_search_char(x, nr_ansi_in_special_symbol);
        if (cmd_id >= 0)
        {
            if (nr_ansi_in_special_symbol_fun[cmd_id] != NULL)
            {
                nr_ansi_in_special_symbol_fun[cmd_id](ansi);
            }
        }
        else if (x == '\033')
        {
            ansi->combine_state = ANSI_WAIT_CTRL_CHAR_END;
            ansi->combine_buf[ansi->cmd_num] = x;
			ansi->cmd_num++;
        }
        else
        {
			nr_ansi_common_char_slover(ansi,x);
        }
    }
    else if (ansi->combine_state == ANSI_WAIT_CTRL_CHAR_END)
    {
        ansi->combine_buf[ansi->cmd_num] = x;

        if (('a' <= x && 'z' >= x) || ('A' <= x && 'Z' >= x) || x== '~')
        {
            cmd_id = ansi_search_char(x, nr_ansi_in_cmd);
            nr_ansi_in_cmd_fun[cmd_id](ansi);

            ansi->cmd_num = 0;
            ansi->combine_state = ANSI_NO_CTRL_CHAR;
        }
        else if (ansi->cmd_num > 18)
        {
            ansi->cmd_num = 0;
            ansi->combine_state = ANSI_NO_CTRL_CHAR;
        }
        else
        {
            ansi->cmd_num++;
        }
    }
    else
    {
        ansi->combine_state = ANSI_NO_CTRL_CHAR;
    }

    return x;
}

/******************* (C) COPYRIGHT 2019 Ji Youzhou *****END OF FILE*****************/
