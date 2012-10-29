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
  edge_intersection.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  This program attempts to create edges between documents using the model \
  P(T|D) P(T'|D') Prod_{W in D AND D'} { P(W|T) P(W|T') }.\n";
  
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

my $document_date = $dbh->prepare(qq|
                        select dt.document_id, dt.term_id, dt.count
                        from document d
                        join document_term dt on (d.id =  dt.document_id)
                        where
                          d.dataset_id = $dataset_id and
                          d.date = ?|);

my $topic_date = $dbh->prepare(qq|
                        select t.date, tt.topic_id, tt.term_id, tt.beta
                        from topic t
                        join topic_term tt on (t.id =  tt.topic_id)
                        where
                          t.dataset_id = $dataset_id and
                          t.date = ?|);

my $document_topic = $dbh->prepare(qq|
                        select document_id, topic_id, weight
                        from document d
                        join document_topic dt on (d.id = dt.document_id)
                        where date = ? and dataset_id = $dataset_id|);

my $edge_insert = $dbh->prepare(qq|
                        insert into edge_intersection
                        (document_a, document_b, topic_a, topic_b,
                         topic_prod, term_prob, term_raw, term_weighted) values
                        (?, ?, ?, ?,
                         ?, ?, ?, ?)|);

# get documents by date
sub document_by_date {
  my $date = shift;
  my $documents = {};
  $document_date->execute($date);
  while (my $d = $document_date->fetchrow_hashref()) {
    $documents->{$d->{document_id}}->{$d->{term_id}} = $d->{count};
  }
  return $documents;
}

# get topics by date
sub topic_by_date {
  my $date = shift;
  my $topics = {};
  my $totals = {};
  $topic_date->execute($date);
  while (my $t = $topic_date->fetchrow_hashref()) {
    $topics->{$t->{topic_id}}->{$t->{term_id}} = $t->{beta};
    $totals->{$t->{topic_id}} += $t->{beta};
  }
  for my $topic (keys(%$topics)) {
    for my $term (keys(%{$topics->{$topic}})) {
      $topics->{$topic}->{$term} = $topics->{$topic}->{$term} / $totals->{$topic};
    }
  }
  return $topics;
}

# get document_topics by date
sub document_topics {
  my $date = shift;
  my $doc_tops = {};
  $document_topic->execute($date);
  while (my $dt = $document_topic->fetchrow_hashref()) {
    $doc_tops->{$dt->{document_id}}->{$dt->{topic_id}} = $dt->{weight};
  }
  return $doc_tops;
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
      $doc_topic_b,
      $union) = @_;
  
  my $smooth = .000001;
  my $p = 0;
  my $raw = 0;
  my $weighted = 0;
  my $a_raw = 0;
  my $b_raw = 0;
  my $a_w = 0;
  my $b_w = 0;
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
my $documents = [];
my $topics = [];
my $document_topics = [];
my $dates = $dbh->selectall_arrayref(qq|
              select distinct(date) 
              from topic 
              where 
                dataset_id = $dataset_id 
              order by date asc|);
for my $date (@$dates) {
  $date = $date->[0];
  my $fdate = $date; $fdate =~ s/-/_/g;
  next if -e "$config->{docroot}/$config->{name}/$fdate.int";
  
  # status
  print STDERR "$date ...\n";

  # get the topics for the current day and 30 days prior
  unshift @$topics, topic_by_date($date);
  unshift @$documents, document_by_date($date);
  unshift @$document_topics, document_topics($date);
  
  # compare each document for the day to the last 30 days
  my $range = 30; $range = scalar(@$documents) if scalar(@$documents) < 30;
  for (my $i = 0; $i < $range; ++$i) {
    
    print STDERR "\tFind best <doc, doc> intersection in $date to $i...\n";
    
    # find doc-doc intersection - O(n^2)
    my @isect_day;
    for my $doc_a_id (sort keys(%{$documents->[0]})) {
      for my $doc_b_id (sort keys(%{$documents->[$i]})) {
        
        # skip over same day repeats
        next if $i == 0 and $doc_b_id <= $doc_a_id;
        
        # get intersection of terms
        my ($union, $intersection) = ({}, {});
        foreach my $t (keys(%{$documents->[0]->{$doc_a_id}}), keys(%{$documents->[$i]->{$doc_b_id}})) {
          $union->{$t}++ && $intersection->{$t}++;
        }
        
        # disallow perfect matched (means duplicate likely)
        if (scalar(keys(%$intersection)) != scalar(keys(%$union))) {
          push @isect_day, {id => "$doc_a_id,$doc_b_id", weight=>scalar(keys(%$intersection))};
        }
      }
    }
    
    # sort and take top - O(n^2 log(n))
    @isect_day = sort {$b->{weight} <=> $a->{weight}} @isect_day;
    
    # limit O(n)
    my $isect_limit = scalar(keys(%{$document_topics->[0]}));
    
    print STDERR "\tFind best <topic, topic> for best <doc, doc> pairs in $date to $i...\n";
    
    # O(n t^2)
    my @perms_day;
    for my $isect (@isect_day) {
      my ($doc_a_id, $doc_b_id) = split(/,/, $isect->{id});
      
      # compute heuristic score
      for my $topic_a_id (sort keys(%{$document_topics->[0]->{$doc_a_id}})) {
        for my $topic_b_id (sort keys(%{$document_topics->[$i]->{$doc_b_id}})) {
          
          # skip over same day repeats
          next if $i == 0 and $topic_b_id <= $topic_a_id;
        
          my $k = "$doc_a_id,$doc_b_id,$topic_a_id,$topic_b_id";
          push @perms_day, {id => $k,
                            weight => $isect->{weight} *
                                      $document_topics->[0]->{$doc_a_id}->{$topic_a_id}*
                                      $document_topics->[$i]->{$doc_b_id}->{$topic_b_id}};
        }
      }
      last if --$isect_limit == 0;
    }
    
    # use heuristic that sorts weighted intersection - O(t log(t))
    @perms_day = sort { $b->{weight} <=> $a->{weight} } @perms_day;
    
    # limit O(n)
    my $perms_limit = scalar(keys(%{$documents->[0]}));
    
    print STDERR "\tSave best <doc, topic> pairs in $date to $i...\n";
    
    # save only the best edges found
    for my $best_edge (@perms_day) {
      my ($doc_a_id, $doc_b_id, $topic_a_id, $topic_b_id) = split(/,/, $best_edge->{id});
      
      # compute intersection of terms again      
      my ($union, $intersection) = ({}, {});
      foreach my $t (keys(%{$documents->[0]->{$doc_a_id}}),
                     keys(%{$documents->[$i]->{$doc_b_id}})) {
        $union->{$t}++ && $intersection->{$t}++;
      }
      
      # for every term in distribution, add
      compute_edge($doc_a_id,
                   $documents->[0]->{$doc_a_id},
                   $topic_a_id,
                   $topics->[0]->{$topic_a_id},
                   $document_topics->[0]->{$doc_a_id}->{$topic_a_id},
                   $doc_b_id,
                   $documents->[$i]->{$doc_b_id},
                   $topic_b_id,
                   $topics->[$i]->{$topic_b_id},
                   $document_topics->[$i]->{$doc_b_id}->{$topic_b_id},
                   $union);
      
      last if --$perms_limit == 0;
    }
  }
  
  pop @$topics if scalar(@$topics) > 30;
  pop @$documents if scalar(@$documents) > 30;
  pop @$document_topics if scalar(@$document_topics) > 30;
  
  # get the documents
  # drop a trigger file to avoid processing intersection again
  `touch $config->{docroot}/$config->{name}/$fdate.int`;
}
