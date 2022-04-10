/*------------------------------------------------*/
/* TJpgDec Quick Evaluation Program for PCs       */
/*------------------------------------------------*/

#include "luat_base.h"
#include "luat_malloc.h"

#include <stdio.h>
#include <string.h>
#include "tjpgd.h"
#include "luat_tjpgd.h"

#define LUAT_LOG_TAG "tjpgd"
#include "luat_log.h"

/* Bytes per pixel of image output */
#define N_BPP (3 - JD_FORMAT)

/* Session identifier for input/output functions (name, members and usage are as user defined) */
typedef struct {
    FILE *fp;               /* Input stream */
    uint8_t *fbuf;          /* Output frame buffer */
    unsigned int wfbuf;     /* Width of the frame buffer [pix] */
} IODEV;


/*------------------------------*/
/* User defined input funciton  */
/*------------------------------*/

unsigned int in_func (JDEC* jd, uint8_t* buff, unsigned int nbyte){
    IODEV *dev = (IODEV*)jd->device;   /* Device identifier for the session (5th argument of jd_prepare function) */
    if (buff) {
        /* Read bytes from input stream */
        return luat_fs_fread(buff, 1, nbyte, dev->fp);
    } else {
        /* Remove bytes from input stream */
        return luat_fs_fseek(dev->fp, nbyte, SEEK_CUR) ? 0 : nbyte;
    }
}


/*------------------------------*/
/* User defined output funciton */
/*------------------------------*/

int out_func (JDEC* jd, void* bitmap, JRECT* rect){
    IODEV *dev = (IODEV*)jd->device;
    uint8_t *src, *dst;
    uint16_t y, bws, bwd;
    /* Put progress indicator */
    if (rect->left == 0) {
        LLOGI("%lu%%", (rect->top << jd->scale) * 100UL / jd->height);
    }
    /* Copy the output image rectanglar to the frame buffer */
    src = (uint8_t*)bitmap;
    dst = dev->fbuf + N_BPP * (rect->top * dev->wfbuf + rect->left);  /* Left-top of destination rectangular */
    bws = N_BPP * (rect->right - rect->left + 1);     /* Width of source rectangular [byte] */
    bwd = N_BPP * dev->wfbuf;                         /* Width of frame buffer [byte] */
    for (y = rect->top; y <= rect->bottom; y++) {
        memcpy(dst, src, bws);   /* Copy a line */
        src += bws; dst += bwd;  /* Next line */
    }
    return 1;    /* Continue to decompress */
}


/*------------------------------*/
/* Program Jpeg_Dec             */
/*------------------------------*/

uint8_t * luat_tjpgd(const char* input_file){
    JRESULT res;      /* Result code of TJpgDec API */
    JDEC jdec;        /* Decompression object */
    void *work;       /* Pointer to the decompressor work area */
    size_t sz_work = 3500; /* Size of work area */
    IODEV devid;      /* User defined device identifier */

    devid.fp = luat_fs_fopen(input_file, "rb");
    if (!devid.fp){
        LLOGI("Jpeg_Dec open the file failed...");
        return NULL;
    }
    /* Allocate a work area for TJpgDec */
    work = luat_heap_malloc(sz_work);
    if(work == NULL){
        LLOGI("Jpeg_Dec work malloc failed...");
        res = -1;
        goto __exit;
    }
    /* Prepare to decompress */
    res = jd_prepare(&jdec, in_func, work, sz_work, &devid);
    if (res == JDR_OK){
        /* It is ready to dcompress and image info is available here */
        LLOGI("Image size is %u x %u.\n%u bytes of work ares is used.\n", jdec.width, jdec.height, sz_work - jdec.sz_pool);
        devid.fbuf = luat_heap_malloc(N_BPP * jdec.width * jdec.height); /* Frame buffer for output image */
        if(devid.fbuf == NULL)
        {
            LLOGI("Jpeg_Dec devid.fbuf malloc failed, need to use %d Bytes ...", N_BPP * jdec.width * jdec.height);
            res = -1;
            goto __exit;
        }
        devid.wfbuf = jdec.width;
        res = jd_decomp(&jdec, out_func, 0);   /* Start to decompress with 1/1 scaling */
        if (res == JDR_OK) {
            /* Decompression succeeded. You have the decompressed image in the frame buffer here. */
            return devid.fbuf;
            LLOGI("Decompression succeeded.");
        }
        else{
            LLOGI("jd_decomp() failed (rc=%d)", res);
        }

    }
    else{
        LLOGI("jd_prepare() failed (rc=%d)", res);
    }
__exit:
    if(work != NULL){
        luat_heap_free(work);             /* Discard work area */
    }
    luat_fs_fclose(devid.fp);       /* Close the JPEG file */
    return NULL;
}

