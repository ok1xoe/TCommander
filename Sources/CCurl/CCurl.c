#include "CCurl.h"
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *data; size_t len; size_t cap; } mc_buf;

typedef struct { mc_progress_fn cb; void *ctx; int upload; } mc_prog;

int mc_global_init(void) { return (int)curl_global_init(CURL_GLOBAL_DEFAULT); }
void mc_free(void *p) { free(p); }

static size_t write_buf(char *ptr, size_t size, size_t nmemb, void *userdata) {
    mc_buf *b = (mc_buf *)userdata;
    size_t n = size * nmemb;
    if (b->len + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap * 2 : 4096;
        while (cap < b->len + n + 1) cap *= 2;
        char *p = (char *)realloc(b->data, cap);
        if (!p) return 0;
        b->data = p; b->cap = cap;
    }
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    b->data[b->len] = 0;
    return n;
}

static int xferinfo(void *p, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow) {
    mc_prog *pr = (mc_prog *)p;
    if (!pr->cb) return 0;
    return pr->upload ? pr->cb(pr->ctx, ulnow, ultotal) : pr->cb(pr->ctx, dlnow, dltotal);
}

static CURL *setup(const mc_opts *o, const char *url, char *err) {
    CURL *c = curl_easy_init();
    if (!c) return NULL;
    curl_easy_setopt(c, CURLOPT_URL, url);
    if (o->user && o->user[0]) curl_easy_setopt(c, CURLOPT_USERNAME, o->user);
    if (o->password) curl_easy_setopt(c, CURLOPT_PASSWORD, o->password);
    curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, o->connect_timeout > 0 ? o->connect_timeout : 15L);
    if (o->low_speed_timeout > 0) {
        curl_easy_setopt(c, CURLOPT_LOW_SPEED_LIMIT, 1L);
        curl_easy_setopt(c, CURLOPT_LOW_SPEED_TIME, o->low_speed_timeout);
    }
    if (o->tls) curl_easy_setopt(c, CURLOPT_USE_SSL, (long)CURLUSESSL_ALL);
    if (o->insecure) {
        curl_easy_setopt(c, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(c, CURLOPT_SSL_VERIFYHOST, 0L);
    }
    curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);
    if (err) { err[0] = 0; curl_easy_setopt(c, CURLOPT_ERRORBUFFER, err); }
    return c;
}

static int finish(CURL *c, CURLcode rc, char *err, size_t errlen) {
    if (rc != CURLE_OK && err && errlen && err[0] == 0) {
        snprintf(err, errlen, "%s", curl_easy_strerror(rc));
    }
    curl_easy_cleanup(c);
    return (int)rc;
}

int mc_list(const mc_opts *o, const char *url, int mlsd, char **out, size_t *outlen, char *err, size_t errlen) {
    CURL *c = setup(o, url, err);
    if (!c) return CURLE_FAILED_INIT;
    mc_buf b = {0};
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, write_buf);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &b);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 120L);
    if (mlsd) curl_easy_setopt(c, CURLOPT_CUSTOMREQUEST, "MLSD");
    CURLcode rc = curl_easy_perform(c);
    if (rc == CURLE_OK) { *out = b.data ? b.data : strdup(""); *outlen = b.len; }
    else { free(b.data); *out = NULL; *outlen = 0; }
    return finish(c, rc, err, errlen);
}

int mc_download(const mc_opts *o, const char *url, const char *local_path, int64_t resume_from,
                mc_progress_fn cb, void *ctx, char *err, size_t errlen) {
    FILE *f = fopen(local_path, resume_from > 0 ? "ab" : "wb");
    if (!f) { snprintf(err, errlen, "Nelze otevřít %s", local_path); return CURLE_WRITE_ERROR; }
    CURL *c = setup(o, url, err);
    if (!c) { fclose(f); return CURLE_FAILED_INIT; }
    mc_prog pr = { cb, ctx, 0 };
    curl_easy_setopt(c, CURLOPT_WRITEDATA, f);
    curl_easy_setopt(c, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(c, CURLOPT_XFERINFOFUNCTION, xferinfo);
    curl_easy_setopt(c, CURLOPT_XFERINFODATA, &pr);
    if (resume_from > 0) curl_easy_setopt(c, CURLOPT_RESUME_FROM_LARGE, (curl_off_t)resume_from);
    CURLcode rc = curl_easy_perform(c);
    fclose(f);
    return finish(c, rc, err, errlen);
}

int mc_upload(const mc_opts *o, const char *url, const char *local_path,
              mc_progress_fn cb, void *ctx, char *err, size_t errlen) {
    FILE *f = fopen(local_path, "rb");
    if (!f) { snprintf(err, errlen, "Nelze číst %s", local_path); return CURLE_READ_ERROR; }
    fseek(f, 0, SEEK_END); long long size = ftell(f); fseek(f, 0, SEEK_SET);
    CURL *c = setup(o, url, err);
    if (!c) { fclose(f); return CURLE_FAILED_INIT; }
    mc_prog pr = { cb, ctx, 1 };
    curl_easy_setopt(c, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(c, CURLOPT_READDATA, f);
    curl_easy_setopt(c, CURLOPT_INFILESIZE_LARGE, (curl_off_t)size);
    curl_easy_setopt(c, CURLOPT_FTP_CREATE_MISSING_DIRS, (long)CURLFTP_CREATE_DIR);
    curl_easy_setopt(c, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(c, CURLOPT_XFERINFOFUNCTION, xferinfo);
    curl_easy_setopt(c, CURLOPT_XFERINFODATA, &pr);
    CURLcode rc = curl_easy_perform(c);
    fclose(f);
    return finish(c, rc, err, errlen);
}

int mc_command(const mc_opts *o, const char *url, const char **cmds, int ncmds, char *err, size_t errlen) {
    CURL *c = setup(o, url, err);
    if (!c) return CURLE_FAILED_INIT;
    struct curl_slist *list = NULL;
    for (int i = 0; i < ncmds; i++) list = curl_slist_append(list, cmds[i]);
    curl_easy_setopt(c, CURLOPT_QUOTE, list);
    curl_easy_setopt(c, CURLOPT_NOBODY, 1L);
    CURLcode rc = curl_easy_perform(c);
    curl_slist_free_all(list);
    return finish(c, rc, err, errlen);
}
