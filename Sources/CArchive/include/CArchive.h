// Minimální deklarace systémové libarchive (hlavičky nejsou součástí Command Line Tools SDK).
// ABI je stabilní; funkce odpovídají <archive.h> a <archive_entry.h> verze 3.x.
#ifndef CARCHIVE_H
#define CARCHIVE_H

#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <time.h>

struct archive;
struct archive_entry;

#define CARCHIVE_OK 0
#define CARCHIVE_EOF 1
#define CARCHIVE_WARN (-20)
#define CARCHIVE_FAILED (-25)
#define CARCHIVE_FATAL (-30)

#define CARCHIVE_IFREG 0x8000
#define CARCHIVE_IFDIR 0x4000
#define CARCHIVE_IFLNK 0xA000

// čtení
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_filter_count(struct archive *);
int archive_filter_code(struct archive *, int);
int archive_format(struct archive *);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);

// záznamy
struct archive_entry *archive_entry_new(void);
struct archive_entry *archive_entry_clone(struct archive_entry *);
void archive_entry_free(struct archive_entry *);
const char *archive_entry_pathname(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
mode_t archive_entry_mode(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
void archive_entry_set_pathname(struct archive_entry *, const char *);
void archive_entry_set_size(struct archive_entry *, int64_t);
void archive_entry_set_filetype(struct archive_entry *, unsigned int);
void archive_entry_set_perm(struct archive_entry *, mode_t);
void archive_entry_set_mtime(struct archive_entry *, time_t, long);
void archive_entry_set_symlink(struct archive_entry *, const char *);

// zápis
struct archive *archive_write_new(void);
int archive_write_set_format_zip(struct archive *);
int archive_write_set_format_pax_restricted(struct archive *);
int archive_write_set_format_7zip(struct archive *);
int archive_write_add_filter_none(struct archive *);
int archive_write_add_filter_gzip(struct archive *);
int archive_write_add_filter_bzip2(struct archive *);
int archive_write_add_filter_xz(struct archive *);
int archive_write_open_filename(struct archive *, const char *);
int archive_write_header(struct archive *, struct archive_entry *);
ssize_t archive_write_data(struct archive *, const void *, size_t);
int archive_write_close(struct archive *);
int archive_write_free(struct archive *);

#endif
