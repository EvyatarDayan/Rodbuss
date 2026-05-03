//
//  GzipHelper.c
//  Rödbuss
//
//  Decompresses gzip data using system zlib (for GTFS-RT feeds that are gzip-compressed).
//

#include <zlib.h>
#include <stdlib.h>
#include <string.h>

int gzip_decompress(const unsigned char *in, size_t in_len, unsigned char **out, size_t *out_len) {
    if (in == NULL || in_len < 10 || out == NULL || out_len == NULL) return -1;
    if (in[0] != 0x1f || in[1] != 0x8b) return -1; /* not gzip */

    z_stream strm = {0};
    /* 16 + 15 means gzip format for inflateInit2 */
    if (inflateInit2(&strm, 16 + 15) != Z_OK) return -1;

    strm.next_in = (z_const Bytef *)in;
    strm.avail_in = (uInt)in_len;

    size_t buf_size = in_len * 4;
    if (buf_size < 65536) buf_size = 65536;
    unsigned char *buf = (unsigned char *)malloc(buf_size);
    if (!buf) { inflateEnd(&strm); return -1; }

    strm.next_out = buf;
    strm.avail_out = (uInt)buf_size;

    int ret = inflate(&strm, Z_FINISH);
    if (ret != Z_STREAM_END && ret != Z_OK) {
        free(buf);
        inflateEnd(&strm);
        return -1;
    }

    *out_len = strm.total_out;
    *out = (unsigned char *)realloc(buf, strm.total_out);
    if (!*out) *out = buf; /* use buf as-is if realloc fails */
    inflateEnd(&strm);
    return 0;
}
