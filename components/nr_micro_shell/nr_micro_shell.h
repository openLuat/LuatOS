/**
 * @file      nr_micro_shell.h
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
#ifndef __nr_micro_shell_h
#define __nr_micro_shell_h

#ifdef __cplusplus
extern "C"
{
#endif

    /* Includes ------------------------------------------------------------------*/
#include "stdio.h"
#include "nr_micro_shell_config.h"
#include "ansi.h"

#ifndef shell_printf
#define shell_printf(fmt, args...) printf(fmt, ##args);
#endif

    typedef void (*shell_fun_t)(char, char *);

    typedef struct static_cmd_function_struct
    {
        char cmd[NR_SHELL_CMD_NAME_MAX_LENGTH];
        void (*fp)(char argc, char *argv);
        char *description;
    } static_cmd_st;

    typedef struct shell_history_queue_struct
    {
        unsigned short int fp;
        unsigned short int rp;

        unsigned short int len;
        unsigned short int index;

        unsigned short int store_front;
        unsigned short int store_rear;
        unsigned short int store_num;

        char queue[NR_SHELL_MAX_CMD_HISTORY_NUM + 1];
        char buf[NR_SHELL_CMD_HISTORY_BUF_LENGTH + 1];

    } shell_his_queue_st;

    typedef struct nr_shell
    {
        char user_name[NR_SHELL_USER_NAME_MAX_LENGTH];
        const static_cmd_st *static_cmd;
        shell_his_queue_st cmd_his;
    } shell_st;

    void _shell_init(shell_st *shell);
    void shell_parser(shell_st *shell, char *str);
    char *shell_cmd_complete(shell_st *shell, char *str);
    void shell_his_queue_init(shell_his_queue_st *queue);
    void shell_his_queue_add_cmd(shell_his_queue_st *queue, char *str);
    unsigned short int shell_his_queue_search_cmd(shell_his_queue_st *queue, char *str);
    void shell_his_copy_queue_item(shell_his_queue_st *queue, unsigned short i, char *str_buf);

    extern shell_st nr_shell;

#define shell_init()            \
    {                           \
        ansi_init(&nr_ansi);    \
        _shell_init(&nr_shell); \
    }

#if NR_SHELL_END_OF_LINE == 1
#define NR_SHELL_END_CHAR '\r'
#else
#define NR_SHELL_END_CHAR '\n'
#endif
	
#if NR_SHELL_END_OF_LINE == 0
#define NR_SHELL_NEXT_LINE "\n"
#endif

#if NR_SHELL_END_OF_LINE == 1
#define NR_SHELL_NEXT_LINE "\r\n"
#endif
	
#if NR_SHELL_END_OF_LINE == 2
#define NR_SHELL_NEXT_LINE "\r\n"
#endif

#define shell(c)                                             \
    {                                                        \
        if (ansi_get_char(c, &nr_ansi) == NR_SHELL_END_CHAR) \
        {                                                    \
            shell_parser(&nr_shell, nr_ansi.current_line);   \
            ansi_clear_current_line(&nr_ansi);               \
        }                                                    \
    }

#ifdef USING_RT_THREAD
    int rt_nr_shell_system_init(void);
#endif

#define NR_USED __attribute__((used))
#define NR_SECTION(x) __attribute__((section(".rodata.nr_shell_cmd" x)))
#define NR_SHELL_CMD_EXPORT_START(cmd, func) \
    NR_USED const static_cmd_st _nr_cmd_start_ NR_SECTION("0.end") = {#cmd, NULL}
#define NR_SHELL_CMD_EXPORT(cmd, func) \
    NR_USED const static_cmd_st _nr_cmd_##cmd NR_SECTION("1") = {#cmd, func}
#define NR_SHELL_CMD_EXPORT_END(cmd, func) \
    NR_USED const static_cmd_st _nr_cmd_end_ NR_SECTION("1.end") = {#cmd, NULL}

    
#ifdef NR_SHELL_USING_EXPORT_CMD
	extern const static_cmd_st _nr_cmd_start_;
#define nr_cmd_start_add (&_nr_cmd_start_+1)
#else
	extern const static_cmd_st static_cmd[];
#define nr_cmd_start_add (&static_cmd[0])
#endif

#ifdef __cplusplus
}
#endif

#endif
/******************* (C) COPYRIGHT 2019 Ji Youzhou *****END OF FILE*****************/
