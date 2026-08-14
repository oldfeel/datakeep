// SIGSYS：Android < 12 的 seccomp 会拦截 Go 1.23+ 的 pidfd_open 等系统调用并直接杀进程。
// gomobile 共享库里 Go 自带的 SIGSYS 忽略不可靠，须在加载 libgojni 前安装本处理器，
// 把 seccomp 违规转成 -ENOSYS，让 Go 回退到旧路径。
// 参考：https://github.com/golang/go/issues/70508

#include <errno.h>
#include <jni.h>
#include <signal.h>
#include <string.h>

#if defined(__linux__)
#include <ucontext.h>

#ifndef SYS_SECCOMP
#define SYS_SECCOMP 1
#endif

static struct sigaction previous_sigsys_action;

static void sigsys_handler(int sig, siginfo_t *info, void *ucontext) {
  if (info == NULL || ucontext == NULL || info->si_code != SYS_SECCOMP) {
    if (previous_sigsys_action.sa_flags & SA_SIGINFO) {
      previous_sigsys_action.sa_sigaction(sig, info, ucontext);
    } else if (previous_sigsys_action.sa_handler == SIG_IGN) {
      return;
    } else if (previous_sigsys_action.sa_handler != SIG_DFL) {
      previous_sigsys_action.sa_handler(sig);
    } else {
      sigaction(SIGSYS, &previous_sigsys_action, NULL);
      raise(SIGSYS);
    }
    return;
  }

  ucontext_t *ctx = (ucontext_t *)ucontext;
#if defined(__arm__)
  ctx->uc_mcontext.arm_r0 = (unsigned long)(-ENOSYS);
#elif defined(__aarch64__)
  ctx->uc_mcontext.regs[0] = (unsigned long long)(-ENOSYS);
#elif defined(__i386__)
  ctx->uc_mcontext.gregs[REG_EAX] = (unsigned long)(-ENOSYS);
#elif defined(__x86_64__)
  ctx->uc_mcontext.gregs[REG_RAX] = (unsigned long long)(-ENOSYS);
#endif
}
#endif

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)vm;
  (void)reserved;
#if defined(__linux__)
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = sigsys_handler;
  sa.sa_flags = SA_SIGINFO | SA_NODEFER;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGSYS, &sa, &previous_sigsys_action);
#endif
  return JNI_VERSION_1_6;
}
