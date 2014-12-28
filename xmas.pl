#!/usr/bin/perl -w

use strict;
use warnings;

use FCGI;

use OPC;
use Time::HiRes qw/usleep/;
use Config;

use XML::Simple;
use Data::Dumper;

if (! $Config{usethreads}) {
  printf("Ain't got no threads\n");
  # TODO: Add something to make it work without threads
  # does anyone NOT compile perl with threading support
  # any more?
  exit(1);
}

use threads;
use threads::shared;

my $xml = new XML::Simple (ForceArray => 1);
my $config = $xml->XMLin("config.xml");
my $ledconfig;
print Dumper($config);

if($config->{config}) {
  printf("Loading [%s]\n", $config->{config}[0]);
  $ledconfig = $xml->XMLin($config->{config}[0]);
  print Dumper($ledconfig);
} else {
  printf("No config file found, exiting\n");
  exit(1);
}

my $socket;
my $request;

if($config->{port}){
  $socket = FCGI::OpenSocket( $config->{port}[0], 5 );
  $request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR,
      \%ENV, $socket );
}

my $running = 1;

$SIG{INT} = \&interrupt;

sub interrupt {
  $running = 0;
}

my $num_leds = 100;
my $client = new OPC('127.0.0.1:7890');
$client->can_connect();

my @pixels :shared = ();
my $on :shared = $config->{port} ? 0 : 1;

sub setPixel {
  my $l = shift;
  my @rgb :shared = (shift, shift, shift);
  if(!$on) {
    $rgb[0] = 0;
    $rgb[1] = 0;
    $rgb[2] = 0;
  }
  $pixels[$l] = \@rgb;
}

# TODO: Implement Action Set to move this to the XML file.
my @white  = ([0x7f, 0x7f, 0x70],
              [0x5E, 0x5E, 0x54],
              [0x3F, 0x3F, 0x38],
              [0x1F, 0x1F, 0x1C]);

my @drips = ( [37,87], [38,88], [39,89], [40,90], [41,91], 
              [42,92], [43,93], [44,94], [45,95], [46,96],
              [47,97], [48,98], [49,99] );

sub drip {
  my $led = shift;
  my $count = shift;
  my $lpos = shift;

  if( $led eq 0 ) {
    $lpos++;
    if($lpos > $count + 3) {
      $lpos = 0;
    }
  } 

  my $loff = $lpos - $led;

  if($loff >= 0 && $loff <= 3) {
    return ($lpos, $white[$loff][0], $white[$loff][1], $white[$loff][2]);
  }
  return ($lpos, 0x0, 0x0, 0x0);
}

sub dodrip {
  my $delay = shift;
  my $index = shift;
  my $set = shift;
  my $dripset;
  my $dripcnt;
  my $bled;
  my $pos = 0;

  local $SIG{KILL} = sub { threads->exit };

  while($running) {
    {
      $dripcnt = $#$set;
#      lock(@pixels);
      for($dripset = 0; $dripset <= $dripcnt; $dripset++) {
        my @rgb = ();
        ($pos, @rgb) = drip($dripset, $dripcnt, $pos);
        foreach $bled (@{@$set[$dripset]}) {
          setPixel($bled, $rgb[0], $rgb[1], $rgb[2]);
        }
      }
    }
    usleep($delay);
  }
}

sub dofade {
  my @set = @{$_[0]};
  my @rainbow = @{$_[1]};
  my @var = @{$_[2]};
  my $index = $_[3];
  my $delay = $_[4];
  my $bled;

  local $SIG{KILL} = sub { threads->exit };
  while($running) {
    {
#      lock(@pixels);
      foreach $bled (@set) {
        setPixel($bled, $rainbow[$index]->[0], $rainbow[$index]->[1], $rainbow[$index]->[2]);
      }
    }
    if($index eq 9) { $index = 0; } else { $index++; }
    usleep($delay);
  }
}

sub dosolid {
  my @set = @{$_[0]};
  my @color = @{$_[1]};
  my @var = @{$_[2]};
  my $delay = $_[3];

  my $gled;
  local $SIG{KILL} = sub { threads->exit };
  while($running) {
    {
#      lock(@pixels);
      foreach $gled (@set) {
        setPixel($gled, $color[0] + int(rand($var[0])), $color[1] + int(rand($var[1])), $color[2] + int(rand($var[2])));
      }
    }
    usleep($delay);
  }
}


my $set = [0,6,10];
my $dir = [1,1,1];

my @yellow = (0x7f, 0x7f, 0x00);

my $led = 0;


for($led = 0; $led < $num_leds; $led++) {
  {
#    lock(@pixels);
    setPixel($led, 0, 0, 0);
  }
}

sub sendleds {
  local $SIG{KILL} = sub { threads->exit };
  my @leds;
  my $l;
  
  for($l = 0; $l < $num_leds; $l++) {
    $leds[$l] = ();
  }

  while($running) {
    {
      lock(@pixels);
      for($l = 0; $l < $num_leds; $l++) {
        $leds[$l][0] = $pixels[$l][0];
        $leds[$l][1] = $pixels[$l][1];
        $leds[$l][2] = $pixels[$l][2];
      }
    }
    $client->put_pixels(0,\@leds);
    
    usleep(10000);
  }
}

my @thrds = ();
my $threadcnt = 0;
$thrds[$threadcnt++] = threads->create( \&dodrip, 400000, 0, \@drips);
my @ledsets = @{$ledconfig->{set}};
my $ledsetcnt = $#ledsets + 1;

printf("\nLoading %i sets\n", $ledsetcnt);
for(my $i = 0; $i < $ledsetcnt; $i++) {
  my @lset = @{$ledsets[$i]->{led} || []};
  my $name = $ledsets[$i]->{name}[0] || "Nameless";
  my $delay = $ledsets[$i]->{delay}[0] || 1000000; #default 1s
  my $start = $ledsets[$i]->{start}[0] || 0;
  my @lcolors = @{$ledsets[$i]->{color} || [{red=>[0],green=>[0],blue=>[0]}]};
  printf("Found %i colors\n", $#lcolors + 1);
  my @lvariances = @{$ledsets[$i]->{variance} || [{red=>[0],green=>[0],blue=>[0]}] }; #default no variance
  printf("Found %i variances\n", $#lvariances +1);

  if(($#lcolors + 1) != ($#lvariances + 1) && ($#lvariances + 1 != 1)) {
    printf("Variances must either match number of colors or be singular\n");
    next;
  }

  if($#lset <= 0) {
    print("Skipping no leds\n");
    next;
  }

  if($#lcolors +1 == 1) {
    my @lcolor = (hex($lcolors[0]{red}[0]), 
                  hex($lcolors[0]{green}[0]),
                  hex($lcolors[0]{blue}[0]));

    my @lvariance = (hex($lvariances[0]{red}[0]),
                     hex($lvariances[0]{green}[0]),
                     hex($lvariances[0]{blue}[0]));


    printf("%s with %i Leds of color %x,%x,%x variance %i,%i,%i\n", 
            $name, $#lset, 
            $lcolor[0], $lcolor[1], $lcolor[2],
            $lvariance[0],$lvariance[1],$lvariance[2]);

    $thrds[$threadcnt++] = threads->create( \&dosolid, \@lset, \@lcolor, \@lvariance, $delay);
  } else {
    my @colorset;
    my $i = 0;
    for($i = 0; $i <= $#lcolors; $i++) {
      @{$colorset[$i]} = (hex($lcolors[$i]{red}[0]),
                       hex($lcolors[$i]{green}[0]),
                       hex($lcolors[$i]{blue}[0]));
    }

    my @lvariance = (hex($lvariances[0]{red}[0]),
                     hex($lvariances[0]{green}[0]),
                     hex($lvariances[0]{blue}[0]));

    printf("%s with %i leds of %i colors\n", $name, $#lset+1, $#colorset+1);

    $thrds[$threadcnt++] = threads->create( \&dofade, \@lset, \@colorset, \@lvariance, $start, $delay);
  }
}

$thrds[$threadcnt++] = threads->create( \&sendleds );

if($config->{port}){
  my $count;
  while( $request->Accept() >= 0 && $running ) {
    # Massive TODO List:
    # * Template Engine to move html generation out
    # * Add Config File listing to switch LED behaviors
    # * Add Config Editing/Creation
    # * Make it Pretty
    print "Content-type: text/html\r\n\r\n";
    print("<html><head><title>XMas Tree</title></head><body><div>\n");
    my $buffer="";
    if ($ENV{'REQUEST_METHOD'} eq "POST") {
      read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
    }

    if($buffer =~ /on=On/) {
      printf("<span>Lights On</span>\n");
      $on = 1;
    } elsif ($buffer =~ /off=Off/) {
      printf("<span>Lights Off</span>\n");
      $on = 0;
    }
    {
#      lock(@pixels);
      for($led = 0; $led < $num_leds; $led++) {
        printf("<span id='led%i' style='color: \#%02x%02x%02x\'>*</span>", $led, ${$pixels[$led]}[0], ${$pixels[$led]}[1], ${$pixels[$led]}[2]);
        if((($led + 1) % 10)==0){printf("<br />\n");}
      }
    }
    printf("<form action='/fcgi' method='post'>\n");
    printf("<input type='hidden' name='serial' value='%i' />", $count++);
    printf("<input type='submit' name='on' value='On' />");
    printf("<input type='submit' name='off' value='Off' />");
    printf("</form>\n");

    printf("<span>Debug, ignore:</span><br />");
    printf("<span>[%s]</span><br /><br /><br />", $buffer);

    foreach my $key (sort(keys %ENV)) {
      print "<span>$key = $ENV{$key}</span><br>\n";
    }

    printf("\n</div></body></html>\n");
  }
  $request->Finish();
  FCGI::CloseSocket( $socket );
} else {
  while($running){sleep 1;}
}


foreach my $thr (threads->list()) { $thr->kill('KILL')->detach;    }

for($led = 0; $led < 100; $led++) {
  {
    lock(@pixels);
    setPixel($led, 0, 0, 0);
  }
}
{
  lock(@pixels);
  $client->put_pixels(0,\@pixels);
}
