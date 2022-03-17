#ifndef INTERNAL_VARIABLE_H                              /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_VARIABLE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for variables.
 */
#include "ruby/internal/config.h"
#include <stddef.h>             /* for size_t */
#include "constant.h"           /* for rb_const_entry_t */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/ruby.h"          /* for VALUE */

/* global variable */

#define ROBJECT_TRANSIENT_FLAG    FL_USER2

/* variable.c */
void rb_gc_mark_global_tbl(void);
void rb_gc_update_global_tbl(void);
size_t rb_generic_ivar_memsize(VALUE);
VALUE rb_search_class_path(VALUE);
VALUE rb_attr_delete(VALUE, ID);
VALUE rb_ivar_lookup(VALUE obj, ID id, VALUE undef);
void rb_autoload_str(VALUE mod, ID id, VALUE file);
VALUE rb_autoload_at_p(VALUE, ID, int);
NORETURN(VALUE rb_mod_const_missing(VALUE,VALUE));
rb_gvar_getter_t *rb_gvar_getter_function_of(ID);
rb_gvar_setter_t *rb_gvar_setter_function_of(ID);
void rb_gvar_readonly_setter(VALUE v, ID id, VALUE *_);
void rb_gvar_ractor_local(const char *name);
static inline bool ROBJ_TRANSIENT_P(VALUE obj);
static inline void ROBJ_TRANSIENT_SET(VALUE obj);
static inline void ROBJ_TRANSIENT_UNSET(VALUE obj);
uint32_t rb_obj_ensure_iv_index_mapping(VALUE obj, ID id);

typedef uint16_t shape_id_t;

struct rb_shape {
    // Put frozen into the shape's flags
    VALUE flags;
    // id -> st_table;
    struct rb_id_table * edges;
    // Store all previously seen ivars
    struct rb_id_table * iv_table;
    shape_id_t id;
    shape_id_t parent_id;
    ID edge_name;
    // TODO: remove these four fields (eventually move frozen into flags)
    uint16_t transition_count;
    uint32_t miss_on_set;
    uint32_t miss_on_get;
    bool frozen;
};

#ifndef rb_shape_t
typedef struct rb_shape rb_shape_t;
#define rb_shape_t rb_shape_t
#endif

shape_id_t get_shape_id(VALUE obj);
rb_shape_t* get_shape_by_id(shape_id_t shape_id);
rb_shape_t* get_shape(VALUE obj);
rb_shape_t* get_next_shape(rb_shape_t* obj, ID id);
rb_shape_t* get_root_shape();
void set_shape(VALUE obj, rb_shape_t* shape);
void set_shape_id(VALUE obj, shape_id_t shape_id);
int get_iv_index_from_shape(rb_shape_t * shape, ID id, VALUE * value);
void transition_shape(VALUE obj, ID id);

# define MAX_SHAPE_ID 0xFFFE
# define INVALID_SHAPE_ID (MAX_SHAPE_ID + 1)

RUBY_SYMBOL_EXPORT_BEGIN
/* variable.c (export) */
void rb_mark_generic_ivar(VALUE);
void rb_mv_generic_ivar(VALUE src, VALUE dst);
VALUE rb_const_missing(VALUE klass, VALUE name);
int rb_class_ivar_set(VALUE klass, ID vid, VALUE value);
void rb_iv_tbl_copy(VALUE dst, VALUE src);
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
VALUE rb_gvar_get(ID);
VALUE rb_gvar_set(ID, VALUE);
VALUE rb_gvar_defined(ID);
void rb_const_warn_if_deprecated(const rb_const_entry_t *, VALUE, ID);
void rb_init_iv_list(VALUE obj);
MJIT_SYMBOL_EXPORT_END

static inline bool
ROBJ_TRANSIENT_P(VALUE obj)
{
#if USE_TRANSIENT_HEAP
    return FL_TEST_RAW(obj, ROBJECT_TRANSIENT_FLAG);
#else
    return false;
#endif
}

static inline void
ROBJ_TRANSIENT_SET(VALUE obj)
{
#if USE_TRANSIENT_HEAP
    FL_SET_RAW(obj, ROBJECT_TRANSIENT_FLAG);
#endif
}

static inline void
ROBJ_TRANSIENT_UNSET(VALUE obj)
{
#if USE_TRANSIENT_HEAP
    FL_UNSET_RAW(obj, ROBJECT_TRANSIENT_FLAG);
#endif
}

#endif /* INTERNAL_VARIABLE_H */
