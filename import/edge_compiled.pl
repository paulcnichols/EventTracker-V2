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
my $min_dist = .3;

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

  $dbh->{AutoCommit} = 0;
  
  # read similarities from pipes STDOUT until done
  while (<FH_OUT>) {
    chomp;
    my ($topic_a, $topic_b, $s) = split(/,/);
    $topic_sim->execute($topic_a, $topic_b, $s);
  }
  close FH_OUT;
  
  $dbh->commit();
  $dbh->{AutoCommit} = 1;
  
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
    
  open2(*FH_OUT, *FH_IN, "java -Xmx4g -jar $config->{binroot}/import/distance/distance.jar $min_dist");

  # compute similarity between documents
  print "Computing distance...\n";
  my $date_id = 0;
  for my $date (reverse sort keys(%$documents)) {
    for my $doc (keys(%{$documents->{$date}})) {
      my $f =  join " ", map { "$_:$documents->{$date}->{$doc}->{$_}"} keys(%{$documents->{$date}->{$doc}});
      printf FH_IN "%d,%d,%s\n", $date_id, $doc, $f;
    }
    $date_id++;
  }
  close FH_IN;
  
  $dbh->{AutoCommit} = 0;

  # read similarities from pipes STDOUT until done
  while (<FH_OUT>) {
    chomp;
    my ($document_a, $document_b, $s) = split(/,/);
    $document_sim->execute($document_a, $document_b, $s);
  }
  close FH_OUT;
  
  $dbh->commit();
  $dbh->{AutoCommit} = 1;
  
  # drop a trigger file to avoid processing topic again
  `touch $config->{docroot}/$config->{name}/$fdate.dsim`;
}
