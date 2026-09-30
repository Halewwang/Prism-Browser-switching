#include <libproc.h>
#include <sys/proc_info.h>
#include <stdint.h>
#include <string.h>

// Read the kernel's microsecond birth timestamp, rather than ps's rounded
// display time. A reused PID must not be mistaken for the original process.
int prism_installer_pid_identity(int pid, uint64_t *seconds, uint64_t *microseconds, uint32_t *uid) {
    struct proc_bsdinfo info;
    memset(&info, 0, sizeof(info));
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (bytes != sizeof(info) || info.pbi_pid != pid) return 0;
    *seconds = info.pbi_start_tvsec;
    *microseconds = info.pbi_start_tvusec;
    *uid = info.pbi_uid;
    return 1;
}

int prism_installer_pid_architecture(int pid, int32_t *type, int32_t *subtype) {
    struct proc_archinfo info;
    memset(&info, 0, sizeof(info));
    int bytes = proc_pidinfo(pid, PROC_PIDARCHINFO, 0, &info, sizeof(info));
    if (bytes != sizeof(info)) return 0;
    *type = info.p_cputype;
    *subtype = info.p_cpusubtype;
    return 1;
}
