#!/usr/bin/perl
use strict;
#use warnings;
use common;
use parser;


my $re_class  = qr|[-_0-9a-zA-Z\$/]+|;
my $re_const  = qr|\[([a-z]+[0-9]+)\]|;

my @standard_types = ("Double", "Float", "Null", "Integer", "Object", "Short", "Long", "Character", 
		      "Top", "Uninitialized", "UninitializedThis");
my %standard_type;
foreach my $s (@standard_types) { $standard_type{$s} = 1; }

# (?| : prevent matches renumbering
sub combine_regexps
{
    my $re = "(?|" . join("|", @_) . ")";
    return qr/$re/;
}

# statements/instructions with escaped object types (Lclass;)
my $re_escaped_instr = combine_regexps(
    qr|^\.field|,
    qr|^\.method|,
    qr|^[L0-9: \t]*invoke|,
    qr|^[L0-9: \t]*getfield|,
    qr|^[L0-9: \t]*putfield|,
    qr|^[L0-9: \t]*getstatic|,
    qr|^[L0-9: \t]*putstatic|,
    qr|^[L0-9: \t]*checkcast|,
    qr|^[L0-9: \t]*multianewarray|
    );

# statements/instructions with bare types
my $re_bare_instr = combine_regexps(
    qr|^(\.super)|,
    qr|^(\.implements)|,
    qr|^([L0-9: \t]*new)|,
    qr|^([L0-9: \t]*instanceof)|,
    qr|^([L0-9: \t]*checkcast)|,
    qr|^([L0-9: \t]*anewarray)|,
    qr|^([L0-9: \t]*\.catch)|,
    qr|^([L0-9: \t]*\w+field Field)|,
    qr|^([L0-9: \t]*invoke\w* \w*Method)|,
    qr|^([L0-9: \t]*\w+static Field)|,
    qr|^([L0-9: \t]*ldc_w Class)| 
    );

# statements with multiple bare types
my $re_multi_bare = combine_regexps(
    qr|(^[L0-9: \t]*locals) (.*)|,
    qr|(^[L0-9: \t]*stack) (.*)|,
    qr|(^[L0-9: \t]*\.stack append) (.*)|,
    qr|(^[L0-9: \t]*\.stack stack_1) (.*)|,
    qr|(^[ \t]*\.exceptions) (.*)|
    );

my $re_std_type = qr/[A-KM-Z]/;
my $re_before_types = qr/(?|^|[ ;()[])/;

sub forall_types_in_file
{
    my ($asm, $handler, $extra_parser) = @_;
    my @out;
   
    open(IN, "< $asm") || die "couldn't open $asm\n";
    my @lines = <IN>;
    close(IN);

    my $innerclasses_mode = 0;
    my $localvariabletable_mode = 0;
    my $classname;
    for (my $line = 1, my $prev = "";  
	 my $s = $lines[$line - 1];
	 $line++, $prev = $s, push(@out, $s))
    {
	if ($extra_parser) {  $s = $extra_parser->($s, $asm, $classname, $prev, $line);  }
	
	if ($s =~ m/^\.innerclasses/)     { $innerclasses_mode = 1; next; }
	if ($s =~ m/^\.end innerclasses/) { $innerclasses_mode = 0; }

	if ($s =~ m/^ *\.localvariabletable/)      { $localvariabletable_mode = 1; next; }	
	if ($s =~ m/^ *\.end localvariabletable/)  { $localvariabletable_mode = 0;  }
	if ($localvariabletable_mode)
	{   
	    if ($s =~ m/ L($re_class); /)
	    {  	$s = "$` L" . $handler->($1, "", $s, $asm) . "; $'";  }
	    if ($s =~ m/$re_const/)
	    {   die "$asm: const found, fixme !\n$s\n";  }
	    next; 
	}
	
	if ($s =~ m/$re_escaped_instr/)
	{
	    # Rename all object types 'Lclass;' into 'Lnewclass;'
	    # We must be careful not to match something like
	    #   'Ljavax/swing/JLabel;'  as class  'abel'
	    # so check where it starts. Also there could be basic types before us ('I' 'J' 'Z' ...) as in:
	    #   invokespecial Method Foo m (IILBar;)V     ; -> Foo.m(int, int, Bar)

	    # Can't just do this, would loop if renamed matches pattern.
	    # And can't use s|||g here either.
	    # while ($s =~ s|($re_before_types$re_std_type*)L($re_class);|$1L$class_mapping{$2};|) { }
	    
	    # such a hack, but gets the job done
	    my @parts = split(";", $s);
	    my $n = @parts;
	    for (my $i = 0; $i < $n - 1; $i++)
	    {
		if ($parts[$i] =~ m|($re_before_types$re_std_type*)L($re_class)$|)
		{   $parts[$i] = "$`$1L" . $handler->($2, "", $s, $asm);  }
	    }
	    $s = join(";", @parts);
	}
	
	# Statements with bare types
	
	if (my %c = parse_class($s, $asm))
	{   
	    $classname = $c{class}; 
	    $c{class} = $handler->($classname, "class", $s, $asm);
	    $s = make_class(%c);  next;
	}

	if (my %m = parse_enclosing_method_any($s, $asm))
	{
	    $m{class} = $handler->($m{class}, "enclosing method", $s, $asm);
	    $s = make_enclosing_method(%m);  next;
	}

	if ($s =~ m/$re_bare_instr ($re_class) /)
	{   $s = "$1 " . $handler->($2, "", $s, $asm) . " $'"; next;  }

	
	# locals / stack
	if ($s =~ m/$re_multi_bare/ || $innerclasses_mode)
	{
	    my ($head, $types) = ($1, $2);
	    my $tail = "";
	    my @types = ($types ? split(' ', $types) : () );
	    
	    if ($innerclasses_mode)
	    { 
		$head = "   ";
		my @all = split(' ', $s);
		@types = ($all[0], $all[1]); # just need to translate first two
		splice(@all, 0, 2);          # remainng ones
		$tail = join(" ", @all);
	    }
	    
	    for (my $i = 0; $i < @types; $i++)
	    {
		if ($types[$i] eq "Uninitialized") { $i++; next; }
		if ($standard_type{$types[$i]}) { next; }
		if ($types[$i] =~ m|$re_const| && $types[$i] ne "[0]")
		{   die "$asm: const found, fixme !\n$s\n";  }
		if ($types[$i] =~ m|^($re_class)$|)
		{   $types[$i] = $handler->($1, "", $s, $asm);  }
	    }
	    $types = join(" ", @types);
	    $s = "$head $types $tail\n";
	}
    }

    return @out;
}



1;
