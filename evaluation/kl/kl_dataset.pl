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
  kl_dataset.pl <conf.yaml> <min-occurence=1>\n\n";
  
  print STDERR "Description:\
  This program calculates divergence of the distribution of terms and entities \
  over time.  The minimum number of occurences a term or entity must occur \
  can be specifed as well.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}
my $min_occurence = $ARGV[1] ? $ARGV[1] : 1;

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
                        where dataset_id = $dataset_id
                        order by published asc|);

my $doc_terms_dataset = $dbh->prepare(qq|
                        select distinct(term_id) as id
                        from document d
                        join document_term dt on (d.id = dt.document_id)
                        where d.dataset_id = $dataset_id|);

my $doc_terms = $dbh->prepare(qq|
                        select *
                        from document_term
                        where document_id = ? and count > ?|);

my $doc_entity_dataset = $dbh->prepare(qq|
                        select e.id, e.type
                        from document d
                        join document_entity de on (d.id = de.document_id)
                        join entity e on (de.entity_id = e.id)
                        where d.dataset_id =  $dataset_id
                        group by entity_id, type|);

my $doc_entities = $dbh->prepare(qq|
                        select *
                        from document_entity
                        join entity on (id = entity_id)
                        where document_id = ? and count >= ?|);

# create output file
my $output = $ARGV[0];
$output =~ s/\.yaml$//;
$output = (split(/\//, $output))[-1];
$output = "$output.dataset.kl";
open FH, ">", $output or error("Failed to create output file: $output");

# compare current distributions, p, to new distributions, q, over time
my $p = {};
my $p_n = {};
my $p_smooth = {};

# initalize distribution with psuedo counts
$doc_terms_dataset->execute();
while (my $dt = $doc_terms_dataset->fetchrow_hashref()) {
  $p->{TERMS}->{$dt->{id}} = 0;
}

# initialize distribution with psuedo counts
$doc_entity_dataset->execute();
while (my $de = $doc_entity_dataset->fetchrow_hashref()) {
  $p->{$de->{type}}->{$de->{id}} = 0;
}
for my $type (keys(%$p)) {
  $p_n->{$type} = 1;
  $p_smooth->{$type} = 1 / scalar(keys(%{$p->{$type}}));
  for my $id (keys(%{$p->{$type}})) {
    $p->{$type}->{$id} = $p_smooth->{$type};
  }
}

# for every document in the dataset in order of timestamp
$docs->execute();

# write header
my @eorder = keys(%$p);
push @eorder, 'TERMS';
print FH 'PUBLISHED,'.join(','. @eorder) . "\n";

my $i=0;
while (my $d = $docs->fetchrow_hashref()) {
  my $q = {};
  my $q_n = {};
  
  # add terms to new distribution 
  $doc_terms->execute($d->{id}, $min_occurence);
  while (my $dt = $doc_terms->fetchrow_hashref()) {
    $q->{TERMS}->{$dt->{term_id}} = $dt->{count};
    $q_n->{TERMS} += $dt->{count};
  }
  
  # add entities to new distribution
  $doc_entities->execute($d->{id}, $min_occurence);
  while (my $de = $doc_entities->fetchrow_hashref()) {
    $q->{$de->{type}}->{$de->{id}} = $de->{count};
    $q_n->{$de->{type}} += $de->{count};
  }
  
  # calculate kl divergence = - sum_x { p(x)log[q(x)] - p(x)log[p(x)] }
  my $kl = {};
  my $kl_val = [];
  for my $type (@eorder) {
    $q_n->{$type} = 0 if !exists($q_n->{$type});
    $kl->{$type} = 0;
    while (my ($k, $v) = each %{$p->{$type}}) {
      my $px = $v / $p_n->{$type};
      my $qx_v = exists($q->{$type}->{$k}) ? $q->{$type}->{$k} + $v : $v;
      my $qx =  $qx_v / ($q_n->{$type} + $p_n->{$type});
      $kl->{$type} += $px*(log($px) - log($qx));
      $p->{$type}->{$k} = $qx_v;
    }
    $p_n->{$type} += $q_n->{$type};
    push @$kl_val, $kl->{$type};
  }
  
  print FH "$d->{published}," . join(',', @$kl_val) . "\n";
  printf "%d\t%f\n", ++$i, $kl_val->[0];
}
close FH;
