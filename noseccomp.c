#define _GNU_SOURCE
#include <stdarg.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <dlfcn.h>
int prctl(int option, ...) {
    va_list ap; unsigned long a2,a3,a4,a5;
    va_start(ap, option);
    a2=va_arg(ap,unsigned long); a3=va_arg(ap,unsigned long);
    a4=va_arg(ap,unsigned long); a5=va_arg(ap,unsigned long);
    va_end(ap);
    if (option == PR_SET_SECCOMP) return 0;
    static int (*real)(int,unsigned long,unsigned long,unsigned long,unsigned long)=0;
    if(!real) real=dlsym(RTLD_NEXT,"prctl");
    return real(option,a2,a3,a4,a5);
}
long syscall(long number, ...) {
    va_list ap; long a1,a2,a3,a4,a5,a6;
    va_start(ap, number);
    a1=va_arg(ap,long); a2=va_arg(ap,long); a3=va_arg(ap,long);
    a4=va_arg(ap,long); a5=va_arg(ap,long); a6=va_arg(ap,long);
    va_end(ap);
    if (number == SYS_seccomp) return 0;
    static long (*real)(long,long,long,long,long,long,long)=0;
    if(!real) real=dlsym(RTLD_NEXT,"syscall");
    return real(number,a1,a2,a3,a4,a5,a6);
}