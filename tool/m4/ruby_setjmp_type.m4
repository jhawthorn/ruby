dnl -*- Autoconf -*-
AC_DEFUN([RUBY_SETJMP_TYPE], [
# (rb_cv_tsan_enabled is set in configure.ac)
# ThreadSanitizer keeps a shadow call stack which it only unwinds when
# longjmp or siglongjmp is called (_longjmp is not intercepted), and which it
# cannot follow through __builtin_setjmp at all.  Without this the shadow
# stack overflows after enough exceptions and libtsan crashes.
AS_IF([test "$rb_cv_tsan_enabled" = yes], [ac_cv_func___builtin_setjmp=no])
RUBY_CHECK_BUILTIN_SETJMP
RUBY_CHECK_SETJMP(_setjmpex, [], [@%:@include <setjmpex.h>])
RUBY_CHECK_SETJMP(_setjmp)
AC_MSG_CHECKING(for setjmp type)
setjmp_suffix=
AC_ARG_WITH(setjmp-type,
    AS_HELP_STRING([--with-setjmp-type], [select setjmp type]),
	[
	AS_CASE([$withval],
	[__builtin_setjmp], [setjmp=__builtin_setjmp],
	[_setjmp], [ setjmp_prefix=_],
	[sigsetjmp*], [ AC_MSG_WARN(No longer use sigsetjmp; use setjmp instead); setjmp_prefix=],
	[setjmp], [ setjmp_prefix=],
	[setjmpex], [ setjmp_prefix= setjmp_suffix=ex],
	[''], [ unset setjmp_prefix],
	[   AC_MSG_ERROR(invalid setjmp type: $withval)])], [unset setjmp_prefix])
setjmp_cast=
AS_IF([test ${setjmp_prefix+set}], [
    AS_IF([test "${setjmp_prefix}" && eval test '$ac_cv_func_'${setjmp_prefix}setjmp${setjmp_suffix} = no], [
	AC_MSG_ERROR(${setjmp_prefix}setjmp${setjmp_suffix} is not available)
    ])
], [{ AS_CASE("$ac_cv_func___builtin_setjmp", [yes*], [true], [false]) }], [
    setjmp_cast=`expr "$ac_cv_func___builtin_setjmp" : "yes with cast (\(.*\))"`
    setjmp_prefix=__builtin_
    setjmp_suffix=
], [test "$ac_cv_header_setjmpex_h:$ac_cv_func__setjmpex" = yes:yes], [
    setjmp_prefix=
    setjmp_suffix=ex
], [test "$ac_cv_func__setjmp" = yes], [
    setjmp_prefix=_
    setjmp_suffix=
], [
    setjmp_prefix=
    setjmp_suffix=
])
AC_MSG_RESULT(${setjmp_prefix}setjmp${setjmp_suffix}${setjmp_cast:+\($setjmp_cast\)})
AC_DEFINE_UNQUOTED([RUBY_SETJMP(env)], [${setjmp_prefix}setjmp${setjmp_suffix}($setjmp_cast(env))])
longjmp_prefix=$setjmp_prefix
AS_IF([test "$rb_cv_tsan_enabled" = yes], [longjmp_prefix=])
AC_DEFINE_UNQUOTED([RUBY_LONGJMP(env,val)], [${longjmp_prefix}longjmp($setjmp_cast(env),val)])
AS_CASE(["$GCC:$setjmp_prefix"], [yes:__builtin_], [], AC_DEFINE_UNQUOTED(RUBY_JMP_BUF, jmp_buf))
AS_IF([test x$setjmp_suffix = xex], [AC_DEFINE_UNQUOTED(RUBY_USE_SETJMPEX, 1)])
])dnl
