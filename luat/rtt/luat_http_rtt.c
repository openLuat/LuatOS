
#include "luat_base.h"
#include "luat_http.h"
#include "luat_malloc.h"
#define LUAT_LOG_TAG "luat.http"
#include "luat_log.h"

#include "rtthread.h"

#ifdef PKG_USING_WEBCLIENT
#include "webclient.h"


#undef WEBCLIENT_HEADER_BUFSZ
#undef WEBCLIENT_RESPONSE_BUFSZ
#define WEBCLIENT_HEADER_BUFSZ         (512*3)
#define WEBCLIENT_RESPONSE_BUFSZ       (512*3)

static void webclient_req(luat_lib_http_req_t *req)
{
    int fd = -1, rc = WEBCLIENT_OK;
    size_t offset;
    int length, total_length = 0;
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

    rc = webclient_connect(session, URI);
    if (rc != WEBCLIENT_OK)
    {
        /* connect to webclient server failed. */
        LLOGE("http connect fail");
        goto __exit;
    }

    // TODO 把DELETE和PUT支持一下
    rc = webclient_send_header(session, req->body.size == 0 ? WEBCLIENT_GET : WEBCLIENT_POST);
    if (rc != WEBCLIENT_OK)
    {
        /* send header to webclient server failed. */
        LLOGE("http send header fail");
        goto __exit;
    }

    if (req->body.size)
    {
        webclient_write(session, req->body.ptr, req->body.size);

        /* resolve response data, get http status code */
        resp_status = webclient_handle_response(session);
        LLOGD("post handle response(%d).", resp_status);
    }

    if (resp_status  != 200)
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
        while (1)
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
        // TODO 重启?
        return;
    }
    memset(resp, 0, sizeof(luat_lib_http_resp_t));
    resp->luacb = req->luacb;
    resp->code = rc;
    if (rc < 0) {
        luat_http_req_gc(req);
        req->httpcb(resp);
    }
    else {
        if (rc == 200) {
            resp->body.type = 1;
            //if (total_length > 0 && total_length < WE)
        }
        req->httpcb(resp);
    }

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
                           2048,
                           22,
                           20);

    if (tid)
    {
        ret = rt_thread_startup(tid);
    }
    else {
        LLOGE("http thread fail to start");
    }

    return ret == 0 ? 1 : 0;
}


#endif

