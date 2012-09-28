use strict;
use warnings;
use YAML qw(LoadFile DumpFile);
use Proc::PidUtil qw(is_running);
exit if is_running;

sub error {
  my $e = shift;
  
  print STDERR "Error:\
  $e!\n\n";
  
  print STDERR "Usage:\
  downloader.pl <conf.yaml>\n\n";
  
  print STDERR "Description: \
  This program downloads documents from a directory of meta data created \
  by a previously synced set of RSS feeds.  The output has all HTML stripped \
  and is similar to that of the browser lynx.  This script relies on a java \
  based downloader.\n";
  
  exit(1);
}

# check command line arguments
error("No configuration file provided") if (scalar(@ARGV) != 1 or !-f $ARGV[0]);

# load the configuration file
my $config = LoadFile($ARGV[0]);
for my $f (qw(binroot docroot name start end feeds)) {  
  error("Missing field '$f'") if !$config->{$f};
}

# iterate over the directories
my $jobroot = "$config->{docroot}/$config->{name}";
for my $dir (sort glob("$jobroot/*")) {
  next if !-d $dir;
  print "Directory: $dir\n";

  my $job = [];  
  for my $f (glob("$dir/*.yaml")) {
    next if -e "$f.txt" or -e "$f.failed";
    eval {
      
      # load the configuration file with the url
      my $u = LoadFile($f);
      
      # add job
      push @$job, join("\t", $f, $u->{url});

    };
  }  
  close JOB_FH;
  
  next if !scalar(@$job);
  
  # write URLs to process into a temporary file
  my $job_file = sprintf("/tmp/fetch_urls_%s.txt", (split(/\//, $dir))[-1]);
  print "Creating downloader input '$job_file'.\n";
  open JOB_FH, ">", $job_file or die "Failed to create job file!";
  print JOB_FH join("\n", @$job);
  close JOB_FH;
  
  # open the java downloader as a pipe
  my $cmd =  "java -jar $config->{binroot}/rss/downloader/downloader.jar 10 $job_file";
  open DOWNLOADER_FH, "$cmd|";
  while (<DOWNLOADER_FH>) {
    print;
  }
  close DOWNLOADER_FH;
  
  # remove temporary file
  `rm $job_file`;
}  


