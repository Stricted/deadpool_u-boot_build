/*
 * fake_time.c - ptrace-based time + urandom spoofing for statically-linked binaries.
 *
 * LD_PRELOAD cannot intercept symbols in statically-linked binaries.  This
 * wrapper uses ptrace(PTRACE_SYSCALL) to:
 *  - catch SYS_time / SYS_gettimeofday / SYS_clock_gettime and substitute
 *    SOURCE_DATE_EPOCH, making aml_encrypt embed a deterministic timestamp.
 *  - catch SYS_open / SYS_openat for /dev/urandom and redirect to /dev/zero,
 *    making the mbedTLS CSPRNG seed deterministic (all-zero) so RSA/AES
 *    operations produce the same output every build.
 *
 * Some aml_encrypt variants (e.g. fip/g12a/aml_encrypt_g12a from the BPI
 * FIP) call gettimeofday through the Linux vDSO, a userspace mapping that
 * bypasses the kernel syscall path entirely — ptrace PTRACE_SYSCALL cannot
 * trap vDSO calls.  To force those variants back to real syscalls we zero
 * out the AT_SYSINFO_EHDR and AT_SYSINFO entries in the auxiliary vector
 * immediately after exec (before any user code runs).  With no vDSO address,
 * glibc's startup skips vDSO registration and falls back to direct syscalls,
 * which ptrace can then intercept normally.  This is safer than unmapping the
 * vDSO pages because it doesn't leave a dangling pointer in AT_SYSINFO_EHDR.
 *
 * Build:  cc -O2 -o fake_time fake_time.c
 * Usage:  TZ=UTC ./fake_time EPOCH_SECS /path/to/aml_encrypt [args...]
 */
#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <errno.h>

#ifndef __x86_64__
#  error "fake_time is x86-64 only (syscall numbers are architecture-specific)"
#endif

#define SYS_OPEN           2
#define SYS_OPENAT       257
#define SYS_GETTIMEOFDAY  96
#define SYS_TIME         201
#define SYS_CLOCK_GETTIME 228

#define AT_SYSINFO     32   /* vDSO __kernel_vsyscall address (legacy) */
#define AT_SYSINFO_EHDR 33  /* vDSO ELF header address (used by modern glibc) */

static uint64_t frozen_epoch;

static void poke64(pid_t pid, uint64_t addr, uint64_t val)
{
    if (!addr) return;
    ptrace(PTRACE_POKEDATA, pid, (void *)(uintptr_t)addr, (void *)(uintptr_t)val);
}

/*
 * Read a short string from the tracee's address space.
 */
static void peek_string(pid_t pid, uint64_t addr, char *buf, size_t maxlen)
{
    size_t i;
    memset(buf, 0, maxlen);
    for (i = 0; i < maxlen; i += 8) {
        errno = 0;
        long word = ptrace(PTRACE_PEEKDATA, pid, (void *)(uintptr_t)(addr + i), NULL);
        if (errno) break;
        size_t copy = (maxlen - i < 8) ? maxlen - i : 8;
        memcpy(buf + i, &word, copy);
        if (memchr(buf + i, '\0', copy)) break;
    }
}

/*
 * Redirect /dev/urandom opens to /dev/zero so mbedTLS CSPRNG seeds from a
 * deterministic (all-zero) source.
 */
static void redirect_urandom(pid_t pid, uint64_t path_addr)
{
    char path[16];
    peek_string(pid, path_addr, path, sizeof(path));
    if (strcmp(path, "/dev/urandom") != 0)
        return;

    static const char devzero[16] = "/dev/zero";
    long w0, w1;
    memcpy(&w0, devzero,     8);
    memcpy(&w1, devzero + 8, 8);
    ptrace(PTRACE_POKEDATA, pid, (void *)(uintptr_t)(path_addr + 0), (void *)(uintptr_t)w0);
    ptrace(PTRACE_POKEDATA, pid, (void *)(uintptr_t)(path_addr + 8), (void *)(uintptr_t)w1);
}

/*
 * Zero out AT_SYSINFO_EHDR (and AT_SYSINFO) in the tracee's auxiliary vector
 * so glibc does not register the vDSO at startup.  Without a vDSO, all time
 * functions fall back to real syscalls that ptrace can intercept.
 *
 * On x86-64 Linux the initial stack layout at exec time is:
 *   [rsp]   argc
 *   [rsp+8] argv[0] ... argv[argc-1] NULL
 *           envp[0] ... NULL
 *           auxv pairs: [type][value] ... [AT_NULL][0]
 *
 * We walk this structure with PTRACE_PEEKDATA and zero matching value fields.
 * Called once, at the first SIGTRAP (exec event) before any user code runs.
 */
static void clear_vdso_auxv(pid_t pid)
{
    struct user_regs_struct regs;
    if (ptrace(PTRACE_GETREGS, pid, NULL, &regs) < 0) return;

    uint64_t p = regs.rsp;

    /* read argc */
    errno = 0;
    long argc = ptrace(PTRACE_PEEKDATA, pid, (void *)(uintptr_t)p, NULL);
    if (errno || argc < 0 || argc > 65536) return;
    p += 8;

    /* skip argv (argc entries) + NULL terminator */
    p += (uint64_t)(argc + 1) * 8;

    /* skip envp: walk until NULL pointer */
    for (;;) {
        errno = 0;
        long ptr = ptrace(PTRACE_PEEKDATA, pid, (void *)(uintptr_t)p, NULL);
        if (errno || ptr == 0) break;
        p += 8;
    }
    p += 8; /* skip the NULL terminator */

    /* walk auxv [type, value] pairs until AT_NULL */
    for (;;) {
        errno = 0;
        long type = ptrace(PTRACE_PEEKDATA, pid, (void *)(uintptr_t)p, NULL);
        if (errno || type == 0 /* AT_NULL */) break;

        if (type == AT_SYSINFO_EHDR || type == AT_SYSINFO)
            ptrace(PTRACE_POKEDATA, pid, (void *)(uintptr_t)(p + 8), 0);

        p += 16; /* type (8 bytes) + value (8 bytes) */
    }
}

int main(int argc, char *argv[])
{
    if (argc < 3) {
        fprintf(stderr, "usage: %s EPOCH_SECS program [args...]\n", argv[0]);
        return 1;
    }

    frozen_epoch = (uint64_t)atoll(argv[1]);

    pid_t child = fork();
    if (child < 0) { perror("fork"); return 1; }

    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) < 0) {
            perror("ptrace(TRACEME)"); _exit(1);
        }
        raise(SIGSTOP);
        execv(argv[2], argv + 2);
        perror("execv"); _exit(127);
    }

    int status;
    waitpid(child, &status, 0);   /* wait for initial SIGSTOP */
    ptrace(PTRACE_SETOPTIONS, child, 0, (void *)(long)PTRACE_O_TRACESYSGOOD);

    int      in_syscall  = 0;
    long     cur_nr      = -1;
    uint64_t cur_arg1    = 0, cur_arg2 = 0;
    int      pending_sig = 0;
    int      exec_done   = 0;

    for (;;) {
        ptrace(PTRACE_SYSCALL, child, NULL, (void *)(long)pending_sig);
        pending_sig = 0;

        if (waitpid(child, &status, 0) < 0) break;
        if (WIFEXITED(status))   return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);
        if (sig != (SIGTRAP | 0x80)) {
            if (!exec_done && sig == SIGTRAP) {
                /* First SIGTRAP is the exec event — zero AT_SYSINFO_EHDR in
                 * the auxv so glibc falls back to syscall-path time functions
                 * that ptrace can intercept.  No pages are unmapped so there
                 * is no dangling pointer risk. */
                clear_vdso_auxv(child);
                exec_done = 1;
            } else {
                pending_sig = (sig == SIGTRAP) ? 0 : sig;
            }
            continue;
        }

        struct user_regs_struct regs;
        ptrace(PTRACE_GETREGS, child, NULL, &regs);

        if (!in_syscall) {
            cur_nr   = (long)regs.orig_rax;
            cur_arg1 = regs.rdi;
            cur_arg2 = regs.rsi;
            in_syscall = 1;

            if (cur_nr == SYS_OPEN)
                redirect_urandom(child, cur_arg1);
            else if (cur_nr == SYS_OPENAT)
                redirect_urandom(child, cur_arg2);

            continue;
        }

        in_syscall = 0;

        switch (cur_nr) {
        case SYS_TIME:
            regs.rax = frozen_epoch;
            ptrace(PTRACE_SETREGS, child, NULL, &regs);
            poke64(child, cur_arg1, frozen_epoch);
            break;

        case SYS_GETTIMEOFDAY:
            poke64(child, cur_arg1,     frozen_epoch);
            poke64(child, cur_arg1 + 8, 0);
            break;

        case SYS_CLOCK_GETTIME:
            poke64(child, cur_arg2,     frozen_epoch);
            poke64(child, cur_arg2 + 8, 0);
            break;
        }
    }

    return 1;
}
