use strict;
use warnings;
my $conf = $ARGV[0] or do {
  print "Usage:\n\tperl do.pl <conf.yaml>\n";
  exit;
};
my @steps;
push @steps, {cmd=>"perl rss/sync.pl $conf", status=>"Syncing RSS feed"};
push @steps, {cmd=>"perl rss/downloader.pl $conf", status=>"Downloading Articles"};
push @steps, {cmd=>"perl transform/nlp.pl $conf", status=>"Applying NLP Extraction"};
push @steps, {cmd=>"perl transform/topic.pl $conf", status=>"Applying Topic Modeling"};
push @steps, {cmd=>"perl import/import.pl $conf", status=>"Importing features into database"};
push @steps, {cmd=>"perl import/edge_compiled.pl $conf", status=>"Computing topic-topic similarities"};
 
for my $s (@steps) {
  print "\n########################################\n";
  print "## $s->{status}\n";
  print "## $s->{cmd}\n";
  print "########################################\n\n";
  open PIPE_FH, "$s->{cmd} |" or do {
    print "Failed to run command '$s->{cmd}'!\n";
    exit;
  };
  while (<PIPE_FH>) { print; }
  close PIPE_FH;
}
