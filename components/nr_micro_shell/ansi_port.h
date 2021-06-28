/**
 * @file      ansi_port.h
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

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __ansi_port_h
#define __ansi_port_h

#ifdef __cplusplus
extern "C"
{
#endif

    /* Includes ------------------------------------------------------------------*/
#include "ansi_def.h"

    void nr_ansi_ctrl_common_slover(ansi_st *ansi);
    void nr_ansi_in_newline(ansi_st *ansi);
    void nr_ansi_in_backspace(ansi_st *ansi);
    void nr_ansi_in_up(ansi_st *ansi);
    void nr_ansi_in_down(ansi_st *ansi);
    void nr_ansi_in_left(ansi_st *ansi);
    void nr_ansi_in_right(ansi_st *ansi);
    void nr_ansi_in_tab(ansi_st *ansi);
    void nr_ansi_in_enter(ansi_st *ansi);
    void nr_ansi_in__(ansi_st *ansi);
    void nr_ansi_common_char_slover(ansi_st *ansi, char x);

/** special characters functions \b,\n,\r,\t*/
#define nr_ansi_in_bsb_function nr_ansi_in_backspace
#define nr_ansi_in_bsn_function nr_ansi_in_newline
#define nr_ansi_in_bsr_function nr_ansi_in_enter
#define nr_ansi_in_bst_function nr_ansi_in_tab

/** control characters functions */
#define nr_ansi_in_m_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_I_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_A_function nr_ansi_in_up
#define nr_ansi_in_B_function nr_ansi_in_down
#define nr_ansi_in_C_function nr_ansi_in_right
#define nr_ansi_in_D_function nr_ansi_in_left
#define nr_ansi_in_X_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_K_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_M_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_P_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_J_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_at_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_L_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_l_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_h_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_n_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_H_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_s_function nr_ansi_ctrl_common_slover
#define nr_ansi_in_u_function nr_ansi_ctrl_common_slover
#define nr_ansi_in___function nr_ansi_in__

#ifdef __cplusplus
}
#endif

#endif
/******************* (C) COPYRIGHT 2019 Ji Youzhou *****END OF FILE*****************/
