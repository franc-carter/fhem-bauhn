
# Defines the functionality of the WiFi Power switch
# Requires BauhnBridge to be defined first

package main;

use strict;
use warnings;
use POSIX;
use SetExtensions;
use IO::Socket;
use IO::Select;
use IO::Interface::Simple;
use Data::Dumper;

my $port = 10000;

my $fbk_preamble = pack('C*', (0x68,0x64,0x00,0x1e,0x63,0x6c));
my $twenties     = pack('C*', (0x20,0x20,0x20,0x20,0x20,0x20));
my $subscribed   = pack('C*', (0x68,0x64,0x00,0x18,0x63,0x6c));
my $ctl_preamble = pack('C*', (0x68,0x64,0x00,0x17,0x64,0x63));
my $onoff        = pack('C*', (0x68,0x64,0x00,0x17,0x73,0x66));
my $ctl_on       = pack('C*', (0x00,0x00,0x00,0x00,0x01));
my $ctl_off      = pack('C*', (0x00,0x00,0x00,0x00,0x00));

sub BauhnDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "BauhnDevice_Define";
  $hash->{SetFn}    = "BauhnDevice_Set";
  $hash->{Match}    = ".*";
  $hash->{ParseFn}  = "BauhnDevice_Parse";
  $hash->{AttrList} = "IODev ". $readingFnAttributes;
}

sub getMacStr($)
{
  my ($packet) = @_;

  my @mac = unpack('C*', substr($packet, 6, 6));
  @mac    = map {sprintf("%02x",$_)} @mac;
  my $mac = join(":", @mac);

  return $mac;
}

sub macStr2Bin($)
{
  my ($macstr) = @_;
  my @mac      = split(':', $macstr);
  @mac         = map { hex("0x".$_) } split(':', $macstr);
  my $mac      = pack('C*', @mac);

  return $mac;
}

sub subscribe($$)
{
  my ($hash, $macstr)     = @_;

  my $mac          = macStr2Bin($macstr);
  my $reversed_mac = scalar(reverse($mac));
  my $subscribe    = $fbk_preamble.$mac.$twenties.$reversed_mac.$twenties;
  my $to           = sockaddr_in($port, inet_aton("255.255.255.255"));
  my $ret          = IOWrite($hash, $subscribe, $to);
}

sub BauhnDevice_GetUpdate($)
{
    my ($hash) = @_;

    Log(5, "BauhnDevice_GetUpdate: $hash->{ID}");

    subscribe($hash, $hash->{ID});

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "BauhnDevice_GetUpdate", $hash, 0);
}

sub BauhnDevice_Parse($$)
{
  my ($hash, $msg) = @_;

  LogDecodedPacket("BauhnDevice_Parse", $msg);

  my $macstr = $msg->{macstr};
  my $dev_hash = $modules{BauhnDevice}{defptr}{$macstr};

  if ($msg->{type} eq 'ONOFF') {
      $dev_hash->{STATE}  = $msg->{state};
      DoTrigger($dev_hash->{NAME}, $msg->{state});
  }
  elsif ($msg->{type} eq 'SUBSCRIBED') {
      $dev_hash->{STATE} = $msg->{state};
      $dev_hash->{fhem}{iaddr} = $msg->{iaddr};
      DoTrigger($dev_hash->{NAME}, $msg->{state});
  }
  else {
      Log(5, "BauhnDevice_Parse: ignoring $msg->{type}");
  }

  return undef;
}

sub BauhnDevice_Define($$)
{
    my ($hash, $def) = @_;

    my ($name, $type, $macstr) = split(' ', $def);
    if (!defined($macstr)) {
        return "Usage: <NAME> BauhnDevice <XX:XX:XX:XX:XX:XX>"
    }
    $macstr = lc($macstr);

    Log(3, "BauhnDevice_Define: $name at $macstr");

    $hash->{STATE}    = 'Initialized';
    $hash->{ID}       = $macstr;
    $hash->{fhem}{id} = $macstr;
    $hash->{INTERVAL} = 120;

    $modules{BauhnDevice}{defptr}{$macstr} = $hash;

    AssignIoPort($hash);
    if(defined($hash->{IODev}->{NAME})) {
        Log3 $name, 1, "$name: I/O device is " . $hash->{IODev}->{NAME};
    } else {
        Log3 $name, 1, "$name: no I/O device";
    }

    subscribe($hash, $macstr);

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "BauhnDevice_GetUpdate", $hash, 0);

    return undef;
}

sub BauhnDevice_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);
  my $macstr = $hash->{ID};
  delete($modules{BauhnDevice}{defptr}{$macstr});

  return undef;
}

sub BauhnDevice_Set($@)
{
  my ($hash,$name,@args) = @_;

  my $list         = undef;
  my $mac          = macStr2Bin($hash->{ID});
  my $reversed_mac = scalar(reverse($mac));
  my $to           = $hash->{fhem}{iaddr};

  my ($action) = @args;
  if ($action eq 'off') {
      IOWrite($hash, $ctl_preamble.$mac.$twenties.$ctl_off, $to);
      $hash->{STATE} = "off";
  } elsif ($action eq 'on') {
      IOWrite($hash, $ctl_preamble.$mac.$twenties.$ctl_on, $to);
      $hash->{STATE} = "on";
  } else {
      $list = "off:noArg on:noArg toggle:noArg";
      return SetExtensions($hash, $list);
  }
  return $list;
}

1;


