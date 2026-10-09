// The vendored libraylib.a was compiled against glibc >= 2.38, which renames
// strtol & co. to their C23 variants. The release links against glibc 2.29, so
// these forward to the classic functions (C23 only adds the "0b" prefix).
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

long __isoc23_strtol(const char *s, char **e, int b) { return strtol(s, e, b); }
long long __isoc23_strtoll(const char *s, char **e, int b) { return strtoll(s, e, b); }
unsigned long __isoc23_strtoul(const char *s, char **e, int b) { return strtoul(s, e, b); }
unsigned long long __isoc23_strtoull(const char *s, char **e, int b) { return strtoull(s, e, b); }
int __isoc23_vsscanf(const char *s, const char *f, va_list a) { return vsscanf(s, f, a); }
int __isoc23_sscanf(const char *s, const char *f, ...) {
	va_list a;
	va_start(a, f);
	int r = vsscanf(s, f, a);
	va_end(a);
	return r;
}
