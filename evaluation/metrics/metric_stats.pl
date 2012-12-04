use strict;
use warnings;
my $items = {};
open FH, $ARGV[0];
my $header=<FH>;
my $dates = {};
while (<FH>) {
  chomp;
  my ($topic, $date, $neighbor, $weight, $alpha, $n) = split(/,/);
  push @{$items->{$topic}}, {topic=>$topic, date=>$date, neighbor=>$neighbor, weight=>$weight, n=>$n, alpha=>$alpha};
  $dates->{$date} = 1;
}

my $i=0;
my $dkeys=[sort(keys(%$dates))];
for my $d (@$dkeys) {
 $dates->{$d} = ++$i; 
}

for my $topic (keys(%$items)) {
  for (my $i = 7; $i < scalar(keys(%$dates)); ++$i) {
    my $sd = 0;
    my $sa = 0;
    my $m = 0;
    for my $d (@{$items->{$topic}}) {
      if ($dates->{$d->{date}} < $i and $dates->{$d->{date}} >= $i-7) {
        $sd += $d->{n};
        $sa += $d->{alpha};
      }
    }
    
    printf "%d,$dkeys->[$i],%d,%f,%f,%f,%f\n", $topic, $sd, $sa, scalar(@{$items->{$topic}}) / 7, $sd*scalar(@{$items->{$topic}}) / 7, $sa*scalar(@{$items->{$topic}}) / 7;
  }
}

