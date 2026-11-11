#ifndef F64_UNISTD_H
#define F64_UNISTD_H

#include <stddef.h>
#include <sys/types.h>

#define F_OK 0
#define R_OK 4
#define W_OK 2

int access(const char *path, int mode);
int unlink(const char *path);
int usleep(unsigned usec);

#endif
