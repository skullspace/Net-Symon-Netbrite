#!/usr/bin/perl
use strict;
use warnings;
use lib 'lib';

use Net::Symon::NetBrite qw(:constants);
use Net::Symon::NetBrite::Zone;

use Net::XMPP;
use Config::Simple;


my $cfg = new Config::Simple('app.ini');

my $sign = Net::Symon::NetBrite->new(
    address => $cfg->param('NETBRITE.address')
);

$sign->zones(
    main  => Net::Symon::NetBrite::Zone->new(
       rect => [0, 1, 160, 16],
        default_font => 'script_24',
        default_color => COLOR_YELLOW,
    ));

my $server = $cfg->param('XMPP.server');
my $port = $cfg->param('XMPP.port');
my $username = $cfg->param('XMPP.username');
my $password = $cfg->param('XMPP.password');
my $resource = $cfg->param('XMPP.resource');
my $Connection = new Net::XMPP::Client(debuglevel=>0, debugfile=>'stdout');
my %messageQueue = ();
my %workingQueue = ();

$Connection->SetCallBacks(message=>\&InMessage, presence=>\&InPresence);

my $status = $Connection->Connect(hostname=>$server,
                                  componentname=>$server,
                                  port=>$port,
                                  srv=>1,
                                  tls=>1,
                                  ssl_ca_path=>'/etc/ssl/certs');

$SIG{HUP} = \&Stop;
$SIG{KILL} = \&Stop;
$SIG{TERM} = \&Stop;
$SIG{INT} = \&Stop;

if (!(defined($status))) {
    print "ERROR:  Jabber server is down or connection was not allowed.\n";
    print "        ($!)\n";
    exit(0);
}

my @result = $Connection->AuthSend(username=>$username,
                                   password=>$password,
                                   resource=>$resource);

if ($result[0] ne "ok") {
    print "ERROR: Authorization failed: $result[0] - $result[1]\n";
    exit(0);
}

$Connection->RosterGet();
$Connection->PresenceSend(priority=>1);

my $lastMessage = time();
while(defined($Connection->Process(2))) {
    if (time() - $lastMessage >= 10){
        if (DisplayNextMessage()){
            $lastMessage = time();
        }
    }
}

exit(0);

sub DisplayNextMessage {
    # We only read directly from the workingQueue, as the main message
    # queue is likely to change while  we iterate through it. Iterating through
    # a changing hash table is undefined behaviour in perl. We update
    # the workingQueue at the end of each complete loop.
    my ($key, $messages) = each(%workingQueue);

    if (!$key){ #start from the beginning
        %workingQueue = %messageQueue;
        ($key, $messages) = each(%workingQueue);
    }

    if ($key){
        my $message = shift $messages;
        $sign->message('main', $message);
        if (!@{ $messages }){
            delete $messageQueue{$key};
        }
        return 1;
    }
    else {
        return 1;
    }
}

sub Stop {
    print "Exiting...\n";
    $Connection->Disconnect();
    exit(0);
}

sub InPresence {
    my ($sid, $presence) = @_;
    if ($presence->GetType() eq 'subscribe') {
        $Connection->Subscription(type=>'subscribed',
                                  to=>$presence->GetFrom());
    }
}

sub InMessage {
    my ($sid, $message) = @_;
    
    my $type = $message->GetType();
    my $fromJID = $message->GetFrom("jid");
    
    my $from = $fromJID->GetUserID();
    my $resource = $fromJID->GetResource();
    my $body = $message->GetBody();

    #ignore 'User typing' messages created when on pidgeon
    if ($body ne '') { 
        print "===\n";
        print "Message ($type)\n";
        print "  From: $from ($resource)\n";
        print "  Body: $body\n";
        push( @{ $messageQueue{$from} }, $body);
    }
}

