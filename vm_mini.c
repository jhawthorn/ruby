/* The VM as linked into miniruby: without builtin AOT code, which miniruby
 * itself generates (see builtin_aot.c). */
#define RUBY_VM_MINI 1
#include "vm.c"
