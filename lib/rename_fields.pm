#!/usr/bin/perl
use common;
use parser;

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
	if (my %c = parse_class($s, $asm))  {  $classname = $c{class};  }

	if (my %f = parse_field($s, $asm))
	{
	    push(@fields, $f{field} );
	    $type_count{ $f{type} }++;
	    $fields{"$classname:$f{field}"} = $f{type};
	}
    }
    close(IN);

    foreach my $field (@fields)
    {
	my $type = $fields{"$classname:$field"};	
	my $newfield = $renamer->($classname, $field, $type, $type_count{$type}, $asm);
	if ($newfield eq $field)  {  next;  }
	$new_fields{"$classname:$newfield"} = $type;
	$fields_mapping{"$classname:$field"} = "$newfield";
	#printf("%10s -> %s\n", "$classname:$field", "$newfield");
    }
}

sub get_fields_mapping
{
    my ($renamer) = @_;

    foreach_class_most_basic_first(
	sub 
	{
	    my ($class) = @_;
	    if (!external_class($class))
	    {   get_fields_mapping_for_file("$class.j", $renamer);   }
	});
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
	if (my %c = parse_class($s, $asm))  {  $classname = $c{class};  }

	if (my %f = parse_field($s, $asm))
	{  
	    #print "field: '$field'  type: '$type'\n";
	    $f{field} = $fields_mapping{"$classname:$f{field}"};
	    if (!$f{field})  {  next;  }
	    $s = make_field(%f);
	}

	# getfield putfield getstatic putstatic
	if (my %f = parse_getfield($s, $asm))	
	{
#	    my ($call, $class, $field, $type) = ($1, $2, $3, $4);
	    my $def_class = lookup_field_class($f{class}, $f{field});
	    # Field defined outside scope of project ? don't interfere ...
	    if (!$def_class || external_class($def_class))    
	    {  next;  }
	    $f{field} = $fields_mapping{"$def_class:$f{field}"};
	    if (!$f{field})  {  next;  }
	    $s = make_getfield(%f);
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
    log_info("Renaming fields ...\n");
    foreach my $file (@FILES)
    {  
	log_info("%-70s\r", $file);
	rename_fields_for_file($file);  
    }
    log_info("%-70s\r", "");
}

1;
