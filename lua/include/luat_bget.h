/*
    Interface definitions for luat_bget.c, the memory management package.
    在原版基础上，改成纯函数实现
*/
//#include <assert.h>
#include <string.h>

typedef long bufsize;

#define MemSize     int               /* Type for size arguments to memxxx()
                                         functions such as memcmp(). */

#define SizeQuant   8                 /* Buffer allocation size quantum:
                                         all buffers allocated are a
                                         multiple of this size.  This
                                         MUST be a power of two. */

#if 1
#define BufStats    1                 /* Define this symbol to enable the
                                         bstats() function which calculates
                                         the total free space in the buffer
                                         pool, the largest available
                                         buffer, and the total space
                                         currently allocated. */
#endif

#if 0
#define FreeWipe    1                 /* Wipe free buffers to a guaranteed
                                         pattern of garbage to trip up
                                         miscreants who attempt to use
                                         pointers into released buffers. */
#endif

#if 1
#define BestFit     1                 /* Use a best fit algorithm when
                                         searching for space for an
                                         allocation request.  This uses
                                         memory more efficiently, but
                                         allocation will be much slower. */
#endif


/* Queue links */

struct qlinks {
    struct bfhead *flink;             /* Forward link */
    struct bfhead *blink;             /* Backward link */
};

/* Header in allocated and free buffers */

struct bhead {
    bufsize prevfree;                 /* Relative link back to previous
                                         free buffer in memory or 0 if
                                         previous buffer is allocated.  */
    bufsize bsize;                    /* Buffer size: positive if free,
                                         negative if allocated. */
};
#define BH(p)   ((struct bhead *) (p))

/*  Header in directly allocated buffers (by acqfcn) */

struct bdhead {
    bufsize tsize;                    /* Total size, including overhead */
    struct bhead bh;                  /* Common header */
};
#define BDH(p)  ((struct bdhead *) (p))

/* Header in free buffers */

struct bfhead {
    struct bhead bh;                  /* Common allocated/free header */
    struct qlinks ql;                 /* Links on free list */
};
#define BFH(p)  ((struct bfhead *) (p))

// static struct bfhead freelist = {     /* List of free buffers */
//     {0, 0},
//     {&freelist, &freelist}
// };

typedef struct luat_bget
{
#ifdef BufStats
    bufsize totalloc;          /* Total space currently allocated */
    bufsize maxalloc;
    unsigned long numget;
    unsigned long numrel;   /* Number of bget() and brel() calls */
#endif /* BufStats */
    struct bfhead freelist;
}luat_bget_t;

void luat_bget_init(luat_bget_t* bg);
void luat_bpool(luat_bget_t* bg, void *buffer, bufsize len);
void *luat_bget(luat_bget_t* bg, bufsize size);
void *luat_bgetz(luat_bget_t* bg, bufsize size);
void *luat_bgetr(luat_bget_t* bg, void *buffer, bufsize newsize);
void luat_brel(luat_bget_t* bg, void *buf);
// void luat_bectl(luat_bget_t* bg, int (*compact)(bufsize sizereq, int sequence), void *(*acquire)(bufsize size), void (*release)(void *buf), bufsize pool_incr);
void luat_bstats(luat_bget_t* bg, bufsize *curalloc, bufsize *totfree, bufsize *maxfree, unsigned long  *nget, unsigned long *nrel);
// void luat_bstatse(luat_bget_t* bg, bufsize *pool_incr, long *npool, unsigned long *npget, unsigned long *nprel, unsigned long *ndget, unsigned long *ndrel);
// void luat_bufdump(luat_bget_t* bg, void *buf);
// void luat_bpoold(luat_bget_t* bg, void *pool, int dumpalloc, int dumpfree);
// int luat_bpoolv(luat_bget_t* bg, void *pool);
bufsize luat_bstatsmaxget(luat_bget_t* bg);
