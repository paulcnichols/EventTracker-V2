use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use DBIx::Wrapper;
use Proc::PidUtil qw(is_running);
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  similarity_histogram.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  Gather data to create a histogram of the similarities.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

# create the database handle
my $dbh = DBI->connect(
                    $config->{database},
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");

my $dataset_id = $dbh->selectall_arrayref(qq|
                        select id
                        from dataset
                        where name = '$config->{name}'|)->[0]->[0] or error("No such dataset");

my $range_document = $dbh->prepare(qq|
                        select count(*) as n
                        from document_similarity
                        join document a on (document_a = a.id)
                        where
                          cosign_similarity >= ?
                          and cosign_similarity < ?
                          and dataset_id = $dataset_id|);

my $range_topic = $dbh->prepare(qq|
                        select count(*) as n
                        from topic_similarity
                        join topic a on (topic_a = a.id)
                        where
                          cosign_similarity >= ?
                          and cosign_similarity < ?
                          and dataset_id = $dataset_id|);

open FH, ">", "similarity_$config->{name}.csv";
my $step = .01;
for (my $i=.3; $i <= 1.0; $i += $step) {
  $range_document->execute($i, $i+$step);
  my $n = $range_document->fetchrow_hashref()->{n};
  printf FH "document,%f,%d\n", $i, $n;
}

for (my $i=.3; $i <= 1.0; $i += $step) {
  $range_topic->execute($i, $i+$step);
  my $n = $range_topic->fetchrow_hashref()->{n};
  printf FH "topic,%f,%d\n", $i, $n;
}
close FH;
