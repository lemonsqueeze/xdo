#!/usr/bin/perl
# find jdk / outside classes

use File::Basename;
use Cwd;

my $jrelib = "/home/java/jdk1.8.0_65/jre/lib";

my $confdir = "$ENV{HOME}/.jdasm";
my $indexdir = "$confdir/index";
my $cachedir = "$confdir/cache";


####################################################################

sub run_cmd
{
    my ($cmd) = @_;
    system($cmd) == 0 || die("error command failed: $cmd");
}

# map class to jar file containing it
my %class_to_jar;

sub index_jar
{
    my ($jar) = @_;

    my $index = "$indexdir/" . basename($jar);
    (-f $index) || run_cmd("jar tf '$jar' > '$index'");
    open(IN, "< $index") || die("couldn't open '$index'");
    foreach my $file (<IN>)
    {
	chomp($file);
	if (!($file =~ m|\.class|)) { next; }
	$file =~ s|\.class||;
	$class_to_jar{$file} = $jar;
    }
    close(IN);
}


my $init = 0;
sub init
{
    (-d $confdir) || mkdir($confdir) || die("couldn't create $confdir");
    (-d $indexdir) || mkdir($indexdir) || die("couldn't create $indexdir");
    (-d $cachedir) || mkdir($cachedir) || die("couldn't create $cachedir");    

    my @jars = glob("$jrelib/*.jar");
    foreach my $jar (@jars)
    {
	index_jar($jar);
    }

    $init = 1;
}


sub dasm_ext_class
{
    if (!$init) { init(); }

    my ($class) = @_;
    my $cwd = cwd();
    chdir($cachedir) || die("cache dir not found");

    my $jar = $class_to_jar{$class};
    (-f $jar) || die("class '$class' not found in any jars");
    run_cmd("jar xf '$jar' '$class.class' ");
    (-f "$class.class") || die("jar extract failed");

    # Ok, have class file. Disassemble
    print "dasm $class\n";
    run_cmd("java_dasm '$class.class'");
    (-f "$class.j") || die("java_dasm failed");

    chdir($cwd) || die("chdir failed !");
}

sub get_ext_class_file
{
    my ($class) = @_;
    my $file = "$cachedir/$class.j";
    if (-f $file) { return $file; }

    dasm_ext_class($class);
    return $file;
}

1;