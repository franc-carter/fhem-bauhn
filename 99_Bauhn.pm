
package main;

use strict;
use warnings;
use POSIX;

use vars qw($FW_ME);      # webname (default is fhem), needed by Color
use SetExtensions;
use strict;
use IO::Socket;
use IO::Select;
use IO::Interface::Simple;
use Data::Dumper;

my $port = 10000;

my $fbk_preamble = pack('C*', (0x68,0x64,0x00,0x1e,0x63,0x6c));
my $ctl_preamble = pack('C*', (0x68,0x64,0x00,0x17,0x64,0x63));
my $ctl_on       = pack('C*', (0x00,0x00,0x00,0x00,0x01));
my $ctl_off      = pack('C*', (0x00,0x00,0x00,0x00,0x00));
my $twenties     = pack('C*', (0x20,0x20,0x20,0x20,0x20,0x20));
my $onoff        = pack('C*', (0x68,0x64,0x00,0x17,0x73,0x66));
my $subscribed   = pack('C*', (0x68,0x64,0x00,0x18,0x63,0x6c));

my $socket = IO::Socket::INET->new(Proto=>'udp', LocalPort=>$port, Broadcast=>1) ||
                 die "Could not create listen socket: $!\n";
$socket->autoflush();

sub LogPacket(@)
{
    my @packet = @_;

    my $str = sprintf("%02x " x @packet, @packet);
    Log(1,$str);
}

sub Bauhn_Initialize($$)
{
    my ($hash) = @_;

    $hash->{SetFn}     = "Bauhn_Set";
    $hash->{DefFn}     = "Bauhn_Define";
    $hash->{ReadFn}    = "Bauhn_Read";
    $hash->{AttrList}  = "setList ". $readingFnAttributes;
}

sub Bauhn_Define($$)
{
    my ($hash, $def) = @_;

    my ($name, $type, $macstr, $interval) = split("[ \t]+", $def);
    if (!defined($macstr)) {
       return "Usage: define <name> Bauhn <mac> [interval]";
    }

    my @mac = split(':', $macstr);
    @mac = map { hex("0x".$_) } split(':', $macstr);
    my $mac = pack('C*', @mac);

    $hash->{fhem}{bauhn} = findBauhn($mac);
    $hash->{ID}          = $macstr;
    $hash->{INTERVAL}    = $interval || 60;
    $hash->{STATE}       = $hash->{fhem}{bauhn}->{on} ? "on" : "off";
    $hash->{fhem}{id}    = $mac;
    $hash->{FD}          = fileno($hash->{fhem}{bauhn}->{socket});
    $selectlist{$macstr} = $hash;

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Bauhn_GetUpdate", $hash, 0);

    return undef;
}

sub Bauhn_GetUpdate($)
{
    my ($hash) = @_;

    my $mac          = $hash->{fhem}{bauhn}->{mac};
    my $reversed_mac = scalar(reverse($mac));
    my $subscribe    = $fbk_preamble.$mac.$twenties.$reversed_mac.$twenties;

    # We need to do this to keep the discovery/subscription alive
    my $socket = $hash->{fhem}{bauhn}->{socket};
    my $saddr  = $hash->{fhem}{bauhn}->{saddr};
    $socket->send($subscribe, 0, $saddr);

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Bauhn_GetUpdate", $hash, 0);
}

sub Bauhn_Set($@)
{
    my ($hash, $name, @args) = @_;

    my $list = undef;
    my $bauhn = $hash->{fhem}{bauhn};
    if ($args[0] eq "on") {
        $bauhn->{on} = 1;
        controlBauhn($hash->{fhem}{bauhn}, "on");
        $hash->{STATE} = 'on';
    }
    elsif ($args[0] eq "off") {
        $bauhn->{on} = 0;
        controlBauhn($hash->{fhem}{bauhn}, "off");
        $hash->{STATE} = 'off';
    }
    elsif ($args[0] eq "toggle") {
        $bauhn->{on} = $bauhn->{on} ? 0 : 1;
        my $status = $bauhn->{on} ? "on" : "off";
        controlBauhn($hash->{fhem}{bauhn}, $status);
        $hash->{STATE} = $status;
    }
    else {
        $list = "off:noArg on:noArg toggle:noArg";
    }

    return $list;
}

sub Bauhn_Read()
{
    my ($hash, $dev) = @_;

    my $packet;
    my $bauhn  = $hash->{fhem}{bauhn};
    my $socket = $bauhn->{socket};
    my $select = IO::Select->new($socket) || die "Could not create Select: $!\n";
    while (my @ready = $select->can_read(0.1)) {
        my $from = $socket->recv($packet,1024) || return 0;
        my @data = unpack('C*', $packet);
        if (substr($packet,6,6) eq $bauhn->{mac}) {
            if (substr($packet,0,6) eq $onoff) {
                $bauhn->{on}   = (substr($packet,-1,1) eq chr(1)) ? 1 : 0;
                $hash->{STATE} = $hash->{fhem}{bauhn}->{on} ? "on" : "off";
                readingsSingleUpdate($hash,"state",$hash->{STATE},1);
            }
        }
    }

    return undef;
}

sub findBauhnOnInterface($$)
{
    my ($mac,$if) = @_;

    my $bauhn;
    my $reversed_mac = scalar(reverse($mac));
    my $subscribe    = $fbk_preamble.$mac.$twenties.$reversed_mac.$twenties;

    my $select = IO::Select->new($socket) ||
                     die "Could not create Select: $!\n";

    my $to_addr = sockaddr_in($port, inet_aton($if->broadcast));
    $socket->send($subscribe, 0, $to_addr) ||
        die "Send error: $!\n";

    my $n = 0;
    while($n < 10) {
        my @ready = $select->can_read(0.5);
        foreach my $fh (@ready) {
            my $packet;
            my $from = $socket->recv($packet,1024) || die "recv: $!";
            if ((substr($packet,0,6) eq $subscribed) && (substr($packet,6,6) eq $mac)) {
                my ($port, $iaddr) = sockaddr_in($from);
                $bauhn->{mac}      = $mac;
                $bauhn->{saddr}    = $from;
                $bauhn->{socket}   = $socket;
                $bauhn->{on}       = (substr($packet,-1,1) eq chr(1));
                return $bauhn;
            }
        }
        $n++;
    }
    close($socket);
    return undef;
}

sub findBauhn($)
{
    my ($mac) = @_;

    my @interfaces = IO::Interface::Simple->interfaces;
    @interfaces = grep(!/^lo$/, @interfaces);
    
    for(my $n=0; $n<2; $n++) {
        for my $if (@interfaces) {
            my $bauhn = findBauhnOnInterface($mac, $if);
            if (defined($bauhn)) {
                return $bauhn;
            }
        }
    }
    return undef;
}

sub controlBauhn($$)
{
    my ($bauhn,$action) = @_;
 
    my $mac = $bauhn->{mac};

    if ($action eq "on") {
        $action   = $ctl_preamble.$mac.$twenties.$ctl_on;
    }
    if ($action eq "off") {
        $action   = $ctl_preamble.$mac.$twenties.$ctl_off;
    }

    my $select = IO::Select->new($bauhn->{socket}) ||
                     die "Could not create Select: $!\n";

    my $n = 0;
    while($n < 6) {
        $bauhn->{socket}->send($action, 0, $bauhn->{saddr}) ||
            die "Send error: $!\n";

        my @ready = $select->can_read(0.5);
        foreach my $fh (@ready) {
            my $packet;
            my $from = $bauhn->{socket}->recv($packet,1024) ||
                           die "recv: $!";
            my @data = unpack("C*", $packet);
            my @packet_mac = @data[6..11];
            if (($onoff eq substr($packet,0,6)) && ($mac eq substr($packet,6,6))) {
                return 1;
            }
        }
        $n++;
    }
    return 0;
}

return 1;
