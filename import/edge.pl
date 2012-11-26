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
  edge.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  This program attempts to create edges between documents.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

my $DAYS = 15;

# create the database handle
my $dbh = DBI->connect(
                    $config->{database},
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");
my $dataset_id = $dbh->selectall_arrayref(qq|
                        select id
                        from dataset
                        where name = '$config->{name}'|)->[0]->[0] or error("No such dataset");
my $topic_sim = $dbh->prepare(qq|
                        insert into topic_similarity
                        (topic_a, topic_b, cosign_similarity) values
                        (?, ?, ?)|);
my $document_sim = $dbh->prepare(qq|
                        insert into document_similarity
                        (document_a, document_b, cosign_similarity) values
                        (?, ?, ?)|);
my $topic_date = $dbh->prepare(qq|
                        select t.date, tt.topic_id, tt.term_id, tt.beta
                        from topic t
                        join topic_term tt on (t.id =  tt.topic_id)
                        where
                          t.dataset_id = $dataset_id and
                          ? >= t.date and
                          t.date > date(date_sub(?, interval $DAYS DAY))|);
my $document_date = $dbh->prepare(qq|
                        select d.date, dt.document_id, dt.term_id, dt.count
                        from document d
                        join document_term dt on (d.id =  dt.document_id)
                        where
                          d.dataset_id = $dataset_id and
                          ? >= d.date and
                          d.date > date(date_sub(?, interval $DAYS DAY))|);
sub topic_window {
  my $date = shift;
  my $topics = {};
  $topic_date->execute($date, $date);
  while (my $t = $topic_date->fetchrow_hashref()) {
    $topics->{$t->{date}}->{$t->{topic_id}}->{$t->{term_id}} = $t->{beta};
  }
  return $topics;
}
sub document_window {
  my $date = shift;
  my $documents = {};
  $document_date->execute($date, $date);
  while (my $t = $document_date->fetchrow_hashref()) {
    $documents->{$t->{date}}->{$t->{document_id}}->{$t->{term_id}} = $t->{count};
  }
  return $documents;
}

sub cosign_similarity {
  my ($id_a, $beta_a, $id_b, $beta_b) = @_;
  my $union={};
  my $dot = 0.0;
  my $norm_a = 0.0;
  my $norm_b = 0.0;
  my $similarity = 0.0;
  for my $term (keys(%$beta_a)) {
    if (exists($beta_b->{$term})) {
      $union->{$term} = 1;
      $dot += $beta_a->{$term} * $beta_b->{$term};
    }
    $norm_a += $beta_a->{$term}**2
  }
  $norm_a = sqrt($norm_a);
  for my $term (keys(%$beta_b)) {
    $norm_b += $beta_b->{$term}**2
  }
  $norm_b = sqrt($norm_b);
  $similarity = $dot / ($norm_a * $norm_b);
  return $similarity
}

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
  next if -e "$config->{docroot}/$config->{name}/$fdate.tsim";
  
  # status
  print "$date ...\n";

  # get the topics for the current day and X days prior
  my $topics = topic_window($date);
  
  # compute similarity between topics
  print "Computing distance...\n";
  my $curr = delete($topics->{$date});
  for my $topic_a (keys(%$curr)) {
    for my $prev (sort keys(%$topics)) {
      for my $topic_b (keys(%{$topics->{$prev}})) {
        my $s = cosign_similarity($topic_a, $curr->{$topic_a}, $topic_b, $topics->{$prev}->{$topic_b});        
        $topic_sim->execute($topic_a, $topic_b, $s) if $s > .3;
      }
    }
  }
  
  # drop a trigger file to avoid processing topic again
  `touch $config->{docroot}/$config->{name}/$fdate.tsim`;
}

# now do document similarity
$dates = $dbh->selectall_arrayref(qq|
              select distinct(date) 
              from document 
              where 
                dataset_id = $dataset_id 
              order by date asc|);
for my $date (@$dates) {
  $date = $date->[0];
  my $fdate = $date; $fdate =~ s/-/_/g;
  next if -e "$config->{docroot}/$config->{name}/$fdate.dsim";
  
  # status
  print "Doc $date ...\n";

  # get the documents for the current day and X days prior
  my $documents = document_window($date);
  
  $dbh->{AutoCommit} = 0;
  
  # remove current day
  print "Computing distance...\n";
  my $curr = delete($documents->{$date});
  for my $document_a (sort keys(%$curr)) {
    for my $day (reverse sort keys(%$documents)) {
      for my $document_b (sort keys(%{$documents->{$day}})) {
        my $s = cosign_similarity($document_a,
                                  $curr->{$document_a},
                                  $document_b,
                                  $documents->{$day}->{$document_b});
        $dbh->do(sprintf(qq|insert into document_similarity
                        (document_a, document_b, cosign_similarity) values
                        (%d, %d, %f)|, $document_a, $document_b, $s)) if $s > .3;
      }
    }
  }
  $dbh->commit();
  $dbh->{AutoCommit} = 1;
  
  # drop a trigger file to avoid processing topic again
  `touch $config->{docroot}/$config->{name}/$fdate.dsim`;
}