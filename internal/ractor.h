#ifndef INTERNAL_RACTOR_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RACTOR_H

#include "ruby/ractor.h"

void rb_ractor_ensure_main_ractor(const char *msg);

bool rb_ractor_foreign_shareable_p_continue(VALUE obj);

/* rb_ractor_shareable_p for an object read out of a class that another Ractor owns.
 * Such an object may live in another Ractor's objspace, where walking it (and promoting
 * it to shareable) races its owner's mutator and GC, so the walk is left to the owner. */
static inline bool
rb_ractor_foreign_shareable_p(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj) || RB_OBJ_SHAREABLE_P(obj)) return true;
    return rb_ractor_foreign_shareable_p_continue(obj);
}

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_RACTOR_H */
