package Cloud;
use Dancer::Plugin::Database;
use Cache::Memcached;

# Save expensive database queries in memcache
my $cache = Cache::Memcached->new(servers=>['localhost:11211']);

#
# Get list of valid dates
#
sub get_dates {
  my $dataset_id = shift;
  my $sth = database->prepare(qq|
                        select distinct(date)
                        from topic
                        where dataset_id = $dataset_id
                        order by date asc|);
  $sth->execute();
  my $dates = [];
  while (my $d = $sth->fetchrow_hashref()) {
    push @$dates, $d->{date};
  }
  return $dates;
}

#
# Get ranking of topic weights by similarity
#
sub get_topic_weights {
  my $dataset_id = shift;
  my $date = shift;
  
  my $topic_sim_key = "$dataset_id-$date-topic-sim";
  my $topic_sim = $cache->get($topic_sim_key);
  if (!$topic_sim) {
    # get topic weights by sum of similarities with other topics
    my $sth = database->prepare(qq|select id, sum(cosign_similarity) as weight
                                    from (
                                      select t.id, cosign_similarity 
                                      from topic t
                                      join topic_similarity_all ts on (t.id = topic_a)
                                      where dataset_id = $dataset_id and date = '$date'
                                    union
                                      select t.id, cosign_similarity
                                      from topic t
                                      join topic_similarity_all ts on (t.id = topic_b)
                                      where dataset_id = $dataset_id and date = '$date'
                                    ) s
                                    group by id 
                                    order by weight desc|);
    $sth->execute();
    while (my $t = $sth->fetchrow_hashref()) {
      $topic_sim->{$t->{id}} = $t->{weight};
    }
    $cache->set($topic_sim_key, $topic_sim);
  }
  return $topic_sim;
}

#
# Get topic ids and prior by date
#
sub get_topics_by_date {
  my $dataset_id = shift;
  my $date = shift;
  
  my $topic_key = "$dataset_id-$date-topics";
  my $topics = $cache->get($topic_key);
  if (!$topics) {
    # get the top 5 topics
    my $sth = database->prepare(qq|select id as topic_id, alpha
                                   from topic t
                                   where dataset_id = $dataset_id and date = '$date'|);
    $sth->execute();
    $topics = {};
    while (my $t = $sth->fetchrow_hashref()) {
      $topics->{$t->{topic_id}} = {alpha => $t->{alpha}};
    }
    $cache->set($topic_key, $topics);
  }
  return $topics;
}

#
# Get topic terms
#
sub get_topic_terms {
  my $topic = shift;
  
  my $topic_key = "topic-terms-$topic";
  my $topic_terms = $cache->get($topic_key);
  if (!$topic_terms) {
    my $sth = database->prepare(qq|select str, beta
                                   from topic_term tt
                                   join term t on (tt.term_id = t.id)
                                   where tt.topic_id = $topic|);
    $sth->execute();
    $topic_terms = [];
    while (my $tt = $sth->fetchrow_hashref()) {
      push @$topic_terms, $tt->{str};
    }
  }
  return $topic_terms;
}

#
# Get documents for a topic
#
sub get_topic_documents {
  my $topic = shift;
  my $document_key = "topic-documents-$topic";
  my $documents = $cache->get($document_key);
  if (!$documents) {
    my $sth = database->prepare(qq|select * 
                                  from document d
                                  join document_topic_all dt on (d.id = dt.document_id)
                                  where
                                    dt.topic_id = $topic and
                                    dt.weight > .05
                                  order by weight desc|);
    $sth->execute();
    $documents = [];
    while (my $d = $sth->fetchrow_hashref()) {
      push @$documents, $d;
    }
    $cache->set($document_key, $documents);
  }
  return $documents;
}

#
# Given a topic, return similar topics
#
sub get_similar_topics {
  my $topic = shift;
  
  # get topics similar to passed in topic
  my $sim_topic_k = "similar-topics-$topic";
  my $sim_topic = $cache->get($sim_topic_k);
  if (!$sim_topic) {
    my $sth = database->prepare(qq|
                      select
                        if(a.id = $topic, b.id, a.id) as id,
                        if(a.id = $topic, b.date, a.date) as date,
                        cosign_similarity as weight
                      from topic_similarity
                      join topic a on (topic_a = a.id)
                      join topic b on (topic_b = b.id) 
                      where topic_a = $topic or topic_b = $topic
                      order by date asc|);
    $sth->execute();
    $sim_topic = [];
    while (my $t = $sth->fetchrow_hashref()) {
      push @$sim_topic, $t;
    }
    $cache->set($sim_topic_k, $sim_topic);
  }
  return $sim_topic;
}

sub do {
  my $name = shift;
  my $offset = shift || 0;
  my $dataset_id = database->quick_select('dataset', {name => $name})->{id};

  # get dates to choose from
  my $dates = get_dates($dataset_id);
  return {} if ($offset > scalar(@$dates));

  my $topics_k = "$dataset_id-$dates->[$offset]-topics-full";
  my $topics = $cache->get($topics_k);
  if (!$topics) {
    # get topic ranking
    my $topic_sim = get_topic_weights($dataset_id, $dates->[$offset]);
    
    # get topic terms
    $topics = get_topics_by_date($dataset_id, $dates->[$offset]);
    
    # get top terms for each topic
    for my $t (keys(%$topics)) {
      $topics->{$t}->{words} = [@{get_topic_terms($t)}[0..9]];
      $topics->{$t}->{weight} = $topic_sim->{$t} || 0;
    }
    $cache->set($topics_k, $topics);
  }
  return {offset => $offset,
          date => $dates->[$offset],
          topics => $topics};
}

sub do_topic {
  my $name = shift;
  my $topic = shift;
  my $dataset_id = database->quick_select('dataset', {name => $name})->{id};
  
  my $neighbors_k = "similar-topics-$topic-all";
  my $neighbors = $cache->get($neighbors_k);
  if (!$neighbors) {
    
    # get dates to choose from
    my $dates = get_dates($dataset_id);
    
    # get current topic
    my $current = database->quick_select('topic', {id=>$topic});
    $current->{weight} = 1.0;
    
    # get similar topics
    my $similar_topics = get_similar_topics($topic);
    
    # format topics into nice windowed format
    $neighbors = [];
    for my $d (@$dates) {
      push @$neighbors, {date => $d, topics=>[]};
      if ($d eq $current->{date}) {
        push @{$neighbors->[-1]->{topics}}, $current;
      }
      
      while (scalar(@$similar_topics) and $similar_topics->[0]->{date} eq $d) {
        my $t = shift @$similar_topics;
        push @{$neighbors->[-1]->{topics}}, $t;
      }
      
      for my $t (@{$neighbors->[-1]->{topics}}) {
        $t->{words} = [@{get_topic_terms($t->{id})}[0..9]];
        $t->{documents} = get_topic_documents($t->{id});
      }
    }
    
    # remove leading dates
    #while (scalar(@{$neighbors->[0]->{topics}}) == 0) {
    #  shift @$neighbors;
    #}
    
    # remove trailing dates
    #while (scalar(@{$neighbors->[-1]->{topics}}) == 0) {
    #  pop @$neighbors;
    #}
    
    $cache->set($neighbors_k, $neighbors);
  }
  
  return $neighbors;
}