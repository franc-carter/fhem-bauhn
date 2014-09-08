
package main;

use strict;
use warnings;
use POSIX;
use SetExtensions;
use IO::Socket;
use IO::Select;
#use Data::Dumper;

my $port = 10000;

my $fbk_preamble = pack('C*', (0x68,0x64,0x00,0x1e,0x63,0x6c));
my $ctl_preamble = pack('C*', (0x68,0x64,0x00,0x17,0x64,0x63));
my $ctl_on       = pack('C*', (0x00,0x00,0x00,0x00,0x01));
my $ctl_off      = pack('C*', (0x00,0x00,0x00,0x00,0x00));
my $twenties     = pack('C*', (0x20,0x20,0x20,0x20,0x20,0x20));
my $onoff        = pack('C*', (0x68,0x64,0x00,0x17,0x73,0x66));
my $subscribed   = pack('C*', (0x68,0x64,0x00,0x18,0x63,0x6c));

sub LogPacket($$)
{
    my ($header,$packet) = @_;

    my @packet = unpack('C*', $packet);
    my $str = sprintf("%02x " x @packet, @packet);
    Log(4,"$header: $str");
}

sub LogDecodedPacket($$)
{
  my ($header,$packet) = @_;

  my $type   = $packet->{type};
  my $macstr = $packet->{macstr};
  my $state  = $packet->{state};

  Log(3, "$header: $type $macstr $state");
}

sub getMacStr($)
{
  my ($packet) = @_;

  my @mac = unpack('C*', substr($packet, 6, 6));
  @mac    = map {sprintf("%02x",$_)} @mac;
  my $mac = join(":", @mac);

  return $mac;
}

sub decodeBauhnPacket($$)
{
    my ($from, $packet) = @_;

    my ($port, $iaddr) = sockaddr_in($from);
    my $from_str = inet_ntoa($iaddr);
    my $decoded = {
        from  => $from_str,
        port  => $port,
        type  => "UNKNOWN",
        iaddr => $from,
    };
    if (length($packet) >= 12) {
        $decoded->{macstr} = getMacStr($packet);

        my $type = substr($packet,0,6);
        if ($type eq $subscribed) {
            $decoded->{type}  = "SUBSCRIBED";
            $decoded->{state} = (substr($packet,-1,1) eq chr(1)) ? "on" : "off";
        }
        elsif ($type eq $ctl_preamble) {
            $decoded->{type}  = "CTL_PREAMBLE";
            $decoded->{state} = (substr($packet,-1,1) eq chr(1)) ? "on" : "off";
        }
        elsif ($type eq $fbk_preamble) {
            $decoded->{type}  = "FBK_PREAMBLE";
        }
        elsif ($type eq $onoff) {
            $decoded->{type}  = "ONOFF";
            $decoded->{state} = (substr($packet,-1,1) eq chr(1)) ? "on" : "off";
        }
    }
    return $decoded;
}

sub BauhnBridge_Initialize($)
{
  my ($hash) = @_;

  # Provider
  $hash->{ReadFn}   = "BauhnBridge_Read";
  $hash->{WriteFn}  = "BauhnBridge_Write";
  $hash->{Clients}  = ":BauhnDevice:";

  #Consumer
  $hash->{DefFn}    = "BauhnBridge_Define";
  $hash->{AttrList} = "key";
}

sub BauhnBridge_Define($$)
{
  my ($hash, $def) = @_;

  $hash->{STATE} = 'Initialized';
  $hash->{INTERVAL} = 60;

  my ($name,$bauhn) = split(" ", $def);

  my $socket = IO::Socket::INET->new(
                   Proto=>'udp',
                   LocalPort=>$port,
                   Broadcast=>1,
               );
  if (!defined($socket)) {
    return "BauhnBridge_Define: Could not open socket on $port";
  }
  $socket->autoflush();
  $hash->{bauhn}{socket} = $socket;
  $hash->{FD} = fileno($socket);

  $hash->{INTERVAL} = 60;
  $hash->{NAME} = $name;
  $selectlist{$name} = $hash;

  return undef;
}

sub BauhnBridge_Read($@)
{
  my ($hash) = $_[0];

  my $packet;
  my $from    = $hash->{bauhn}{socket}->recv($packet,1024);
  my $decoded = decodeBauhnPacket($from,$packet);

  LogPacket("BauhnBridge_Read", $packet);
  LogDecodedPacket("BauhnBridge_Read", $decoded);

  Dispatch($hash, $decoded, undef);

  return undef;
}

sub BauhnBridge_Write($$$)
{
  my ($hash,$packet,$to)= @_;

  my $decoded = decodeBauhnPacket($to,$packet);
  LogDecodedPacket("BauhnBridge_Write", $decoded);

  LogPacket("BauhnBridge_Write: ",$packet);
  $hash->{bauhn}{socket}->send($packet,0,$to);

  return undef;
}

1;

