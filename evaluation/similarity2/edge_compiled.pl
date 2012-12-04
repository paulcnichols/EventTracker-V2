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
  edge.pl <conf.yaml> <date>\n\n";
  
  print STDERR "Description:\
  This program attempts to create edges between documents.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 2 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

my $DAYS = 15;
my $min_dist = -1;
my $date = $ARGV[1];

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
                        select t.date, tt.topic_id, tt.term_id, tt.beta
                        from topic t
                        join topic_term tt on (t.id =  tt.topic_id)
                        where
                          t.dataset_id = $dataset_id and
                          ? >= t.date and
                          t.date > date(date_sub(?, interval $DAYS DAY))|);
sub topic_window {
  my $date = shift;
  my $topics = {};
  $topic_date->execute($date, $date);
  while (my $t = $topic_date->fetchrow_hashref()) {
    $topics->{$t->{date}}->{$t->{topic_id}}->{$t->{term_id}} = $t->{beta};
  }
  return $topics;
}

# get the topics for the current day and X days prior
my $topics = topic_window($date);

open2(*FH_OUT, *FH_IN, "java -Xmx4g -jar $config->{binroot}/import/distance/distance.jar $min_dist");

# compute similarity between topics
print "Computing distance...\n";
my $date_id = 0;
for my $date (reverse sort keys(%$topics)) {
  for my $top (keys(%{$topics->{$date}})) {
    my $f =  join " ", map { "$_:$topics->{$date}->{$top}->{$_}"} keys(%{$topics->{$date}->{$top}});
    printf FH_IN "%d,%d,%s\n", $date_id, $top, $f;
  }
  $date_id++;
}
close FH_IN;

  
# read similarities from pipes STDOUT until done
while (<FH_OUT>) {
  chomp;
  my ($topic_a, $topic_b, $s) = split(/,/);
  print "$topic_a, $topic_b, $s\n";
}
close FH_OUT;
