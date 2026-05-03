//
//  Rödbuss-Bridging-Header.h
//  Rödbuss
//

#ifndef Rödbuss_Bridging_Header_h
#define Rödbuss_Bridging_Header_h

#include <stddef.h>

/// Decompresses gzip data. Returns 0 on success, -1 on error.
/// On success, *out points to malloc'd data (caller must free) and *out_len is set.
int gzip_decompress(const unsigned char *in, size_t in_len, unsigned char **out, size_t *out_len);

#endif
