#!/usr/bin/perl
use File::Path qw(make_path);
use File::Basename;

my $re_pathid      = qr|([0-9a-zA-Z_\$/]*)|;

my %class_mapping;
my %rev_class_mapping;

sub class_mapping_for_file
{
    my ($asm, $renamer) = @_;
    my $r = 0;

    open(IN, "< $asm") || die "couldn't open $asm\n";
    foreach my $s (<IN>)
    {
	if (!($s =~ m|^\.class.* $re_pathid  *$|))  {  next;  }
	my $class = $1;
	my $dest  = $renamer->($class);
	if ($dest ne $class)
	{   $class_mapping{$class} = $dest;  }

	######################################################################
	# Sanity checks	
	
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
	if ($rev_class_mapping{$dest} ne "")
	{ 
	    die "error: '$class' \n" . 
		"  and  '$rev_class_mapping{$dest}' \n" . 
		"  would both end up in '$dest'\n";  
	}
	#######################################################################
	
	$rev_class_mapping{$dest} = $class;
	$r = ($class ne $dest);
	last;
    }
    close(IN);
    return $r;
}

# First pass: figure out class mapping and do some sanity checks.
# $renamer is called to do the actual renaming
sub get_class_mapping
{
    my ($renamer, $files) = @_;
    
    print "Looking up classes ...\n";
    my $renames = 0;
    foreach my $file (@$files)
    {
	$renames += class_mapping_for_file($file, $renamer);
    }
    if (!$renames) { print "No classes to rename.\n"; exit 0; }
}


##########################################################################


sub move_class_file
{
    my ($asm, $class) = @_;
    (-f "$class.j") || die "shouldn't happen";    
    
    my $dest = $class_mapping{$class};    
    $dest .= ".j";
    
    my $dir = dirname($dest);
    make_path($dir);

    rename($asm, $dest) || die("error: rename $asm $dest failed, aborting.\n");
    return 1;
}


my $class_for_name = 0;
my @warnings;

sub class_for_name_warnings
{
    my ($asm, $s, $classname, $prev, $l) = @_;
    if ($s =~ m|^[L0-9: \t]*invokestatic Method java/lang/Class forName|)
    {   
	$class_for_name = 1;    
	if (($prev =~ m|^[L0-9: \t]*ldc '(.*)'|) && $class_mapping{$1})
	{   
	    my $file = ($class_mapping{$classname} ? "$class_mapping{$classname}.j" : $asm);
	    push(@warnings, sprintf("%s:%i:  $prev", $file, $l - 1));
	}
    }
    
    if (($s =~ m|^[L0-9: \t]*ldc '(.*)'|) && length($1) >= 5)
    {   
	my $c = $1;  $c =~ s|\.|/|g;
	if ($class_mapping{$c}) {
	    my $file = ($class_mapping{$classname} ? "$class_mapping{$classname}.j" : $asm);
	    push(@warnings, sprintf("%s:%i:  $s", $file, $l));
	}
    }    
}


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

sub rename_types_in_file
{
    my ($asm) = @_;
    my $out = "${asm}.new";
    my $classfile = "$asm"; $classfile =~ s|\.j|\.class|;

    open(IN, "< $asm") || die "couldn't open $asm\n";
    open(OUT, "> $out") || die "couldn't write to $out\n";

    my $innerclasses_mode = 0;
    my $localvariabletable_mode = 0;
    my $classname;
    for (my $l = 1, my $prev = "";  
	 my $s = <IN>;  
	 $l++, $prev = $s, print OUT $s)
    {
	if ($s =~ m/^\.innerclasses/)     { $innerclasses_mode = 1; next; }
	if ($s =~ m/^\.end innerclasses/) { $innerclasses_mode = 0; }

	if ($s =~ m/^ *\.localvariabletable/)      { $localvariabletable_mode = 1; next; }	
	if ($s =~ m/^ *\.end localvariabletable/)  { $localvariabletable_mode = 0;  }
	if ($localvariabletable_mode)
	{   
	    if ($s =~ m/ L$re_pathid; / && $class_mapping{$1})
	    {  	$s =   " L$class_mapping{$1}; ";  }
	    next; 
	}

	# Class.forName() Warnings
	class_for_name_warnings($asm, $s, $classname, $prev, $l);
	
	if ($s =~ m/$re_escaped_instr/)
	{
	    # Rename all object types 'Lclass;' into 'Lnewclass;'
	    # We must be careful not to match something like
	    #   'Ljavax/swing/JLabel;'  as class  'abel'
	    # so check where it starts. Also there could be basic types before us ('I' 'J' 'Z' ...) as in:
	    #   invokespecial Method Foo m (IILBar;)V     ; -> Foo.m(int, int, Bar)

	    # Can't just do this, would loop if renamed matches pattern.
	    # And can't use s|||g here either.
	    # while ($s =~ s|($re_before_types$re_std_type*)L$re_pathid;|$1L$class_mapping{$2};|) { }
	    
	    # such a hack, but gets the job done =)
	    my @parts = split(";", $s);
	    my $n = @parts;
	    for (my $i = 0; $i < $n - 1; $i++)
	    {
		if ($parts[$i] =~ m|($re_before_types$re_std_type*)L$re_pathid$| && $class_mapping{$2})
		{   $parts[$i] = "$`$1L$class_mapping{$2}";  }
	    }
	    $s = join(";", @parts);
	}
	
	# Statements with bare types
	if ($s =~ m/(^\.class.*) $re_pathid  *$/ && $class_mapping{$2})
	{   $s = "$1 $class_mapping{$2} $'";   $classname = $2; next;  }

	if ($s =~ m/$re_bare_instr $re_pathid / && $class_mapping{$2})
	{   $s = "$1 $class_mapping{$2} $'"; next;  }

	
	# locals / stack
	if ($s =~ m/$re_multi_bare/ || $innerclasses_mode)
	{
	    my ($head, $types) = ($1, $2);
	    my $tail = "";
	    @types = split(' ', $types);
	    
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
		if ($types[$i] =~ m|^$re_pathid$| && $class_mapping{$1})
		{   $types[$i] = $class_mapping{$1}; }
	    }
	    $types = join(" ", @types);
	    $s = "$head $types $tail\n";
	}
    }
    close(IN);
    close(OUT);

    rename($out, $asm);
    unlink($classfile);
    
    if ($classname eq "")  {  return 0;  }
    return move_class_file($asm, $classname);
}


sub rename_classes
{
    my @FILES = @_;
    print "Moving classes ...\n";
    my $renamed_classes = 0;
    foreach my $file (@FILES)
    {  
	printf("%-70s\r", $file);    
	$renamed_classes += rename_types_in_file($file);
    }
    printf("%-70s\r", "");
    printf("Renamed %i classes\n", $renamed_classes);

    if ($class_for_name)
    {
	print "\nwarning: app uses Class.forName(), moving classes may break it.\n";
	if (@warnings) {  print "following lines look like hardcoded renamed classes:\n"; }
	foreach my $s (@warnings)
	{  print $s;  }
    }
}


1;
