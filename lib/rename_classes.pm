#!/usr/bin/perl
use strict;
#use warnings;
use File::Path qw(make_path);
use File::Basename;

use common;
use parser;
use forall_types;

my %class_mapping;
my %rev_class_mapping;

# Sanity checks	
sub rename_checks
{
    my ($class, $dest, $asm) = @_;

    my $base = $asm;  $base =~ s|\.j||;
    if ($base ne $class) 
    {
	die "error: bad location:\n" .
	    "file '$asm' should be in '$class.j' according to class name\n" 
    }
    if ($dest =~ m|/$|) 
    {   die "error: bad pattern, would rename '$class' to '$dest'\n";   }
    if (-f "$dest.j" && $class ne $dest) 
    {
	die "error: clash moving '$class' to '$dest' :\n" .
	    "'$dest' already exists.\n";  
    }
    if ($rev_class_mapping{$dest})
    { 
	die "error: '$class' \n" . 
	    "  and  '$rev_class_mapping{$dest}' \n" . 
	    "  would both end up in '$dest'\n";  
    }
}

sub class_mapping
{
    my ($class) = @_;
    return $class_mapping{$class};
}

sub rev_class_mapping
{
    my ($class) = @_;
    return $rev_class_mapping{$class};
}

sub class_mapping_for_file
{
    my ($asm, $renamer, $checks) = @_;
    my $r = 0;

    open(IN, "< $asm") || die "couldn't open $asm\n";
    foreach my $s (<IN>)
    {
	my %c = parse_class($s, $asm);
	if (!%c)  {  next;  }

	my $class = $c{class};
	my $dest  = $renamer->($class);
	if ($dest ne $class)
	{   $class_mapping{$class} = $dest;  }

	if ($checks)
	{   rename_checks($class, $dest, $asm);  }
	
	$rev_class_mapping{$dest} = $class;
	$r = ($class ne $dest);
	last;
    }
    close(IN);
    return $r;
}

# First pass: figure out class mapping and do some sanity checks.
# $renamer is called to do the actual renaming.
# Process inner classes last to make renamer's life easier.
sub get_class_mapping
{
    my ($files, $renamer, $checks) = @_;
    
    log_info("Looking up classes ...\n");
    my $renames = 0;
    foreach my $file (grep(!/\$/, @$files)) {  $renames += class_mapping_for_file($file, $renamer, $checks);  }
    foreach my $file (grep(/\$/,  @$files)) {  $renames += class_mapping_for_file($file, $renamer, $checks);  }
    if (!$renames) { log_info("No classes to rename.\n"); exit 0; }
}


##########################################################################

my $class_for_name = 0;
my @warnings;

sub uses_class_for_name
{
    return $class_for_name;
}

sub class_for_name_warnings
{
    return @warnings;
}

# Class.forName() Warnings
sub check_class_for_name_calls
{
    my ($s, $asm, $classname, $prev, $line) = @_;
    if ($s =~ m|^[L0-9: \t]*invokestatic Method java/lang/Class forName|)
    {   
	$class_for_name = 1;    
	if (($prev =~ m|^[L0-9: \t]*ldc '(.*)'|) && $class_mapping{$1})
	{   
	    my $file = ($classname && $class_mapping{$classname} ? "$class_mapping{$classname}.j" : $asm);
	    push(@warnings, sprintf("%s:%i:  $prev", $file, $line - 1));
	}
    }
    
    if (($s =~ m|^[L0-9: \t]*ldc '(.*)'|) && length($1) >= 5)
    {   
	my $c = $1;  $c =~ s|\.|/|g;
	if ($class_mapping{$c}) {
	    my $file = ($classname && $class_mapping{$classname} ? "$class_mapping{$classname}.j" : $asm);
	    push(@warnings, sprintf("%s:%i:  $s", $file, $line));
	}
    }    

    return $s;
}


##########################################################################

sub move_class_file
{
    my ($file) = @_;
    my $class = "$file"; $class =~ s|\.j||;	
    (-f "$class.j") || die "shouldn't happen";    
    
    if (!$class_mapping{$class})  {  return;  }
    my $dest = $class_mapping{$class};    
    $dest .= ".j";
    
    my $dir = dirname($dest);
    make_path($dir);

    rename($file, $dest) || die("error: rename '$file' '$dest' failed, aborting.\n");
}


my $renamed_classes = 0;

sub rename_handler
{
    my ($class, $type, $s) = @_;
    my $c = $class_mapping{$class};
    if ($c && $type eq "class")  {  $renamed_classes++;  }
    return ($c ? $c : $class);
}

sub rename_types_in_file
{
    my ($asm, $extra_parser) = @_;
    return forall_types_in_file($asm, \&rename_handler, $extra_parser);
}

sub rename_classes
{
    my @FILES = @_;
    log_info("Moving classes ...\n");

    foreach my $file (@FILES)
    {  
	log_info("%-70s\r", $file);
	my @out = rename_types_in_file($file, \&check_class_for_name_calls);
	
	open(OUT, "> $file") || die "couldn't write to $file\n";
	print OUT @out;
	close(OUT);

	my $classfile = "$file"; $classfile =~ s|\.j|.class|;	
	unlink($classfile);
	move_class_file($file);
    }
    log_info("%-70s\r", "");
    log_info("Renamed %i classes\n", $renamed_classes);

    if (uses_class_for_name())
    {
	log_warn("\nwarning: app uses Class.forName(), moving classes may break it.\n");
	my @warnings = class_for_name_warnings();
	if (@warnings) {  log_warn("possibly hardcoded renamed classes:\n"); }
	foreach my $s (@warnings)
	{  log_warn("%s", $s);  }
    }
}


1;
