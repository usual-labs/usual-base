#include "CGitShim.h"
#include <git2.h>

int usualbase_git_start(const char *user_agent, int connect_timeout, int server_timeout)
{
	int error;

	if ((error = git_libgit2_init()) < 0)
		return error;
	if ((error = git_libgit2_opts(GIT_OPT_SET_USER_AGENT, user_agent)) < 0)
		return error;
	if ((error = git_libgit2_opts(GIT_OPT_SET_SERVER_CONNECT_TIMEOUT, connect_timeout)) < 0)
		return error;
	return git_libgit2_opts(GIT_OPT_SET_SERVER_TIMEOUT, server_timeout);
}
