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
  edge_prepare.pl <conf.yaml> <document-topic=.3> <topic-similarity=.9> <document-similarity=.8>\n\n";
  
  print STDERR "Description:\
  This program caches the set of document-topic pairs to consider.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

# threshold
my $document_topic_thresh = $ARGV[1] || .15;
my $topic_similarity_thresh = $ARGV[2] || .6;
my $document_similarity_thresh = $ARGV[3] || .65;

# create the database handle
my $dbh = DBI->connect(
                    $config->{database},
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");
my $dataset_id = $dbh->selectall_arrayref(qq|
                        select id
                        from dataset
                        where name = '$config->{name}'|)->[0]->[0] or error("No such dataset");

my $doc_topics = $dbh->prepare(qq|
                        select
                          document_a, document_b, topic_a, topic_b,
                          dta.weight as document_topic_a_weight,
                          dtb.weight as document_topic_b_weight,
                          ds.cosign_similarity as document_similarity,
                          ts.cosign_similarity as topic_similarity
                        from document_similarity ds
                        join document d on (ds.document_a = d.id)
                        join document_topic dta on (ds.document_a = dta.document_id)
                        join document_topic dtb on (ds.document_b = dtb.document_id)
                        join topic_similarity ts on (dta.topic_id = ts.topic_a and dtb.topic_id = ts.topic_b)
                        where 
                          d.dataset_id = $dataset_id and
                          dta.weight >= $document_topic_thresh and
                          dtb.weight >= $document_topic_thresh and
                          ts.cosign_similarity >= $topic_similarity_thresh and
                          ds.cosign_similarity >= $document_similarity_thresh|);

print "Executing query...\n";
$doc_topics->execute();

print "Saving tuples...\n";
open FH, ">", "$config->{name}_tuples.csv";
while (my $dt = $doc_topics->fetchrow_hashref()) {
  print FH join(",",
                $dt->{document_a}, $dt->{document_b},
                $dt->{topic_a}, $dt->{topic_b},
                $dt->{document_topic_a_weight},
                $dt->{document_topic_b_weight},
                $dt->{document_similarity},
                $dt->{topic_similarity}) . "\n";
}
close FH;




