#!/usr/bin/perl
use Cwd;

$classpath = "";
$initial_cwd = cwd();

sub global_init
{
    $| = 1;
    
    if ($ARGV[0] eq "-cp" || $ARGV[0] eq "-classpath")
    {
	shift(@ARGV);  $classpath = pop(@ARGV);
    }
}


###########################################################

# 0: nothing
# 1: warnings
# 2: info
# 3: debug
$log_level = 2;

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

1;
