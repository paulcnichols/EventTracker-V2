package StoryUtil;
use Dancer::Plugin::Database;

# Get recent articles as a starting point
sub get_recent {
  my $name = shift;
  my $limit = shift || 100;
  
  # get dataset id
  my $dataset_id = database->quick_select('dataset', {name => $name})->{id};
  my $sth = database->prepare(
                  qq|select *, from_unixtime(published) as timestamp
                      from document
                      where dataset_id = ?
                      order by published desc
                      limit ?|);
  $sth->execute($dataset_id, $limit);
  my $documents = [];
  while (my $r=$sth->fetchrow_hashref) {
    $r->{name} = $name;
    push @$documents, $r;
  }
  return $documents;
}

# find neighbors
sub neighbors {
  my $params = shift;
  my $sql = sprintf(
            qq|select t.topic_id as topic_id,
                      t.weight as topic_weight,
                      tsim.cosign_similarity as similarity,
                      sim_d.topic_id as sim_topic,
                      sim_d.weight as sim_topic_weight,
                      sim_d.document_id as doc_id,
                      (log(t.weight)+log(tsim.cosign_similarity)+log(sim_d.weight)) as edge
              from document_topic t
              join topic t_info on (t.topic_id = t_info.id)
              join topic_similarity tsim on (t.topic_id = tsim.%s)
              join topic tsim_info on (tsim.%s = tsim_info.id)
              join document_topic sim_d on (sim_d.topic_id = tsim.%s)
              where 
                t.document_id = %d and
                sim_d.document_id != %d and
                t_info.dataset_id = %d and
                -- t.weight > %f and
                tsim.cosign_similarity > %f and
                -- sim_d.weight > %f and
                tsim_info.date >= date_sub(from_unixtime(%d), interval 30 day) and 
                tsim_info.date <= date_add(from_unixtime(%d), interval 30 day)
              order by edge desc
              limit %d|,
            $params->{incoming} ? 'topic_b' : 'topic_a',
            $params->{incoming} ? 'topic_a' : 'topic_b',
            $params->{incoming} ? 'topic_a' : 'topic_b',
            $params->{id},
            $params->{id},
            $params->{dataset_id},
            $params->{topic_thresh},
            $params->{sim_thresh},
            $params->{topic_thresh},
            $params->{published},
            $params->{published},
            $params->{limit});
  my $sth = database->prepare($sql); $sth->execute();
  my $results = [];
  while (my $r = $sth->fetchrow_hashref) { push @$results, $r; }
  return $results;
};

# function to create an edge strength.  assume log product of weights for now
sub edge {
  my $params = shift;
  return
    log($params->{neighbor}->{topic_weight}) +
    log($params->{neighbor}->{similarity}) +
    log($params->{neighbor}->{sim_topic_weight});
}

# get the subgraph
sub get_subgraph {
  my $params = shift;
  my $document_id = $params->{document_id};
  
  # initialize
  my $depth = $params->{depth};
  my $limit = $params->{limit};
  my $dataset_id = database->quick_select('dataset', {name => $params->{name}})->{id};
  my $start = database->quick_select('document', {id => $document_id});
  my $edges = [];
  my $vertices = {};
  my $frontier = {$start->{id} => $start};
  my $new_frontier = {};
  
  # main algorithm
  while ($depth > 0) {
    for my $d (keys(%$frontier)) {
      $d = $frontier->{$d};
      
      # add d to documents
      $vertices->{$start->{id}} = $start;
      
      # params to neighbor routine
      my $n = {id => $d->{id},
               limit => $limit,
               dataset_id => $dataset_id,
               published => $d->{published},
               topic_thresh => $params->{topic_thresh},
               sim_thresh => $params->{sim_thresh}};
      
      # get incoming 
      $n->{incoming} = 1;
      my $d_new_incoming = neighbors($n);
      for my $d_new (@$d_new_incoming) {
        my $id = $d_new->{doc_id};
        if (!exists($frontier->{$id}) and !exists($vertices->{$id})) {
          $new_frontier->{$id} = database->quick_select('document', {id => $id});
        }
        push @$edges, {a_id => $id,
                       b_id => $d->{id},
                       weight => edge({id => $d->{id},
                                       forward => 1,
                                       neighbor => $d_new})};
      }
      
      # get outgoing
      $n->{incoming} = 0;
      my $d_new_outgoing = neighbors($n);
      for my $d_new (@$d_new_outgoing) {
        my $id = $d_new->{doc_id};
        if (!exists($frontier->{$id}) and !exists($vertices->{$id})) {
          $new_frontier->{$id} = database->quick_select('document', {id => $id});
        }
        push @$edges, {a_id => $d->{id},
                       b_id => $id,
                       weight => edge({id => $d->{id},
                                       forward => 0,
                                       neighbor => $d_new})};
      }
    }
    $frontier = $new_frontier;
    $depth--;
  }
  
  # add the remaining frontier to vertices
  for my $d (keys(%$frontier)) {
    $vertices->{$d} = $frontier->{$d};
  }
  
  return {start => $document_id, nodes => [values(%$vertices)], edges => $edges};
}


1;