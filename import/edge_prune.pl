use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use DBIx::Wrapper;
use Proc::PidUtil qw(is_running);
use FileHandle;
use IPC::Open2;
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  edge_prune.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  This program attempts to calculate a score for topics to prune them if necissary.\n";
  
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

my $topic_date = $dbh->prepare(qq|
                        select *
                        from topic_term
                        join topic on (topic_id = id)
                        where date = ? and dataset_id = $dataset_id|);

my $topic_filter = $dbh->prepare(qq|insert ignore into topic_prune (topic_id) values (?)|);

my $filter_threshold = .6;

sub topic_by_date {
  my $date = shift;
  $topic_date->execute($date);
  my $topics = {};
  while (my $t = $topic_date->fetchrow_hashref()) {
    $topics->{$t->{topic_id}}->{$t->{term_id}} = $t->{beta};
  }
  return $topics;
}

sub topics_to_prune {
  my $tp = $dbh->prepare(qq|
                  select *
                  from topic_term
                  join topic_prune_start using(topic_id)|);
  $tp->execute();
  my $topics_prune = {};
  while (my $t = $tp->fetchrow_hashref()) {
    $topics_prune->{$t->{topic_id}}->{$t->{term_id}} = $t->{beta};
  }
  return $topics_prune;
}

sub cosign_similarity {
  my ($topic_a,
      $topic_a_weights,
      $topic_b,
      $topic_b_weights,
      $thresh) = @_;
  
  my $n = 0;
  my $a_norm = 0;
  my $b_norm = 0;
  for my $t (keys(%$topic_a_weights)) {
    if (exists($topic_b_weights->{$t})) {
      $n += $topic_a_weights->{$t}*$topic_b_weights->{$t};
    }
    $a_norm += $topic_a_weights->{$t}**2;
  }
  $a_norm = sqrt($a_norm);
  for my $t (keys(%$topic_b_weights)) {
    $b_norm += $topic_b_weights->{$t}**2;
  }
  $b_norm = sqrt($b_norm);
  $n = $n / ($a_norm * $b_norm);
  if ($n > $thresh) {
    $topic_filter->execute($topic_b);
  }
}

my $prune_start = topics_to_prune();

# first do topic similarity
my $dates = $dbh->selectall_arrayref(qq|
              select distinct(date) 
              from topic 
              where 
                dataset_id = $dataset_id 
              order by date asc|);
for my $date (@$dates) {
  $date = $date->[0];
  my $fdate = $date; $fdate =~ s/-/_/g;
  #next if -e "$config->{docroot}/$config->{name}/$fdate.tprune";
  
  # status
  print "$date ...\n";

  my $topics = topic_by_date($date);
  for my $a (keys(%$prune_start)) {
    for my $b (keys(%$topics)) {
      cosign_similarity($a, $prune_start->{$a}, $b, $topics->{$b}, $filter_threshold);
    }
  }
  
  # drop a trigger file to avoid processing topic again
  #`touch $config->{docroot}/$config->{name}/$fdate.tprune`;
}
