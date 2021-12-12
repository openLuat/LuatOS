
#include "luat_base.h"
#include "luat_http.h"
#include "luat_malloc.h"
#define LUAT_LOG_TAG "http"
#include "luat_log.h"

#include "rtthread.h"

#ifdef SAL_USING_POSIX
#include "webclient.h"
#include "fcntl.h"

#undef WEBCLIENT_HEADER_BUFSZ
#undef WEBCLIENT_RESPONSE_BUFSZ
#define WEBCLIENT_HEADER_BUFSZ         (512*3)
#define WEBCLIENT_RESPONSE_BUFSZ       (512*3)

static void webclient_req(luat_lib_http_req_t *req)
{
    int fd = -1, rc = WEBCLIENT_OK;
    size_t offset;
    int length = 0;
    size_t total_length = 0;
    unsigned char *ptr = RT_NULL;
    struct webclient_session* session = RT_NULL;
    int resp_status = 0;
    const char* filename = req->dwpath;
    const char* URI = req->url;

    session = webclient_session_create(WEBCLIENT_HEADER_BUFSZ);
    if(session == RT_NULL)
    {
        rc = -WEBCLIENT_NOMEM;
        goto __exit;
    }
    else {
        LLOGD("webclient_session_create ok");
    }
        

    rc = webclient_connect(session, URI);
    if (rc != WEBCLIENT_OK)
    {
        /* connect to webclient server failed. */
        LLOGE("http connect fail");
        goto __exit;
    }
    else {
        LLOGD("http connect ok");
    }

    // TODO 把DELETE和PUT支持一下
    rc = webclient_send_header(session, req->body.size == 0 ? WEBCLIENT_GET : WEBCLIENT_POST);
    if (rc != WEBCLIENT_OK)
    {
        /* send header to webclient server failed. */
        LLOGE("http send header fail");
        goto __exit;
    }
    else {
        LLOGD("http send header ok");
    }

    if (req->body.size)
    {
        webclient_write(session, req->body.ptr, req->body.size);
    }

    /* resolve response data, get http status code */
    resp_status = webclient_handle_response(session);
    LLOGD("post handle response(%d).", resp_status);

    if (resp_status  < 200)
    {
        LLOGW("get file failed, wrong response: %d (-0x%X).", resp_status, resp_status);
        rc = -WEBCLIENT_ERROR;
        goto __exit;
    }

    fd = open(req->dwpath, O_WRONLY | O_CREAT | O_TRUNC, 0);
    if (fd < 0)
    {
        LLOGW("get file failed, open file(%s) error.", filename);
        rc = -WEBCLIENT_ERROR;
        goto __exit;
    }

    ptr = (unsigned char *) web_malloc(WEBCLIENT_RESPONSE_BUFSZ);
    if (ptr == RT_NULL)
    {
        LLOGW("get file failed, no memory for response buffer.");
        rc = -WEBCLIENT_NOMEM;
        goto __exit;
    }

    if (session->content_length < 0)
    {
        while (total_length < 64*1024)
        {
            length = webclient_read(session, ptr, WEBCLIENT_RESPONSE_BUFSZ);
            if (length > 0)
            {
                write(fd, ptr, length);
                total_length += length;
                //LOG_RAW(">");
            }
            else
            {
                break;
            }
        }
    }
    else
    {
        for (offset = 0; offset < (size_t) session->content_length;)
        {
            length = webclient_read(session, ptr,
                    session->content_length - offset > WEBCLIENT_RESPONSE_BUFSZ ?
                            WEBCLIENT_RESPONSE_BUFSZ : session->content_length - offset);

            if (length > 0)
            {
                write(fd, ptr, length);
                total_length += length;
                //LOG_RAW(">");
            }
            else
            {
                break;
            }

            offset += length;
        }
    }

    if (total_length)
    {
        LLOGW("save %d bytes.", total_length);
    }

__exit:
    if (fd >= 0)
    {
        close(fd);
    }

    if (session != RT_NULL)
    {
        webclient_close(session);
    }

    if (ptr != RT_NULL)
    {
        web_free(ptr);
    }

    
    luat_lib_http_resp_t *resp = luat_heap_malloc(sizeof(luat_lib_http_resp_t));
    if (resp == NULL) {
        LLOGE("sys out of memory! malloc for luat_lib_http_resp_t return NULL");
        luat_http_req_gc(req);
        // TODO 重启?
        return;
    }
    memset(resp, 0, sizeof(luat_lib_http_resp_t));
    resp->luacb = req->luacb;
    resp->code = resp_status > 0 ? resp_status : rc;
    if (resp->code < 0) {
        LLOGD("http req error %d %p %p", rc, resp, req->httpcb);
        req->httpcb(resp);
    }
    else {
        if (resp_status >= 200) {
            resp->body.type = 1;
            if (total_length > 0 && total_length < WEBCLIENT_RESPONSE_BUFSZ) {
                resp->body.ptr = luat_heap_malloc(total_length);
                if (resp->body.ptr != NULL) {
                    fd = open(req->dwpath, O_RDONLY, 0);
                    if (fd) {
                        read(fd, resp->body.ptr, total_length);
                        close(fd);
                        resp->body.size = total_length;
                    }
                    else {
                        resp->body.size = 0;
                        luat_heap_free(resp->body.ptr);
                        LLOGW("resp file is fail to open");
                    }
                }
                else {
                    LLOGW("resp body malloc fail!!! size=%d", total_length);
                }
            }
            else {
                LLOGI("resp is too big, only save at file");
            }
        }
        else {
            LLOGI("resp code < 200, skip body");
        }
        req->httpcb(resp);
    }
    LLOGD("http every done, clean req");
    luat_http_req_gc(req);
}

static void luat_http_thread_entry(void* arg) {
    luat_lib_http_req_t *req = (luat_lib_http_req_t *)arg;

    // 默认下载到到文件里
    if (req->dwpath[0] == 0x00) {
        strcpy(req->dwpath, "/httpdw.bin");
    }
    
    webclient_req(req);
    
}

int luat_http_req(luat_lib_http_req_t *req) {
    rt_thread_t tid;
    int ret = -1;

    tid = rt_thread_create("http",
                           luat_http_thread_entry,
                           req,
                           4*1024,
                           22,
                           20);

    if (tid)
    {
        ret = rt_thread_startup(tid);
    }
    else {
        LLOGE("http thread fail to start");
    }

    return ret;
}


#endif

