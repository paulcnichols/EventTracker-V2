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
  import.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  This program imports document data, as well as extracted NLP and topic \
  information, into a database for viewing by the portal.  It is advisable \
  to avoid looking at the source code as its a nasty pile of crap.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(database database_user database_password database_root docroot name binroot)) {  
  error("Missing field '$f'") if !exists($config->{$f});
}

# load the stoplists from the topic extraction
my $stopwords = {};
open FH, $config->{binroot}.'/transform/topic/stoplists/en.txt' and do {
  while (<FH>) {
    chomp;
    $stopwords->{$_} = 1;
  }
  close FH;
};

# create the database handle
my $dbh = DBI->connect(
                    $config->{database},
                    $config->{database_user},
                    $config->{database_password}) or error("Cannot connect to database");

# prepare some commonly used queries for speed
my $term_select = $dbh->prepare(qq|select * from term where str = ?|);
my $term_insert = $dbh->prepare(qq|insert into term (str) values(?)|);
my $entity_select = $dbh->prepare(qq|select * from entity where str = ? and type = ?|);
my $entity_insert = $dbh->prepare(qq|insert into entity (str, type) values(?, ?)|);
my $doc_term_insert = $dbh->prepare(qq|insert into document_term (document_id, term_id, count) values (?, ?, ?) on duplicate key update count = count + ?|);
my $doc_entity_insert = $dbh->prepare(qq|insert into document_entity (document_id, entity_id, count) values (?, ?, ?) on duplicate key update count = count + ?|);
my $doc_insert = $dbh->prepare(qq|insert into document (title, url, dataset_id, published, date) values (?, ?, ?, ?, date(from_unixtime(?)))|);
my $topic_insert = $dbh->prepare(qq|insert into topic (dataset_id, date, alpha) values (?, ?, ?)|);
my $topic_term_insert = $dbh->prepare(qq|insert into topic_term (topic_id, term_id, beta) values (?, ?, ?)|);
my $doc_topic_insert = $dbh->prepare(qq|insert into document_topic (document_id, topic_id, weight) values (?, ?, ?)|);
my $term_cache = {};
sub term_to_id {
  my $t = shift;
  return $term_cache->{$t} if exists($term_cache->{$t});
  $term_select->execute($t);
  my $term_id = $term_select->fetchrow_hashref();
  if (!$term_id) {
    $term_insert->execute($t);
    $term_id = $dbh->{mysql_insertid};
  }
  else {
    $term_id = $term_id->{id};
  }
  $term_cache->{$t} = $term_id;
  return $term_id;
}
my $entity_cache = {};
sub entity_to_id {
  my ($e, $t) = @_;
  return $entity_cache->{"$e-$t"} if exists($entity_cache->{"$e-$t"});
  $entity_select->execute($e, $t);
  my $entity_id = $entity_select->fetchrow_hashref();
  if (!$entity_id) {
    $entity_insert->execute($e, $t);
    $entity_id = $dbh->{mysql_insertid};
  }
  else {
    $entity_id = $entity_id->{id};
  }
  $entity_cache->{"$e-$t"} = $entity_id;
  return $entity_id;
}
sub dataset_to_id {
  my $name = shift;
  my $dataset_id = $dbh->selectrow_hashref(qq|select * from dataset where name = '$name'|);
  if (!$dataset_id) {
    $dbh->prepare(qq|insert into dataset (name) values ('$name')|)->execute();
    $dataset_id = $dbh->{mysql_insertid};
  }
  else {
    $dataset_id = $dataset_id->{id};
  }
  return $dataset_id;
}

# get a dataset id
my $dataset_id = dataset_to_id($config->{name});

# use the topic data files as the trigger mechanism because they are the last to be created
for my $f (glob($config->{docroot} . '/' . $config->{name} . '/*.alpha')) {
  my $dir = $f; $dir =~ s/\.alpha$//;
  my $alpha = $f;
  my $beta = "$dir.beta";
  my $date = (split(/\//, $dir))[-1]; $date =~ s/_/-/g;
  
  # use presense of topics as indicator of previously inserted date
  my $topics = $dbh->selectall_arrayref(qq|select * from topic where dataset_id = $dataset_id and date='$date'|);
  next if scalar(@$topics);
  
  # status
  print "Importing $date...\n";

  # load the alpha distribution
  my $topic_map = {};
  open TOPICS, $alpha and do {
    while (<TOPICS>) {
      chomp;
      my ($t, $alpha) = split(/, /);
      $topic_insert->execute($dataset_id, $date, $alpha);
      $topic_map->{$t} = $dbh->{mysql_insertid};
    }
    close TOPICS;
  };
  
  # load the beta distribution
  open BETA, $beta and do {
    while (<BETA>) {
      chomp;
      my ($topic, $term, $weight) = split(/, /);
      $topic_term_insert->execute($topic_map->{$topic}, term_to_id($term), $weight);
    }
  };
  
  # import the documents
  for my $bow (glob("$dir/*.bow")) {
    my $yaml = $bow;
    $yaml =~ s/\.bow$//;
    my $document = LoadFile($yaml);
    $document->{dataset_id} = $dataset_id;
    
    # add the document
    $doc_insert->execute($document->{title},
                         $document->{url},
                         $document->{dataset_id},
                         $document->{published},
                         $document->{published});
    my $document_id = $dbh->{mysql_insertid};
    
    # read document terms
    my $terms = {};
    open BOW, $bow and do {
      while (<BOW>) {
        chomp;
        my ($t, $f) = split(/\t/);
        $t = lc($t);
        $terms->{$t} += $f if !exists($stopwords->{$t}) and !($t =~ /^\d+$/);
      }
      close BOW;
    };
    
    # add document_terms
    for my $t (keys(%$terms)) {
      $doc_term_insert->execute($document_id, term_to_id($t), $terms->{$t}, $terms->{$t});
    }
    
    # read entities
    my $entities = {};
    open NOUNS, $yaml . '.txt.nouns' and do {
      while (my $e = <NOUNS>) {
        chomp($e);
        $e = lc($e);
        $e =~ s/[^A-Za-z ]//g;
        next if !length($e);
        $entities->{$e}->{NOUN} += 1;
      }
      close NOUNS;
    };
    open NAMES, $yaml . '.txt.names' and do {
      while (my $e = <NAMES>) {
        $e = lc($e);
        $e =~ s/[^A-Za-z ]//g;
        next if !length($e);
        $entities->{$e}->{NAME} += 1;
      }
      close NAMES;
    };
    open ORGS, $yaml . '.txt.orgs' and do {
      while (my $e = <ORGS>) {
        $e = lc($e);
        $e =~ s/[^A-Za-z ]//g;
        next if !length($e);
        $entities->{$e}->{ORGANIZATION} += 1;
      }
      close ORGS;
    };
    open LOCS, $yaml . '.txt.locs' and do {
      while (my $e = <LOCS>) {
        $e = lc($e);
        $e =~ s/[^A-Za-z ]//g;
        next if !length($e);
        $entities->{$e}->{LOCATION} += 1;
      }
      close LOCS;
    };
    
    # add document_entities
    for my $e (keys(%$entities)) {
      for my $t (keys(%{$entities->{$e}})) {
        $doc_entity_insert->execute($document_id,
                                    entity_to_id($e, $t),
                                    $entities->{$e}->{$t},
                                    $entities->{$e}->{$t});
      }
    }
    
    # read the document topics
    open TOPICS, $yaml . '.txt.topics' and do {
      while (<TOPICS>) {
        chomp;
        my ($topic, $weight) = split(/, /);
        $doc_topic_insert->execute($document_id, $topic_map->{$topic}, $weight);
      }
      close TOPICS;
    };
  }
}

