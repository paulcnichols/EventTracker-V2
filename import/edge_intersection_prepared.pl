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
  edge_intersection_prepared.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  This program attempts to create edges between documents using the model \
  P(T|D) P(T'|D') Prod_{W in D AND D'} { P(W|T) P(W|T') } and the cosign \
  similarity between DxT and D'xT'.\n";
  
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

my $topic_terms = $dbh->prepare(qq|
                        select *
                        from topic_term
                        where topic_id = ?|);

my $document_terms = $dbh->prepare(qq|
                        select *
                        from document_term
                        where document_id = ?|);

my $edge_insert = $dbh->prepare(qq|
                        insert into edge_intersection
                        (document_a, document_b, topic_a, topic_b,
                         topic_prod, term_prob, term_raw, term_weighted) values
                        (?, ?, ?, ?,
                         ?, ?, ?, ?)|);
my $topics = {};
sub topic {
  my $topic_id = shift;
  return $topics->{$topic_id} if exists($topics->{$topic_id});
  my $topic = {};
  my $total = 0;
  
  $topic_terms->execute($topic_id);
  while (my $t = $topic_terms->fetchrow_hashref()) {
    $topic->{$t->{term_id}} = $t->{beta};
    $total += $t->{beta};
  }
  for my $term (keys(%$topic)) {
    $topic->{$term} = $topic->{$term} / $total;
  }
  $topics->{$topic_id} = $topic;
  return $topic;
}

my $documents = {};
sub document {
  my $document_id = shift;
  return $documents->{$document_id} if exists($documents->{$document_id});
  my $document = {};
  
  $document_terms->execute($document_id);
  while (my $d = $document_terms->fetchrow_hashref()) {
    $document->{$d->{term_id}} = $d->{count};
  }
  $documents->{$document_id} = $document;
  return $document;
}

# compute the strength of an edge
sub compute_edge {
  my ($doc_a,
      $doc_a_terms,
      $topic_a,
      $topic_a_weights,
      $doc_topic_a,
      $doc_b,
      $doc_b_terms,
      $topic_b,
      $topic_b_weights,
      $doc_topic_b) = @_;
  
  my $smooth = .000001;
  my $p = 0;
  my $raw = 0;
  my $weighted = 0;
  my $a_raw = 0;
  my $b_raw = 0;
  my $a_w = 0;
  my $b_w = 0;
  my $union = {};
  for my $t1 (keys(%$doc_a_terms)) {
    $union->{$t1}++;
  }
  for my $t2 (keys(%$doc_b_terms)) {
    $union->{$t2}++;
  }
  for my $w (keys(%$union)) {
    my $ai_raw = 0;
    my $bi_raw = 0;
    my $ai_w = 0;
    my $bi_w = 0;
    if (exists($doc_a_terms->{$w})) {
      $ai_raw += $doc_a_terms->{$w};
    }
    if (exists($topic_a_weights->{$w})) {
      $p += log($topic_a_weights->{$w});
      $ai_w = $topic_a_weights->{$w};
    }
    else {
      $p += log($smooth);
      $ai_w = $smooth;
    }
    if (exists($doc_b_terms->{$w})) {
      $bi_raw += $doc_b_terms->{$w};
    }
    if (exists($topic_b_weights->{$w})) {
      $p += log($topic_b_weights->{$w});
      $bi_w = $topic_b_weights->{$w};
    }
    else {
      $p += log($smooth);
      $bi_w = $smooth;
    }
    $raw += $ai_raw * $bi_raw;
    $a_raw += $ai_raw**2;
    $b_raw += $bi_raw**2;
    $weighted += $ai_raw * $ai_w * $bi_raw * $bi_w;
    $a_w += ($ai_raw * $ai_w) **2;
    $b_w += ($bi_raw * $bi_w) **2;
  }
  $raw = $raw / (sqrt($a_raw) * sqrt($b_raw));
  $weighted = $weighted / (sqrt($a_w) * sqrt($b_w));
  $edge_insert->execute($doc_a > $doc_b ? $doc_a : $doc_b,
                        $doc_a > $doc_b ? $doc_b : $doc_a,
                        $topic_a > $topic_b ? $topic_a : $topic_b,
                        $topic_a > $topic_b ? $topic_b : $topic_a,
                        $doc_topic_a * $doc_topic_b,
                        $p,
                        $raw,
                        $weighted);
}

$dbh->{AutoCommit} = 0;


open FH, "$config->{name}_tuples.csv";
while (<FH>) {
  chomp;
  my $dt = {};
 ($dt->{document_a}, $dt->{document_b},
  $dt->{topic_a}, $dt->{topic_b},
  $dt->{document_topic_a_weight},
  $dt->{document_topic_b_weight},
  $dt->{document_similarity},
  $dt->{topic_similarity}) = split(/,/);
 
  compute_edge(
      $dt->{document_a},
      document($dt->{document_a}),
      $dt->{topic_a},
      topic($dt->{topic_a}),
      $dt->{document_topic_a_weight},
      $dt->{document_b},
      document($dt->{document_b}),
      $dt->{topic_b},
      topic($dt->{topic_b}),
      $dt->{document_topic_b_weight});
}
close FH;

$dbh->commit();