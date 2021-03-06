package Story;
use StoryUtil;
use Cloud;
use Dancer ':syntax';
use Dancer::Plugin::Database;

our $VERSION = '0.1';

set serializer => 'JSON';

get '/' => sub {
    my $name =  database->quick_select('dataset', {id=>1})->{name};
    redirect '/' . $name;
};

get '/:name/?' => sub {
    my $name = params->{name};
    my $offset = params->{offset} ? int(params->{offset}) : 0;
    my $limit = params->{limit} ? int(params->{limit}) : 100;
    template 'index', {documents => StoryUtil::get_recent($name, $offset, $limit)};
};

get '/cloud_data/:name/:offset/?' => sub {
    my $name = params->{name};
    my $offset = params->{offset};
    return to_json(Cloud::do($name, $offset));
};

get '/cloud_data_topic/:name/:topic/?' => sub {
    my $name = params->{name};
    my $topic = params->{topic};
    return to_json(Cloud::do_topic($name, $topic));
};

get '/cloud/:name/?' => sub {
    my $name = params->{name};
    template 'cloud', {name=>$name};  
};

get '/:name/subgraph/:document_id/?' => sub {
    my $name = params->{name};
    my $settings = {name => $name,
                    document_id => params->{document_id},
                    depth => params->{depth} ? int(params->{depth}) : 3,
                    branch => params->{branch} ? int(params->{branch}) : 2,
                    sim_thresh => params->{sim_thresh} ? params->{sim_thresh} : .8,
                    topic_thresh => params->{topic_thresh} ? params->{topic_thresh} : .3,
                    doc_thresh => params->{doc_thresh} ? params->{doc_thresh} : .3,
                    window => params->{window} ? params->{window} : 30,
                    method => params->{method} ? params->{method} : 'topic',};
    my $data = StoryUtil::get_subgraph($settings);
    template 'explore', {name=>$name,
                         start=>$data->{start},
                         data=>to_json($data),
                         dataargs=>$settings};
};

true;
