

#ifndef AT_TOK_H
#define AT_TOK_H 1

int at_tok_start(char **p_cur);
int at_tok_nextint(char **p_cur, int *p_out);
int at_tok_nexthexint(char **p_cur, int *p_out);

int at_tok_nextbool(char **p_cur, char *p_out);
int at_tok_nextstr(char **p_cur, char **out);

int at_tok_hasmore(char **p_cur);

int at_tok_nextparenthes(char **p_cur,char **p_out);


#endif /*AT_TOK_H */
