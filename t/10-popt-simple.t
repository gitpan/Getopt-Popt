# $Id: 10-popt-simple.t,v 1.2 2003/09/05 22:15:12 dirt Exp $
# vim: syn=perl ts=8 sw=4 sts=4 et
use Test;
BEGIN { plan tests => 16 };
use Getopt::Popt qw(:all);
use strict;
my $qux = "";
my $option = new Getopt::Popt::Option(  
                                longName    => "qux", 
                                shortName   => "q",
                                argInfo     => POPT_ARG_STRING,
                                arg         => \$qux,
                                val         => 23,
                                descrip     => "descrip");
my $popt;
my $rc;
# test Getopt::Popt->new() with an empty argv
eval {
    $popt = new Getopt::Popt(name => "",
                     argv => [],
                     options => [$option], 
                     dont_prepend_progname => 1);
};
ok($@ =~ /empty argv/);

# test Getopt::Popt->new() with an empty option list
eval {
    $popt = new Getopt::Popt(name => "",argv => ["--qux=testval"],options => [], flags => 0);
};
ok($@ =~ /empty options list/);

# test Getopt::Popt->new() (using longName)
$popt = new Getopt::Popt(name => "",argv => ["--qux=testval"],options => [$option], flags => 0);

# test autoloader
eval {
    $popt->_qux_qux_notreal();
};
ok($@ =~ /no such method/);

# test static methods
eval {
    Getopt::Popt->getNextOpt();
};
ok($@ =~ /Not a reference to/);


# test Getopt::Popt->getNextOpt()
$popt = new Getopt::Popt(name => "",argv => ["--qux=testval"],options => [$option], flags => 0);
ok($option->getArgInfo(),POPT_ARG_STRING);
ok($popt->getNextOpt(),23);
ok($qux,"testval");

# test Getopt::Popt->DESTROY()
undef($popt);

# test Getopt::Popt->new() (using shortName)
$popt = new Getopt::Popt(name => "",argv => ["--qux=testval"],options => [$option], flags => 0);
$qux = "";
ok($popt->getNextOpt(),23);
ok($popt->getNextOpt(),-1);
ok($qux,"testval");

# test Getopt::Popt->resetContext()
$popt->resetContext();
$qux = "";
ok($popt->getNextOpt(),23);
ok($popt->getNextOpt(),-1);
ok($qux,"testval");

# test implicit Getopt::Popt::Option creation
$popt = new Getopt::Popt(
                name       => "",
                argv       => ["--qux=testval"],
                options    => [{    longName    => "qux",
                                    shortName   => "q",
                                    argInfo     => POPT_ARG_STRING,
                                    arg         => \$qux,
                                    val         => 23,
                                    descrip     => "descrip",
                                    argDescrip  => "",
                               }],
                flags => 0);
ok($popt->getNextOpt(),23);
ok($popt->getNextOpt(),-1);
ok($qux,"testval");
