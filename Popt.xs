/* $Id: Popt.xs,v 1.47 2003/09/05 22:15:12 dirt Exp $
 * vim: syn=xs ts=8 sts=4 sw=4 et fo=croql tw=70
 *
 * Perl XS interface to the popt(3) library.
 *
 * NB: this is my first XS module of any meaningful size, and I wrote
 * it over a 3-day weekend as a "fun" project, so go easy on me if
 * something looks painfully idiotic. Like this comment, for example. 
 */
#include <popt.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdlib.h>

/* This is a wrapper to hold the argv and options arrays: 
 *     - need to free the allocated arrays and keep their scalar
 *       refcounts accurate, because I think popt returns pointers to
 *       positions within the string?
 *     - need to make a contiguous array of struct poptOptions to pass
 *       to popt, assembled out of the non-contiguous array of
 *       Getopt::Popt::Options
 *     - need to hack at the copied options array to strip off argInfo
 *       bitop flags (see _new_blessed_poptContext() and
 *       _assign_argref())
 *     - need to keep aliases around because their argv's are still
 *       used by popt, even if the alias object is undef'd and
 *       destroyed
 */
struct poptContext_wrapper {
    /* argv array */
    AV *av_argv;
    char **ch_argv;
    int argc;

    /* options array */
    AV *av_options;
    struct poptOption *popt_options;
    int num_options;
    poptContext popt_context;

    /* aliases array */
    AV *av_aliases;
};

/* This wrapper holds the argv array so its refcount stays above 0. 
 * Stored as a scalar ref and blessed into Getopt::Popt::Alias */
struct poptAlias_wrapper {
    AV* av_argv; /* place to hold onto args */
    struct poptAlias popt_alias; /* real data */
};

/* The SV arg is used to store a reference to a scalar for assignment
 * after poptGetContext() call. 
 *
 * Stored as a scalar ref and blessed into Getopt::Popt::Option. */
struct poptOption_wrapper {
    SV* sv_arg; /* place to stick the sv to return */
    struct poptOption popt_option; /* real mccoy */
};


/* 
 * Getters: get a wrapper out of a scalar ref; automatically called
 * by the typemap.
 */

/* get the context wrapper struct from our blessed scalar ref thing */
struct poptContext_wrapper *get_context_wrapper(SV* this) {
    if(!sv_derived_from(this,"Getopt::Popt") || !sv_isobject(this)) {
        croak("Not a reference to a Getopt::Popt object");
    }
    return INT2PTR(struct poptContext_wrapper*, SvIV(SvRV(this)));
}

/* get the option wrapper struct from our blessed scalar ref thing */
struct poptAlias_wrapper *get_alias_wrapper(SV* this) {
    if(!sv_derived_from(this,"Getopt::Popt::Alias") || !sv_isobject(this)) {
        croak("Not a reference to a Getopt::Popt::Alias object");
    }
    return INT2PTR(struct poptAlias_wrapper*, SvIV(SvRV(this)));
}

/* get the option wrapper struct from our blessed scalar ref thing */
struct poptOption_wrapper *get_option_wrapper(SV* this) {
    if(!sv_derived_from(this,"Getopt::Popt::Option") || !sv_isobject(this)) {
        croak("Not a reference to a Getopt::Popt::Option object");
    }
    return INT2PTR(struct poptOption_wrapper*, SvIV(SvRV(this)));
}

MODULE = Getopt::Popt   PACKAGE = Getopt::Popt::Alias
PROTOTYPES: DISABLE

=cut

NOTE: parameters are expected to be validated before this function
gets called, although some validation is performed.

=cut

SV*
_new_blessed_poptAlias(xclass, longName, shortName, argv)
    char* xclass
    char* longName
    char shortName
    SV* argv
    PREINIT:
    struct poptAlias_wrapper *alias_wrapper;
    struct poptAlias *popt_alias;
    SV* sv_array_elem;
    STRLEN len;
    int item;
    PPCODE:
    /* validation checks */
    /* make sure argv is an arrayref */
    /* XXX: we're doing this twice (once in the calling code, again here) */
    if(!SvROK(argv) || SvTYPE(SvRV(argv)) != SVt_PVAV) {
        croak("argv isn't an arrayref");
    }

    /* create the alias */
    New(78, alias_wrapper, 1, struct poptAlias_wrapper);
    /* shortcut */
    popt_alias = &(alias_wrapper->popt_alias);

    /* set longName and shortName */
    len = strlen(longName);
    if(len) {
        New(78, popt_alias->longName, len+1, char);
        strncpy((char *) popt_alias->longName, longName, len+1);
    } else {
        popt_alias->longName = NULL;
    }
    popt_alias->shortName = shortName;

    /* get the argv array and increment its refcount*/
    alias_wrapper->av_argv = (AV *) SvREFCNT_inc(SvRV(argv));
    popt_alias->argc = av_len(alias_wrapper->av_argv) + 1;

    /* copy the AV into a char** */
    /* do a malloc() here because the man page says "must be free()able" */
    popt_alias->argv = malloc(sizeof(char *) * (popt_alias->argc + 1));
    /* check for failure */
    if(popt_alias->argv == NULL) {
        /* cleanup and abort */
        if(popt_alias->longName) Safefree(popt_alias->longName);
        SvREFCNT_dec(alias_wrapper->av_argv);
        Safefree(alias_wrapper);
        croak("argv malloc() failed");
    }

    for(item = 0; item < popt_alias->argc; item++) {
        sv_array_elem = *(av_fetch(alias_wrapper->av_argv, item, 0));
        /* set the arg */
        /* XXX: after the alias has been added to the
         * context we'll still need the string even if this alias
         * object is destroyed */
        popt_alias->argv[item] = SvPV_nolen(sv_array_elem);
    }
    /* cap it off */
    popt_alias->argv[item] = NULL;

    /* bless it and return */
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), xclass, (void*)alias_wrapper);
    XSRETURN(1);

void
DESTROY(self)
    struct poptAlias_wrapper* self
    PREINIT:
    int item;
    SV* sv_array_elem;
    PPCODE:
    /*
    fprintf(stderr,"Getopt::Popt::Alias::DESTROY() called\n");
    fprintf(stderr,"av_arg refcount=%d\n",SvREFCNT(self->av_argv));
    for(item = 0; item < av_len(self->av_argv); item++) {
        sv_array_elem = *(av_fetch(self->av_argv, item, 0));
        fprintf(stderr,"item[%d]->value=\"%s\"\n",item,SvPV_nolen(sv_array_elem));
        fprintf(stderr,"item[%d]->refcount=%d\n",item,SvREFCNT(sv_array_elem));
    }*/
    /* decrement the refcount on av_argv so it goes away */
    SvREFCNT_dec((SV *) self->av_argv);
    /* free the longName */
    if(self->popt_alias.longName) { 
        Safefree(self->popt_alias.longName);
    }
    /* XXX: just gunna have to assume libpopt will take care off that malloc()d
     * argv array */


MODULE = Getopt::Popt   PACKAGE = Getopt::Popt::Option

=head

_new_blessed_poptOption()

Create a new poptOption struct; the tricky part here is creating
arg based on argInfo.

NOTE: parameters are expected to be validated before this function
gets called, although some validation is performed.

=cut

SV*
_new_blessed_poptOption(xclass, longName, shortName, argInfo, arg, val, descrip, argDescrip)
    char* xclass
    char* longName
    char shortName
    int argInfo
    SV* arg
    int val
    char* descrip
    char* argDescrip
    PREINIT:
    struct poptOption_wrapper* self;
    struct poptOption *popt_option;
    STRLEN len;
    PPCODE:
    /* create the option */
    Newz(78, self, 1, struct poptOption_wrapper);

    /* assign the arg, if given */
    if(SvOK(arg)) {
        /* make sure it's a reference to a scalar/undef 
         * XXX: we're doing this twice (once in the calling code, again here) */
        if(SvROK(arg)) {
            /* store the referenced scalar and increment its refcount */
            self->sv_arg = SvREFCNT_inc(SvRV(arg));
        } else {
            /* cleanup and abort */
            Safefree(self);
            croak("arg isn't a reference");
        }
    } else {
        /* if arg wasn't given, argInfo better be POPT_ARG_[NONE|VAL] */
        /* XXX: popt(3) manpage makes it look like only POPT_ARG_NONE
         * can have a null arg. popt.c says otherwise. Whatever. */
        if((argInfo & POPT_ARG_MASK) != POPT_ARG_NONE &&
           (argInfo & POPT_ARG_MASK) != POPT_ARG_VAL) {
            /* cleanup and abort */
            Safefree(self);
            croak("arg was undef, but argInfo was not POPT_ARG_NONE or POPT_ARG_VAL");
        } 

        self->sv_arg = NULL;
    }

    /* shortcut */
    popt_option = &(self->popt_option);

    /* assign longName, if given */
    if(longName) {
        /* XXX: doing strlen*() but could skip this if we used the raw SV*
         * instead (with SvCUR()) */
        len = strlen(longName);
        New(78, popt_option->longName, len+1, char);
        /* XXX: could be a very dangerous buffer overflow here */
        strncpy((char *) popt_option->longName,
                (const char *)longName,
                len+1);
    } else {
        popt_option->longName = NULL;
    }

    /* assign shortName, if given */
    popt_option->shortName = shortName;
    /* assign descrip, if given */
    if(descrip) {
        len = strlen(descrip);
        New(78, popt_option->descrip, len+1, char);
        strncpy((char *)popt_option->descrip,
                (const char *)descrip,
                len+1);
    } else {
        popt_option->descrip = NULL;
    }

    /* assign argDescrip, if given */
    if(argDescrip) {
        len = strlen(argDescrip);
        New(78, popt_option->argDescrip, len+1, char);
        strncpy((char *)popt_option->argDescrip,
                (const char *)argDescrip,
                len+1);
    } else {
        popt_option->argDescrip = NULL;
    }

    /* store the argInfo and val */
    popt_option->argInfo = argInfo;
    popt_option->val = val;

    /* create the space to store the arg */
    switch(popt_option->argInfo & POPT_ARG_MASK) {
    case POPT_ARG_NONE:
        /* check if we an svref was given or not */
        if(self->sv_arg == NULL) {
            popt_option->arg = NULL;
            break;
        } else { 
            /* continue to POPT_ARG_INT */
        }

    case POPT_ARG_VAL:
        /* check if we an svref was given or not */
        if(self->sv_arg == NULL) {
            popt_option->arg = NULL;
            break;
        } else { 
            /* continue to POPT_ARG_INT */
        }

    case POPT_ARG_INT:
        /* create a place to put it */
        New(78, popt_option->arg, 1, int);
        /* copy the value in case bitops were given */
        /* XXX: produces a warning if sv_arg isn't numeric */
        *((int *)popt_option->arg) = (int) SvIV(self->sv_arg);
        break;

    case POPT_ARG_LONG:
        /* create a place to put it */
        New(78, popt_option->arg, 1, long);
        /* copy the value in case bitops were given */
        /* XXX: produces a warning if sv_arg isn't numeric */
        *((long *)popt_option->arg) = (long) SvIV(self->sv_arg);
        break;

    case POPT_ARG_STRING:
        New(78, popt_option->arg, 1, char *);
        break;

    case POPT_ARG_FLOAT:
        New(78, popt_option->arg, 1, float);
        break;

    case POPT_ARG_DOUBLE:
        New(78, popt_option->arg, 1, double);
        break;

    default:
        /* cleanup and abort; XXX: lines duplicated in DESTROY */
        if(popt_option->descrip) Safefree(popt_option->longName);
        if(popt_option->descrip) Safefree(popt_option->descrip);
        if(popt_option->argDescrip) Safefree(popt_option->argDescrip);
        Safefree(self);
        croak("unknown argInfo value %d",argInfo);
    }

    /* bless it and return */
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), xclass, (void*)self);
    XSRETURN(1);

=cut

_assign_argref($self)

$self - blessed Getopt::Popt::Option

=cut

void
_assign_argref(self)
    struct poptOption_wrapper* self 
    PREINIT:
    struct poptOption *popt_option;
    SV* sv_arg;
    PPCODE:
    /* shortcuts */
    popt_option = &(self->popt_option);
    sv_arg = self->sv_arg;

    /* check if it was a string */
    if((popt_option->argInfo & POPT_ARG_MASK) == POPT_ARG_STRING) {
        sv_setpv(sv_arg, *((char **)popt_option->arg));
        PUTBACK; /* xs magic cut-n-pasted */
        return;
    }

    /* figure out how to assign the numeric scalar */
    switch(popt_option->argInfo & POPT_ARG_MASK) {
    case POPT_ARG_NONE:
        /* 'INT' and 'NONE' are the only one allowed to be null */
        if(sv_arg == NULL) break;
    case POPT_ARG_INT:
        sv_setiv(sv_arg, *((int *)popt_option->arg));
        break;

    case POPT_ARG_VAL:
        if(sv_arg == NULL) break;
        /* The bit op argInfo flags (POPT_ARGFLAG_OR/AND/XOR) get
         * stripped off in _new_blessed_poptContext(). Here we
         * re-assign the arg using popt's own functions and the user's
         * original val, so that the behavior is the same. */
        poptSaveInt(    (int *)popt_option->arg,    /* new value dest */
                        popt_option->argInfo,       /* user's orig argInfo */
                        popt_option->val);          /* user's orig val */

        sv_setiv(sv_arg, *((int *)popt_option->arg));
        break;

    case POPT_ARG_LONG:
        sv_setiv(sv_arg, *((long *)popt_option->arg));
        break;

    case POPT_ARG_FLOAT:
        sv_setnv(sv_arg, *((float *)popt_option->arg));
        break;

    case POPT_ARG_DOUBLE:
        sv_setnv(sv_arg, *((double *)popt_option->arg));
        break;

    default:
        /* XXX: shouldn't get here */
        croak("unknown argInfo value %d",popt_option->argInfo);
    }
    /* return the _real_ val */
    /*RETVAL = popt_option->val; TODO: make this work */

void
DESTROY(self)
    SV* self
    PREINIT:
    /* note: can't use a typemap, otherwise we'd lose sv_derived_from */
    struct poptOption_wrapper* option_wrapper = get_option_wrapper(self);
    struct poptOption *popt_option;
    PPCODE:
    /* Getopt::Popt::Option destructor */
    /*fprintf(stderr,"Getopt::Popt::Option::DESTROY called\n");*/
    /* decrement the refcount of anything we were holding onto */
    if(option_wrapper->sv_arg) {
        SvREFCNT_dec(option_wrapper->sv_arg);
    }
    /* shortcut */
    popt_option = &(option_wrapper->popt_option);
    /* free any allocated args */
    if(popt_option->arg) { 
        Safefree(option_wrapper->popt_option.arg);
    }
    /* free all the strings */
    if(popt_option->longName) Safefree(popt_option->longName);
    if(popt_option->descrip) Safefree(popt_option->descrip);
    if(popt_option->argDescrip) Safefree(popt_option->argDescrip);
    Safefree(option_wrapper);

void
_test_assign_arg(option_wrapper, str)
    struct poptOption_wrapper* option_wrapper
    char* str
    PREINIT:
    PPCODE:
    /*fprintf(stderr,"got: %s\n",SvPV_nolen(str));*/
    if((option_wrapper->popt_option.argInfo & POPT_ARG_MASK) != POPT_ARG_STRING) {
        croak("can only test with strings for now");
    }
    *((char **)option_wrapper->popt_option.arg) = str;

=cut

Not a big fan of this mixed-case function name business, especially
since this file isn't very consistent; but the precedence has been set
by libpopt.

=cut

SV *
getLongName(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    PREINIT:
    CODE:
    RETVAL = option_wrapper->popt_option.longName ?
                newSVpv(option_wrapper->popt_option.longName,0) :
                &PL_sv_undef;
    OUTPUT:
    RETVAL

SV *
getShortName(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    PREINIT:
    CODE:
    RETVAL = newSVpv(&(option_wrapper->popt_option.shortName),1);
    OUTPUT:
    RETVAL

SV *
getArgInfo(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    CODE:
    RETVAL = newSViv(option_wrapper->popt_option.argInfo);
    OUTPUT:
    RETVAL

SV *
getArg(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    CODE:
    RETVAL = option_wrapper->sv_arg ?
            newRV_inc(option_wrapper->sv_arg) :
            &PL_sv_undef;
    OUTPUT:
    RETVAL

SV *
getVal(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    CODE:
    RETVAL = newSViv(option_wrapper->popt_option.val);
    OUTPUT:
    RETVAL

SV *
getDescrip(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    CODE:
    RETVAL = option_wrapper->popt_option.descrip ? 
                newSVpv(option_wrapper->popt_option.descrip,0) :
                &PL_sv_undef;
    OUTPUT:
    RETVAL

SV *
getArgDescrip(option_wrapper)
    struct poptOption_wrapper* option_wrapper 
    CODE:
    RETVAL = option_wrapper->popt_option.argDescrip ? 
                newSVpv(option_wrapper->popt_option.argDescrip,0) :
                &PL_sv_undef;
    OUTPUT:
    RETVAL

MODULE = Getopt::Popt   PACKAGE = Getopt::Popt::Option::AUTOHELP

SV*
_new_blessed_poptOption_AUTOHELP(xclass)
    SV* xclass
    PREINIT:
    struct poptOption_wrapper* self;
    STRLEN len;
    PPCODE:
    /* create the option */
    New(78, self, 1, struct poptOption_wrapper);
    self->sv_arg = NULL;
    /* XXX: POPT_AUTOHELP ends with a comma */
    self->popt_option = (struct poptOption) POPT_AUTOHELP
    /* bless it and return */
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), SvPV_nolen(xclass), (void*)self);
    XSRETURN(1);

void
_assign_argref(self)
    struct poptOption_wrapper* self 
    PPCODE:
    /* overload our parent */
    /* nop - shouldn't ever be called anyway */

void
DESTROY(self)
    struct poptOption_wrapper *self
    PPCODE:
    /* overload Getopt::Popt::Option's descructor */
    Safefree(self);


MODULE = Getopt::Popt   PACKAGE = Getopt::Popt

=cut

Constants are loaded in a somewhat hacky way (but IMHO cleaner than
AutoLoader), creating function aliases for all constants to be
autoloaded into the module.

Currently unfinished values:
    POPT_ARG_CALLBACK
    POPT_ARG_INCLUDE_TABLE (and probably never will be finished)

Constants not exported:

    Callback stuff: 
        POPT_CBFLAG_CONTINUE
        POPT_CBFLAG_INC_DATA
        POPT_CBFLAG_POST
        POPT_CBFLAG_PRE
        POPT_CBFLAG_SKIPOPTION

    Table stuff:
        POPT_OPTION_DEPTH 

=cut

int
get_constant()
    ALIAS:
    Getopt::Popt::constant_POPT_ARGFLAG_AND          = POPT_ARGFLAG_AND
    Getopt::Popt::constant_POPT_ARGFLAG_DOC_HIDDEN   = POPT_ARGFLAG_DOC_HIDDEN
    Getopt::Popt::constant_POPT_ARGFLAG_LOGICALOPS   = POPT_ARGFLAG_LOGICALOPS
    Getopt::Popt::constant_POPT_ARGFLAG_NAND         = POPT_ARGFLAG_NAND
    Getopt::Popt::constant_POPT_ARGFLAG_NOR          = POPT_ARGFLAG_NOR
    Getopt::Popt::constant_POPT_ARGFLAG_NOT          = POPT_ARGFLAG_NOT
    Getopt::Popt::constant_POPT_ARGFLAG_ONEDASH      = POPT_ARGFLAG_ONEDASH
    Getopt::Popt::constant_POPT_ARGFLAG_OPTIONAL     = POPT_ARGFLAG_OPTIONAL
    Getopt::Popt::constant_POPT_ARGFLAG_OR           = POPT_ARGFLAG_OR
    Getopt::Popt::constant_POPT_ARGFLAG_STRIP        = POPT_ARGFLAG_STRIP
    Getopt::Popt::constant_POPT_ARGFLAG_XOR          = POPT_ARGFLAG_XOR
    Getopt::Popt::constant_POPT_ARG_DOUBLE           = POPT_ARG_DOUBLE
    Getopt::Popt::constant_POPT_ARG_FLOAT            = POPT_ARG_FLOAT
    Getopt::Popt::constant_POPT_ARG_INT              = POPT_ARG_INT
    Getopt::Popt::constant_POPT_ARG_INTL_DOMAIN      = POPT_ARG_INTL_DOMAIN
    Getopt::Popt::constant_POPT_ARG_LONG             = POPT_ARG_LONG
    Getopt::Popt::constant_POPT_ARG_MASK             = POPT_ARG_MASK
    Getopt::Popt::constant_POPT_ARG_NONE             = POPT_ARG_NONE
    Getopt::Popt::constant_POPT_ARG_STRING           = POPT_ARG_STRING
    Getopt::Popt::constant_POPT_ARG_VAL              = POPT_ARG_VAL
    Getopt::Popt::constant_POPT_BADOPTION_NOALIAS    = POPT_BADOPTION_NOALIAS
    Getopt::Popt::constant_POPT_CONTEXT_KEEP_FIRST   = POPT_CONTEXT_KEEP_FIRST
    Getopt::Popt::constant_POPT_CONTEXT_NO_EXEC      = POPT_CONTEXT_NO_EXEC
    Getopt::Popt::constant_POPT_CONTEXT_POSIXMEHARDER= POPT_CONTEXT_POSIXMEHARDER
    Getopt::Popt::constant_POPT_ERROR_BADNUMBER      = POPT_ERROR_BADNUMBER
    Getopt::Popt::constant_POPT_ERROR_BADOPERATION   = POPT_ERROR_BADOPERATION
    Getopt::Popt::constant_POPT_ERROR_BADOPT         = POPT_ERROR_BADOPT
    Getopt::Popt::constant_POPT_ERROR_BADQUOTE       = POPT_ERROR_BADQUOTE
    Getopt::Popt::constant_POPT_ERROR_ERRNO          = POPT_ERROR_ERRNO
    Getopt::Popt::constant_POPT_ERROR_NOARG          = POPT_ERROR_NOARG
    Getopt::Popt::constant_POPT_ERROR_OPTSTOODEEP    = POPT_ERROR_OPTSTOODEEP
    Getopt::Popt::constant_POPT_ERROR_OVERFLOW       = POPT_ERROR_OVERFLOW
    CODE:
        RETVAL = ix;
    OUTPUT:
    RETVAL


=cut

We need to increment refcounts to argv (because char *'s will probably point
into it) and options (because they contain a reference to the scalar we
want to assign). Though if somebody messes with elements in those arrays we
could end up in a world of hurt, but it'd be their own damn fault.

We assume parameters have been validated before this function gets called,
although some validation is performed.

=cut

SV*
_new_blessed_poptContext(xclass, name, argv, options, flags)
    char* xclass
    char* name
    SV* argv
    SV* options
    int flags
    PREINIT:
    struct poptContext_wrapper *self;
    struct poptOption_wrapper *option_wrapper;
    int item;
    SV* sv_option;
    SV* sv_arg;
    int rc;
    PPCODE:
    /* validation checks */
    /* XXX: we're doing these checks twice (once in the calling code, again here) */
    /* make sure argv is an arrayref */
    if(!SvROK(argv) || SvTYPE(SvRV(argv)) != SVt_PVAV) {
        croak("argv isn't an arrayref");
    }
    /* make sure options is an arrayref */
    if(!SvROK(options) || SvTYPE(SvRV(options)) != SVt_PVAV) {
        croak("options isn't an arrayref");
    }

    /* create the context wrapper */
    New(78, self, 1, struct poptContext_wrapper);
    /* get the argv AV and increment its refcount */
    self->av_argv = (AV *) SvREFCNT_inc(SvRV(argv));
    /* get argc */
    self->argc = av_len(self->av_argv) + 1; /* $#{$argv} + 1 */
    /* copy argv and increment each element's refcount */
    New(78, self->ch_argv, self->argc, char *);
    for(item = 0; item < self->argc; item++) {
        /* fetch the array element; sv_argv[item] = $argv->[item] */
        sv_arg = *(av_fetch(self->av_argv, item, 0));
        /* assign its string to argv */
        self->ch_argv[item] = SvPV_nolen(sv_arg);
    }
    /* setup the options arrays */
    /* get the options AV and increment its refcount*/
    self->av_options = (AV *) SvREFCNT_inc(SvRV(options)); 
    self->num_options = av_len(self->av_options) + 1; /* $#{$options} + 1 */
    New(78, self->popt_options, 
            self->num_options + 1,  /* +1 to include POPT_TABLEEND */
            struct poptOption); 
    /* setup the options array */
    /*fprintf(stderr,"self->num_options=%d\n",self->num_options);*/
    for(item = 0; item < self->num_options; item++) {
        /* get the Getopt::Popt::Option out of the array; sv_option = $options->[item] */
        sv_option = *(av_fetch(self->av_options,item,0));
        /* get the option wrapper struct out of the Getopt::Popt::Option */
        option_wrapper = get_option_wrapper(sv_option);
        /* get the poptOption struct out of the option wrapper so we
         * can pass the popt_options array to poptGetContext() later 
         * Creating a (shallow) copy to form a contiguous array of
         * options, and so we can muck with the argInfo stuff. */
        self->popt_options[item] = option_wrapper->popt_option;

        /* strip off the OR/AND/XOR junk off argInfo so the arg
         * doesn't get mutilated before we can perform bit ops on it
         * with the _real_ val */
        if((self->popt_options[item].argInfo & POPT_ARG_MASK) == POPT_ARG_VAL) {
            self->popt_options[item].argInfo = POPT_ARG_NONE;
            if(self->popt_options[item].argInfo & POPT_ARGFLAG_OR) 
                self->popt_options[item].argInfo ^= POPT_ARGFLAG_OR;
            if(self->popt_options[item].argInfo & POPT_ARGFLAG_AND) 
                self->popt_options[item].argInfo ^= POPT_ARGFLAG_AND;
            if(self->popt_options[item].argInfo & POPT_ARGFLAG_XOR) 
                self->popt_options[item].argInfo ^= POPT_ARGFLAG_XOR;

        }

        self->popt_options[item].val = item+1; /* +1 to skip 0, 0 is supposedly reserved */
    }
    /* add the end marker */
    self->popt_options[item] = (struct poptOption) POPT_TABLEEND;

    /* initialize the aliases array */
    self->av_aliases = newAV();

    /*
    fprintf(stderr,"Getopt::Popt::new(): self->argc=\"%d\"\n",self->argc);
    for(item = 0; item < self->argc; item++) {
        fprintf(stderr,"Getopt::Popt::new(): self->ch_argv[%d]=%s\n",
                item,self->ch_argv[item]);
    }*/
    /* get the actual poptContext */
    self->popt_context = poptGetContext(name,
                                    self->argc,
                                    (const char **) self->ch_argv,
                                    (const struct poptOption *) self->popt_options,
                                    flags);
    /* bless it and return */
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), xclass, (void*)self);
    XSRETURN(1);

void
DESTROY(self)
    struct poptContext_wrapper *self 
    PREINIT:
    int item;
    PPCODE:
    /*fprintf(stderr,"Getopt::Popt::DESTROY called\n");*/
    /* free the poptContext */
    poptFreeContext(self->popt_context);
    /* decrement recounts of the argv array */
    SvREFCNT_dec(self->av_argv);
    /* free the char argv arrays */
    Safefree(self->ch_argv);
    /* decrement the refcounts of the options array */
    SvREFCNT_dec(self->av_options);
    /* free the options array */
    Safefree(self->popt_options);
    /* free the aliases array */
    SvREFCNT_dec(self->av_aliases);
    /* free ourself */
    Safefree(self);

int
getNextOpt(self)
    struct poptContext_wrapper *self 
    PREINIT:
    int rc = 99999;
    int option_index;
    SV* sv_option;
    struct poptOption_wrapper *option_wrapper;
    CODE:
    /* get the next opt in a while loop so that if it's a POPT_ARG_VAL
     * we don't return the val back to the user */
    while((rc = poptGetNextOpt(self->popt_context)) >= 0) {
        /* scoot back 1 because when we skipped 0 (because supposedly
         * it's a special val) */
        option_index = rc - 1;

        /* get the Getopt::Popt::Option out of the array, $sv_option = $options->[item] */
        sv_option = *(av_fetch(self->av_options,option_index,0));
        if(!sv_option) {
            croak("internal error: couldn't fetch option %d from options array ", 
                    option_index);
        }
        
        /* assign this option's argref, i.e.
         * $sv_option->_assign_argref() */
        PUSHMARK(SP);
        XPUSHs(sv_option); /* Getopt::Popt::Option object */
        PUTBACK;
        call_method("_assign_argref",G_DISCARD);

        /* return the user's original val */
        option_wrapper = get_option_wrapper(sv_option);
        RETVAL = option_wrapper->popt_option.val;

        /* XXX: it'd be nice if _assign_argref returned the val and if
         * we should return or continue to the next opt or not
         * (keeping in line with OOP data hiding) but I just couldn't
         * get call_method() to work with return values as advertised.
         * TODO: do it right */


        /* keep the behavior specified in the manpage: 
         * POPT_ARG_VAL causes the parsing function not to return a
         * value, since the value of val has already been used. */
        if((option_wrapper->popt_option.argInfo & POPT_ARG_MASK) == POPT_ARG_VAL) {
            /* keep eating args */
            continue;
        } else {
            /* return to the user */
            break;
        }
    } 

    if(rc < 0) 
        RETVAL = rc; /* return the -1/error code */;

    OUTPUT:
    RETVAL

=cut
void
assignOptionArgs(self)
    struct poptContext_wrapper *self 
    PREINIT:
    int item;
    SV *sv_array_elem;
    PPCODE:
    /* call the _assign_argref method on all options */
    for(item = 0; item < av_len(self->av_options)+1; item++) {
        sv_array_elem = *(av_fetch(self->av_options, item, 0));
        PUSHMARK(SP);
        XPUSHs(sv_array_elem);
        PUTBACK;
        call_method("_assign_argref",G_DISCARD);
    }
=cut

void 
resetContext(self)
    struct poptContext_wrapper *self
    PPCODE:
    poptResetContext(self->popt_context);


const char *
getOptArg(self)
    struct poptContext_wrapper *self
    CODE:
    RETVAL = poptGetOptArg(self->popt_context);
    OUTPUT:
    RETVAL

const char *
getArg(self)
    struct poptContext_wrapper *self
    CODE:
    RETVAL = poptGetArg(self->popt_context);
    OUTPUT:
    RETVAL

const char *
peekArg(self)
    struct poptContext_wrapper *self
    CODE:
    RETVAL = poptPeekArg(self->popt_context);
    OUTPUT:
    RETVAL

void
getArgs(self)
    SV* self
    PREINIT:
    /* this craziness is to avoid const warnings during compilation */
    struct poptContext_wrapper *real_self = get_context_wrapper(self);
    const char **args = poptGetArgs(real_self->popt_context);
    PPCODE:
    while(args && *args) {
        XPUSHs(sv_2mortal(newSVpv(*args, 0)));
        args++;
    }

const char *
strerror(this, error)
    SV* this
    int error
    CODE:
    RETVAL = poptStrerror(error);
    OUTPUT:
    RETVAL

const char *
badOption(self, flags=0)
    struct poptContext_wrapper *self 
    int flags
    CODE:
    RETVAL = poptBadOption(self->popt_context,flags);
    OUTPUT:
    RETVAL

int
readDefaultConfig(self, flags=0)
    struct poptContext_wrapper *self
    int flags
    CODE:
    RETVAL = poptReadDefaultConfig(self->popt_context, flags);
    OUTPUT:
    RETVAL

int
readConfigFile(self, filename)
    struct poptContext_wrapper *self 
    char* filename
    CODE:
    RETVAL = poptReadConfigFile(self->popt_context, filename);
    OUTPUT:
    RETVAL

int
addAlias(self, alias_wrapper, flags=0)
    struct poptContext_wrapper *self
    struct poptAlias_wrapper *alias_wrapper
    int flags
    CODE:
    /* push on a reference to the alias's argv array so that its
     * refcount goes up and popt can still use it even if this alias
     * object gets de-allocated */
    av_push(self->av_aliases, newRV_inc((SV *)alias_wrapper->av_argv));
    RETVAL = poptAddAlias(  self->popt_context, 
                            alias_wrapper->popt_alias, 
                            flags);
    OUTPUT:
    RETVAL

=cut

Note: will push onto the argv originally passed to Getopt::Popt::new() (does this so
that stuffed args won't get garbage collected);

XXX: allocates a _temporary_ char **argv, which may cause problems if popt's
implementation changes.

=cut

int
stuffArgs(self,...)
    struct poptContext_wrapper *self
    PREINIT:
    SV *sv_array_elem;
    char **ch_argv;
    int num_args;
    int item;
    CODE:
    /* some additional param checking that xsubpp can't do for us */
    if(items < 2) {
        croak("Usage: Getopt::Popt::stuffArgs(self, arg1, arg2, ...)");
    }
    /* iterate through the user's strings, push it onto the
     * wrapper's argv (so the element's don't get garbage collected)
     * and build up a new ch_argv to pass to poptStuffArgs() */
    num_args = items - 1; /* subtrack off the $self arg */
    New(78, ch_argv, num_args + 1, char *); /* +1 for NULL at the end */
    for(item = 0; item < num_args; item++) {
        /* fetch it */
        sv_array_elem = ST(item + 1); /* offset +1 to skip over $self */
        /* push it and increment its refcount*/
        av_push(self->av_argv, SvREFCNT_inc(sv_array_elem));
        /* store it */
        ch_argv[item] = SvPV_nolen(sv_array_elem);
    }
    /* cap it off */
    ch_argv[item] = NULL;

    /* do the call */
    RETVAL = poptStuffArgs(self->popt_context, (const char **)ch_argv);

    /* XXX: poptStuffArgs() does a poptDupArgv() of ch_argv, so we
     * should be able to safely deallocate ch_argv */
    Safefree(ch_argv);

    OUTPUT:
    RETVAL

void
setOtherOptionHelp(self, str)
    struct poptContext_wrapper *self
    char *str
    PPCODE:
    /* this function is only in the example in the manpage, not
     * actually documented anywhere */
    poptSetOtherOptionHelp(self->popt_context, str);

=cut
TODO: printHelp(), printUsage(), callbacks, parseArgvString(),
dupArgv()

=cut
