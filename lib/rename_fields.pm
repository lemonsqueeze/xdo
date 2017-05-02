#!/usr/bin/perl

my $re_class = qr|[0-9a-zA-Z_\$/]+|;
my $re_types = qr|[A-Za-z0-9_;/[\$]+|;

################################################################################

my %fields;
my %new_fields;
my %fields_mapping;

sub new_field_defined
{
    my ($class, $field) = @_;
    foreach my $c (class_and_parents($class)) 
    {  
	if ($new_fields{"$c:$field"} ne "") { return 1; }  
    }
    return 0;
}

sub get_fields_mapping_for_file
{
    my ($asm, $renamer) = @_;

    open(IN, "< $asm") || die "couldn't open $asm";

    # Parse fields first so we know how many of each type there is
    my $classname;
    my %type_count;
    my @fields;
    while (my $s = <IN>)
    {
	if ($s =~ m|^\.class.* ($re_class) *$|)  { $classname = $1; }

	if ($s =~ m|(^\.field.*) (\w+) ($re_types) *$|)
	{  
	    my ($field, $type) = ($2, $3);
	    push(@fields, $field);
	    $type_count{$type}++;
	    $fields{"$classname:$field"} = $type;
	}
    }
    close(IN);

    foreach my $field (@fields)
    {
	my $type = $fields{"$classname:$field"};	
	my $newfield = $renamer->($classname, $field, $type, $type_count{$type});
	if ($newfield eq $field)  {  next;  }
	$new_fields{"$classname:$newfield"} = $type;
	$fields_mapping{"$classname:$field"} = "$newfield";
	#printf("%10s -> %s\n", "$classname:$field", "$newfield");
    }
}

sub get_fields_mapping
{
    my ($renamer) = @_;
    
    # process classes from most basic to most derived
    my %classes_todo = %classes;    
    while (%classes_todo)
    {
	foreach my $class (keys(%classes_todo))
	{
	    my $parent = $extends{$class};
	    if ($classes_todo{$parent}) { next; }
	    
	    if (!external_class($class))
	    {   get_fields_mapping_for_file("$class.j", $renamer);   }
	    delete $classes_todo{$class};
	}
    }
    
}


################################################################################

sub lookup_field_class
{
    my ($class, $field) = @_;
    
    foreach my $c (class_and_parents($class)) 
    {
	if ($fields{"$c:$field"})  {  return $c;  }
    }
    return "";  # Field defined outside of project
}

sub rename_fields_for_file
{
    my ($asm) = @_;    
    my $out = "${asm}.new";
    my $classfile = "$asm"; $classfile =~ s|\.j|\.class|;
    
    open(IN, "< $asm") || die "couldn't open $asm";
    open(OUT, "> $out") || die "couldn't write to $out";

    my $classname;
    for (; my $s = <IN>; print OUT $s)
    {
	if ($s =~ m|^\.class.* ($re_class) *$|)  { $classname = $1; }

	if ($s =~ m|(^\.field.*) (\w+) ($re_types) *$|)
	{  
	    my ($decl, $field, $type) = ($1, $2, $3);
	    #print "field: '$field'  type: '$type'\n";
	    my $newfield = $fields_mapping{"$classname:$field"};
	    if (!$newfield)  {  next;  }
	    $s = "$decl $newfield $type \n";
	}

	# getfield putfield getstatic putstatic
	if ($s =~ m|(^[L0-9: \t]*\w+ Field) ($re_class) (\w+) ($re_types) *$|)
	{
	    my ($call, $class, $field, $type) = ($1, $2, $3, $4);
	    my $def_class = lookup_field_class($class, $field);
	    # Field defined outside scope of project ? don't interfere ...
	    if (!$def_class || external_class($def_class))    
	    {  next;  }
	    my $newfield = $fields_mapping{"$def_class:$field"};
	    if (!$newfield)  {  next;  }
	    $s = "$call $class $newfield $type \n";
	}
    }

    close(OUT);
    close(IN);
    rename($out, $asm);
    unlink($classfile);
}

sub rename_fields
{
    my @FILES = @_;
    print "Renaming fields ...\n";
    foreach my $file (@FILES)
    {  
	printf("%-70s\r", $file);
	rename_fields_for_file($file);  
    }
    printf("%-70s\r", "");
}

1;
