use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use JSON qw(from_json to_json);
use LWP::Simple;
use Time::Local;
use Digest::SHA1  qw(sha1_hex);
use Proc::PidUtil qw(is_running);
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  sync.pl <conf.yaml>\n\n";
  
  print STDERR "Description:\
  This program downloads metadata for RSS feeds in the provided \
  configuration file.  The output of this process is a directory \
  populated with trigger files.  The content download will recognize \
  these files and download them.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(docroot name start end feeds)) {  
  error("Missing field '$f'") if !$config->{$f};
}

# validate the doc root or attempt to create it
`mkdir $config->{docroot}` if !-d $config->{docroot};
error("Failed to create document root") if !-d $config->{docroot};

# validate the job root or attempt to create it
my $jobroot = "$config->{docroot}/$config->{name}";
`mkdir $jobroot` if !-d $jobroot;
error("Failed to create job root") if !-d $jobroot;

# convert the start date into a unix timestamp
my ($month, $day, $year) = split(/\//, $config->{start});
my $start = timelocal(0, 0, 0, $day, $month-1, $year);
($month, $day, $year) = split(/\//, $config->{end});
my $end = timelocal(0, 0, 0, $day, $month-1, $year);

# for each feed, consult google reader api to download the latest set of sources
for my $feed (@{$config->{feeds}}) {
  print "Process feed '$feed->{name}'...\n";

  # get the most recent timestamp on disk
  my $recent = 0;
  my @recent_dirs = sort glob("$jobroot/*");
  if (scalar(@recent_dirs)) {
    my @recent_files = sort glob("$recent_dirs[-1]/*.$feed->{name}.*.yaml");
    $recent = $recent_files[-1] if scalar(@recent_files);
    $recent = (split(/\//, $recent))[-1];
    $recent = (split(/\./, $recent))[0];
  }
  $recent = $start if ! $recent;
  
  my $continue;
  do {
    # contact the unofficial google reader api for meta data
    my $url = "http://www.google.com/reader/api/0/stream/contents/feed/$feed->{url}?n=1000&ot=$recent";
    $url .= '&c=' . $continue if $continue;
    my $data = from_json(get($url));
    $continue = $data->{continuation} || '';
  
    for my $item (@{$data->{items}}) {

      # create the daily directory if does not exist
      my $timestamp = $item->{published};
      next if $timestamp > $end;
      
      my ($sec, $min, $hour, $day, $month, $year) = (localtime($timestamp))[0 .. 5]; 
      my $daily_dir = sprintf("$jobroot/%d_%02d_%02d", 1900 + $year, 1 + $month, $day);
      `mkdir $daily_dir` if !-d $daily_dir;
      
      # drop the trigger file for document
      my $url = $item->{alternate}->[0]->{href};
      my $title = $item->{title};
      my $trigger_file = sprintf("%s/%s.%s.%s.yaml", $daily_dir, $timestamp, $feed->{name}, sha1_hex($url));
      
      if (!-f $trigger_file) {
        print "Writing file $trigger_file...\n";
        DumpFile($trigger_file, {url => $url, published => $timestamp, title=>$title});
      }
    }
  } while ($continue);
}