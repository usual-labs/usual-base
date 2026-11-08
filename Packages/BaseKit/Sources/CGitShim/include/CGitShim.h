#ifndef CGITSHIM_H
#define CGITSHIM_H

/// Initializes libgit2 and sets its process-wide options. `git_libgit2_opts` is variadic, which
/// Swift can't call. Timeouts are in milliseconds. Returns 0 or a libgit2 error code.
int usualbase_git_start(const char *user_agent, int connect_timeout, int server_timeout);

#endif
