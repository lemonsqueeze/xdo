#!/usr/bin/perl
# class hierarchy
use common;
use jdk_types;
use parser;

my $re_class = qr|[0-9a-zA-Z_\$/]+|;

# project files + external classes
@FILES_AND_EXT;
%file_for_class;

%classes;
%ext_classes;   # External classes (jdk ...)
%interfaces;

%extends;
%extended;
%implements;

sub file_class_info
{
    my ($asm) = @_;
    open(IN, "< $asm") || die "couldn't open $asm";

    my $classname;
    my $super;
    my @ifaces;
    foreach my $s (<IN>)
    {
	if (my %c = parse_class($s, $asm))
	{  
	    $classname = $c{class};
	    if ($c{decl} =~ m/interface/)  {  $interfaces{$classname} = 1;  }
	}

	if ($s =~ m/^\.super  *($re_class) *$/)      {  $super = "$1";  }
	if ($s =~ m/^\.implements  *($re_class) *$/) {  push(@ifaces, $1);  }
	if ($s =~ m/^\.method/)  { last; }
    }
    close(IN);

    # Sanity checks
    $classname || die "$asm: no class found !";
    $super || ($classname eq "java/lang/Object") || die "$asm: no parent class ?!";

    #print "$classname > $super\n";    
    $classes{$classname} = 1;
    $file_for_class{$classname} = $asm;
    $extends{$classname} = $super;
    $extended{$super} = 1;
    $implements{$classname} = join(", ", @ifaces);
}

sub implemented_interfaces
{
    my ($class) = @_;    

    return split(", ", $implements{$class});
}

sub class_and_parents
{
    my ($class) = @_;
    my @classes;
    for (; $class ne ""; $class = $extends{$class})
    {
	push(@classes, $class);  
    }

    return @classes;
}

sub external_class
{
    my ($class) = @_;
    return (!$classes{$class} || $ext_classes{$class});
}


# call $func($class) for each class, from most basic to most derived
sub foreach_class_most_basic_first
{
    my ($func) = @_;
    my %classes_left = %classes;

    sub interface_or_jlo
    {  
	my ($class) = @_;  
	return ($interfaces{$class} || $class eq "java/lang/Object");
    }

    sub foreach_class_if
    {
	my ($test, $func) = @_;
	for (my $cont = 1; %classes_left && $cont; )
	{
	    $cont = 0;
	    foreach my $class (keys(%classes_left))
	    {
		my $parent = $extends{$class};
		if ($classes_left{$parent})    {  next;  }
		if ($test && !$test->($class)) {  next;  }
		
		$func->($class);
		$cont = 1;
		delete $classes_left{$class};
	    }
	}
    }

    # interfaces first
    foreach_class_if(\&interface_or_jlo, $func);
    foreach_class_if(0, $func);
    !keys(%classes_left) || die "classes left !";
}

sub get_ext_classes_and_interfaces
{
    my ($class) = @_;
    if ($classes{$class} || $class eq "") { return; }    

    #print "external class: $class\n";
    my $file = get_ext_class_file($class);
    file_class_info($file);
    push(@FILES_AND_EXT, $file);
    $ext_classes{$class} = 1;
    
    foreach my $i (implemented_interfaces($class))
    {
	get_ext_classes_and_interfaces($i);
    }
    get_ext_classes_and_interfaces($extends{$class});
}

sub get_class_info
{
    log_info("Getting class info ...\n");
    foreach my $file (@_)
    {  
	file_class_info($file);
    }

    @FILES_AND_EXT = @_;
    # Lookup external (jdk) parent classes also
    foreach my $class (keys(%classes))
    {
	get_ext_classes_and_interfaces($extends{$class});
	foreach my $i (implemented_interfaces($class))
	{
	    get_ext_classes_and_interfaces($i);
	}

    }
}

1;
