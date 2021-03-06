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
  topic_fit.pl <conf.yaml> <date> <database=events>\n\n";
  
  print STDERR "Description:\
  Run stats on the topic job.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) < 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

error("No date provided!") if scalar(@ARGV) < 2 or !($ARGV[1] =~ /\d{4}-\d{2}-\d{2}/);
my $date = $ARGV[1];
my $database = $ARGV[2] || 'events';

# create the database handle
my $dbh = DBI->connect(
                    "DBI:mysql:$database;host=localhost",
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");

my $dataset_id = $dbh->selectall_arrayref(qq|
                        select id
                        from dataset
                        where name = '$config->{name}'|)->[0]->[0] or error("No such dataset");

my $topics = $dbh->prepare(qq|
                        select *
                        from topic_term tt
                        join topic tp on (tt.topic_id = tp.id)
                        join term t on (tt.term_id = t.id)
                        where tp.dataset_id = $dataset_id and tp.date = '$date'|);

#my $entities = $dbh->prepare(qq|
#                        select e.str, type
#                        from topic_term tt
#                        join topic tp on (tt.topic_id = tp.id)
#                        join term t on (tt.term_id = t.id)
#                        straight_join entity e on (t.str = e.str)
#                        where tp.dataset_id = $dataset_id and tp.date = '$date' and e.type != 'NOUN'|);
#
#$entities->execute();
#
#my $entity_map = {};
#while (my $e = $entities->fetchrow_hashref()) {
#  $entity_map->{$e->{str}}->{$e->{type}} = 1;
#}

$topics->execute();

my $topic_dist = {};
my $topic_types = {};
my $topic_weight = {};
while (my $t = $topics->fetchrow_hashref()) {
  $topic_dist->{$t->{topic_id}}->{$t->{str}} = $t->{beta};
  $topic_weight->{$t->{topic_id}} = $t->{alpha};
}
for my $t_id (sort {$topic_weight->{$b} <=> $topic_weight->{$a}} keys(%$topic_weight)) {
  my $total = 0;
  for my $w (keys(%{$topic_dist->{$t_id}})) {
    $total += $topic_dist->{$t_id}->{$w};
  }
  for my $w (keys(%{$topic_dist->{$t_id}})) {
    $topic_dist->{$t_id}->{$w} /= $total;
    #if ($entity_map->{$w}) {
    #  for my $tt (keys(%{$entity_map->{$w}})) {        
    #    $topic_types->{$t_id}->{$tt} += $topic_dist->{$t_id}->{$w};
    #  }
    #}
  }
  
  my @strs;
  for my $tt (sort {$topic_dist->{$t_id}->{$b} <=> $topic_dist->{$t_id}->{$a}} keys(%{$topic_dist->{$t_id}})) {
    push @strs, $tt; #sprintf("%s,%f", $tt, $topic_dist->{$t_id}->{$tt});
    last if scalar(@strs) > 10;
  }
  printf "%s,%d,%s\n", $topic_weight->{$t_id}, $t_id, join(' ', @strs);
}

