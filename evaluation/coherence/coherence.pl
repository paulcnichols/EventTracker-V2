use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use DBIx::Wrapper;
use Proc::PidUtil qw(is_running);
use List::Util qw(shuffle);
use List::MoreUtils qw(uniq);
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  coherence.pl <conf.yaml> <start=2012-08-25> <days=14> <limit=300> <edges=10>\n\n";
  
  print STDERR "Description:\
  This program generates data to evaluate the created edges.  Starting from a \
  'start' date, 'limit' documents will be grabbed per day for 'days' days and \
  the various methods will be compared.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}
my $start = '2012-08-25';
my $days = 14;
my $doc_limit = 300;
my $edge_limit = 10;

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

my $sample_docs = $dbh->prepare(qq|
                        select *
                        from document
                        where
                          dataset_id = $dataset_id and
                          date = date_add('$start', interval ? day)|);

my $edges_topic_sim = $dbh->prepare(qq|
                        (
                          select 
                            dtb.document_id as document_b,
                            dta.topic_id as topic_a, 
                            dtb.topic_id as topic_b,
                            log(dta.weight)+log(dtb.weight)+log(ts.cosign_similarity) as edge
                          from document_topic dta
                          join topic_similarity ts on (dta.topic_id = ts.topic_a)
                          join document_topic dtb on (ts.topic_b = dtb.topic_id)
                          where dta.document_id = ?
                        ) union
                        (
                          select
                            dtb.document_id as document_b, 
                            dta.topic_id as topic_a, 
                            dtb.topic_id as topic_b,
                            log(dta.weight)+log(dtb.weight)+log(ts.cosign_similarity) as edge
                          from document_topic dta
                          join topic_similarity ts on (dta.topic_id = ts.topic_b)
                          join document_topic dtb on (ts.topic_a = dtb.topic_id)
                          where dta.document_id = ?
                        )
                        order by edge desc|);

my $edges_document_sim = $dbh->prepare(qq|
                        (
                          select 
                            document_b,
                            cosign_similarity as edge
                          from document_similarity
                          where document_a = ?
                        ) union
                        (
                          select
                            document_a as document_b, 
                            cosign_similarity as edge
                          from document_similarity 
                          where document_b = ?
                        )
                        order by edge desc|);
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

sub sample {
  my $offset = shift;
  my $docs = {};
  $sample_docs->execute($offset);
  while (my $d = $sample_docs->fetchrow_hashref()) {
    $docs->{$d->{id}} = $d;
  }
  return $docs;
}

sub kl {
  my $doc_id = shift;
  my $neighbors = shift;
  
  # nothing to do without neighbors 
  return 0 if scalar(keys(%$neighbors)) == 0;
  
  my $doc = document($doc_id);
  my $p = {};
  my $pn = 0;
  for my $t (keys(%$doc)) {
    $p->{$t} = $doc->{$t};
    $pn += $doc->{$t};
  }
  
  my $q = {};
  my $qn = {};
  for my $n_id (keys(%$neighbors)) {
    my $n = document($n_id);
    for my $t (keys(%$n)) {
      $q->{$t} += $n->{$t};
      $qn += $n->{$t};
    }
  }
  
  # create the smoothing factor out of 1 / sum(terms) of the probability space.
  # divide that furhter by all the terms not in p or q respectively.
  my $ps = 0;
  my $qs = 0;
  for my $t (uniq(keys(%$p), keys(%$q))) {
    $ps += 1 if !exists($p->{$t});
    $qs += 1 if !exists($q->{$t});
  }
  $ps = (1/($pn||1))/($ps+1);
  $qs = (1/($qn||1))/($qs+1);
  
  my $kl = 0;
  for my $t (uniq(keys(%$p), keys(%$q))) {
    my $pt = exists($p->{$t}) ? $p->{$t} / ($pn+1) : $ps;
    my $qt = exists($q->{$t}) ? $q->{$t} / ($qn+1) : $qs;
    $kl += $pt*log($pt) - $pt*log($qt);
  }
  return $kl;
}

sub wcss {
  my $doc_id = shift;
  my $neighbors = shift;
  
  # nothing to do without neighbors 
  return 0 if scalar(keys(%$neighbors)) == 0;
  
  # treat start as centroid
  my $centroid = {};
  my $start = document($doc_id);
  for my $t (keys(%$start)) {
    $centroid->{$t} += $start->{$t};
  }
  for my $n (keys (%$neighbors)) {
    my $other = document($n);
    for my $t (keys(%$other)) {
      $centroid->{$t} += $other->{$t}; 
    }
  }
  for my $t (keys(%$centroid)) {
    $centroid->{$t} /= (scalar(keys(%$neighbors)) + 1);
  }
  
  my $wcss = 0;
  for my $t (keys(%$centroid)) {
    $wcss += ($centroid->{$t} - ($start->{$t}||0))**2;
  }
  
  for my $n (keys (%$neighbors)) {
    my $other = document($n);
    for my $t (keys(%$centroid)) {
      $wcss += ($centroid->{$t}- ($other->{$t}||0))**2;
    }
  }
  return $wcss;
}

# calculate within cluster sum of squares
sub mse {
  my $doc_id = shift;
  my $neighbors = shift;
  
  # nothing to do without neighbors 
  return 0 if scalar(keys(%$neighbors)) == 0;
  
  # treat start as centroid
  my $centoid = document($doc_id);
  
  my $wcss = 0;
  for my $n (keys (%$neighbors)) {
    my $other = document($n);
    for my $t (uniq(keys(%$centoid), keys(%$other))) {
      $wcss += (($centoid->{$t}||0) - ($other->{$t}||0))**2;
    }
  }
  return $wcss;
}

sub variance {
  my $doc_id = shift;
  my $neighbors = shift;
  
  # nothing to do without neighbors 
  return 0,0 if scalar(keys(%$neighbors)) == 0;
  
  my $mean = 0;
  for my $n (keys(%$neighbors)) {
    $mean += $neighbors->{$n}->{edge};
  }
  $mean /= scalar(keys(%$neighbors));
  my $var = 0;
  for my $n (keys(%$neighbors)) {
    $var += ($neighbors->{$n}->{edge} - $mean)**2;
  }
  $var /= scalar(keys(%$neighbors));
  
  return $mean, $var;
}

my $stats_lim   = {};
my $stats_some = {};
my $stats_partial = {};
my $totals_lim = {};
my $totals_some = {};
my $totals_partial = {};
sub compare {
  my $doc = shift;
  my $edges_ts = {};
  my $edges_ds = {};
  
  $edges_topic_sim->execute($doc, $doc);
  while (my $e = $edges_topic_sim->fetchrow_hashref()) {
    $edges_ts->{$e->{document_b}} = {edge=>$e->{edge}, topic_a=>0, topic_b=>0, m=>1}
      if scalar(keys(%$edges_ts)) < $edge_limit and !exists($edges_ts->{$e->{document_b}});
  }
  
  $edges_document_sim->execute($doc, $doc);
  while (my $e = $edges_document_sim->fetchrow_hashref()) {
    $edges_ds->{$e->{document_b}} = {edge=>$e->{edge}, topic_a=>0, topic_b=>0, m=>2}
      if scalar(keys(%$edges_ds)) < $edge_limit and !exists($edges_ds->{$e->{document_b}});
  }

  my $all_lim =
        scalar(keys(%$edges_ts)) >= $edge_limit &&
        scalar(keys(%$edges_ds)) >= $edge_limit;
  
  my $all_some =
        scalar(keys(%$edges_ts)) > 0 &&
        scalar(keys(%$edges_ds)) > 0;

  if ($all_lim) {
    $totals_lim->{1} += scalar(keys(%$edges_ts));
    $totals_lim->{2} += scalar(keys(%$edges_ds));   
  }
  elsif ($all_some) { 
    $totals_some->{1} += scalar(keys(%$edges_ts));
    $totals_some->{2} += scalar(keys(%$edges_ds)); 
  }
  else {
    $totals_partial->{1} += scalar(keys(%$edges_ts));
    $totals_partial->{2} += scalar(keys(%$edges_ds));
  }

  my $edges = [$edges_ts, $edges_ds];
  my $r = [$doc];
    
  # do stats to determine recall similarity between methods
  my $intersection = 0;
  for my $k (keys(%$edges_ts)) {
    $intersection += 1 if exists($edges_ds->{$k});
  }
  
  # calculate coherence measures
  push @$r, scalar(keys(%$edges_ts));
  push @$r, kl($doc, $edges_ts);
  push @$r, wcss($doc, $edges_ts);
  push @$r, mse($doc, $edges_ts);
  push @$r, variance($doc, $edges_ts);
  push @$r, scalar(keys(%$edges_ds));
  push @$r, kl($doc, $edges_ds);
  push @$r, wcss($doc, $edges_ds);
  push @$r, mse($doc, $edges_ds);
  push @$r, variance($doc, $edges_ds);
  push @$r, $intersection;
  return $all_some, $r; 
}

open FH_COHERENCE, ">", "coherence_$config->{name}.txt";

# start a slice in the middle of the week and gather
# statistics on a sampling of the data
for (my $i = 0; $i < $days; ++$i) {
  
  print "Offset $i from $start...\n";
  
  # get sample
  my $docs = sample($i);
  
  # for each sample, calculate neighbors by edge policy
  my $n = 0;
  for my $doc_id (shuffle(keys(%$docs))) {
    my ($some, $r) = compare($doc_id);
    print FH_COHERENCE join(',', @$r) . "\n";
    $n++ if $some;
    last if $n > $doc_limit;
  }
}
close FH_COHERENCE;

