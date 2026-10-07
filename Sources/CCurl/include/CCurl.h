// Tenký C wrapper nad systémovou libcurl (curl_easy_setopt je variadická, ze Swiftu ji nelze volat).
#ifndef CCURL_H
#define CCURL_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    const char *user;
    const char *password;
    int tls;                 // 0 = bez šifrování, 1 = explicitní TLS (AUTH TLS) na ftp://
    int insecure;            // 1 = nekontrolovat certifikát (self-signed)
    long connect_timeout;    // sekundy
    long low_speed_timeout;  // sekundy bez přenosu = chyba (0 = vypnuto)
} mc_opts;

// Vrací nenulovou hodnotu pro přerušení přenosu.
typedef int (*mc_progress_fn)(void *ctx, int64_t transferred, int64_t total);

int mc_global_init(void);
void mc_free(void *p);

// Výpis adresáře (url musí končit "/"). Při `mlsd` se použije MLSD místo LIST. Data vrací v *out (uvolnit mc_free).
int mc_list(const mc_opts *o, const char *url, int mlsd, char **out, size_t *outlen, char *err, size_t errlen);

int mc_download(const mc_opts *o, const char *url, const char *local_path, int64_t resume_from,
                mc_progress_fn cb, void *ctx, char *err, size_t errlen);

int mc_upload(const mc_opts *o, const char *url, const char *local_path,
              mc_progress_fn cb, void *ctx, char *err, size_t errlen);

// Pošle FTP příkazy (DELE, MKD, RMD, RNFR/RNTO …) bez přenosu dat.
int mc_command(const mc_opts *o, const char *url, const char **cmds, int ncmds, char *err, size_t errlen);

#define MC_ABORTED 42   // CURLE_ABORTED_BY_CALLBACK

#endif
