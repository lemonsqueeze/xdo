#!/usr/bin/perl
# class hierarchy
use strict;
#use warnings;
use common;
use jdk_types;
use parser;

my $re_class = qr|[-_0-9a-zA-Z\$/]+|;

# project files + external classes
my %class_file;

my %classes;
my %ext_classes;   # External classes (jdk ...)
my %interfaces;

my %parent_class;
my %extended;
my %implements;

sub file_class_info
{
    my ($asm) = @_;
    open(IN, "< $asm") || die "couldn't open $asm";

    my $classname;
    my $super = "";
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
    $class_file{$classname} = $asm;
    $parent_class{$classname} = $super;
    $extended{$super} = 1;
    $implements{$classname} = join(", ", @ifaces);
}

sub classes
{
    return sort(keys(%classes));
}

sub is_class
{
    my ($class) = @_;
    return $classes{$class};
}

sub interfaces
{
    return sort(keys(%interfaces));
}

sub is_interface
{
    my ($class) = @_;
    return $interfaces{$class};
}

sub parent_class
{
    my ($class) = @_;
    return $parent_class{$class};
}

sub extended
{
    my ($class) = @_;
    return $extended{$class};
}

sub class_file
{
    my ($class) = @_;
    return $class_file{$class};
}

sub implemented_interfaces
{
    my ($class) = @_;    

    my $interfaces = $implements{$class};
    if ($interfaces)  {  return split(", ", $interfaces);  }
    return ();
}

sub class_and_parents
{
    my ($class) = @_;
    my @classes;
    for (; $class; $class = $parent_class{$class})
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

sub interface_or_jlo
{  
    my ($class) = @_;  
    return ($interfaces{$class} || $class eq "java/lang/Object");
}

# classes ordered from most basic to most derived
sub classes_most_basic_first
{    
    my @list;
    my %todo = %classes;
    
    my $foreach_class_if = sub
    {
	my ($test) = @_;
	for (my $cont = 1; %todo && $cont; )
	{
	    $cont = 0;
	    foreach my $class (keys(%todo))
	    {
		if ($todo{parent_class($class)})  {  next;  }
		if ($test && !$test->($class))    {  next;  }
		
	        push(@list, $class);
		$cont = 1;
		delete $todo{$class};
	    }
	}
    };

    # interfaces first
    $foreach_class_if->(\&interface_or_jlo);
    $foreach_class_if->(0);
    !keys(%todo) || die "classes left !";
    return @list;
}

sub get_ext_classes_and_interfaces
{
    my ($class) = @_;
    if (!$class || $classes{$class}) { return; }    

    #print "external class: $class\n";
    my $file = get_ext_class_file($class);
    file_class_info($file);
    $ext_classes{$class} = 1;
    
    foreach my $i (implemented_interfaces($class))
    {
	get_ext_classes_and_interfaces($i);
    }
    get_ext_classes_and_interfaces($parent_class{$class});
}

# all class files, including external classes
sub all_class_files
{
    my @files;
    foreach my $class (classes())
    {   push (@files, class_file($class));  }
    return @files;
}

sub get_class_info
{
    log_info("Getting class info ...\n");
    foreach my $file (@_)
    {  
	file_class_info($file);
    }

    # Lookup external (jdk) parent classes also
    foreach my $class (keys(%classes))
    {
	get_ext_classes_and_interfaces($parent_class{$class});
	foreach my $i (implemented_interfaces($class))
	{
	    get_ext_classes_and_interfaces($i);
	}

    }
}

1;
