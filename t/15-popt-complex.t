# $Id: 15-popt-complex.t,v 1.2 2003/09/05 22:15:12 dirt Exp $
# vim: syn=perl ts=8 sw=4 sts=4 et
use Getopt::Popt qw(:all);
use strict;
use Test;
BEGIN { plan tests => 48 };
my $qux;
my $rc;
my $option = new Getopt::Popt::Option(  
                                longName    => "qux", 
                                shortName   => "q",
                                argInfo     => POPT_ARG_STRING,
                                arg         => \$qux,
                                val         => 23,
                                descrip     => "qux descrip");
# test POPT_ARG_VAL
my $val_set;
my $popt = new Getopt::Popt(
                    name       => "",
                    argv       => [qw(-v --hurk)],
                    options    => [
                                  {   
                                   longName    => "valor",
                                   shortName   => "v",
                                   argInfo     => POPT_ARG_VAL, 
                                   arg         => \$val_set,
                                   val         => 22,
                                  },
                                  ],
                   );
ok($popt->getNextOpt(),POPT_ERROR_BADOPT); # '--hurk'
ok($val_set,22);

# test bitwise operations
my ($xor,$and,$or,$valor) = (1234,1,1,1);
$popt = new Getopt::Popt(
                name       => "",
                argv       => [qw(--xor=1234 --and=1 --or=2 --valor)],
                options    => [
                               {   
                                longName    => "xor",
                                argInfo     => POPT_ARG_INT | POPT_ARGFLAG_XOR,
                                arg         => \$xor,
                                #val         => val,
                               },
                               {   
                                longName    => "and",
                                argInfo     => POPT_ARG_INT | POPT_ARGFLAG_AND,
                                arg         => \$and,
                                #val         => val,
                               },
                               {   
                                longName    => "or",
                                argInfo     => POPT_ARG_INT | POPT_ARGFLAG_OR,
                                arg         => \$or,
                                #val         => val,
                               },
                               {   
                                longName    => "valor",
                                argInfo     => POPT_ARG_VAL | POPT_ARGFLAG_OR, 
                                arg         => \$valor,
                                val         => '+2',
                               },
                               ],
                );
ok($popt->getNextOpt() >= 0);  
ok($xor,0); # xor with itself should be 0
ok($popt->getNextOpt() >= 0);  
ok($and,1); # 1 & 1 = 1
ok($popt->getNextOpt() >= 0);  
ok($or,3); # 1 | 2 = 3
ok($popt->getNextOpt(), -1);  
ok($valor,3); # 1 | 2 = 3

# test passing POPT_ARG_STRING with no arg
eval {
    $popt = new Getopt::Popt(
                    name   => "",
                    argv   => ["--die=segfault"],
                    options=> [{   longName    => "die",
                                    argInfo     => POPT_ARG_STRING,
                                    val         => 22,
                                }],
                     flags  => 0);
};
ok($@ =~ /argInfo was not POPT_ARG_/);

# TODO: make a note that --help exists so perl (probably?) won't clean up
# test Getopt::Popt->new() (with AUTOHELP)
my $pid = open(AUTOHELP_TEST,"-|");
die "couldn't fork: $!" unless defined $pid;
if($pid) {
    # parent: search for the arg description
    my @help = <AUTOHELP_TEST>;
    #print "got: @help\n";
    my $descrip = "qux descrip";
    ok(grep /$descrip/o,@help);

} 
# child: should just print out help and exit
else {
    close(STDERR) || die "couldn't close stderr: $!";
    open(STDERR,">&STDIN") || die "couldn't dup stderr: $!";
    $popt = new Getopt::Popt(
                    name => "",
                    argv => ["--help"],
                    options => [$option,POPT_AUTOHELP],
                    flags => 0);
    $rc = $popt->getNextOpt();
    $rc = $popt->getNextOpt();
    die "shouldn't have gotten here";
}

# test Getopt::Popt->getOptArg()
$popt = new Getopt::Popt(name => "",argv => ["--qux=testval"], options => [$option]);
ok($popt->getNextOpt(),23);
ok($popt->getOptArg(),"testval");

# test Getopt::Popt->getArgs()
$popt = new Getopt::Popt(name => "",argv => ["testval"],options => [$option], flags => 0);
ok($popt->getNextOpt(),-1);
my $arg = $popt->peekArg();
ok($arg,"testval");
my @args = $popt->getArgs();
ok(@args == 1);
ok($args[0] eq "testval");
ok($popt->getNextOpt(),-1);

$popt = new Getopt::Popt(name => "",argv => [],options => [$option], flags => 0);
$popt->getNextOpt();
ok(!defined($popt->peekArg()));
ok(!defined($popt->getArg()));
ok(!defined($popt->getArgs()));

# test Getopt::Popt::strerror()
ok($popt->strerror(POPT_ERROR_BADNUMBER),"invalid numeric value");

# test character val stuff
$popt = new Getopt::Popt(   name => "",
                    argv =>[qw(-a -b -c --hurk)], 
                    options => [
                        {   shortName => 'a', 
                            argInfo => POPT_ARG_NONE, 
                            val => 'a',
                        },
                        {   shortName => 'b', 
                            argInfo => POPT_ARG_NONE, 
                            val => 'b',
                        },
                        {   shortName => 'c', 
                            argInfo => POPT_ARG_NONE, 
                            val => 1101,
                        },
                    ],
                );
my $char = $popt->getNextOptChar();
ok($char,"a");
ok(int($char),ord("a"));
ok($popt->getNextOptChar(),"b");
$char = $popt->getNextOptChar();
ok($char == 1101);
eval { $popt->getNextOptChar() };
ok($@ =~ /--hurk/);
ok(!defined($popt->getNextOptChar()));

# test super-long args
my $long_arg = "long_arg"x5000;
my $long_val = "long_val"x5000;
$popt = new Getopt::Popt(name => "",
                 argv => ["--$long_arg=$long_val"],
                 options =>[{   longName    => $long_arg,
                                shortName   => "",
                                argInfo     => POPT_ARG_STRING,
                                arg         => \$qux,
                                val         => 23,
                                descrip     => "descrip",
                                argDescrip  => "",
                        }],
                flags => 0);
ok($popt->getNextOpt(),23);
ok($qux eq $long_val);
ok($popt->getOptArg(),$long_val);

# test aliases
my $h_val = 33;
my $u_val = 58;
my $flavored_val = 29;
my $kisses_val = 97;
$popt = new Getopt::Popt(name => "alias-test",
                 argv => ["alias-test","--hurk","--taco"],
                 options => [
                        {   shortName => 'h',
                            argInfo => POPT_ARG_NONE,
                            val => $h_val,
                            descrip => "h",
                        },
                        {   shortName => 'u',
                            argInfo => POPT_ARG_NONE,
                            val => $u_val,
                        },
                        {
                            longName => "flavored",
                            argInfo => POPT_ARG_NONE,
                            val => $flavored_val,
                        },
                        {
                            longName => "kisses",
                            argInfo => POPT_ARG_NONE,
                            val => $kisses_val,
                        },
                        ]);
# --hurk gets aliased to -h -u in test-aliases
ok($popt->readConfigFile("./test-aliases") == 0);
ok($popt->getNextOpt(),$h_val);
ok($popt->getNextOpt(),$u_val);
# create the alias for --taco
my $alias = new Getopt::Popt::Alias(longName => "taco",argv => [qw(--flavored --kisses)]);
$popt->addAlias($alias,0);
undef($alias);
ok($popt->getNextOpt(),$flavored_val);
ok($popt->getNextOpt(),$kisses_val);
ok($popt->getNextOpt(),-1);

# test Getopt::Popt->badOption()
$popt = new Getopt::Popt(name => "", argv => ["--badarg"], options => [POPT_AUTOHELP]);
ok($popt->getNextOpt(),POPT_ERROR_BADOPT);
ok($popt->badOption(POPT_BADOPTION_NOALIAS),"--badarg");
ok($popt->getNextOpt(),-1);

# test Getopt::Popt->stuffArgs()
my $norp_val = 29;
my $stuffed_val = 37;
my $burrito_val = 73;
$popt = new Getopt::Popt(name =>"",
                 argv => ["--norp"],
                 options => [{  longName    => "norp", 
                                argInfo     => POPT_ARG_NONE, 
                                val         => $norp_val,
                                },
                               {longName    => "stuffed",
                                argInfo     => POPT_ARG_NONE, 
                                val         => $stuffed_val,
                                },
                               {longName    => "burrito",
                                argInfo     => POPT_ARG_NONE,
                                val         => $burrito_val,
                               }]);
ok($popt->getNextOpt(),$norp_val);
ok($popt->getNextOpt(),-1);
ok($popt->stuffArgs(qw(--stuffed --burrito)) == 0);
ok($popt->getNextOpt(),$stuffed_val);
ok($popt->getNextOpt(),$burrito_val);
ok($popt->getNextOpt(),-1);

# test Getopt::Popt->stuffArgs() with no args
eval {
    ok($popt->stuffArgs() < 0);
};
ok($@ =~ /Usage: /);


