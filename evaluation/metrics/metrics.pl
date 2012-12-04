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
  metrics.pl <conf.yaml> <topic>\n\n";
  
  print STDERR "Description:\
  This program calculates the metrics of the topics for a given day.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

my $topic = $ARGV[1];
my $thres = .6;
my $topic_thresh = .15;

# create the database handle
my $dbh = DBI->connect(
                    $config->{database},
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");
my $dataset_id = $dbh->selectall_arrayref(qq|
                        select id
                        from dataset
                        where name = '$config->{name}'|)->[0]->[0] or error("No such dataset");


my $topic_neighbors = $dbh->prepare(qq|
                            select *,
                              ta.date as a_date, tb.date as b_date,
                              ta.alpha as a_alpha, tb.alpha as b_alpha
                            from topic_similarity
                            join topic ta on (topic_a = ta.id)
                            join topic tb on (topic_b = tb.id)
                            where topic_a = ? or topic_b = ?|);
my $document_topics = $dbh->prepare(qq|
                            select document_id, weight
                            from document_topic
                            where topic_id = ? and weight > $topic_thresh|);

sub subgraph {
  my $topic = shift;
  my $topic_info = $dbh->selectall_arrayref(qq|select date, alpha from topic where id = $topic|)->[0];
  my $frontier = [{topic=>$topic, weight=>1, date => $topic_info->[0], alpha=>$topic_info->[1]}];
  my $visited = {};
  my $r = [];
  while (scalar(@$frontier)) {
    my $v = shift @$frontier;
    push @$r, $v;
    $topic_neighbors->execute($v->{topic}, $v->{topic});
    while (my $n = $topic_neighbors->fetchrow_hashref()) {
      my $nt = $n->{topic_a} == $v->{topic} ? $n->{topic_b} : $n->{topic_a};
      my $date = $n->{topic_a} == $v->{topic} ? $n->{b_date} : $n->{a_date};
      my $alpha = $n->{topic_a} == $v->{topic} ? $n->{b_alpha} : $n->{a_alpha};
      my $w = $n->{cosign_similarity}*$v->{weight};
      if ($w > $thres and !$visited->{$nt}) {
        push @$frontier, {topic=>$nt, weight=>$w, date=>$date, alpha=>$alpha};
        $visited->{$nt} = 1;
      }
    }
  }
  
  #print "date,topic,weight,n\n";
  my $d = {};
  for my $i (sort {$a->{date} cmp $b->{date}} @$r) {
    $document_topics->execute($i->{topic});
    my $n = 0;
    while (my $dt = $document_topics->fetchrow_hashref()) {
      $n++ if !$d->{$dt->{document_id}};
      $d->{$dt->{document_id}} = 1;
    }
    print "$topic,$i->{date},$i->{topic},$i->{weight},$i->{alpha},$n\n";
  }
}

my $mid = $dbh->prepare(qq|select * from topic where date = '2012-09-01' and dataset_id = $dataset_id|); $mid->execute();
while (my $m = $mid->fetchrow_hashref()) {
  subgraph($m->{id});
}
