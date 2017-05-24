#!/usr/bin/perl
use common;

my $re_class = qr|[0-9a-zA-Z_\$/]+|;
my $re_types = qr|[A-Za-z0-9_;/[\$]+|;
my $re_uconst = qr|\[u[0-9]+\]|;


################################################################################

%methods;
%methods_mapping;
%methods_namespace;	# all methods defined until now, old and new.

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

sub check_method_type
{
    my ($file, $class, $method, $type) = @_;
    if ($type =~ m|^$re_uconst|) {  die "$file: $class.$method() call: uconst type found\n" .
					"run xdo uconstfix first\n"; }
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
	if ($s =~ m|^\.class.* ($re_class) *$|)  { $class = $1; }

	if ($s =~ m|(^\.method.*) (\w+) : ([^ ]*)|)
	{  
	    my ($method, $type) = ($2, $3);
	    check_method_type($asm, $classname, $method, $type);
	    $methods{"$class:$method:$type"} = 1;

	    add_method_mapping($class, $method, $type, $renamer);

	    $methods_namespace{"$class:$method"} = 1;
	}
    }

    close(IN);    
}

sub get_methods_mapping
{
    my ($renamer) = @_;
    log_info("Looking up methods ...\n");

    # process classes from most basic to most derived
    my %classes_todo = %classes;    
    while (%classes_todo)
    {
	foreach my $class (keys(%classes_todo))
	{
	    my $parent = $extends{$class};
	    if ($classes_todo{$parent}) { next; }
	    
	    methods_mapping_for_file($file_for_class{$class}, $renamer);
	    delete $classes_todo{$class};
	}
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
	if ($s =~ m|^\.class.* ($re_class) *$|) {  $classname = $1;  }

	if ($s =~ m|(^\.method.*) (\w+) : ([^ ]*)|)
	{  
	    my ($decl, $method, $type) = ($1, $2, $3);
	    check_method_type($asm, $classname, $method, $type);
	    $method = lookup_renamed_method($classname, $method, $type);
	    $s = sprintf("%s %s : %s \n", $decl, $method, $type);
	}

	if ($s =~ m|(^[L0-9: \t]*invoke\w* \w*Method) ($re_class) (\w+) ([^ ]*)(.*)|)
	{
	    my ($call, $class, $method, $type, $tail) = ($1, $2, $3, $4, $5);
	    check_method_type($asm, $class, $method, $type);
	    $method = lookup_renamed_method($class, $method, $type);
	    $s = sprintf("%s %s %s %s%s\n", $call, $class, $method, $type, $tail);
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
