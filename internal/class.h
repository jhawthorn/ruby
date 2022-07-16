#ifndef INTERNAL_CLASS_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_CLASS_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Class.
 */
#include "id_table.h"           /* for struct rb_id_table */
#include "internal/gc.h"        /* for RB_OBJ_WRITE */
#include "internal/serial.h"    /* for rb_serial_t */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/intern.h"        /* for rb_alloc_func_t */
#include "ruby/ruby.h"          /* for struct RBasic */

#ifdef RCLASS_SUPER
# undef RCLASS_SUPER
#endif

struct rb_subclass_entry {
    VALUE klass;
    struct rb_subclass_entry *next;
    struct rb_subclass_entry *prev;
};

struct rb_iv_index_tbl_entry {
    uint32_t idx;
    uint16_t shape_source_id;
    uint16_t shape_dest_id;
};

struct rb_cvar_class_tbl_entry {
    uint32_t index;
    rb_serial_t global_cvar_state;
    VALUE class_value;
};

struct rb_classext_struct {
    struct st_table *iv_tbl;
#if SIZEOF_SERIAL_T == SIZEOF_VALUE /* otherwise m_tbl is in struct RClass */
    struct rb_id_table *m_tbl;
#endif
    struct rb_id_table *const_tbl;
    struct rb_id_table *callable_m_tbl;
    struct rb_id_table *cc_tbl; /* ID -> [[ci, cc1], cc2, ...] */
    struct rb_id_table *cvc_tbl;
    size_t superclass_depth;
    VALUE *superclasses;
    struct rb_subclass_entry *subclasses;
    struct rb_subclass_entry *subclass_entry;
    /**
     * In the case that this is an `ICLASS`, `module_subclasses` points to the link
     * in the module's `subclasses` list that indicates that the klass has been
     * included. Hopefully that makes sense.
     */
    struct rb_subclass_entry *module_subclass_entry;
#if SIZEOF_SERIAL_T != SIZEOF_VALUE && !USE_RVARGC /* otherwise class_serial is in struct RClass */
    rb_serial_t class_serial;
#endif
    const VALUE origin_;
    const VALUE refined_class;
    rb_alloc_func_t allocator;
    const VALUE includer;
    uint32_t max_iv_count;
    uint16_t shape_id;
};

struct RClass {
    struct RBasic basic;
    VALUE super;
#if !USE_RVARGC
    struct rb_classext_struct *ptr;
#endif
#if SIZEOF_SERIAL_T == SIZEOF_VALUE
    /* Class serial is as wide as VALUE.  Place it here. */
    rb_serial_t class_serial;
#else
    /* Class serial does not fit into struct RClass. Place m_tbl instead. */
    struct rb_id_table *m_tbl;
# if USE_RVARGC
    rb_serial_t *class_serial_ptr;
# endif
#endif
};

typedef struct rb_subclass_entry rb_subclass_entry_t;
typedef struct rb_classext_struct rb_classext_t;

#if USE_RVARGC
#  define RCLASS_EXT(c) ((rb_classext_t *)((char *)(c) + sizeof(struct RClass)))
#else
#  define RCLASS_EXT(c) (RCLASS(c)->ptr)
#endif
#define RCLASS_IV_TBL(c) (*RCLASS_IV_TBL_inline(c))
#define RCLASS_CONST_TBL(c) (RCLASS_EXT(c)->const_tbl)
#if SIZEOF_SERIAL_T == SIZEOF_VALUE
# define RCLASS_M_TBL(c) (RCLASS_EXT(c)->m_tbl)
#else
# define RCLASS_M_TBL(c) (RCLASS(c)->m_tbl)
#endif
#define RCLASS_CALLABLE_M_TBL(c) (RCLASS_EXT(c)->callable_m_tbl)
#define RCLASS_CC_TBL(c) (RCLASS_EXT(c)->cc_tbl)
#define RCLASS_CVC_TBL(c) (RCLASS_EXT(c)->cvc_tbl)
#define RCLASS_ORIGIN(c) (RCLASS_EXT(c)->origin_)
#define RCLASS_REFINED_CLASS(c) (RCLASS_EXT(c)->refined_class)
#if SIZEOF_SERIAL_T == SIZEOF_VALUE
# define RCLASS_SERIAL(c) (RCLASS(c)->class_serial)
#else
# if USE_RVARGC
#  define RCLASS_SERIAL(c) (*RCLASS(c)->class_serial_ptr)
# else
#  define RCLASS_SERIAL(c) (RCLASS_EXT(c)->class_serial)
# endif
#endif
#define RCLASS_INCLUDER(c) (RCLASS_EXT(c)->includer)
#define RCLASS_SUBCLASS_ENTRY(c) (RCLASS_EXT(c)->subclass_entry)
#define RCLASS_MODULE_SUBCLASS_ENTRY(c) (RCLASS_EXT(c)->module_subclass_entry)
#define RCLASS_ALLOCATOR(c) (RCLASS_EXT(c)->allocator)
#define RCLASS_SUBCLASSES(c) (RCLASS_EXT(c)->subclasses)
#define RCLASS_SUPERCLASS_DEPTH(c) (RCLASS_EXT(c)->superclass_depth)
#define RCLASS_SUPERCLASSES(c) (RCLASS_EXT(c)->superclasses)

#define RICLASS_IS_ORIGIN FL_USER0
#define RCLASS_CLONED     FL_USER1
#define RCLASS_SUPERCLASSES_INCLUDE_SELF FL_USER2
#define RICLASS_ORIGIN_SHARED_MTBL FL_USER3

#ifndef shape_id_t
typedef uint16_t shape_id_t;
#define shape_id_t shape_id_t
#endif

static inline shape_id_t
RCLASS_SHAPE_ID(VALUE obj)
{
    return RCLASS_EXT(obj)->shape_id;
}

static inline st_table **RCLASS_IV_TBL_inline(VALUE c) {
    if (RB_TYPE_P(c, T_ICLASS)) {
        VALUE original_module = RBASIC(c)->klass;
        if (RB_TYPE_P(original_module, T_MODULE) && RCLASS_EXT(c)->iv_tbl != RCLASS_EXT(original_module)->iv_tbl) {
            fprintf(stderr, "iv_tables don't match:\n");
            rb_obj_info_dump(c);
            fprintf(stderr, "  %p\n", RCLASS_EXT(c)->iv_tbl);
            rb_obj_info_dump(original_module);
            fprintf(stderr, "  %p\n", RCLASS_EXT(original_module)->iv_tbl);
            rb_bug("iv_tables");
        }
    }
    return &(RCLASS_EXT(c)->iv_tbl);
}

static inline void RCLASS_SET_IV_TBL(VALUE c, st_table *iv_tbl) {
    if (RB_TYPE_P(c, T_ICLASS)) {
    }
    RCLASS_EXT(c)->iv_tbl = iv_tbl;
}

/* class.c */
void rb_class_subclass_add(VALUE super, VALUE klass);
void rb_class_remove_from_super_subclasses(VALUE);
void rb_class_update_superclasses(VALUE);
size_t rb_class_superclasses_memsize(VALUE);
void rb_class_remove_subclass_head(VALUE);
int rb_singleton_class_internal_p(VALUE sklass);
VALUE rb_class_boot(VALUE);
VALUE rb_class_s_alloc(VALUE klass);
VALUE rb_module_s_alloc(VALUE klass);
void rb_module_set_initialized(VALUE module);
void rb_module_check_initializable(VALUE module);
VALUE rb_make_metaclass(VALUE, VALUE);
VALUE rb_include_class_new(VALUE, VALUE);
void rb_class_foreach_subclass(VALUE klass, void (*f)(VALUE, VALUE), VALUE);
void rb_class_detach_subclasses(VALUE);
void rb_class_detach_module_subclasses(VALUE);
void rb_class_remove_from_module_subclasses(VALUE);
VALUE rb_obj_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_protected_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_private_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_public_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_class_undefined_instance_methods(VALUE mod);
VALUE rb_special_singleton_class(VALUE);
VALUE rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach);
VALUE rb_singleton_class_get(VALUE obj);
void rb_undef_methods_from(VALUE klass, VALUE super);

static inline void RCLASS_SET_ORIGIN(VALUE klass, VALUE origin);
static inline void RICLASS_SET_ORIGIN_SHARED_MTBL(VALUE iclass);
static inline VALUE RCLASS_SUPER(VALUE klass);
static inline VALUE RCLASS_SET_SUPER(VALUE klass, VALUE super);
static inline void RCLASS_SET_INCLUDER(VALUE iclass, VALUE klass);

MJIT_SYMBOL_EXPORT_BEGIN
VALUE rb_class_inherited(VALUE, VALUE);
VALUE rb_keyword_error_new(const char *, VALUE);
MJIT_SYMBOL_EXPORT_END

static inline void
RCLASS_SET_ORIGIN(VALUE klass, VALUE origin)
{
    RB_OBJ_WRITE(klass, &RCLASS_ORIGIN(klass), origin);
    if (klass != origin) FL_SET(origin, RICLASS_IS_ORIGIN);
}

static inline void
RICLASS_SET_ORIGIN_SHARED_MTBL(VALUE iclass)
{
    FL_SET(iclass, RICLASS_ORIGIN_SHARED_MTBL);
}

static inline bool
RICLASS_OWNS_M_TBL_P(VALUE iclass)
{
    return FL_TEST_RAW(iclass, RICLASS_IS_ORIGIN | RICLASS_ORIGIN_SHARED_MTBL) == RICLASS_IS_ORIGIN;
}

static inline void
RCLASS_SET_INCLUDER(VALUE iclass, VALUE klass)
{
    RB_OBJ_WRITE(iclass, &RCLASS_INCLUDER(iclass), klass);
}

static inline VALUE
RCLASS_SUPER(VALUE klass)
{
    return RCLASS(klass)->super;
}

static inline VALUE
RCLASS_SET_SUPER(VALUE klass, VALUE super)
{
    if (super) {
        rb_class_remove_from_super_subclasses(klass);
        rb_class_subclass_add(super, klass);
    }
    RB_OBJ_WRITE(klass, &RCLASS(klass)->super, super);
    rb_class_update_superclasses(klass);
    return super;
}

#endif /* INTERNAL_CLASS_H */
