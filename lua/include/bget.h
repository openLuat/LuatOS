/*
    Interface definitions for bget.c, the memory management package.
*/

typedef long bufsize;
void bpool(void *buffer, bufsize len);
void *bget(bufsize size);
void *bgetz(bufsize size);
void *bgetr(void *buffer, bufsize newsize);
void brel(void *buf);
void bectl(int (*compact)(bufsize sizereq, int sequence), void *(*acquire)(bufsize size), void (*release)(void *buf), bufsize pool_incr);
void bstats(bufsize *curalloc, bufsize *totfree, bufsize *maxfree, unsigned long  *nget, unsigned long *nrel);
void bstatse(bufsize *pool_incr, long *npool, unsigned long *npget, unsigned long *nprel, unsigned long *ndget, unsigned long *ndrel);
void bufdump(void *buf);
void bpoold(void *pool, int dumpalloc, int dumpfree);
int bpoolv(void *pool);
bufsize bstatsmaxget(void);
