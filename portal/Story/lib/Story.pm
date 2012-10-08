package Story;
use StoryUtil;
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
    my $limit = params->{limit} ? int(params->{limit}) : 100;
    template 'index', {documents => StoryUtil::get_recent($name, $limit)};
};

get '/:name/:document_id/?' => sub {
    my $name = params->{name};
    my $document_id = params->{document_id};
    template 'explore', {document_id => $document_id, name => $name};
};

get '/:name/explore/:document_id/?' => sub {
    my $name = params->{name};
    my $document_id = params->{document_id};
    template 'explore', {document_id => $document_id, dataset => $name};
};
get '/:name/subgraph/:document_id/?' => sub {
    my $name = params->{name};
    my $document_id = params->{document_id};
    my $depth = params->{depth} ? int(params->{depth}) : 2;
    my $limit = params->{limit} ? int(params->{limit}) : 5;
    my $topic_threshold = params->{topic_thresh} ? params->{topic_thresh} : .3;
    my $similarity_threshold = params->{sim_thresh} ? params->{sim_thresh} : .9;
    my $window = params->{window} ? params->{window} : 30;
    return StoryUtil::get_subgraph({name => $name,
                                    document_id => $document_id,
                                    depth => $depth,
                                    limit => $limit,
                                    topic_thresh => $topic_threshold,
                                    sim_thresh => $similarity_threshold});
};

true;
