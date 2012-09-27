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
  topic.pl <conf.yaml> <min-doc=5>\n\n";
  
  print STDERR "Description: \
  This program takes previously downloaded documents and applies LDA topic \
  modelling to directories of content and saves the resulting topic-term \
  distributions and document-topic distributions.  An optional minimum number \
  of documents for a topic job can be supplied.  The default minimum is 5. \
  This program relies on the previously built java application topic.jar.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# get minimum doc count
my $doc_count = 5;
$doc_count = int($ARGV[1]) if exists($ARGV[1]) and $ARGV[1] =~ /\d+/;

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
  next if -e "$dir.alpha" or -e "$dir.beta";
  next if scalar(@{[glob("$dir/*.txt")]}) < $doc_count;
  print "Directory: $dir\n";
  
  # get number of files and use to guess number of topics.  (However, this is
  # all a wild guess - choosing topics is a black art)
  my $ntopics =  100; #$ntopics = $ntopics / log($ntopics);
  
  # open the java downloader as a pipe
  my $cmd =  "java -Xmx4g -jar $config->{binroot}/transform/topic/topic.jar $dir $ntopics $config->{binroot}/transform/topic/stoplists/en.txt";
  open NLP_FH, "$cmd|";
  while (<NLP_FH>) {
    print;
  }
  close NLP_FH;  
}  

