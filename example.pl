#!/usr/bin/perl
#
# Perl implementation of the example listed in the popt(3) manpage.
# 
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

  $popt = new Getopt::Popt(argv => \@ARGV, options => \@optionsTable);
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
