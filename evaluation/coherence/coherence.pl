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
                            log(dta.weight)*log(dtb.weight)*log(ts.cosign_similarity) as edge
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
                            log(dta.weight)*log(dtb.weight)*log(ts.cosign_similarity) as edge
                          from document_topic dta
                          join topic_similarity ts on (dta.topic_id = ts.topic_b)
                          join document_topic dtb on (ts.topic_a = dtb.topic_id)
                          where dta.document_id = ?
                        )
                        order by edge desc|);

my $edges_document_sim = $dbh->prepare(qq|
                        (
                          select 
                            dtb.document_id as document_b,
                            dta.topic_id as topic_a, 
                            dtb.topic_id as topic_b,
                            log(dta.weight)*log(dtb.weight)*log(ds.cosign_similarity) as edge
                          from document_topic dta
                          join document_similarity ds on (dta.document_id = ds.document_a)
                          join document_topic dtb on (ds.document_b = dtb.document_id)
                          where dta.document_id = ?
                        ) union
                        (
                          select
                            dtb.document_id as document_b, 
                            dta.topic_id as topic_a, 
                            dtb.topic_id as topic_b,
                            log(dta.weight)*log(dtb.weight)*log(ds.cosign_similarity) as edge
                          from document_topic dta
                          join document_similarity ds on (dta.document_id = ds.document_b)
                          join document_topic dtb on (ds.document_a = dtb.document_id)
                          where dta.document_id = ?
                        )
                        order by edge desc|);

my $edges_probability = $dbh->prepare(qq|
                        (
                          select 
                            document_b,
                            topic_a,
                            topic_b,
                            log(topic_prod) + term_prob as edge
                          from edge_intersection
                          where document_a = ?
                        ) union
                        (
                          select 
                            document_a as document_b,
                            topic_b as topic_a,
                            topic_a as topic_b,
                            log(topic_prod) + term_prob as edge
                          from edge_intersection
                          where document_b = ?
                        )
                        order by edge desc|);

my $edges_weighted = $dbh->prepare(qq|
                        (
                          select 
                            document_b,
                            topic_a,
                            topic_b,
                            log(topic_prod) +  log(term_weighted) as edge
                          from edge_intersection
                          where document_a = ?
                        ) union
                        (
                          select 
                            document_a as document_b,
                            topic_b as topic_a,
                            topic_a as topic_b,
                            log(topic_prod) +  log(term_weighted) as edge
                          from edge_intersection
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

my $document_topics = {};
sub document_topic {
  my $document_id = shift;
  my $topic_id = shift;
  my $m = shift;
  
  return document($document_id) if $m <= 2;
  
  if ($m == 3) {
    my $k = "$document_id-$topic_id-$m";
    return $document_topics->{$k} if $document_topics->{$k};
    
    my $document = document($document_id) ;
    my $topic= topic($topic_id);
    my $nd = {};
    for my $t (keys(%$document)) {
      $nd->{$t} = $document->{$t}*($topic->{$t}||0);
    }
    $document_topics->{$k} = $nd;
    return $nd;
  }
  else {
    my $k = "$document_id-$topic_id-$m";
    return $document_topics->{$k} if $document_topics->{$k};
    
    my $document = document($document_id) ;
    my $topic= topic($topic_id);
    my $nd = {};
    for my $t (keys(%$document)) {
      $nd->{$t} = $topic->{$t} || .000001;
    }
    $document_topics->{$k} = $nd;
    return $nd;
  }
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

# calculate within cluster sum of squares
sub mse {
  my $doc_id = shift;
  my $neighbors = shift;
  
  # nothing to do without neighbors 
  return 0 if scalar(keys(%$neighbors)) == 0;

  # find average distance from centroid
  my $wcss = 0;
  for my $d (keys (%$neighbors)) {
    my $da = document_topic($doc_id, $neighbors->{$d}->{topic_a}, $neighbors->{$d}->{m});
    my $db = document_topic($d, $neighbors->{$d}->{topic_b}, $neighbors->{$d}->{m});
    for my $t (uniq(keys(%$da), keys(%$db))) {
      $wcss += (($da->{$t}||0) - ($db->{$t}||0))**2;
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
  my $edges_tp = {};
  my $edges_dw = {};
  
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
  
  $edges_probability->execute($doc, $doc);
  while (my $e = $edges_probability->fetchrow_hashref()) {
    $edges_tp->{$e->{document_b}} = {edge=>$e->{edge}, topic_a=>$e->{topic_a}, topic_b=>$e->{topic_b}, m=>3}
      if scalar(keys(%$edges_tp)) < $edge_limit and !exists($edges_tp->{$e->{document_b}});
  }
  
  $edges_weighted->execute($doc, $doc);
  while (my $e = $edges_weighted->fetchrow_hashref()) {
    $edges_dw->{$e->{document_b}} = {edge=>$e->{edge}, topic_a=>$e->{topic_a}, topic_b=>$e->{topic_b}, m=>4}
      if scalar(keys(%$edges_dw)) < $edge_limit and !exists($edges_dw->{$e->{document_b}});
  }
  
  my $all_lim =
        scalar(keys(%$edges_ts)) > $edge_limit &&
        scalar(keys(%$edges_ds)) > $edge_limit &&
        scalar(keys(%$edges_tp)) > $edge_limit &&
        scalar(keys(%$edges_dw)) > $edge_limit;
  
  my $all_some =
        scalar(keys(%$edges_ts)) > 0 &&
        scalar(keys(%$edges_ds)) > 0 &&
        scalar(keys(%$edges_tp)) > 0 &&
        scalar(keys(%$edges_dw)) > 0;        

  if ($all_lim) {
    $totals_lim->{1} += scalar(keys(%$edges_ts));
    $totals_lim->{2} += scalar(keys(%$edges_ds));
    $totals_lim->{3} += scalar(keys(%$edges_tp));
    $totals_lim->{4} += scalar(keys(%$edges_dw));    
  }
  elsif ($all_some) { 
    $totals_some->{1} += scalar(keys(%$edges_ts));
    $totals_some->{2} += scalar(keys(%$edges_ds));
    $totals_some->{3} += scalar(keys(%$edges_tp));
    $totals_some->{4} += scalar(keys(%$edges_dw));    
  }
  else {
    $totals_partial->{1} += scalar(keys(%$edges_ts));
    $totals_partial->{2} += scalar(keys(%$edges_ds));
    $totals_partial->{3} += scalar(keys(%$edges_tp));
    $totals_partial->{4} += scalar(keys(%$edges_dw));  
  }

  my $edges = [$edges_ts, $edges_ds, $edges_tp, $edges_dw];
  my $r = [$doc];
  for (my $i = 0; $i < 4; ++$i) {
    
    # do stats to determine recall similarity between methods
    for (my $j = $i + 1; $j < 4; ++$j) {
      my $intersection = 0;
      for my $k (keys(%{$edges->[$i]})) {
        $intersection += 1 if exists($edges->[$j]->{$k});
      }
      if ($all_lim) {       
        $stats_lim->{$i+1}->{$j+1} += $intersection; 
      }
      elsif ($all_some) {
        $stats_some->{$i+1}->{$j+1} += $intersection; 
      }
      else {
        $stats_partial->{$i+1}->{$j+1} += $intersection; 
      }
    }
    
    # calculate coherence measures
    push @$r, scalar(keys(%{$edges->[$i]}));
    push @$r, kl($doc, $edges->[$i]);
    push @$r, wcss($doc, $edges->[$i]);
    push @$r, mse($doc, $edges->[$i]);
    push @$r, variance($doc, $edges->[$i]);
  }
  return $all_some, $r; 
}

open FH_OVERLAP, ">", "overlap_$config->{name}.txt";
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

for (my $i=1; $i <= 4; ++$i) {
  printf FH_OVERLAP "tot_lim,%d,%d\n", $i, $totals_lim->{$i};
  printf FH_OVERLAP "tot_some,%d,%d\n", $i, $totals_some->{$i};
  printf FH_OVERLAP "tot_partial,%d,%d\n", $i, $totals_partial->{$i};
  for (my $j=$i+1; $j <= 4; ++$j) {
    printf FH_OVERLAP "isect_lim,%d,%d,%d\n", $i, $j, $stats_lim->{$i}->{$j};
    printf FH_OVERLAP "isect_some,%d,%d,%d\n", $i, $j, $stats_some->{$i}->{$j};
    printf FH_OVERLAP "isect_partial,%d,%d,%d\n", $i, $j, $stats_partial->{$i}->{$j};
  }
}
close FH_OVERLAP;
