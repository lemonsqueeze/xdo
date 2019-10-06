#!/usr/bin/perl
use strict;
#use warnings;
use Cwd;

our $classpath = "";
our $initial_cwd = cwd();

sub global_init
{
    $| = 1;
    
    if (@ARGV &&
	($ARGV[0] eq "-cp" || $ARGV[0] eq "-classpath"))
    {
	shift(@ARGV);  $classpath = pop(@ARGV);
    }
}


###########################################################

# 0: nothing
# 1: warnings
# 2: info
# 3: debug
our $log_level = 2;

sub log_warn
{
    if ($log_level >= 1)  {  printf(@_);  }
}

sub log_info
{
    if ($log_level >= 2)  {  printf(@_);  }
}

sub log_debug
{
    if ($log_level >= 3)  {  printf(@_);  }    
}


###########################################################
# Exception handling
# http://c2.com/cgi/wiki?ExceptionHandlingInPerl

sub try(&) { eval {$_[0]->()} }
sub throw($) { die $_[0] }
sub catch(&) { $_[0]->($@) if $@ }

# Example:
#    try {
#        throw "stuff";
#    };
#    catch {
#        print $@;
#    };


1;
