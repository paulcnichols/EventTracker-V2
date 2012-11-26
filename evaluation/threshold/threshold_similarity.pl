use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use DBIx::Wrapper;
use Proc::PidUtil qw(is_running);
use Time::HiRes qw(time);
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  threshold_similarity.pl <conf.yaml> <min-date>\n\n";
  
  print STDERR "Description:\
  This program calculates the change in a few key values at differing thresholds \
  to aid setting the optimal one.\n";
  
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

my $docs_neighbors = $dbh->prepare(qq|call neighbors_sim(?, ?, ?, ?)|);
my $docs_neighbors_terms = $dbh->prepare(qq|call neighbors_sim_terms(?, ?, ?, ?)|);
my $docs_neighbors_entities = $dbh->prepare(qq|call neighbors_sim_entities(?, ?, ?, ?)|);

# create output file
my $output = $ARGV[0];
$output =~ s/\.yaml$//;
$output = (split(/\//, $output))[-1];
$output = "$output.similarity.thresh";
open FH, ">", $output or error("Failed to create output file: $output");

# data header
my @header = qw(
  ID
  SIMILARITY
  WEIGHT
  MIN_DATE
  MAX_DATE
  NUM_DOCS
  ENT_DOCS
  NUM_TOPICS
  ENT_TOPICS
  N);
print FH join(',', @header) . "\n";

my $MIN_SIMILARITY = .70;
my $MIN_WEIGHT = .15;
my $STEP = .025;
my $DATE_LIMIT = 50;
my $DATES = {};

# query over a 2 week range, preferably in the middle
$docs->execute();
while (my $d = $docs->fetchrow_hashref()) {
  
  # sample the documents by date
  $DATES->{$d->{date}} += 1;
  next if ($DATES->{$d->{date}} > $DATE_LIMIT);
  
  my $start_time = time();

  # perform query for neighors and save useful bits
  $docs_neighbors->execute($d->{id}, $d->{published}, $MIN_SIMILARITY, $MIN_WEIGHT);
  
  my @neighbors;
  while (my $dn = $docs_neighbors->fetchrow_hashref()) {
    push @neighbors, $dn;
  }
  @neighbors = sort {$a->{cosign_similarity} <=> $b->{cosign_similarity} ||
                     $a->{weight_a} <=> $b->{weight_a} ||
                     $a->{weight_b} <=> $b->{weight_b}} @neighbors;
  
  # for the various threshold levels, compute delta distributions
  my $sim_i = 0;
  for (my $similarity=$MIN_SIMILARITY; $similarity < 1; $similarity += $STEP) {
    
    # find first position of greater cosign similarity
    for (my $i=$sim_i; $i < scalar(@neighbors); ++$i) {
      if ($neighbors[$i]->{cosign_similarity} > $similarity) {
        $sim_i = $i;
        last;
      }
    }
    
    my $weight_i = $sim_i;
    for (my $weight = $MIN_WEIGHT; $weight < 1; $weight += $STEP) {
          
      # find first position of greater weight
      for (my $i=$weight_i; $i < scalar(@neighbors); ++$i) {
        if ($neighbors[$i]->{weight_a} >= $weight and $neighbors[$i]->{weight_b} >= $weight) {
          $weight_i = $i;
          last;
        }
      }
      
      my $min = $start;
      my $max = $start;
      my $documents = {};
      my $topics = {};
      my $N = 0;
      for (my $i=$weight_i;  $i < scalar(@neighbors); ++$i) {
        my $n = $neighbors[$i];
        $min = $n->{date} if ($n->{date} cmp $min) < 0;
        $max = $n->{date} if ($n->{date} cmp $max) > 0;
        $documents->{$n->{document_id}} += 1;
        $topics->{$n->{topic_a}} += 1;
        $topics->{$n->{topic_b}} += 1;
        $N += 1;
      }
      my $document_entropy = 0;
      my $topic_entropy = 0;
      if ($N > 0) {
        for my $d (keys(%$documents)) {
          my $p = $documents->{$d} / $N;
          $document_entropy -= $p * log($p); 
        }
        for my $t (keys(%$topics)) {
          my $p = $topics->{$t} / $N;
          $topic_entropy -= $p * log($p);
        }
      }
      printf FH "%d,%f,%f,%s,%s,%d,%f,%d,%f,%d\n",
                    $d->{id},
                    $similarity,
                    $weight,
                    $min,
                    $max,
                    scalar(keys(%$documents)),
                    $document_entropy,
                    scalar(keys(%$topics)),
                    $topic_entropy,
                    $N;
    }
  }
  printf "%d completed in %f seconds over %d documents.\n", $d->{id}, time() - $start_time, scalar(@neighbors);
}
close FH;