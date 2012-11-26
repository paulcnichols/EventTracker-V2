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
  kl_similarity.pl <conf.yaml> <min-date>\n\n";
  
  print STDERR "Description:\
  This program calculates divergence of the distribution of terms and entities \
  over time.  The minimum number of occurences a term or entity must occur \
  can be specifed as well.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) < 1 or !-f $ARGV[0]);
error("No start date provided") if (scalar(@ARGV) < 2 or !($ARGV[1] =~ /\d{4}-\d{2}-\d{2}/));

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}
my $start = $ARGV[1];

# create the database handle
my $dbh = DBI->connect(
                    $config->{database},
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");

my $dataset_id = $dbh->selectall_arrayref(qq|
                        select id
                        from dataset
                        where name = '$config->{name}'|)->[0]->[0] or error("No such dataset");

my $docs = $dbh->prepare(qq|
                    select *
                    from document
                    where
                      dataset_id = $dataset_id and
                      date > '$start' and date < date_add('$start', INTERVAL 14 DAY)|);

my $doc_terms = $dbh->prepare(qq|
                      select term_id, count as c
                      from document_term
                      where document_id = ?|);

my $doc_entities = $dbh->prepare(qq|
                      select entity_id, type, count as c
                      from document_entity de
                      join entity e on (de.entity_id = e.id)
                      where document_id = ?|);

my $docs_neighbors = $dbh->prepare(qq|call neighbors_sim(?, ?, ?, ?)|);
my $docs_neighbors_terms = $dbh->prepare(qq|call neighbors_sim_terms(?, ?, ?, ?)|);
my $docs_neighbors_entities = $dbh->prepare(qq|call neighbors_sim_entities(?, ?, ?, ?)|);

# create output file
my $output = $ARGV[0];
$output =~ s/\.yaml$//;
$output = (split(/\//, $output))[-1];
$output = "$output.similarity.kl";
open FH, ">", $output or error("Failed to create output file: $output");

# data header
my @header = qw(
  ID
  SIMILARITY
  WEIGHT
  MIN_DATE
  MAX_DATE
  NUM_DOCS
  NUM_TOPICS
  N
  TERM
  TERM_IN
  TERM_OUT
  TERM_KL
  NOUN
  NOUN_IN
  NOUN_OUT
  NOUN_KL
  ORGANIZATION
  ORGANIZATION_IN
  ORGANIZATION_OUT
  ORGANIZATION_KL
  LOCATION
  LOCATION_IN
  LOCATION_OUT
  LOCATION_KL
  NAME
  NAME_IN
  NAME_OUT
  NAME_KL);
print FH join(',', @header) . "\n";

# query over a 2 week range, preferably in the middle
$docs->execute();
while (my $d = $docs->fetchrow_hashref()) {
  
  # get current docs terms
  $doc_terms->execute($d->{id});
  
  my $p = {};
  my $p_n = {};
  while (my $t = $doc_terms->fetchrow_hashref()) {
    $p->{TERM}->{$t->{term_id}} += $t->{c};
    $p_n->{TERM} += $t->{c};
  }
  
  # get current docs entities
  $doc_entities->execute($d->{id});

  while (my $e = $doc_entities->fetchrow_hashref()) {
    $p->{$e->{type}}->{$e->{entity_id}} += $e->{c};
    $p_n->{$e->{type}} += $e->{c};
  }

  # for the various threshold levels, compute delta distributions
  for (my $similarity=.5; $similarity <= .9; $similarity += .1) {
    my $skip = 0;
    for (my $weight = .1; $weight <=.9; $weight += .1) {
      # query for neighbors if last query returned results
      my $n = 0;
      my $min = $start;
      my $max = $start;
      my $docs = {};
      my $topics = {};
      if (!$skip) {
        
        # perform query for neighors and save useful bits
        $docs_neighbors->execute($d->{id}, $d->{published}, $similarity, $weight);
        
        while (my $dn = $docs_neighbors->fetchrow_hashref()) {
          $min = $dn->{date} if (($dn->{date} cmp $min) < 0);
          $max = $dn->{date} if (($dn->{date} cmp $max) > 0);
          $docs->{$dn->{document_id}} += 1;
          $topics->{$dn->{topic_a}} += 1;
          $topics->{$dn->{topic_b}} += 1;
          $n = $n + 1;
        }
        
        if ($n == 0) {
          $skip = 1;
        }
      }
      my $r = {ID => $d->{id},
               SIMILARITY=>$similarity,
               WEIGHT=>$weight,
               MIN_DATE=>$min,
               MAX_DATE=>$max,
               NUM_DOCS => scalar(keys(%$docs)),
               NUM_TOPICS => scalar(keys(%$topics)),
               N=>$n};
      
      # no results, stub out row
      if ($skip) {
        for my $k (@header) {
          $r->{$k} = 0 if !exists($r->{$k});
        }
      }
      # results found, compute divergence measures
      else {
        my $q = {};
        my $q_n = {};
        
        $docs_neighbors_terms->execute($d->{id}, $d->{published}, $similarity, $weight);
        
        while (my $dnt = $docs_neighbors_terms->fetchrow_hashref()) {
          $q->{TERM}->{$dnt->{term_id}} += $dnt->{c};
          $q_n->{TERM} += $dnt->{c};
        }
        
        $docs_neighbors_entities->execute($d->{id}, $d->{published}, $similarity, $weight);
        
        while (my $dne = $docs_neighbors_entities->fetchrow_hashref()) {
          $q->{$dne->{type}}->{$dne->{entity_id}} += $dne->{c};
          $q_n->{$dne->{type}} += $dne->{c};
        }

        for my $type (qw(TERM NOUN ORGANIZATION LOCATION NAME)) {
          $q_n->{$type} = 0 if (!exists($q_n->{$type}));
          $p_n->{$type} = 0 if (!exists($p_n->{$type}));
          $r->{$type} = scalar(keys(%{$p->{$type}}));
          for my $q_type (keys(%{$q->{$type}})) {
            if (!exists($p->{$type}) or !exists($p->{$type}->{$q_type}) ) {
              $r->{$type.'_OUT'} += 1;
            }
            else {
              $r->{$type.'_IN'} += 1;
            }
          }
          $r->{$type.'_OUT'} ||= 0;
          $r->{$type.'_IN'} ||= 0;
          
          # very nasty computation of kl divergence.  give every term a psuedo count
          my $psuedo = 1 /  ($r->{$type} + $r->{$type.'_OUT'});
          my $kl = 0;
          for my $p_type (keys(%{$p->{$type}})) {
            my $pt = ($p->{$type}->{$p_type} + $psuedo) / ($p_n->{$type} + 1);
            my $qt = $psuedo;
            if (exists($q->{$type}) and exists($q->{$type}->{$p_type})) {
              $qt  = ($qt + $q->{$type}->{$p_type}) / ($q_n->{$type} + 1);
            }
            else {
              $qt  = ($qt) / ($q_n->{$type} + 1);
            }
            $kl += $pt*log($pt) - $pt*log($qt);
          }
          for my $q_type (keys(%{$q->{$type}})) {
            my $qt = ($q->{$type}->{$q_type} + $psuedo) / ($q_n->{$type} + 1);
            my $pt = $psuedo;
            if (exists($p->{$type}) and exists($p->{$type}->{$q_type})) {
              $pt  = ($pt + $p->{$type}->{$q_type}) / ($p_n->{$type} + 1);
            }
            else {
              $pt  = ($pt) / ($p_n->{$type} + 1);
            }
            $kl += $pt*log($pt) - $pt*log($qt);
          }
          $r->{$type.'_KL'} = $kl;
        }
      }
      printf "%d %f %f %d\n", $r->{ID}, $r->{SIMILARITY}, $r->{WEIGHT}, $r->{N};
    
      my @h;
      for my $k (@header) {
        push @h, $r->{$k} || 0;
      }
      print FH join(',', @h) . "\n";
    }
  }
}

close FH;