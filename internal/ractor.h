#ifndef INTERNAL_RACTOR_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RACTOR_H

void rb_ractor_ensure_main_ractor(const char *msg);

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_SYMBOL_EXPORT_END

/* ractor.c */
void rb_obj_mark_no_ivars(VALUE obj);

#endif /* INTERNAL_RACTOR_H */
