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

my $document_date = $dbh->prepare(qq|
                        select d.date, dt.document_id, dt.term_id, dt.count
                        from document d
                        join document_term dt on (d.id =  dt.document_id)
                        where
                          d.dataset_id = $dataset_id and
                          ? = d.date|);

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
  next if -e "$config->{docroot}/$config->{name}/$fdate.tprune";
  
  # status
  print "$date ...\n";
  
  # drop a trigger file to avoid processing topic again
  `touch $config->{docroot}/$config->{name}/$fdate.tprune`;
}
