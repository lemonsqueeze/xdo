#!/usr/bin/perl
use strict;
#use warnings;
use common;
use parser;

my %methods;
my %methods_mapping;
my %methods_namespace;	# all methods defined until now, old and new.

# For deoverload, must be kept here however.
# is method name already used in new methods namespace ?
sub method_name_in_use
{
    my ($class, $name) = @_;
    foreach my $c (class_and_parents($class)) 
    {
	if ($methods_namespace{"$c:$name"}) { return 1; }  
    }
    return 0;
}

my $re_const = qr|\[([a-z]+[0-9]+)\]|;

sub check_method_type
{
    my ($file, $class, $method, $type) = @_;
    if ($type =~ m|^$re_const|) {  die "$file: $class.$method() call: const found\n" .
				       "run xdo constfix first\n"; }
    if (!($type =~ m|^\(|)) {  die "$file: $class.$method() call: unhandled method type '$type'"; }
}


# Find method's defining class or interface.
# Returns "" if method is bound:
# can't rename methods defined in external classes / interfaces.
# also for now can't rename methods bound to multiple interfaces,
# or methods implementing an interface already defined in a parent class.
sub unbound_method_def_class
{
    my ($class, $method, $type) = @_;
    my $iface_matches = 0;
    
    foreach my $c (class_and_parents($class)) 
    {
	if ($methods{"$c:$method:$type"}) 
	{
	    # method belongs to an interface and a class deeper down ?
	    if ($iface_matches)	     {  return "";  }
	    if (external_class($c))  {  return "";  }
	    $class = $c;
	}	
	
	# Check interfaces implemented
	foreach my $i (implemented_interfaces($c))
	{
	    if ($methods{"$i:$method:$type"}) 
	    {
		# multiple interfaces ?
		if ($iface_matches++)	 {  return "";  }
		if (external_class($i))  {  return "";  }
		$class = $i;
	    }
	}
    }

    return $class;
}

# check if method can be renamed, call renamer and record mapping
sub add_method_mapping
{
    my ($class, $method, $type, $renamer) = @_;
    
    if ($method =~ m/[<>]/)     {  return;  }   # don't rename <init>(), <clinit>()
    
    my $def_class = unbound_method_def_class($class, $method, $type);
    if (!$def_class)            {  return;  }	# can't rename bound methods
    
    my $newmethod = $renamer->($class, $method, $type, $def_class);
    if ($newmethod eq $method)  {  return;  }

    # FIXME could double check that $newmethod doesn't clash with something here
    
    $methods_namespace{"$class:$newmethod"} = 1;
    $methods_mapping{"$class:$method:$type"} = $newmethod;
    #print "$class:$method:$type -> $newmethod\n";
}

sub methods_mapping_for_file
{
    my ($asm, $renamer) = @_;

    open(IN, "< $asm") || die "couldn't open $asm";

    my $class;
    while (my $s = <IN>)
    {
	if (my %c = parse_class($s, $asm))  {  $class = $c{class};  }
	
	if (my %m = parse_method($s, $asm))
	{  
	    check_method_type($asm, $class, $m{method}, $m{type});
	    $methods{"$class:$m{method}:$m{type}"} = 1;

	    add_method_mapping($class, $m{method}, $m{type}, $renamer);

	    $methods_namespace{"$class:$m{method}"} = 1;
	}
    }

    close(IN);    
}

sub get_methods_mapping
{
    my ($renamer) = @_;
    log_info("Looking up methods ...\n");

    foreach my $class (classes_most_basic_first())
    {
	methods_mapping_for_file(class_file($class), $renamer);
    }
}


################################################################################


sub lookup_renamed_method
{
    my ($class, $method, $type) = @_;
    $class = unbound_method_def_class($class, $method, $type);
    if (!$class) {  return $method;  }
    
    if ($methods_mapping{"$class:$method:$type"})
    {  return $methods_mapping{"$class:$method:$type"};  }
    return $method;    
}

sub rename_methods_in_file
{
    my ($asm) = @_;    
    my $out = "${asm}.new";
    my $classfile = "$asm"; $classfile =~ s|\.j|\.class|;


    open(IN, "< $asm") || die "couldn't open $asm";
    open(OUT, "> $out") || die "couldn't write to $out";

    my $classname;
    for (; my $s = <IN>; print OUT $s)
    {
	if (my %c = parse_class($s, $asm))  {  $classname = $c{class};  }

	if (my %m = parse_method($s, $asm))
	{
	    check_method_type($asm, $classname, $m{method}, $m{type});
	    $m{method} = lookup_renamed_method($classname, $m{method}, $m{type});
	    $s = make_method(%m);
	}

	if (my %m = parse_enclosing_method($s, $asm))
	{
	    check_method_type($asm, $classname, $m{method}, $m{type});
	    $m{method} = lookup_renamed_method($m{class}, $m{method}, $m{type});
	    $s = make_enclosing_method(%m);
	}

	if (my %m = parse_method_call($s, $asm))
	{
	    check_method_type($asm, $classname, $m{method}, $m{type});
	    $m{method} = lookup_renamed_method($m{class}, $m{method}, $m{type});
	    $s = make_method_call(%m);
	}
    }
    
    close(OUT);
    close(IN);
    rename($out, $asm);
    unlink($classfile);
}

sub rename_methods
{
    my @FILES = @_;
    log_info("Renaming methods ...\n");
    foreach my $file (@FILES)
    {  
	log_info("%-70s\r", $file);
	rename_methods_in_file($file);  
    }
    log_info("%-70s\r", "");
}

1;
