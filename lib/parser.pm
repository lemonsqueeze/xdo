#!/usr/bin/perl
use strict;
#use warnings;

my $re_class = qr|[-_0-9a-zA-Z\$/]+|;
my $re_types = qr|[-_A-Za-z0-9;/[\$]+|;
my $re_const = qr|\[([a-z]+[0-9]+)\]|;

sub parse_class
{
    my ($s, $asm) = @_;
    if ($s =~ m/^(\.class.*) ($re_class)  *$/)
    {   return ("decl" => $1, "class" => $2);  }
    if ($s =~ m|^\.class|) {  die("parser error: $asm:\n$s\n");  }
    return;
}

sub make_class
{
    my %c = @_;
    return "$c{decl} $c{class} \n";
}

###################################################################################

my $re_method = qr/[-_a-zA-Z0-9<>\$\\]+/;

sub parse_method
{
    my ($s, $asm) = @_;
    if ($s =~ m|^(\.method.*) '?($re_method)'? : ([^ ]*)|)
    {   return ("decl" => $1, "method" => $2, "type" => $3);  }
    if ($s =~ m|^\.method|) {  
	if ($s =~ m|$re_const|)  {  die "$asm: const found, run xdo constfix first:\n$s\n";  }
	die("parser error: $asm:\n$s\n");  
    }
    return;
}

sub make_method
{
    my %m = @_;
    return "$m{decl} $m{method} : $m{type} \n";
}

###################################################################################
# parse .enclosing method statement:
#   .enclosing method classname methodname type

# matches complete and incomplete declarations
sub parse_enclosing_method_any
{
    my ($s, $asm) = @_;
    if ($s !~ m|^\.enclosing method|) {  return;  }
    
    if ($s =~ m|^\.enclosing method ($re_class) '?($re_method)'? ([^ ]+)|)
    {   return ("class" => $1, "method" => $2, "type" => $3);  }

    # incomplete declaration ...
    if ($s =~ m|^\.enclosing method ($re_class) \[0\]|)
    {   return ("class" => $1);  }
    
    die("parser error: $asm:\n$s\n");
}

# matches only complete declarations
sub parse_enclosing_method
{
    my ($s, $asm) = @_;
    my %m = parse_enclosing_method_any($s, $asm);
    if (!$m{method}) {  return;  }
    return %m;
}

sub make_enclosing_method
{
    my %m = @_;
    if ($m{method})
    {  return ".enclosing method $m{class} $m{method} $m{type} \n";  }
    return    ".enclosing method $m{class} [0] \n";
}

###################################################################################

# Note: beware invokeinterface's trailing number                v
#       invokeinterface InterfaceMethod java/util/List size ()I 1
sub parse_method_call
{
    my ($s, $asm) = @_;
    if ($s =~ m/^([L0-9: \t]*invoke\w* \w*Method) ($re_class|$re_types) '?($re_method)'? ([^ ]*) (.*)$/)
    {   return ("call" => $1, "class" => $2, "method" => $3, "type" => $4, "tail" => $5);  }
    if ($s =~ m|^[L0-9: \t]*invoke\w* |) { 
	# TODO: invokedynamic
	if ($s =~ m|^[L0-9: \t]*invokedynamic|)  {  return;  }
	# TODO: array class call:
	#       invokevirtual Method [Ljava/lang/StackTraceElement; clone ()Ljava/lang/Object;
	if ($s =~ m|^[L0-9: \t]*invoke\w* \w*Method \[L$re_class;|)  {  return;  }
	if ($s =~ m|$re_const|)  {  die "$asm: const found, run xdo constfix first:\n$s\n";  }
	die("parser error: $asm:\n$s\n");  
    }
    return;
}

sub make_method_call
{
    my %m = @_;
    return "$m{call} $m{class} $m{method} $m{type} $m{tail}\n";
}

###################################################################################

my $re_field_kw = qr/(?: public| private| protected| final| static| volatile| transient| synthetic| enum)*/;
my $re_field_id = qr/[a-zA-Z0-9_\$]+/;

sub parse_field
{
    my ($s, $asm) = @_;
    if ($s =~ m|^(\.field$re_field_kw) ($re_field_id) ($re_types) (.*)$|)
    {   return ("decl" => $1, "field" => $2, "type" => $3, "tail" => $4);  }
    if ($s =~ m|^\.field|) {  
	if ($s =~ m|$re_const|)  {  die "$asm: const found, run xdo constfix first:\n$s\n";  }
	die("parser error: $asm:\n$s\n");  
    }
    return;
}

sub make_field
{
    my %f = @_;
    return "$f{decl} $f{field} $f{type} $f{tail}\n";
}

###################################################################################

sub parse_getfield
{
    my ($s, $asm) = @_;
    if ($s =~ m|^([L0-9: \t]*\w+ Field) ($re_class) ($re_field_id) ($re_types) *$|)    
    {   return ("call" => $1, "class" => $2, "field" => $3, "type" => $4);  }
    if ($s =~ m|^[L0-9: \t]*\w+ Field |)
    {
	if ($s =~ m|$re_const|)  {  die "$asm: const found, run xdo constfix first:\n$s\n";  }
	die("parser error: $asm:\n$s\n");
    }
    return;
}

sub make_getfield
{
    my %f = @_;
    return "$f{call} $f{class} $f{field} $f{type} \n";
}

1;
