# $Id: 00-constants.t,v 1.2 2003/09/05 22:15:12 dirt Exp $
# vim: syn=perl ts=8 sw=4 sts=4 et
use Getopt::Popt qw(:all);
use strict;
use Test;
BEGIN { plan tests => 19 };

# test constants: borrowed from popt.h,the constants will
# probably have to change if the header ever changes!
# use xor because of signed/unsigned issues

ok(POPT_ARG_NONE,0);
ok(POPT_ARG_STRING,1);
ok(POPT_ARG_INT,2);
ok(POPT_ARG_LONG,3);
#ok(POPT_ARG_INCLUDE_TABLE,4);
#ok(POPT_ARG_CALLBACK,5);
ok(POPT_ARG_INTL_DOMAIN,6);
ok(POPT_ARG_VAL,7);
ok((int(POPT_ARG_MASK) ^ 0x0000FFFF) == 0);
ok((int(POPT_ARGFLAG_ONEDASH) ^ 0x80000000 ) == 0);
ok((int(POPT_ARGFLAG_DOC_HIDDEN) ^ 0x40000000 ) == 0);
ok((int(POPT_ARGFLAG_STRIP) ^ 0x20000000 ) == 0);
ok((int(POPT_ARGFLAG_LOGICALOPS) ^
            (POPT_ARGFLAG_OR|POPT_ARGFLAG_AND|POPT_ARGFLAG_XOR)) == 0);
ok(POPT_ERROR_NOARG,-10);
ok(POPT_ERROR_BADOPT,-11);
ok(POPT_ERROR_OPTSTOODEEP,-13);
ok(POPT_ERROR_BADQUOTE,-15);
ok(POPT_ERROR_ERRNO,-16);
ok(POPT_ERROR_BADNUMBER,-17);
ok(POPT_ERROR_OVERFLOW,-18);
ok(POPT_BADOPTION_NOALIAS,(1 << 0));
