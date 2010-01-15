#!/usr/bin/perl

=pod

=head1 Hostcheck

version : 0.10 - date : 2008/09/01 - author : jc baptiste <jc@phocean.net> - license : GNU/GPLv2

=head2 Description

Hostcheck is a simple script to check the availabily of hosts read from a file.
It can scan ICMP, UDP and TCP.

The host file must be formatted so that each line is like (without quotes) :

C<host:service1,service2,...,servicen>

Example :

C<toto:ssh,http>

C<titi.org:ssh>

C<tata:>

=head2 Prerequisites

Hostcheck is a Perl script based on the following modules : Getopt::Std, Net::Ping, Time::HiRes, Term::ANSIColor and IO::Socket. 

You can download these from CPAN or install them from you favorite Linux distro.

=head2 Synopsis

hostcheck.pl [-utv] FILE

=over

=item

without option : simple ICMP ping scan. FILE must be a valid path to a file containing the hosts to check.

=back

=head3 Options

=over

=item * -v

verbose mode (display warnings, mostly about invalid entrie from the file)

=item * -u

process an UDP ping instead of ICMP

=item * -t

process the TCP services checks (those present in the file)

=back

=cut

use strict;
use warnings;
use Getopt::Std;
use Net::Ping;
#use Data::Dumper;
use Time::HiRes;
use Term::ANSIColor;    # qw(:constants);
use IO::Socket;

my $verbose = 0;
my $msg_invalid_param =
  "ERROR : wrong usage.\nUsage : hostcheck [-vtu] nom_fichier\n";
my $warning = 0;
my @champ;

sub file_parsing {
	my $line;
	my $nomFichier = $_[0];
	print "### Parsing the hosts file...\n";

	# check the file path
	if ( !-e "$nomFichier" ) {
		die "ERROR : file '" . $nomFichier . "' does not exist...\n";
	}

	# open the file
	open( FH, $nomFichier )
	  or die "ERROR : can't open the file : '" . $nomFichier . "'\n";

	# parse it
	my $i = 0;
	while ( $line = <FH> ) {

		# parse the host
		if ( $line !~ /:/ ) {
			$warning++;
			printf(
"\t** Warning : Bad line formating (no ':' character) - line %d skipped\n",
				$i + 1 )
			  unless $verbose == 0;
			$i--;
			next;
		}
		@_ = split( /:/, $line );
		if ( $_[0] =~ /^$/ ) {
			$warning++;
			printf( "\t** Warning : Empty line found - line %d skipped\n",
				$i + 1 )
			  unless $verbose == 0;
			$i--;
			next;
		}
		$champ[$i][0] = $_[0];

		# parse the services
		if ( $_[1] !~ /^$/ ) { @_ = split( /,/, $_[1] ); }
		my $j = 0;
		foreach (@_) {
			if ( $_[$j] =~ /^(ssh|telnet|ftp|http|oracle|ms-sql-s|vnc-server|ms-wbt-server|microsoft-ds)$/ ) {
				chomp( $_[$j] );
				$champ[$i][ $j + 1 ] = $_[$j];
			}
			$j++;
		}
		$i++;
	}

	# end of the file
	$i = -1 if $i <0;
	close(FH) or die "ERROR : fermeture du fichier impossible.\n";
	printf( ">>> OK : %d valid line(s) read\n", $i + 1 );
	return $i;
}

sub ping_check {
	my $check;
	my $host;
	my $nb_host = $_[0];
	my $proto;
	my $tcp_check;
	print "### Running ICMP ping check...\n";

	# if options set
	if   ( $_[1] ) { $proto = "udp"; }
	else           { $proto = "icmp" }
	if   ( $_[2] ) { $tcp_check = 1; }
	else           { $tcp_check = undef }

	# ping options
	$check = Net::Ping->new($proto); # || die "Call to Net::Ping module failed";
	$check->hires();

	#$check->bind($my_addr); # interface source
	my $i = 0;
	my $j = 0;

	# parse the hosts table
	foreach (@champ) {
		$host = $champ[$i][0];

		# ping the host
		( my $ret, my $duration, my $ip ) = $check->ping( $host, 2 );    # || die "Ping failed : error with Net::Ping module";
		($ret) ? print color 'bold green' : print color 'bold red';
		print "\t$host";
		($ip) ? print " [$ip]" : print " [IP ???]";
		print color 'reset';
		print " is ";
		print "NOT reachable\n" unless $ret;
		printf( "reachable --- %.2f ms\n", 1000 * $duration ) if $ret;
		sleep(1);
		
		# tcp scan
		if ( $ret && $tcp_check ) {
			my $k = 1;
			while ( $champ[$i][$k] ) {
				my $serv = $champ[$i][$k];
				my $pip  = gethostbyname($host);
				my $ip   = inet_ntoa($pip);

				# timeout
				eval {
					local $SIG{ALRM} = sub { die "alarm\n" };  # NB: \n required alarm 2;
					my $client = IO::Socket::INET->new(
						PeerAddr => $ip,
						PeerPort => getservbyname( $serv, "tcp" ),
						Proto    => "tcp",
						Timeout  => "1",
						Type     => SOCK_STREAM
					) || die "Fatal error opening the socket !";
					alarm 0;
				};
				# affichage retour
				if ($@) {
					#die
					 #unless $@ eq "alarm\n";    # propagate unexpected errors
					                             # timed out
					print color 'bold red';
					printf("\t\t- $serv ... NOK\n");
					my $nomFichier;
					print color 'reset';
				}
				else {
					print color 'bold green';
					printf("\t\t- $serv ... OK\n");
					print color 'reset';
				}
				$k++;
			}
		}
		$j++ unless $ret;
		$i++;
	}
	$check->close();

	# summary
	($i)
	  ? printf(
		">>> Host alive : %d --- Host down : %d --- Success rate : %d %% <<<\n",
		$i - $j, $j, ( ( $i - $j ) / $i ) * 100 )
	  : die "I could not ping any host : check your network connectivity !\n";
}

# MAIN
# command line arguments
my %opts;
getopts( 'vtu', \%opts );

#print color 'reset';
die $msg_invalid_param
  unless ( $opts{'v'}
	|| $opts{'u'}
	|| $opts{'t'}
	|| $opts{'v'} && $opts{'u'}
	|| $opts{'v'} && $opts{'t'}
	|| $opts{'v'} && $opts{'u'} && $opts{'t'}
	|| !%opts );
if ( $opts{'v'} ) {
	$verbose = 1;
}

# functions call depending on the options
if ( $ARGV[$#ARGV] ) {
	my $nbhosts = file_parsing( $ARGV[$#ARGV] );
	if ( $nbhosts != 0 ) {
		if ( $opts{'u'} && $opts{'t'} ) {
			ping_check( $nbhosts, "udp", "1" );
		}
		elsif ( $opts{'u'} ) {
			ping_check( $nbhosts, "udp" );
		}
		elsif ( $opts{'t'} ) {
			ping_check( $nbhosts, undef, "1" );
		}
		else {
			ping_check( $nbhosts, undef, undef );
		}
	}
	else {
		die "Empty file !";
	}

	# end
	print "### All done !\n";
	if ( $warning != 0 ) {
		print
"\t**Warnings : there are $warning warnings - activate verbose option (-v) to see the messages\n";
	}
}
else {
	die $msg_invalid_param;
}
exit 0;
