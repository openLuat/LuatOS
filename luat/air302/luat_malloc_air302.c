

#include <stdlib.h>
#include <string.h>//add for memset

/* Defining MPU_WRAPPERS_INCLUDED_FROM_API_FILE prevents task.h from redefining
all the API functions to use the MPU wrappers.  That should only be done when
task.h is included from an application file. */
#define MPU_WRAPPERS_INCLUDED_FROM_API_FILE

#include "FreeRTOS.h"
#include "task.h"
//#include "mm_debug.h"//add for memory leak debug
//#include "os_exception.h"
//#include "cmsis_compiler.h"

#include "luat_malloc.h"

#undef MPU_WRAPPERS_INCLUDED_FROM_API_FILE
#undef MM_DEBUG_EN
#undef configASSERT
#define configASSERT 


// add 8 bytes to record footprint for each allocated memory block
//the footprint value should never be modified
#define MALLOC_FOOT_PRINT_SIZE      ( ( size_t ) 8 )


/* Block sizes must not get too small. */
#define heapMINIMUM_BLOCK_SIZE  ( ( size_t ) ( xHeapStructSize << 1 ) )

/* Assumes 8bit bytes! */
#define heapBITS_PER_BYTE       ( ( size_t ) 8 )

/* Allocate the memory for the heap. */
//static void *_ucHeap = (void*) 0x00031000;
//static uint8_t* p = (uint8_t *) 0x00031000;
//static uint8_t *ucHeap = (uint8_t *) 0x00031000;

/* Define the linked list structure.  This is used to link free blocks in order
of their memory address. */
typedef struct A_BLOCK_LINK
{
    struct A_BLOCK_LINK *pxNextFreeBlock;   /*<< The next free block in the list. */
    size_t xBlockSize;/*<< The size of the free block. */
    #ifdef MM_DEBUG_EN
    void * allocateOwner;
    #endif
} BlockLink_t;

/*-----------------------------------------------------------*/

/*
 * Inserts a block of memory that is being freed into the correct position in
 * the list of free memory blocks.  The block being freed will be merged with
 * the block in front it and/or the block behind it if the memory blocks are
 * adjacent to each other.
 */
static void prvInsertBlockIntoFreeList( BlockLink_t *pxBlockToInsert );

/*
 * Called automatically to setup the required heap structures the first time
 * pvPortMalloc() is called.
 */
static void prvHeapInit( void );

/*-----------------------------------------------------------*/

/* The size of the structure placed at the beginning of each allocated memory
block must by correctly byte aligned. */
static const size_t xHeapStructSize = ( sizeof( BlockLink_t ) + ( ( size_t ) ( portBYTE_ALIGNMENT - 1 ) ) ) & ~( ( size_t ) portBYTE_ALIGNMENT_MASK );

/* Create a couple of list links to mark the start and end of the list. */
static BlockLink_t xStart, *pxEnd = NULL;

/* Keeps track of the number of free bytes remaining, but says nothing about
fragmentation. */
static size_t xFreeBytesRemaining = 0U;
static size_t xMinimumEverFreeBytesRemaining = 0U;

/* Gets set to the top bit of an size_t type.  When this bit in the xBlockSize
member of an BlockLink_t structure is set then the block belongs to the
application.  When the bit is free the block is still part of the free heap
space. */
static size_t xBlockAllocatedBit = 0;

#ifdef HEAP_MEM_DEBUG
void *recThreadId[50];
int thIdx = 0;
extern void * osThreadGetId (void);
/*-----------------------------------------------------------*/
#endif

static void *pvPortMalloc( size_t xWantedSize )
{
BlockLink_t *pxBlock, *pxPreviousBlock, *pxNewBlockLink;
void *pvReturn = NULL;
size_t realSize=0;

#ifdef HEAP_MEM_DEBUG
BlockLink_t *pxBlockDbg;
#endif

  //configASSERT(xWantedSize > 0);

    vTaskSuspendAll();
    {
        /* If this is the first call to malloc then the heap will require
        initialisation to setup the list of free blocks. */
        if( pxEnd == NULL )
        {
            #ifdef MM_DEBUG_EN
            mm_trace_init();
            #endif

            prvHeapInit();
        }

        #ifdef HEAP_MEM_DEBUG
        pxBlockDbg = xStart.pxNextFreeBlock;
        while( ( pxBlockDbg->pxNextFreeBlock != NULL ) )
        {
            pxBlockDbg = pxBlockDbg->pxNextFreeBlock;
        }
        if(pxBlockDbg != pxEnd)
        {
            configASSERT(FALSE);
        }
        #endif


        /* Check the requested block size is not so large that the top bit is
        set.  The top bit of the block size member of the BlockLink_t structure
        is used to determine who owns the block - the application or the
        kernel, so it must be free. */
        if( ( xWantedSize & xBlockAllocatedBit ) == 0 )
        {
            /* The wanted size is increased so it can contain a BlockLink_t
            structure in addition to the requested amount of bytes. */
            if( xWantedSize > 0 )
            {
                xWantedSize += xHeapStructSize;
                #ifdef MM_DEBUG_EN
                xWantedSize += MALLOC_FOOT_PRINT_SIZE;// malloc additional 8 bytes at the end
                #endif
                /* Ensure that blocks are always aligned to the required number
                of bytes. */
                if( ( xWantedSize & portBYTE_ALIGNMENT_MASK ) != 0x00 )
                {
                    /* Byte alignment required. */
                    xWantedSize += ( portBYTE_ALIGNMENT - ( xWantedSize & portBYTE_ALIGNMENT_MASK ) );
                    //configASSERT( ( xWantedSize & portBYTE_ALIGNMENT_MASK ) == 0 );
                }
            }

            if( ( xWantedSize > 0 ) && ( xWantedSize <= xFreeBytesRemaining ) )
            {
                /* Traverse the list from the start (lowest address) block until
                one of adequate size is found. */
                pxPreviousBlock = &xStart;
                pxBlock = xStart.pxNextFreeBlock;
                while( ( pxBlock->xBlockSize < xWantedSize ) && ( pxBlock->pxNextFreeBlock != NULL ) )
                {
                    pxPreviousBlock = pxBlock;
                    pxBlock = pxBlock->pxNextFreeBlock;
                }

                /* If the end marker was reached then a block of adequate size
                was not found. */
                if( pxBlock != pxEnd )
                {
                    /* Return the memory space pointed to - jumping over the
                    BlockLink_t structure at its start. */
                    pvReturn = ( void * ) ( ( ( uint8_t * ) pxPreviousBlock->pxNextFreeBlock ) + xHeapStructSize );

                    /* This block is being returned for use so must be taken out
                    of the list of free blocks. */
                    pxPreviousBlock->pxNextFreeBlock = pxBlock->pxNextFreeBlock;

                    /* If the block is larger than required it can be split into
                    two. */
                    if(pxBlock->xBlockSize < xWantedSize)
                    {
                        //configASSERT(FALSE);
                    }
                    if( ( pxBlock->xBlockSize - xWantedSize ) > heapMINIMUM_BLOCK_SIZE )
                    {
                        /* This block is to be split into two.  Create a new
                        block following the number of bytes requested. The void
                        cast is used to prevent byte alignment warnings from the
                        compiler. */
                        pxNewBlockLink = ( void * ) ( ( ( uint8_t * ) pxBlock ) + xWantedSize );
                        //configASSERT( ( ( ( size_t ) pxNewBlockLink ) & portBYTE_ALIGNMENT_MASK ) == 0 );

                        /* Calculate the sizes of two blocks split from the
                        single block. */
                        pxNewBlockLink->xBlockSize = pxBlock->xBlockSize - xWantedSize;
                        pxBlock->xBlockSize = xWantedSize;

                        /* Insert the new block into the list of free blocks. */
                        prvInsertBlockIntoFreeList( pxNewBlockLink );
                    }

                    xFreeBytesRemaining -= pxBlock->xBlockSize;

                    if( xFreeBytesRemaining < xMinimumEverFreeBytesRemaining )
                    {
                        xMinimumEverFreeBytesRemaining = xFreeBytesRemaining;
                    }

                    /* The block is being returned - it is allocated and owned
                    by the application and has no "next" block. */
                    realSize=pxBlock->xBlockSize;
                    pxBlock->xBlockSize |= xBlockAllocatedBit;
                    pxBlock->pxNextFreeBlock = NULL;
                    #ifdef MM_DEBUG_EN
                    pxBlock->allocateOwner= osThreadGetId();

                    /*set the footprint*/
                    *(uint32_t *)((uint8_t*)pxBlock+realSize-MALLOC_FOOT_PRINT_SIZE)=0xdeadbeaf;
                    *(uint32_t *)((uint8_t*)pxBlock+realSize-MALLOC_FOOT_PRINT_SIZE+4)=0xdeadbeaf;
                    #endif
                }
            }
        }

        //traceMALLOC( pvReturn, xWantedSize );
    }

    #ifdef HEAP_MEM_DEBUG
    pxBlockDbg = xStart.pxNextFreeBlock;
    while ((pxBlockDbg->pxNextFreeBlock != NULL))
    {
        pxBlockDbg = pxBlockDbg->pxNextFreeBlock;
    }
    if(pxBlockDbg != pxEnd)
    {
        configASSERT(FALSE);
    }
    #endif

    ( void ) xTaskResumeAll();

    #if( configUSE_MALLOC_FAILED_HOOK == 1 )
    {
        if( pvReturn == NULL )
        {
            extern void vApplicationMallocFailedHook( void );
            vApplicationMallocFailedHook();
        }
        else
        {
            mtCOVERAGE_TEST_MARKER();
        }
    }
    #endif

    //configASSERT( pvReturn != 0 );
    //configASSERT( ( ( ( size_t ) pvReturn ) & ( size_t ) portBYTE_ALIGNMENT_MASK ) == 0 );

    #ifdef MM_DEBUG_EN
	unsigned int func_lr = __GET_RETURN_ADDRESS();
    mm_malloc_trace(pvReturn, xWantedSize, func_lr);
    #endif

    return pvReturn;
}

/*----add for libcoap-------------------------------------------------------*/
static void *pvPortRealloc( void *pv, size_t xWantedSize )
{
    uint8_t *puc = ( uint8_t * ) pv;
    void *newPuc = NULL;
    BlockLink_t *pxLink;

    if(xWantedSize == 0)
    {
        return NULL;
    }

    if( puc != NULL )
    {
        /* The memory being freed will have an BlockLink_t structure immediately before it. */
        puc -= xHeapStructSize;

        /* This casting is to keep the compiler from issuing warnings. */
        pxLink = ( void * ) puc;
        //configASSERT( ( pxLink->xBlockSize & xBlockAllocatedBit ) != 0 );
        //configASSERT( pxLink->pxNextFreeBlock == NULL );
        if( ( pxLink->xBlockSize & xBlockAllocatedBit ) != 0 )
        {
            pxLink->xBlockSize &= ~xBlockAllocatedBit;
            if(pxLink->xBlockSize >= xWantedSize)
            {
                return pv;
            }
            else
            {
                newPuc = pvPortMalloc(xWantedSize);
                if(newPuc != NULL)
                {
                    memset(newPuc, 0, xWantedSize);
                    memcpy(newPuc, pv, pxLink->xBlockSize);
                    return newPuc;
                }else
                {
                    return NULL;
                }
            }
        }
    }

   return NULL;

}

/*-----------------------------------------------------------*/
static void vPortFree( void *pv )
{
uint8_t *puc = ( uint8_t * ) pv;
BlockLink_t *pxLink;
#ifdef HEAP_MEM_DEBUG
BlockLink_t *pxBlockDbg;
#endif

    //configASSERT( pv != NULL );

    //ucHeap
    //configASSERT( (uint32_t)pv >= (uint32_t)ucHeap && (uint32_t)pv < ((uint32_t)ucHeap) + configTOTAL_HEAP_SIZE );

    if( pv != NULL )
    {
        /* The memory being freed will have an BlockLink_t structure immediately
        before it. */
        puc -= xHeapStructSize;

        /* This casting is to keep the compiler from issuing warnings. */
        pxLink = ( void * ) puc;

        //EC_ASSERT( ( pxLink->xBlockSize & xBlockAllocatedBit, 0, 0, 0 ) != 0 );

        /* Check the block is actually allocated. */
        //configASSERT( ( pxLink->xBlockSize & xBlockAllocatedBit ) != 0 );
        //configASSERT( pxLink->pxNextFreeBlock == NULL );

        if( ( pxLink->xBlockSize & xBlockAllocatedBit ) != 0 )
        {
            if( pxLink->pxNextFreeBlock == NULL )
            {
                /* The block is being returned to the heap - it is no longer
                allocated. */
                pxLink->xBlockSize &= ~xBlockAllocatedBit;
                #ifdef MM_DEBUG_EN
                /*check the memory block's footprint*/
                configASSERT(*(uint32_t *)((uint8_t*)pxLink+pxLink->xBlockSize-MALLOC_FOOT_PRINT_SIZE)== 0xdeadbeaf );
                configASSERT(*(uint32_t *)((uint8_t*)pxLink+pxLink->xBlockSize-MALLOC_FOOT_PRINT_SIZE+4) == 0xdeadbeaf );
                #endif

                vTaskSuspendAll();
                #ifdef HEAP_MEM_DEBUG
                pxBlockDbg = xStart.pxNextFreeBlock;
                while ((pxBlockDbg->pxNextFreeBlock != NULL))
                {
                    pxBlockDbg = pxBlockDbg->pxNextFreeBlock;
                }
                if(pxBlockDbg != pxEnd)
                {
                    configASSERT(FALSE);
                }
                #endif
                {
                    /* Add this block to the list of free blocks. */
                    xFreeBytesRemaining += pxLink->xBlockSize;
                    //traceFREE( pv, pxLink->xBlockSize );
                    //configASSERT(pxLink->xBlockSize > 0 && pxLink->xBlockSize < configTOTAL_HEAP_SIZE);

                    prvInsertBlockIntoFreeList( ( ( BlockLink_t * ) pxLink ) );
                }
                #ifdef HEAP_MEM_DEBUG
                pxBlockDbg = xStart.pxNextFreeBlock;
                while ((pxBlockDbg->pxNextFreeBlock != NULL))
                {
                    pxBlockDbg = pxBlockDbg->pxNextFreeBlock;
                }
                if(pxBlockDbg != pxEnd)
                {
                    configASSERT(FALSE);
                }
                #endif
                ( void ) xTaskResumeAll();
            }
        }
        
        #ifdef MM_DEBUG_EN
        mm_free_trace(pv);
        #endif
    }
}
/*-----------------------------------------------------------*/

static size_t xPortGetFreeHeapSize( void )
{
    return xFreeBytesRemaining;
}
/*-----------------------------------------------------------*/

static size_t xPortGetMinimumEverFreeHeapSize( void )
{
    return xMinimumEverFreeBytesRemaining;
}
/*-----------------------------------------------------------*/

//static void vPortInitialiseBlocks( void )
//{
//    /* This just exists to keep the linker quiet. */
//}
/*-----------------------------------------------------------*/

static void prvHeapInit( void )
{
BlockLink_t *pxFirstFreeBlock;
uint8_t *pucAlignedHeap;
size_t uxAddress;
size_t xTotalHeapSize = LUAT_MALLOC_HEAP_SIZE;

    /* Ensure the heap starts on a correctly aligned boundary. */
    /*uxAddress = ( size_t ) ucHeap;

    if( ( uxAddress & portBYTE_ALIGNMENT_MASK ) != 0 )
    {
        uxAddress += ( portBYTE_ALIGNMENT - 1 );
        uxAddress &= ~( ( size_t ) portBYTE_ALIGNMENT_MASK );
        xTotalHeapSize -= uxAddress - ( size_t ) ucHeap;
    }
    */
    pucAlignedHeap = ( uint8_t * ) 0x2B000;
    memset(pucAlignedHeap, 0, LUAT_MALLOC_HEAP_SIZE);

    /* xStart is used to hold a pointer to the first item in the list of free
    blocks.  The void cast is used to prevent compiler warnings. */
    xStart.pxNextFreeBlock = ( void * ) pucAlignedHeap;
    xStart.xBlockSize = ( size_t ) 0;
    /* pxEnd is used to mark the end of the list of free blocks and is inserted
    at the end of the heap space. */
    uxAddress = ( ( size_t ) pucAlignedHeap ) + xTotalHeapSize;
    uxAddress -= xHeapStructSize;
    uxAddress &= ~( ( size_t ) portBYTE_ALIGNMENT_MASK );
    pxEnd = ( void * ) uxAddress;
    pxEnd->xBlockSize = 0;
    pxEnd->pxNextFreeBlock = NULL;

    /* To start with there is a single free block that is sized to take up the
    entire heap space, minus the space taken by pxEnd. */
    pxFirstFreeBlock = ( void * ) pucAlignedHeap;
    pxFirstFreeBlock->xBlockSize = uxAddress - ( size_t ) pxFirstFreeBlock;
    pxFirstFreeBlock->pxNextFreeBlock = pxEnd;

    /* Only one block exists - and it covers the entire usable heap space. */
    xMinimumEverFreeBytesRemaining = pxFirstFreeBlock->xBlockSize;
    xFreeBytesRemaining = pxFirstFreeBlock->xBlockSize;

    /* Work out the position of the top bit in a size_t variable. */
    xBlockAllocatedBit = ( ( size_t ) 1 ) << ( ( sizeof( size_t ) * heapBITS_PER_BYTE ) - 1 );
}
/*-----------------------------------------------------------*/

static void prvInsertBlockIntoFreeList( BlockLink_t *pxBlockToInsert )
{
BlockLink_t *pxIterator;
uint8_t *puc;

    /* Iterate through the list until a block is found that has a higher address
    than the block being inserted. */
    for( pxIterator = &xStart; pxIterator->pxNextFreeBlock < pxBlockToInsert; pxIterator = pxIterator->pxNextFreeBlock )
    {
        /* Nothing to do here, just iterate to the right position. */
    }

    /* Do the block being inserted, and the block it is being inserted after
    make a contiguous block of memory? */
    puc = ( uint8_t * ) pxIterator;
    if( ( puc + pxIterator->xBlockSize ) == ( uint8_t * ) pxBlockToInsert )
    {
        pxIterator->xBlockSize += pxBlockToInsert->xBlockSize;
        pxBlockToInsert = pxIterator;
    }

    /* Do the block being inserted, and the block it is being inserted before
    make a contiguous block of memory? */
    puc = ( uint8_t * ) pxBlockToInsert;
    if( ( puc + pxBlockToInsert->xBlockSize ) == ( uint8_t * ) pxIterator->pxNextFreeBlock )
    {
        if( pxIterator->pxNextFreeBlock != pxEnd )
        {
            /* Form one big block from the two blocks. */
            pxBlockToInsert->xBlockSize += pxIterator->pxNextFreeBlock->xBlockSize;
            pxBlockToInsert->pxNextFreeBlock = pxIterator->pxNextFreeBlock->pxNextFreeBlock;
        }
        else
        {
            pxBlockToInsert->pxNextFreeBlock = pxEnd;
        }
    }
    else
    {
        pxBlockToInsert->pxNextFreeBlock = pxIterator->pxNextFreeBlock;
    }

    /* If the block being inserted plugged a gab, so was merged with the block
    before and the block after, then it's pxNextFreeBlock pointer will have
    already been set, and should not be set here as that would make it point
    to itself. */
    if( pxIterator != pxBlockToInsert )
    {
        pxIterator->pxNextFreeBlock = pxBlockToInsert;
    }
}

void luat_heap_init(void) {
    prvHeapInit();
}

void* luat_heap_malloc(size_t len) {
    return pvPortMalloc(len);
};
void luat_heap_free(void* ptr) {
    vPortFree(ptr);
}
void* luat_heap_realloc(void* ptr, size_t len) {
    return pvPortRealloc(ptr, len);
}
void* luat_heap_calloc(size_t count, size_t _size) {
    void *ptr = luat_heap_malloc(count * _size);
    if (ptr) {
        memset(ptr, 0, _size);
    }
    return ptr;
}

size_t luat_heap_getfree(void) {
    return xPortGetFreeHeapSize();
}

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    if (nsize <= 0) {
        if (ptr) {
            //luat_uart_log("luat_heap_free\n");
            luat_heap_free(ptr);
        }
        return NULL;
    }
    else {
        //if (osize > nsize)
        //    return ptr;
        void *ptr2 = NULL;
        //luat_uart_log("luat_heap_malloc\n");
        ptr2 = luat_heap_malloc(nsize);
        if (ptr2 == NULL) {
            if (nsize < osize)
                return ptr;
            return NULL;
        }
        if (ptr) {
            memset(ptr2, 0, nsize);
            memcpy(ptr2, ptr, osize > nsize ? nsize : osize);
            //luat_uart_log("luat_heap_malloc+free\n");
            luat_heap_free(ptr);
        }
        ptr = ptr2;
        return ptr;
    }
}
