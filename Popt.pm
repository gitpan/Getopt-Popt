# $Id: Popt.pm,v 1.41 2004/11/26 22:22:13 dirt Exp $
# vim: et ts=8 sts=4 sw=4 syn=perl
#
# Getopt::Popt - an interface to the popt(3) library
#
# Written and directed by: James Baker
# Staring: Perl 5
# Featuring: C and XS
# Copyright: 2004 James Baker
# License: Same as Perl's

package Getopt::Popt;
use strict;
use warnings;
use UNIVERSAL qw(isa);
use Scalar::Util qw(dualvar); # XXX: only standard in 5.8
use Carp qw(croak);
use base qw(Exporter DynaLoader);

our $VERSION = '0.02';

# 
# Setup constants
#
use constant ARGFLAG_CONSTANTS => [qw(
    POPT_ARGFLAG_AND POPT_ARGFLAG_DOC_HIDDEN POPT_ARGFLAG_LOGICALOPS
    POPT_ARGFLAG_NAND POPT_ARGFLAG_NOR POPT_ARGFLAG_NOT POPT_ARGFLAG_ONEDASH
    POPT_ARGFLAG_OPTIONAL POPT_ARGFLAG_OR POPT_ARGFLAG_STRIP POPT_ARGFLAG_XOR)];

# TODO: POPT_ARG_INCLUDE_TABLE POPT_ARG_CALLBACK 
use constant ARG_CONSTANTS => [qw(
    POPT_ARG_DOUBLE POPT_ARG_FLOAT POPT_ARG_INT POPT_ARG_INTL_DOMAIN
    POPT_ARG_LONG POPT_ARG_MASK POPT_ARG_NONE POPT_ARG_STRING
    POPT_ARG_VAL)];

use constant BADOPTION_CONSTANTS => [qw(POPT_BADOPTION_NOALIAS)];

use constant CONTEXT_CONSTANTS => [qw(
    POPT_CONTEXT_KEEP_FIRST POPT_CONTEXT_NO_EXEC POPT_CONTEXT_POSIXMEHARDER)];

use constant ERROR_CONSTANTS => [qw(
    POPT_ERROR_BADNUMBER POPT_ERROR_BADOPERATION POPT_ERROR_BADOPT
    POPT_ERROR_BADQUOTE POPT_ERROR_ERRNO POPT_ERROR_NOARG
    POPT_ERROR_OPTSTOODEEP POPT_ERROR_OVERFLOW)];

use constant AUTOHELP_CONSTANTS => [qw(POPT_AUTOHELP)];

# define a new constant that's loaded later
sub POPT_AUTOHELP { new Getopt::Popt::Option::AUTOHELP; }

our %EXPORT_TAGS = ( 
        argflag     => ARGFLAG_CONSTANTS,
        arg         => ARG_CONSTANTS,
        autohelp    => AUTOHELP_CONSTANTS,
        badoption   => BADOPTION_CONSTANTS,
        context     => CONTEXT_CONSTANTS,
        error       => ERROR_CONSTANTS,
        all         => [ 
                        @{ARGFLAG_CONSTANTS()},
                        @{ARG_CONSTANTS()},
                        @{AUTOHELP_CONSTANTS()},
                        @{BADOPTION_CONSTANTS()},
                        @{CONTEXT_CONSTANTS()},
                        @{ERROR_CONSTANTS()},
                       ], 
        );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

# Dynamically define constants as they're used. Caveat: if you don't
# want to import a symbol, you have to do Getopt::Popt->[NAME] rather than
# Getopt::Popt::[NAME]
our $AUTOLOAD;
sub AUTOLOAD () {
    # get the name of the const we're trying to load
    my ($const_name) = ($AUTOLOAD =~ /::([^\:]+$)/);
    if($const_name =~ /^constant_(.*)/) {
        # oops, we've started recursing
        die "no such constant: $1";
    } elsif($const_name !~ /^POPT_/) {
        die "no such method: $const_name";
    }

    # dispatch down to the xs function (or function alias) to get the value
    my $const_val = eval "Getopt::Popt::constant_$const_name()";
    # propagate any errors
    die $@ if $@;
    # create the constant so we don't have to AUTOLOAD it next time
    {
        no strict 'refs';
        *$AUTOLOAD = sub { $const_val }
    }
    return $const_val;
}

# get the party started
bootstrap Getopt::Popt $VERSION;

# create an alias
*{getContext} = *new;

# new() just performs parameter validation and munges the options into
# a hash and passes it off to the real constructor in the XS.
# XXX: wouldn't it be nice if Params::Validate were part of core?
sub new {
    my $class = shift;
    my %params = @_;

    # parameter validation
    die "argv is not an arrayref" unless ref($params{argv}) eq "ARRAY";
    die "options is not an arrayref" unless ref($params{options}) eq "ARRAY";
    die "empty options list" unless @{$params{options}};

    # prepend $0 in argv unless told not to
    # also create a new array so we can make changes to this one
    if(!$params{dont_prepend_progname}) {
        $params{argv} = [$0,@{$params{argv}}];
    } else {
        $params{argv} = [@{$params{argv}}];
    }

    die "empty argv" unless @{$params{argv}};
    
    # surpress warnings
    defined($params{name}) || ($params{name} = "");
    defined($params{flags}) || ($params{flags} = 0);

    # munge all of the options into Getopt::Popt::Option values 
    my @options_array;
    foreach my $option(@{$params{options}}) {
        my $option_obj;

        # make sure $option is a Getopt::Popt::Option
        if(isa($option,"Getopt::Popt::Option")) {
            $option_obj = $option;
        } elsif(ref($option) eq "HASH") {
            # do a perly TMTOWTDI auto-instantition of Getopt::Popt::Option if
            # given a hashref
            $option_obj = new Getopt::Popt::Option(%{$option});
        } else {
            die "bad argument: option $params{option} is neither a Getopt::Popt::Option nor a hashref";
        }

        # store it
        push @options_array,$option_obj;
    }

    # dispatch to the real XS constructor
    return $class->_new_blessed_poptContext($params{name},
                                            $params{argv},
                                            \@options_array, 
                                            $params{flags});
}

# I feel like apologizing for this. But I won't. muuuaahAHA HAH HAH!
sub getNextOptChar {
    my $this = shift;

    # get the int flavor
    my $rc = $this->getNextOpt(); # xs method call

    # end of stuff?
    if($rc == -1) {
        return undef;
    }

    # throw an error
    if($rc < 0) {
        # out with a pretty error message
        croak($this->badOption() . ": " . $this->strerror($rc));
    }

    # super perl magic hackery
    return dualvar(int($rc), chr($rc));
}


package Getopt::Popt::Alias;
use strict;

# new() just does parameter validation and hands everything down to
# the real XS constructor.
sub new {
    my $class = shift;
    my %params = @_;

    unless((defined($params{longName}) && $params{longName} ne "") || 
           (defined($params{shortName}) && $params{shortName} ne "")) 
    {
        die "need a longName or shortName" ;
    }
    if(defined($params{shortName}) && length($params{shortName}) > 1) {
        die "shortName must be a single character";
    }
    if(!defined($params{argv}) || ref($params{argv}) ne "ARRAY" || 
            scalar(@{$params{argv}}) == 0) 
    {
        die "argv must be a non-empty arrayref";
    }

    {
        # turn off warnings because we know we won't care about undef
        no warnings "uninitialized"; 

        return $class->_new_blessed_poptAlias(@params{qw(longName
                                                         shortName
                                                         argv)});
    }
}

package Getopt::Popt::Option;
use strict;
use POSIX qw(strtod);
# TODO: POPT_ARG_INCLUDE_TABLE and misc. help stuff

# new() just does parameter validation and hands everything down to
# the real XS constructor.
sub new {
    my $class = shift;
    my %params = @_;

    # nb: all this __PACKAGE__ business is here because it's possible this
    # class was automatically created in Getopt::Popt::new() and the user could get
    # confused as to what's dying
    unless((defined($params{longName}) && $params{longName} ne "") || 
           (defined($params{shortName}) && $params{shortName} ne "")) 
    {
        die __PACKAGE__ . "::new(): need a longName or shortName" ;
    }

    if(defined($params{shortName}) && length($params{shortName}) > 1) {
        die __PACKAGE__ . "::new(): shortName must be a single character";
    }

    unless(defined($params{argInfo})) {
        die __PACKAGE__ . "::new(): argInfo not given";
    }

    if(defined($params{arg}) && ref($params{arg}) ne "SCALAR") {
        die __PACKAGE__ . "::new(): arg is not a scalar reference";
    }


    if(defined($params{val})) {

        # determine if val is an integer or a character
        if(length($params{val}) == 1) {
            # ok it's a char, convert it to an int
            $params{val} = ord($params{val});
        } else {
            # probably an int, but make sure
            if(is_numeric($params{val})) {
                # cast off the floatness if there was any
                $params{val} = int($params{val});

                # If $val is negative the current behavior is to
                # return it without setting the option's \$arg
                # (because it should be an error condition). But
                # there's nothing stopping the caller from being
                # weird.
                if(($params{val} < 0) && defined($params{arg})) {
                    # winner of this year's Overly Verbose Error Message
                    die __PACKAGE__ . "::new(): val $params{val} is " .
                                        "negative, which looks like an " .
                                        "error code, so arg " .  
                                        $params{arg} . "won't get set by perl";
                }

            } else {
                die "val '$params{val}' isn't a single character and isn't numeric";
            }
        }
    } else {
        # set it to a safe default
        $params{val} = 0;
    }

#    # see if we should do a conversion
#    if(defined($params{valChar})) {
#        # only one type of char allowed
#        if(defined($params{val})) {
#            die "val and valChar both defined (val=$params{val}, valChar='$params{valChar}')"; 
#        }
#        if(length($params{valChar}) > 1) {
#            die "valChar is more than one character: \"$params{valChar}\"";
#        }
#        $params{val} = ord($params{valChar});
#    }
#    # integer form of val
#    elsif(defined($params{val})) {
#        # If $val is negative the current behavior is to return it
#        # without setting the option's \$arg (because it should be an
#        # error condition). But there's nothing stopping the caller
#        # from being weird.
#        if(($params{val} < 0) && defined($params{arg})) {
#            # winner of this year's Overly Verbose Error Message
#            die __PACKAGE__ . "::new(): val $params{val} is negative, " .
#                                "which looks like an error code, so arg " .
#                                $params{arg} . "won't get set by perl";
#        }
#    } else {
#        # default it 
#        $params{val} = 0;
#    }

    {
        # turn off warnings because we know we won't care about undef
        # args at this point
        no warnings "uninitialized"; 

        # create the raw struct (with a new arg malloc()d arg)
        return $class->_new_blessed_poptOption(@params{qw(  
                                                        longName 
                                                        shortName 
                                                        argInfo 
                                                        arg
                                                        val 
                                                        descrip
                                                        argDescrip
                                                    )})
    }

}

# borrowed from perlfaq4:
sub is_numeric {
    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    $! = 0;
    my($num, $unparsed) = strtod($str);
    if (($str eq '') || ($unparsed != 0) || $!) {
        return 0;
    } else {
        return 1;
    }
}


sub test_assign_arg {
    my $this = shift;
    my $val = shift;
    $this->_test_assign_arg($val);
    $this->_assign_argref();
}

package Getopt::Popt::Option::AUTOHELP;
use base qw(Getopt::Popt::Option);

my $SINGLETON;

# reserved type of option, shouldn't contain any arguments
# just returns the singleton
sub new {
    my $class = shift;

    if(@_) {
        die __PACKAGE__ . "::new() takes no arguments";
    }

    return defined($SINGLETON) ? $SINGLETON :
        ($SINGLETON = $class->_new_blessed_poptOption_AUTOHELP());
}

sub test_assign_arg {
    die "AUTOHELP doesn't like you";
}

# vim: ts=4 sw=4 et
1;

__END__

=head1 NAME

Getopt::Popt - Perl interface to the popt(3) library

=head1 SYNOPSIS

    use Getopt::Popt qw(:all);
    
    # setup the options array
    push @options,new Getopt::Popt::Option( 
                                    longName    => "long", 
                                    shortName   => "l",
                                    argInfo     => POPT_ARG_STRING,
                                    arg         => \$qux,
                                    val         => $val);

    # or, if you're lazy, have Getopt::Popt automagically do the new()
    push @options, { shortName => 's', 
                     argInfo => POPT_ARG_NONE, 
                     arg => \$quux,
                     val => 's' 
                   };

    # "val"s can be a single character or an integer:
    push @options, { longName => 'xor',
                     argInfo => POPT_ARG_VAL | POPT_ARGFLAG_XOR,
                     arg => \$quuux,
                     val => 0xbadf00d   # integer
                   },

Enable automatic help/usage messages (--help or --usage):

    push @options, POPT_AUTOHELP;

Create a new popt context:

    $popt = new Getopt::Popt(name       => $alias_name, 
                             argv       => \@ARGV,
                             options    => \@options, 
                             flags      => $flags);

Setup option aliases:

    # load some aliases
    $popt->readDefaultConfig();
    $popt->readConfigFile("/path/to/aliases");
    
    # add your own alias
    $alias = new Getopt::Popt::Alias(longName => "taco", 
                             argv     => [qw(--flavored --kisses)]);
    $popt->addAlias($alias, $alias_flags);

Load options as you would in C:

    # loop through the options, using the popt C way:
    while(($rc = $popt->getNextOpt()) > 0) {
        ...
        # one way to get the arg val
        $bork = $popt->getOptArg();
        ...
        # stuff some args 
        $popt->stuffArgs(qw(-q -u -x));
        ...
        # start over
        $popt->resetContext();
        ...
    }

And handle errors as you would in C:

    $errstr = $popt->strerror($rc);
    $badopt = $popt->badOption($rc,$badopt_flags);

I<Or> try the new perly way:

    eval {
        while(defined($val = $popt->getNextOptChar())) { 
                                              ^^^^-- note!
            # $val is a Scalar::Util::dualvar:
            if($val eq "c") {               # <- character
                ...
            } elsif($val == 0xbeef) {       # <- integer
                ...
            } elsif(ord($val) == 2922) {    # <- utf8, ok!
                ...
            }
            ...
            # you can still stuff args or reset the context as before
            ...
        }
    };
    # check for errors:
    if($@) {
        # prints something like "bad argument: --shoes: unknown option"
        print "bad argument: $@\n"; 
    }

Get leftover args:

    $arg = $popt->peekArg();
    $arg = $popt->getArg();
    @args = $popt->getArgs();


=head1 DESCRIPTION

This module provides an interface to (most of) the functions available
in the popt library. See the popt(3) manpage for more details about
what the popt library can do.

=head1 METHODS

C<Getopt::Popt> should look like a fairly natural object oriented mapping to all of the popt functions.

=head2 Getopt::Popt

=over 4

=item C<Getopt::Popt-E<gt>new( %params )>

Create a new Getopt::Popt context. Parameters map to the arguments to popt's
C<poptGetContext()>, plus one additional argument:

    %params = (
            alias_name  => $name,
            argv        => \@argv,
            options     => \@options,
            flags       => $flags,

            # new and special: 
            dont_prepend_progname => $bool, 
            );

Dies on an error.

=over 4

=item C<$alias_name >

Name for lookup in alias definitions (see the popt(3) manpage). Can be
empty.

=item C<\@argv>

Command line arguments, e.g. C<\@ARGV>. B<NOTE>: 
C<\@argv> will be passed to popt as the array C<($0, @argv)> (a copy is made so
that your C<\@argv> won't be modified) unless given the
C<dont_prepend_progname> option (see below).

=item C<$flags>

Context flags (see CONSTANTS). Defaults to 0.

=item C<\@options>

Options array. All elements must be either a Getopt::Popt::Option or a
hashref; hashrefs will be automagically converted into Getopt::Popt::Options.

=item C<$dont_prepend_progname>

Don't stick C<$0> before C<@argv>. Perl's C<@ARGV> just has arguments
and does not include the current process name, but popt expects
something in C<argv[0]>. So C<$0> is prepended unless this flag has
been set. 
It's an error if C<dont_prepend_progname> is true but C<@argv> is
empty. 

Defaults to 0.

=back

=item C<Getopt::Popt::getNextOptChar()>

This is a wrapper around C<Getopt::Popt::getNextOpt()>. Returns a C<dualvar>
(see L<Scalar::Util>) rather than just an integer. In a numeric
context (C<"0+$ch"> or C<"$ch == $number">) the return value is the
integer value that C<Getopt::Popt::getNextOpt()> would've returned, and in a
string context the return value is a character. Really all it saves
you is having to use C<chr()> all the time.

Returns undef when it's done reading args, dies with a
C<Getopt::Popt::strerror()>'d message on an error. 

=back

See the popt(3) manpage for details on these methods:

=over 4

=item C<Getopt::Popt::resetContext()>

=item C<Getopt::Popt::getNextOpt()>

=item C<Getopt::Popt::getOptArg()>

=item C<Getopt::Popt::getArg()>

=item C<Getopt::Popt::peekArg()>

=item C<Getopt::Popt::getArgs()>

=item C<Getopt::Popt::strerror($error)>

=item C<Getopt::Popt::badOption($flags)>

=item C<Getopt::Popt::readDefaultConfig()>

=item C<Getopt::Popt::readConfigFile()>

=item C<Getopt::Popt::addAlias($alias, $flags)>

=item C<Getopt::Popt::setOtherOptionHelp($str)>

=item C<Getopt::Popt::stuffArgs(@args)>

=back

=head2 Getopt::Popt::Option

=head3 SYNOPSIS

Represents a C<struct poptOption>

=over 4

=item C<Getopt::Popt::Option-E<gt>new( %params )>

Create a new option. C<%params> maps to popt's C<struct poptOption>:

    %params = (
            longName    => $longName,
            shortName   => $shortName,  # single char
            argInfo     => $argInfo,    # see CONSTANTS below
            arg         => \$arg,       # depends on $argInfo
            val         => $val,        # integer OR single character
            descrip     => $descrip,
            argDescrip  => $argDescrip,
            );

Dies on an error.

=over 4

=item C<$longName>

Long name of the argument, e.g. C<"--foo">'s long name is C<"foo">.

=item C<$shortName>

Short name of the argument, e.g. C<"-f">'s short name is C<"f">. Must
be a single character.

=item C<$argInfo>

An integer, bitwise-ORed with different flags (see CONSTANTS below).

=item C<\$arg>

A scalar reference, with the scalar being set to the option argument value.

=item C<$val>

The value to be returned by C<getNextOpt()> (or C<getNextOptChar()>).
Can be a single character or an integer.  

Note that if you want C<$val> to be a real single-digit
integer (and not the character representation of it), pass it in as
"C<+1>" or "C<1.0>", or as "C<\1>". If you use any of the bit
operations (C<POPT_ARGFLAG_[AND|OR|XOR]>) that popt has, it's important
that "1" be a 1 and not C<ord("1")> = 49. Otherwise you probably don't care.

=item C<$descrip>

Long description of the option, used in generating autohelp.

=item C<$argDescrip>

Short description of the argument to the option, used in generating autohelp.

=back

=back

Value getters (no setters):

=over 4

=item C<Getopt::Popt::Option::getLongName()>

=item C<Getopt::Popt::Option::getShortName()>

=item C<Getopt::Popt::Option::getArgInfo()>

=item C<Getopt::Popt::Option::getArg()>

=item C<Getopt::Popt::Option::getVal()>

=item C<Getopt::Popt::Option::getDescrip()>

=item C<Getopt::Popt::Option::getArgDescrip()>

=back

=head2 Getopt::Popt::Alias

=over 4

=head3 SYNOPSIS

Represents a C<struct poptAlias>

=item C<Getopt::Popt::Alias-E<gt>new( %params )>

Create a new alias to pass to C<Getopt::Popt::addAlias()>. C<%params> maps to popt's C<struct poptAlias>:

    %params = (
            longName    => $longName,
            shortName   => $shortName,  # single char
            argv        => \@args,      # non-empty array of args
            );

Dies on an error.

=back

=head1 CONSTANTS

Most of the constant integers defined in C<popt.h> (except for a few
relating to callbacks and table inclusion, see TODO below) are
available for import via the C<:all> tag. Other tags are: 
C<:argflag> for argument flags, C<:arg> for argument types, C<:autohelp>
for C<POPT_AUTOHELP>, C<:badoption> for C<POPT_BADOPTION_NOALIAS>,
C<:context> for context flags, and C<:error> for error values.

You can use the the C<POPT_AUTOHELP> constant just as you would in C. Just put
it on your C<\@options> and autohelp will be enabled.  

=head1 EXAMPLES

The following is a perl implementation of the example given in the popt(3) manpage.

    #!/usr/bin/perl
    use Getopt::Popt qw(:all);
    use strict;

    main();

    sub usage {
      my $popt = shift;
      my $exitcode = shift;
      my $error = shift;
      my $addl = shift;
      # not implemented:
      # $popt->printUsage(\*STDERR, 0); 
      print STDERR "do --help to show options\n";
      print STDERR "$error $addl\n" if $error;
      exit($exitcode);
    }

    sub main {
      my $c;        # used for argument parsing
      my $portname;
      my $speed;    # used in argument parsing to set speed
      my $raw;      # raw mode?
      my @buf;
      my $popt;

      my @optionsTable = (
          {
            longName => "bps", 
            shortName => 'b', 
            argInfo => POPT_ARG_INT, 
            arg => \$speed, 
            val => 0,
            descrip => "signaling rate in bits-per-second", 
            argDescrip => "BPS" 
          },
          {
            longName => "crnl",
            shortName => 'c',
            argInfo => 0,
            val => 'c',
            descrip => "expand cr characters to cr/lf sequences" 
          },
          {  
            longName => "hwflow",
            shortName => 'h',
            argInfo => 0,
            val => 'h',
            descrip => "use hardware (RTS/CTS) flow control" 
          },
          { 
            longName => "noflow",
            shortName => 'n',
            argInfo => 0,
            val => 'n',
            descrip => "use no flow control" 
          },
          {  
            longName => "raw",
            shortName => 'r',
            argInfo => 0,
            arg => \$raw,
            descrip => "don't perform any character conversions" 
          },
          { 
            longName => "swflow",
            shortName => 's',
            argInfo => 0,
            val => 's',
            descrip => "use software (XON/XOF) flow control" 
          } ,
          POPT_AUTOHELP,
      );

      $popt = new Getopt::Popt(argv => \@ARGV,options => \@optionsTable);
      $popt->setOtherOptionHelp("[OPTIONS]* <port>");

      if (@ARGV < 1) {
        # not implemented
        #$popt->printUsage(optCon, stderr, 0);
        print STDERR "not enough arguments: do --help to show options\n";
        exit(1);
      }

      # Now do options processing, get portname
      eval {
        while (defined($c = $popt->getNextOptChar())) {
          push(@buf,'c') if $c eq 'c';
          push(@buf,'h') if $c eq 'h';
          push(@buf,'s') if $c eq 's';
          push(@buf,'n') if $c eq 'n';
        }
      };

      if ($@) {
        # an error occurred during option processing
        my($msg) = ($@ =~ m/(.*) at [\S]+ line \d+\s*$/);
        printf(STDERR  "bad argument: $msg\n");
        exit 1;
      }

      $portname = $popt->getArg();
      if(($portname eq "") || !($popt->peekArg() eq "")) {
        usage($popt, 1, "Specify a single port", ".e.g., /dev/cua0");
      }


      # Print out options, portname chosen
      print("Options  chosen: ");
      print("-$_ ") foreach @buf;
      print("-r ") if(defined($raw));
      print("-b $speed") if(defined($speed));
      print("\nPortname chosen: $portname\n");

      exit(0);
    }

=head1 BUGS

This module should be considered beta quality. Don't use it where a
possible buffer overflow or double-free or something would be a bad
thing. Comments and bug fixes are greatly appreciated!

C<POPT_ARG_VAL> is converted internally to C<POPT_ARG_NONE> (but don't
worry, it still sets C<\$arg> to C<$val>). As a
consequence, the behavior may be slightly different.

If you're using C<POPT_AUTOHELP> and the user gives C<--help> or
C<--usage>, popt exits and any exit handlers, destructors, etc. won't
be called. This is expected to be fixed once printHelp() and
printUsage() get implemented (see TODO below).

Tested with popt-1.6 and popt-1.7 on Debian woody i386, and on slack 9
with popt-1.7, YMMV.

=head1 TODO

Finish writing this documentation.

Need to implement: C<printHelp()>, C<printUsage()>, callbacks,
C<parseArgvString()>, and C<dupArgv()>

Probably won't implement: table inclusion (because it's easier to just
pass around perl arrays of options);

=head1 SEE ALSO

popt(3), L<Getopt::Std>, L<Getopt::Long>, and everything in 
L<http://search.cpan.org/modlist/Option_Parameter_Config_Processing>

The latest version of the popt library is distributed with
rpm and is always available from: L<ftp://ftp.rpm.org/pub/rpm/dist>.

=head1 AUTHORS

This module is by James Baker <jamesb-at-cpan-dot-org>.

The popt library is by Erik W. Troan <ewt-at-redhat-dot-com>.

=head1 COPYRIGHT AND DISCLAIMER

This program is Copyright 2003 by James Baker. This program is free
software; you can redistribute it and/or modify it under the terms of
the Perl Artistic License or the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

If you do not have a copy of the GNU General Public License write to
the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139,
USA.

=cut
