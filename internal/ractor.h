#ifndef INTERNAL_RACTOR_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RACTOR_H

#include "ruby/ractor.h"

void rb_ractor_ensure_main_ractor(const char *msg);

VALUE rb_ractor_foreign_class_value_slow(VALUE klass, ID id, VALUE val);

/* For val, just read from klass's constant, class ivar or class variable id, where klass
 * belongs to another Ractor.  Returns the value to use if it is shareable, else Qundef.
 *
 * An unflagged val may live in another Ractor's objspace, where walking it (and
 * promoting it to shareable) races its owner's mutator and GC.  So the owner is asked
 * to do the walk, and then the slot is re-read: the answer may be a newer value. */
static inline VALUE
rb_ractor_foreign_class_value(VALUE klass, ID id, VALUE val)
{
    if (RB_SPECIAL_CONST_P(val) || RB_OBJ_SHAREABLE_P(val)) return val;
    return rb_ractor_foreign_class_value_slow(klass, id, val);
}

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_RACTOR_H */
