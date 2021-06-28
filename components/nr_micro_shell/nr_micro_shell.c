/**
 * @file      nr_micro_shell.c
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
#include "nr_micro_shell.h"
#include <string.h>
#include <ctype.h>


NR_SHELL_CMD_EXPORT_START(0,NULL);
NR_SHELL_CMD_EXPORT_END(n,NULL);

shell_st nr_shell =
    {
        .user_name = NR_SHELL_USER_NAME,
        .static_cmd = nr_cmd_start_add,
};

static char *nr_shell_strtok(char *string_org, const char *demial)
{
	static unsigned char *last;
	unsigned char *str;
	const unsigned char *ctrl = (const unsigned char *)demial;
	unsigned char map[32];
	int count;

	for (count = 0; count < 32; count++)
	{
		map[count] = 0;
	}
	do
	{
		map[*ctrl >> 3] |= (1 << (*ctrl & 7));
	} while (*ctrl++);
	if (string_org)
	{
		str = (unsigned char *)string_org;
	}
	else
	{
		str = last;
	}
	while ((map[*str >> 3] & (1 << (*str & 7))) && *str)
	{
		str++;
	}
	string_org = (char *)str;
	for (; *str; str++)
	{
		if (map[*str >> 3] & (1 << (*str & 7)))
		{
			*str++ = '\0';
			break;
		}
	}
	last = str;
	if (string_org == (char *)str)
	{
		return NULL;
	}
	else
	{
		return string_org;
	}
}

void _shell_init(shell_st *shell)
{

#ifdef NR_SHELL_SHOW_LOG
	shell_printf(" _   _ ____    __  __ _                  ____  _          _ _ \r\n");
	shell_printf("| \\ | |  _ \\  |  \\/  (_) ___ _ __ ___   / ___|| |__   ___| | |\r\n");
	shell_printf("|  \\| | |_) | | |\\/| | |/ __| '__/ _ \\  \\___ \\| '_ \\ / _ \\ | |\r\n");
	shell_printf("| |\\  |  _ <  | |  | | | (__| | | (_) |  ___) | | | |  __/ | |\r\n");
	shell_printf("|_| \\_|_| \\_\\ |_|  |_|_|\\___|_|  \\___/  |____/|_| |_|\\___|_|_|\r\n");
	shell_printf("                                                              \r\n");
#endif

	shell_printf("%s",shell->user_name);
	shell_his_queue_init(&shell->cmd_his);
	shell_his_queue_add_cmd(&shell->cmd_his, "ls cmd");
	shell->cmd_his.index = 1;
}

shell_fun_t shell_search_cmd(shell_st *shell, char *str)
{
	unsigned int i = 0;
	while (shell->static_cmd[i].fp != NULL)
	{
		if (!strcmp(str, shell->static_cmd[i].cmd))
		{
			return shell->static_cmd[i].fp;
		}
		i++;
	}

	return NULL;
}

void shell_parser(shell_st *shell, char *str)
{
	char argc = 0;
	char argv[NR_SHELL_CMD_LINE_MAX_LENGTH + NR_SHELL_CMD_PARAS_MAX_NUM];
	char *token = str;
	shell_fun_t fp;
	char index = NR_SHELL_CMD_PARAS_MAX_NUM;

	if (shell_his_queue_search_cmd(&shell->cmd_his, str) == 0 && str[0] != '\0')
	{
		shell_his_queue_add_cmd(&shell->cmd_his, str);
	}

	if (strlen(str) > NR_SHELL_CMD_LINE_MAX_LENGTH)
	{
		shell_printf("this command is too long."NR_SHELL_NEXT_LINE);
		shell_printf("%s",shell->user_name);
		return;
	}

	token = nr_shell_strtok(token, " ");
	fp = shell_search_cmd(shell, str);

	if (fp == NULL)
	{
		if (isalpha(str[0]))
		{
			shell_printf("no command named: %s"NR_SHELL_NEXT_LINE, token);
		}
	}
	else
	{
		argv[argc] = index;
		strcpy(argv + index, str);
		index += strlen(str) + 1;
		argc++;

		token = nr_shell_strtok(NULL, " ");
		while (token != NULL)
		{
			argv[argc] = index;
			strcpy(argv + index, token);
			index += strlen(token) + 1;
			argc++;
			token = nr_shell_strtok(NULL, " ");
		}
	}

	if (fp != NULL)
	{
		fp(argc, argv);
	}

	shell_printf("%s",shell->user_name);
}

char *shell_cmd_complete(shell_st *shell, char *str)
{
	char *temp = NULL;
	unsigned char i;
	char *best_matched = NULL;
	unsigned char min_position = 255;

	for (i = 0; shell->static_cmd[i].cmd[0] != '\0'; i++)
	{
		temp = NULL;
		temp = strstr(shell->static_cmd[i].cmd, str);
		if (temp != NULL && ((unsigned long)temp - (unsigned long)(&shell->static_cmd[i]) < min_position))
		{
			min_position = (unsigned long)temp - (unsigned long)(&shell->static_cmd[i]);
			best_matched = (char *)&shell->static_cmd[i];
			if (min_position == 0)
			{
				break;
			}
		}
	}

	return best_matched;
}

void shell_his_queue_init(shell_his_queue_st *queue)
{
	queue->fp = 0;
	queue->rp = 0;
	queue->len = 0;

	queue->store_front = 0;
	queue->store_rear = 0;
	queue->store_num = 0;
}

void shell_his_queue_add_cmd(shell_his_queue_st *queue, char *str)
{
	unsigned short int str_len;
	unsigned short int i;

	str_len = strlen(str);

	if (str_len > NR_SHELL_CMD_HISTORY_BUF_LENGTH)
	{
		return;
	}

	while (str_len > (NR_SHELL_CMD_HISTORY_BUF_LENGTH - queue->store_num) || queue->len == NR_SHELL_MAX_CMD_HISTORY_NUM)
	{

		queue->fp++;
		queue->fp = (queue->fp > NR_SHELL_MAX_CMD_HISTORY_NUM) ? 0 : queue->fp;
		queue->len--;

		if (queue->store_front <= queue->queue[queue->fp])
		{
			queue->store_num -= queue->queue[queue->fp] - queue->store_front;
		}
		else
		{
			queue->store_num -= queue->queue[queue->fp] + NR_SHELL_CMD_HISTORY_BUF_LENGTH - queue->store_front + 1;
		}

		queue->store_front = queue->queue[queue->fp];
	}

	queue->queue[queue->rp] = queue->store_rear;
	queue->rp++;
	queue->rp = (queue->rp > NR_SHELL_MAX_CMD_HISTORY_NUM) ? 0 : queue->rp;
	queue->len++;

	for (i = 0; i < str_len; i++)
	{
		queue->buf[queue->store_rear] = str[i];
		queue->store_rear++;
		queue->store_rear = (queue->store_rear > NR_SHELL_CMD_HISTORY_BUF_LENGTH) ? 0 : queue->store_rear;
		queue->store_num++;
	}
	queue->queue[queue->rp] = queue->store_rear;
}

unsigned short int shell_his_queue_search_cmd(shell_his_queue_st *queue, char *str)
{
	unsigned short int str_len;
	unsigned short int i, j;
	unsigned short int index_temp = queue->fp;
	unsigned short int start;
	unsigned short int end;
	unsigned short int cmd_len;
	unsigned short int matched_id = 0;
	unsigned short int buf_index;

	if (queue->len == 0)
	{
		return matched_id;
	}
	else
	{
		str_len = strlen(str);
		for (i = 0; i < queue->len; i++)
		{
			start = queue->queue[index_temp];
			index_temp++;
			index_temp = (index_temp > NR_SHELL_MAX_CMD_HISTORY_NUM) ? 0 : index_temp;
			end = queue->queue[index_temp];

			if (start <= end)
			{
				cmd_len = end - start;
			}
			else
			{
				cmd_len = NR_SHELL_CMD_HISTORY_BUF_LENGTH + 1 - start + end;
			}

			if (cmd_len == str_len)
			{
				matched_id = i + 1;
				buf_index = start;
				for (j = 0; j < str_len; j++)
				{
					if (queue->buf[buf_index] != str[j])
					{
						matched_id = 0;
						break;
					}

					buf_index++;
					buf_index = (buf_index > NR_SHELL_CMD_HISTORY_BUF_LENGTH) ? 0 : buf_index;
				}

				if (matched_id != 0)
				{
					return matched_id;
				}
			}
		}

		return 0;
	}
}

void shell_his_copy_queue_item(shell_his_queue_st *queue, unsigned short i, char *str_buf)
{
	unsigned short index_temp;
	unsigned short start;
	unsigned short end;
	unsigned short j;

	if (i <= queue->len)
	{
		index_temp = queue->fp + i - 1;
		index_temp = (index_temp > NR_SHELL_MAX_CMD_HISTORY_NUM) ? (index_temp - NR_SHELL_MAX_CMD_HISTORY_NUM - 1) : index_temp;

		start = queue->queue[index_temp];
		index_temp++;
		index_temp = (index_temp > NR_SHELL_MAX_CMD_HISTORY_NUM) ? 0 : index_temp;
		end = queue->queue[index_temp];

		if (start < end)
		{
			for (j = start; j < end; j++)
			{
				str_buf[j - start] = queue->buf[j];
			}

			str_buf[j - start] = '\0';
		}
		else
		{
			for (j = start; j < NR_SHELL_CMD_HISTORY_BUF_LENGTH + 1; j++)
			{
				str_buf[j - start] = queue->buf[j];
			}

			for (j = 0; j < end; j++)
			{
				str_buf[j + NR_SHELL_CMD_HISTORY_BUF_LENGTH + 1 - start] = queue->buf[j];
			}

			str_buf[j + NR_SHELL_CMD_HISTORY_BUF_LENGTH + 1 - start] = '\0';
		}
	}
}

/******************* (C) COPYRIGHT 2019 Ji Youzhou *****END OF FILE*****************/
