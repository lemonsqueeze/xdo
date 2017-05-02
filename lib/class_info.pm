#!/usr/bin/perl
# class hierarchy
use jdk_types;

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

sub parse_class_type
{
    my ($file) = @_;
    open(IN, "< $file") || die "couldn't open $file";

    my $classname;
    my $super;
    my @ifaces;
    foreach my $s (<IN>)
    {
	chomp($s);
	#$s =~ s|/|.|g;
	if ($s =~ m/^\.class.* ($re_class) *$/) { $classname = "$1"; $file_for_class{$classname} = $file; }
	if ($s =~ m/^\.super  *($re_class) *$/) { $super = "$1"; }
	if ($s =~ m/^\.implements  *($re_class) *$/) 
	{ 
	    my $i = $1; 
	    $interfaces{$i} = 1;
	    push(@ifaces, $i); 
	}
	if ($s =~ m/^\.method/)  { last; }
    }
    close(IN);

    $classes{$classname} = 1;
    if ($super ne "") {
	$extends{$classname} = $super;
	#print "$classname -> $super\n";
	$extended{$super} = 1;
    }
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

sub get_ext_classes_and_interfaces
{
    my ($class) = @_;
    if ($classes{$class} || $class eq "") { return; }    

    #print "external class: $class\n";
    my $file = get_ext_class_file($class);
    parse_class_type($file);
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
    print "Getting class info ...\n";    
    foreach my $file (@_)
    {  
	parse_class_type($file);  
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
