# $Id: Makefile.PL,v 1.13 2003/09/05 22:23:01 dirt Exp $
use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'              => 'Getopt::Popt',
    'VERSION_FROM'      => 'Popt.pm',
    'ABSTRACT_FROM'      => 'Popt.pm',
    ($] >= 5.005 ?      ## Add these new keywords supported since 5.005
      (#ABSTRACT         => 'A Perl interface to the popt(3) library.', 
       AUTHOR           => 'James Baker <jamesb-at-cpan-dot-org>') : ()),
    'DEFINE'            => '', 
    #'LIBS'              => ['-L/opt/lib -lpopt'],
    'LIBS'              => ['-lpopt'], 
    #'INC'               => '-I/opt/include', 
    'INC'               => '', 
    #OPTIMIZE            => '-g', 
    OPTIMIZE            => '',
    TYPEMAPS            => ['typemap'],
    PREREQ_PM           => { 'Scalar::Util' => 0, },
    'dist'              => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);
