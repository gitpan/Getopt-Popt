# $Id: 05-option.t,v 1.3 2003/09/05 22:15:12 dirt Exp $
# vim: syn=perl ts=8 sw=4 sts=4 et
use Test;
BEGIN { plan tests => 10 };
use Getopt::Popt qw(:all);
use strict;

# test Getopt::Popt::Option->new() with missing arg
my $option;
eval {
    $option = new Getopt::Popt::Option( longName => "bad", argInfo => POPT_ARG_STRING );
};
ok($@ =~ /arg was undef, but argInfo was not POPT_ARG_NONE/);

# test Getopt::Popt::Option->new() with bad argInfo
my $qux;
eval {
    $option = new Getopt::Popt::Option( 
                                longName => "bad", 
                                argInfo => 47, 
                                arg => \$qux );
};
ok($@ =~ /unknown argInfo value 47/);

# test Getopt::Popt::Option->new() with bad val and arg
eval {
    $option = new Getopt::Popt::Option( 
                                longName => "bad", 
                                argInfo => POPT_ARG_STRING, 
                                arg => \$qux, 
                                val => -5 );
};
ok($@ =~ /is negative/);

# test Getopt::Popt::Option->new()
$option = new Getopt::Popt::Option(     
                                longName    => "qux", 
                                shortName   => "q",
                                argInfo     => POPT_ARG_STRING,
                                arg         => \$qux,
                                val         => 23,
                                descrip     => "descrip");

# test Getopt::Popt::Option->test_assign_arg()
$option->test_assign_arg("testval");
ok($qux,"testval");

# test Getopt::Popt::Option getters
ok("" . $option->getShortName(),"q");
ok("" . $option->getLongName(),"qux");
ok("" . $option->getVal(),23);
ok("" . $option->getArg(),\$qux);
ok("" . $option->getDescrip(),"descrip");

# test static methods
eval {
    Getopt::Popt::Option->getShortName();
};
ok($@ =~ /Not a reference to/);

