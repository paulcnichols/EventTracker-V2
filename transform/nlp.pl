use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use Proc::PidUtil qw(is_running);
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  nlp.pl <conf.yaml>\n\n";
  
  print STDERR "Description: \
  This program takes previously downloaded documents and applies NLP to extract \
  nouns, locations, named entities, and names.  This program relies on the \
  previously built java application nlp.jar.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(binroot docroot name start end feeds)) {  
  error("Missing field '$f'") if !$config->{$f};
}

# iterate over the directories for files to process
my $job = [];
my $jobroot = "$config->{docroot}/$config->{name}";
for my $dir (sort glob("$jobroot/*")) {
  next if !-d $dir;
  print "Directory: $dir\n";
  for my $f (glob("$dir/*.txt")) {
    next if -z $f or -e "$f.nouns" or -e "$f.locs" or -e "$f.orgs" or -e "$f.names";
    push @$job, $f;
  }
}  

# no file to process
exit if !scalar(@$job);

# create a job file
my $job_file = sprintf("/tmp/nlp_files_%d.txt", time);
open JOB_FH, ">", $job_file or die "Failed to create job file!";
print JOB_FH join("\n", @$job);
close JOB_FH;

# open the java downloader as a pipe
my $cmd =  "java -Xmx4g -jar $config->{binroot}/transform/nlp/nlp.jar $config->{binroot}/transform/nlp/models $job_file";
open NLP_FH, "$cmd|";
while (<NLP_FH>) {
  print;
}
close NLP_FH;

# remove temp file
`rm $job_file`;


