# $Id$
#

package HOSTDB;

use strict;
use DBI;
use Socket;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
require AutoLoader;


@ISA = qw(Exporter);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '0.01';

sub _debug_print;
sub _set_error;

# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.


=head1 NAME

HOSTDB - Perl extension to access host database.

=head1 SYNOPSIS

  use HOSTDB;


=head1 DESCRIPTION

The host database contains DNS, subnet and DHCP type host info, use this perl module
to access the data.

=head1 EXPORT

None.

=head1 METHODS

=cut



sub new
{
	my $self = shift;
	my $class = ref $self || $self;
	my %me = @_;
	my $this = bless \%me,$class;
	$this->init ($self);
	$this;
}

sub init
{
	my $self = shift;

	warn ("IN TOP LEVEL HOSTDB init()\n");
}

=head2 get_inifile

	my $hostdbini = Config::IniFiles->new (-file => HOSTDB::get_inifile ());

	The reason to use HOSTDB::get_inifile () instead of 
	$hostdb->get_inifile () is that you probably don't have a HOSTDB
	object yet.

=cut
sub get_inifile
{
	my $fn = "/etc/hostdb.ini";

	if (! -f $fn) {
		die ("$0: Config-file $fn does not exist");
	}

	return ($fn);
}

=head2 clean_hostname

	if (! $hostdb->clean_hostname ($hostname)) {
		print ("given hostname was invalid: $hostdb->{error}\n");
	} else {
		print ("new hostname: $hostname\n");
	}

	This function modified the variable passed to it, like chomp().

	It converts the hostname to lower case, strips any trailing dots
	and finally returns the result of is_valid_fqdn ($new_hostname).

=cut
sub clean_hostname
{
	my $self = shift;
	#my $new = lc ($_[0]);	# lowercase
	my $new = $_[0];	# don't lowercase for now, start doing this in the
				# future and also bulk change everything in database
	my $valid;

	$new =~ s/\.+$//o;	# strip trailing dots

	$valid = $self->is_valid_fqdn ($new) || $self->is_valid_domainname ($new);

	if ($valid and ($new ne $_[0])) {
		$self->_debug_print ("changed '$_[0]' into '$new'");
		$_[0] = $new;
	}

	return ($valid);
}


=head2 clean_domainname

	if (! $hostdb->clean_domainname ($zonename)) {
		print ("given zonename was invalid: $hostdb->{error}\n");
	} else {
		print ("new zonename: $zonename\n");
	}

	This function modified the variable passed to it, like chomp().

	It converts the zonename to lower case, strips any trailing dots
	and finally returns the result of is_valid_domainname ($new_zonename).

=cut
sub clean_domainname
{
	my $self = shift;
	my $new = lc ($_[0]);	# lowercase
	my $valid;

	$new =~ s/\.+$//o;	# strip trailing dots

	$valid = $self->is_valid_domainname ("$new");
	
	if ($valid and ($new ne $_[0])) {
		$self->_debug_print ("changed '$_[0]' into '$new'");
		$_[0] = $new;
	}

	return ($valid);
}


=head2 is_valid_fqdn

	$is_valid = $hostdb->is_valid_fqdn ($hostname);

	Checks with some regexps if $hostname is a valid FQDN host name.

=cut
sub is_valid_fqdn
{
	my $self = shift;
	my $hostname = shift;

	# do NOT clean_hostname() because that function actually uses this one

	# check first and last part separately
	my @hostname_parts = split (/\./, $hostname);
	my $illegal_chars;

	# XXX is 'su.se' a valid FQDN if such an A record exists? For now we don't
	# call it valid. Go check some RFC or something.
	if ($#hostname_parts < 2) {
		$self->_debug_print ("hostname '$hostname' is incomplete");
		goto ERROR;
	}

	# first part (hostname) may NOT begin with a digit and may NOT
	# contain an underscore
	if ($hostname !~ /^[a-zA-Z0-9]/o) {
		$self->_debug_print ("hostname '$hostname' does not begin with an alphabetic character (a-zA-Z)");
		goto ERROR;
	}
	$illegal_chars = $hostname_parts[0];
	$illegal_chars =~ s/[a-zA-Z0-9\-]//og;
	if ($illegal_chars) {
		$self->_debug_print ("hostname part '$hostname_parts[0]' of FQDN '$hostname' contains illegal characters ($illegal_chars)");
		goto ERROR;
	}

	# check TLD, only letters and between 2 and 6 chars long
	# 2 is for 'se', 6 is 'museum'
	if ($hostname_parts[$#hostname_parts] !~ /^[a-zA-Z]{2,6}$/o) {
		$self->_debug_print ("TLD part '$hostname_parts[$#hostname_parts]' of FQDN '$hostname' is invalid (should be 2-6 characters and only alphabetic)");
		goto ERROR;
	}

	# check it all, a bit more relaxed than above (underscores allowed
	# for example).	
	$illegal_chars = $hostname;
	$illegal_chars =~ s/[a-zA-Z0-9\._-]//og;
	if ($illegal_chars) {
		$self->_debug_print ("'$hostname' has illegal characters in it ($illegal_chars)");
		goto ERROR;
	}

	return 1;
ERROR:
	$self->_set_error ("'$hostname' is not a valid FQDN");
	return 0;
}


=head2 is_valid_domainname

	$is_valid = $hostdb->is_valid_domainname ($zonename);

	Checks with some regexps if $zonename is a valid domain name.
	This is nearly the same thing as is_valid_fqdn but a bit more relaxed.

=cut
sub is_valid_domainname
{
	my $self = shift;
	my $domainname = shift;

	# do NOT clean_domainname() because that function actually uses this one

	my @domainname_parts = split (/\./, $domainname);

	if ($#domainname_parts < 1) {
		$self->_debug_print ("domainname '$domainname' is incomplete");
		goto ERROR;
	}

	# check TLD, only letters and between 2 and 6 chars long
	# 2 is for 'se', 6 is 'museum'
	if ($domainname_parts[$#domainname_parts] !~ /^[a-zA-Z]{2,6}$/o) {
		$self->_debug_print ("TLD part '$domainname_parts[$#domainname_parts]' of domain name '$domainname' is invalid (should be 2-6 characters and only alphabetic)");
		goto ERROR;
	}

	# check it all, a bit more relaxed than above (underscores allowed
	# for example).	
	my $illegal_chars = $domainname;
	$illegal_chars =~ s/[a-zA-Z0-9\._-]//og;
	# what is left are illegal chars
	if ($illegal_chars) {
		$self->_debug_print ("'$domainname' has illegal characters in it ($illegal_chars)");
		goto ERROR;
	}

	return 1;
ERROR:
	$self->_set_error ("'$domainname' is not a valid domain name");
	return 0;
}


=head2 clean_mac_address

	if (! $hostdb->clean_mac_address ($mac_address)) {
		print ("given mac address was invalid: $hostdb->{error}\n");
	} else {
		print ("new mac address: $mac_address\n");
	}

	This function modified the variable passed to it, like chomp().

	Accept a mac-address in any of these formats :

	00:2:b3:9a:89:df
	0002.b39a.89df

	and turn it into :

	00:02:b3:9a:89:df
	

=cut
sub clean_mac_address
{
	my $self = shift;
	my $new = lc ($_[0]);
	my @elements;
	my $valid;

	$new =~ s/[\.\-]/:/og;	# replace dots and dashes with colons
	
	if ($new =~ /^([\da-f]+):([\da-f]+):([\da-f]+)$/o) {
		# handle 0002.b39a.89df
		foreach my $tuple (hex ($1), hex ($2), hex ($3)) {
			push (@elements,
				sprintf ("%.2x:%.2x", ($tuple >> 8) & 0xff, $tuple & 0xff));
		}
		$new = join(":", @elements);
	} elsif ($new =~ /^([\da-f]{1,2}):([\da-f]{1,2}):([\da-f]{1,2}):([\da-f]{1,2}):([\da-f]{1,2}):([\da-f]{1,2})$/o) {
		# handle 00:2:b3:9a:89:df
		$new = sprintf("%.2x:%.2x:%.2x:%.2x:%.2x:%.2x", hex ($1), hex ($2), hex ($3), hex ($4), hex ($5), hex ($6));
	}

	$valid = $self->is_valid_mac_address ("$new");
	
	if ($valid and ($new ne $_[0])) {
		$self->_debug_print ("changed '$_[0]' into '$new'");
		$_[0] = $new;
	}

	return ($valid);
}

=head2 is_valid_mac_address

	print("valid\n") if ($hostdb->is_valid_mac_address($mac);
	
	Checks if $mac is a mac address formatted exactly like this: 00:02:b3:9a:89:df
	
	To make other variants of mac addresses be formatted like the one above, use

	$hostdb->clean_mac_address ($mac);

=cut
sub is_valid_mac_address
{
	my $self = shift;
	my $mac = shift;

	if ($mac =~ /^[\da-f]{2,2}:[\da-f]{2,2}:[\da-f]{2,2}:[\da-f]{2,2}:[\da-f]{2,2}:[\da-f]{2,2}$/o) {
		return 1;
	}

	$self->_set_error ("Invalid mac address");
	return 0;
}


=head2 is_valid_subnet

	if (! $hostdb->is_valid_subnet ("130.237.0.0/16")) {
		die ("The world is going under, 130.237.0.0/16 " .
		     "is no longer a valid subnet!\n");
	}

	Check if a subnet is valid.


=cut
sub is_valid_subnet
{
	my $self = shift;
	my $subnet = shift;
	
	$self->_debug_print ("subnet '$subnet'");

	#if ($subnet !~ /^$IP_REGEXP\/$SLASH_REGEXP^/) {
	if ($subnet !~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\/(\d{1,2})$/) {
		$self->_debug_print ("invalid subnet '$subnet'");
		return 0;
	}
	
	my $netaddr = $1;
	my $slash = $2;

	if (! $self->aton ($netaddr)) {
		$self->_debug_print ("invalid netaddr '$netaddr'");
		return 0;
	}

	# XXX is /32 really a valid subnet? isn't that a host?	
	if ($slash < 0 or $slash > 32) {
		$self->_debug_print ("invalid slash '$slash'");
		return 0;
	}
	
	if ($self->get_netaddr ($subnet) ne $netaddr) {
		$self->_set_error ("$subnet is invalid (there are bits in $netaddr outside of mask " .
			$self->slashtonetmask ($slash) . ")");

		$self->_debug_print ("invalid subnet $subnet - netaddr different from calculated (" .
			$self->get_netaddr ($subnet) . ")");

		return 0;
	}

	$self->_debug_print ("$subnet is valid");

	return 1;
}


=head2 is_valid_ip

	die ("Invalid IP '$user_input'\n") if (! $hostdb->is_valid_ip ($user_input));

	Do some checking to determine if this is a valid IP address or not.
	

=cut
sub is_valid_ip
{
	my $self = shift;
	my $ip = shift;
	
	# XXX this routine needs some serious thought... it is not
	# exactly self explanatory and even I don't remember the reasoning
	# any more

	$self->_debug_print ("ip '$ip'");

	if ($ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/o) {
		my @ip = ($1, $2, $3, $4);

		return 1 if ($ip eq "0.0.0.0");
		
		if ($self->aton ($ip) > 0) {
			$self->_debug_print ("is a valid IP");
			return 1;
		}
	}

	return 0;
}


=head2 aton

	$n_ip = $hostdb->ntoa($ip);

	Returns the IP address in binary data representation.
	Just a wrapper for inet_aton().


=cut
sub aton
{
	my $self = shift;
	my $val = shift;

	return (unpack ('N', Socket::inet_aton ($val)));
}


=head2 ntoa

	$ip = $hostdb->ntoa($n_ip);

	Returns the IP address in ascii representation.
	Just a wrapper for inet_ntoa().


=cut
sub ntoa
{
	my $self = shift;
	my $val = shift;
	
	return (Socket::inet_ntoa (pack ('N', $val)));
}


=head2 slashtonetmask

	$netmask = $hostdb->slashtonetmask("26");

	Returns the slash notation for the specified netmask
	(255.255.255.192 in the example)


=cut
sub slashtonetmask
{
	my $self = shift;
	my $slash = shift;

	if ($slash < 0 or $slash > 32) {
		$self->_set_error ("slash '$slash' invalid for IPv4"); # and IPv6 don't use netmasks
		return undef;
	}

	return ("0.0.0.0") if ($slash == 0);
	return ("255.255.255.255") if ($slash == 32);
	
	return ($self->ntoa (-(1 << (32 - $slash))));
}


=head2 netmasktoslash

	$slashnotation = $hostdb->netmasktoslash("255.255.255.192");

	Returns the slash notation for the specified netmask
	(26 in the example)


=cut
sub netmasktoslash
{
	my $self = shift;
	my $netmask = $self->aton(shift);

	my $slash = 0;

	my $t;
	for $t (0..3) {
		my $o = ($netmask >> ($t * 8)) & 0xff;
		
		while ($o) {
			$slash++ if ($o & 1);
			
			$o = $o >> 1;
		}
	}

	return ($slash);
}

=head2 get_num_addresses

	$slash = 24;
	$numhosts = $hostdb->get_num_addresses ($slash);
	
	Returns the number of addresses in a network of size $slash
	(255 in the example)


=cut
sub get_num_addresses
{
	my $self = shift;
	my $slash = shift;
	
	# XXX make unsigned
	return (int (1 << (32 - $slash)));
}


=head2 get_netaddr

	$netaddr = $hostdb->get_netaddr ("192.168.100.4/24");

	Returns the net address of the IP and subnet you specified
	(192.168.100.0 in the example)


=cut
sub get_netaddr
{
	my $self = shift;
	my $subnet = shift;
	
	my ($netaddr, $slash) = split('/', $subnet);
	
	return ($self->ntoa ($self->aton ($netaddr) & $self->aton ($self->slashtonetmask ($slash))));

}


=head2 get_broadcast

	$broadcast = $hostdb->get_broadcast ("192.168.100.4/24");

	Returns the broadcast address of the IP and subnet you specified
	(192.168.100.255 in the example)


=cut
sub get_broadcast
{
	my $self = shift;
	my $subnet = shift;
	
	my ($netaddr, $slash) = split('/', $subnet);
	
	return ($self->ntoa ($self->aton ($self->get_netaddr ($subnet)) + $self->get_num_addresses ($slash) - 1));
}


=head2 dump

	$hostdb->dump();
	
	Dumps all variables of the $hostdb object. Only for debugging.

=cut
sub dump
{
	my $self = shift;

	foreach my $k (sort keys %{$self}) {
		printf "%-20s %s\n",$k,$self->{$k};
	}
}



####################################
# package HOSTDB private functions #
####################################


=head1 PACKAGE HOSTDB PRIVATE FUNCTIONS

	These functions should NEVER be called by a program using this class,
	but are documented here as well just for the sake of documentation.


=head2 _set_error

	$self->_set_error ("operation foo failed: bar");

	Sets internal error string.

=cut
sub _set_error
{
	my $self = shift;
	my @error = @_;

	$self->{error} = join (" ", @error);

	return undef;
}


=head2 _debug_print

	$self->_debug_print ("foo", "bar");

	Prints debug messages if $self->{debug} is true.

=cut
sub _debug_print
{
	my $self = shift;
	my @msg = @_;
	
	return if (! $self->{debug});

	my ($pack, $file, $line, $subname, $hasargs, $wantarray) = caller (1);
	if ($#msg > 0) {
		# multi line, print nice
		warn ("$subname() DEBUG START:\n	", join("\n	", @msg), "\nDEBUG END\n");
	} else {
		warn ("$subname() DEBUG: $msg[0]\n");
	}

	return undef;
}



##################################################################

package HOSTDB::DB;
@HOSTDB::DB::ISA = qw(HOSTDB);


sub init
{
	my $self = shift;

	if (defined ($self->{dsn})) {
		$self->{_dbh} = DBI->connect ($self->{dsn}, $self->{user}, $self->{password}) or die "$DBI::errstr";

		$self->{_hostbyid} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE id = ? ORDER BY id") or die "$DBI::errstr";
		$self->{_hostbypartof} =	$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE partof = ? ORDER BY id") or die "$DBI::errstr";
		$self->{_hostbymac} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE mac = ? ORDER BY mac") or die "$DBI::errstr";
		$self->{_hostbyname} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE hostname = ? ORDER BY hostname") or die "$DBI::errstr";
		$self->{_hostbywildcardname} =	$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE hostname LIKE ? ORDER BY hostname") or die "$DBI::errstr";
		$self->{_hostbyip} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE ip = ? ORDER BY n_ip") or die "$DBI::errstr";
		$self->{_hostbyiprange} =	$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host WHERE n_ip >= ? AND n_ip <= ? ORDER BY n_ip") or die "$DBI::errstr";
		$self->{_allhosts} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.host ORDER BY id") or die "$DBI::errstr";

		$self->{_zonebyname} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.zone WHERE zonename = ? ORDER BY zonename") or die "$DBI::errstr";
		$self->{_allzones} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.zone ORDER BY zonename") or die "$DBI::errstr";

		$self->{_subnet} =		$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.subnet WHERE netaddr = ? AND slashnotation = ? ORDER BY n_netaddr");
		$self->{_subnet_longer_prefix} =	$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.subnet WHERE n_netaddr >= ? AND n_netaddr <= ? ORDER BY n_netaddr");
		$self->{_subnet_closest_match} =	$self->{_dbh}->prepare ("SELECT * FROM $self->{db}.subnet WHERE n_netaddr <= ? ORDER BY n_netaddr DESC LIMIT 1");
	} else {
		$self->_debug_print ("DSN not provided, not connecting to database.");
	}

	$self->user (getpwuid("$<"));
	
	return 1;
}

sub DESTROY
{
	my $self = shift;

	$self->{_dbh}->disconnect();
}


#######################################
# package HOSTDB::DB public functions #
#######################################


=head1 PACKAGE HOSTDB::DB FUNCTIONS


=head2 user

	$hostdb->user("foo") or die("error");

	Set username to use in logging to 'foo' - default is UNIX username.

	-

	$user = $hostdb->user ();

	Get username used in logging.

	

=cut
sub user
{
	my $self = shift;

	if (@_) {
		my $user = shift;

		$self->_debug_print ("Changing username from '$self->{localuser}' to $user");
		$self->{localuser} = $user;

		return 1;
	}

	return ($self->{localuser});
}


=head2 create_host

	$host = $hostdb->create_host();

	Gets you a brand new HOSTDB::Object::Host object.


=cut
sub create_host
{
	my $self = shift;
	
	my $o = bless {},"HOSTDB::Object::Host";
	$o->{hostdb} = $self;
	$o->{debug} = $self->{debug};
	$self->_set_error ($o->{error}), return undef if (! $o->init());
	
	return ($o);
}


=head2 create_zone

	$zone = $hostdb->create_zone();

	Gets you a brand new HOSTDB::Object::Zone object.


=cut
sub create_zone
{
	my $self = shift;
	
	my $o = bless {},"HOSTDB::Object::Zone";
	$o->{hostdb} = $self;
	$o->{debug} = $self->{debug};
	$self->_set_error ($o->{error}), return undef if (! $o->init());
	
	return ($o);
}


=head2 create_subnet

	$subnet = $hostdb->create_subnet(4, "10.1.2.0/24");

	Gets you a brand new HOSTDB::Object::Subnet object.

	The 4 is IPv4. This is just planning ahead, IPv6 is not implemented
	in a number of places.


=cut
sub create_subnet
{
	my $self = shift;
	my $ipver = shift;
	my $subnet = shift;

	my $o = bless {},"HOSTDB::Object::Subnet";
	$o->{hostdb} = $self;
	$o->{ipver} = $ipver;
	$o->{subnet} = $subnet;
	$o->{debug} = $self->{debug};

	$self->_set_error ($o->{error}), return undef if (! $o->init());
	
	return ($o);
}


=head2 findhostbyname

	foreach my $host ($hostdb->findhostbyname ($searchhost)) {
		printf ("%-5s %-20s %s\n", $host->id (), $host->ip (), $host->hostname ());
	}


=cut
sub findhostbyname
{
	my $self = shift;
	my @res;

	$self->_debug_print ("Find host with name '$_[0]'");
	
	if (! $self->is_valid_fqdn ($_[0]) and ! $self->is_valid_domainname ($_[0])) {
		$self->_set_error ("findhostbyname: '$_[0]' is not a valid FQDN or domain name");
		return undef;
	}
	
	$self->_find(_hostbyname => 'HOSTDB::Object::Host', $_[0]);
}


=head2 findhostbyip

	foreach my $host ($hostdb->findhostbyip ($searchhost)) {
		printf ("%-20s %s\n", $host->ip (), $host->hostname ());
	}


=cut
sub findhostbyip
{
	my $self = shift;

	$self->_debug_print ("Find host with IP '$_[0]'");
	
	if (! $self->is_valid_ip ($_[0])) {
		$self->_set_error ("findhostbyip: '$_[0]' is not a valid IP address");
		return undef;
	}
	
	$self->_find(_hostbyip => 'HOSTDB::Object::Host', $_[0]);
}

=head2 findhostbywildcardname

	foreach my $host ($hostdb->findhostbywildcardname ($searchhost)) {
		printf ("%-20s %s\n", $host->ip (), $host->hostname ());
	}


=cut
sub findhostbywildcardname
{
	my $self = shift;

	$self->_debug_print ("Find host with hostname LIKE '$_[0]'");
	
	$self->_find(_hostbywildcardname => 'HOSTDB::Object::Host', $_[0]);
}


=head2 findhostbymac

	foreach my $host ($hostdb->findhostbymac ($searchhost)) {
		printf ("%-20s %-20s %s\n", $host->mac(), $host->ip (),
			$host->hostname ());
	}


=cut
sub findhostbymac
{
	my $self = shift;

	$self->_debug_print ("Find host with MAC address '$_[0]'");
	
	if (! $self->is_valid_mac_address ($_[0])) {
		$self->_set_error ("findhostbymac: '$_[0]' is not a valid MAC address");
		return undef;
	}
	
	$self->_find(_hostbymac => 'HOSTDB::Object::Host', $_[0]);
}


=head2 findhostbyid

	$host = $hostdb->findhostbyid ($id);
	print ($host->hostname ());


=cut
sub findhostbyid
{
	my $self = shift;

	$self->_debug_print ("Find host with id '$_[0]'");
	
	if ($_[0] !~ /^\d+$/) {
		$self->_set_error ("findhostbyid: '$_[0]' is not a valid ID");
		return undef;
	}
	
	$self->_find(_hostbyid => 'HOSTDB::Object::Host', $_[0]);
}


=head2 findhostbypartof

	blah


=cut
sub findhostbypartof
{
	my $self = shift;

	$self->_debug_print ("Find host partof '$_[0]'");
	
	$self->_find(_hostbypartof => 'HOSTDB::Object::Host', $_[0]);
}


=head2 findhostbyiprange

	@hosts = $hostdb->findhostbyiprange ($subnet->netaddr (), $subnet->broadcast ());

	Returns all hosts in a subnet


=cut
sub findhostbyiprange
{
	my $self = shift;

	$self->_debug_print ("Find host by IP range '$_[0]' -> '$_[1]'");
	
	if (! $self->is_valid_ip ($_[0])) {
		$self->_set_error ("findhostbyiprange: start-ip '$_[0]' is not a valid IP adress");
		return undef;
	}
	
	if (! $self->is_valid_ip ($_[1])) {
		$self->_set_error ("findhostbyiprange: stop-ip '$_[1]' is not a valid IP adress");
		return undef;
	}
	
	$self->_find(_hostbyiprange => 'HOSTDB::Object::Host',
			$self->aton ($_[0]), $self->aton ($_[1]));
}


=head2 findallhosts

	@hosts = $hostdb->findallhosts ();


=cut
sub findallhosts
{
	my $self = shift;

	$self->_debug_print ("Find all hosts");
	
	$self->_find(_allhosts => 'HOSTDB::Object::Host');
}


=head2 findzonebyname

	$zone = $hostdb->findzonebyname ($zonename);


=cut
sub findzonebyname
{
	my $self = shift;

	$self->_debug_print ("Find zone with name '$_[0]'");
	
	$self->_find(_zonebyname => 'HOSTDB::Object::Zone', $_[0]);
}


=head2 findallzones

	@zones = $hostdb->findallzones ();


=cut
sub findallzones
{
	my $self = shift;

	$self->_debug_print ("Find all zones");
	
	$self->_find(_allzones => 'HOSTDB::Object::Zone');
}


=head2 findsubnet

	$subnet = $hostdb->findsubnet("192.168.1.1/24");

	Finds a subnet exactly matching what you asked for.


=cut
sub findsubnet
{
	my $self = shift;

	$self->_debug_print ("Find subnet '$_[0]'");

	my ($netaddr, $slash) = split('/', $_[0]);

	$self->_find(_subnet => 'HOSTDB::Object::Subnet', $netaddr, $slash);
}


=head2 findsubnetclosestmatch

	$subnet = $hostdb->findsubnetclosestmatch("192.168.1.1");

	Finds the most specific subnet for the IP you supplied


=cut
sub findsubnetclosestmatch
{
	my $self = shift;

	$self->_debug_print ("Find subnet for IP '$_[0]'");

	$self->_find(_subnet_closest_match => 'HOSTDB::Object::Subnet', $self->aton ($_[0]));
}


=head2 findsubnetlongerprefix

	$subnet = $hostdb->findsubnetlongerprefix("130.237.0.0/16");

	Finds all subnets inside the supernet you supply


=cut
sub findsubnetlongerprefix
{
	my $self = shift;
	my $supernet = shift;

	$self->_debug_print ("Find all subnets inside '$supernet'");

	my ($netaddr, $slash) = split('/', $supernet);
	my $broadcast = $self->get_broadcast ($supernet);

	$self->_find(_subnet_longer_prefix => 'HOSTDB::Object::Subnet',
		$self->aton ($netaddr), $self->aton ($broadcast));
}


########################################
# package HOSTDB::DB private functions #
########################################


=head1 PACKAGE HOSTDB::DB PRIVATE FUNCTIONS

	These functions should NEVER be called by a program using this class,
	but are documented here as well just for the sake of documentation.


=head2 _find

	$self->_find(_hostbyname => 'HOSTDB::Object::Host', 'min.it.su.se');

	Executes the pre-prepared SQL query _hostbyname, returns one or many
	HOSTDB::Object::Host object.

	If in scalar context, returns just the first record - otherwise an array.	

=cut
sub _find
{
	my $self = shift;
	my $key = shift;
	my $class = shift;
	my $sth = $self->{$key};

	$sth->execute(@_) or die "$DBI::errstr";

	if (defined ($self->{debug}) and $self->{debug} > 0) {
		my @t;
		
		# make list of query arguments suitable for debugging
		my $t2;
		foreach $t2 (@_) {
			push (@t, "'$t2'");
		}
		
		$self->_debug_print ("Got " . $sth->rows . " entry(s) when querying for " .
			join(", ", @t) . " ($class)\n");
	}

	my (@retval,$hr);
	while ($hr = $sth->fetchrow_hashref()) {
		my $o = bless $hr,$class;
		foreach my $k (keys %{$hr}) {
			# strip leading and trailing white space on all keys
			$hr->{$k} =~ s/^\s*(.*?)\s*$/$1/;
		}
		$o->{hostdb} = $self;
		$o->{debug} = $self->{debug};
		$o->init();
		push(@retval,$o);
	}
	$sth->finish();
	wantarray ? @retval : $retval[0];
}





##################################################################

package HOSTDB::Object;
@HOSTDB::Object::ISA = qw(HOSTDB);

sub init
{


}


##################################################################

package HOSTDB::Object::Host;
@HOSTDB::Object::Host::ISA = qw(HOSTDB::Object);

sub init
{
	my $self = shift;
	my $hostdb = $self->{hostdb};

	$self->_debug_print ("creating object");

	if ($hostdb->{_dbh}) {
		$self->{_new_host} = $hostdb->{_dbh}->prepare ("INSERT INTO $hostdb->{db}.host (dhcpmode, dhcpstatus, mac, dnsmode, dnsstatus, hostname, ip, n_ip, owner, ttl, user, partof, mac_address_ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
			or die "$DBI::errstr";
		$self->{_update_host} = $hostdb->{_dbh}->prepare ("UPDATE $hostdb->{db}.host SET dhcpmode = ?, dhcpstatus = ?, mac = ?, dnsmode = ?, dnsstatus = ?, hostname = ?, ip = ?, n_ip = ?, owner = ?, ttl = ?, user = ?, partof = ?, mac_address_ts = ?, WHERE id = ?")
			or die "$DBI::errstr";

		$self->{_get_last_id} = $hostdb->{_dbh}->prepare ("SELECT LAST_INSERT_ID()")
			or die "$DBI::errstr";
	}
	
	return 1;
}

=head1 PACKAGE HOSTDB::Object::Host


=head2 commit

	$host->commit () or die ("Could not commit host object: $host->{error}\n");

	Commit this host object to database. Works on new host objects as well
	as updated ones.


=cut
sub commit
{
	my $self = shift;

	# fields in database order
	my @db_values = ($self->dhcpmode (),
			 $self->dhcpstatus (),
			 $self->mac_address (),
			 $self->dnsmode (),
			 $self->dnsstatus (),
			 $self->hostname (),
			 $self->ip (),
			 $self->n_ip (),
			 $self->owner (),
			 $self->ttl (),
			 $self->user (),
			 $self->partof (),
			 $self->mac_address_ts ()
			);
	my $sth;
	if (defined ($self->id ()) and $self->id () >= 0) {
		$sth = $self->{_update_host};
		$sth->execute (@db_values, $self->id ())
			or die "$DBI::errstr";
		
		# XXX check number of rows affected?

		$sth->finish();
	} else {
		# this is a new entry

		$sth = $self->{_new_host};
		$sth->execute (@db_values) or die "$DBI::errstr";

		$sth->finish ();

		# fill in $self->{id}
		$sth = $self->{_get_last_id};
		$sth->execute () or die "$DBI::errstr";
		my @t = $sth->fetchrow_array ();
		$self->{id} = $t[0];
		$sth->finish ();
	}	

	return 1;
}


=head2 dhcpmode

	Set DHCP mode for this host. This can be either DYNAMIC or STATIC.


	# set property
	$host->dhcpmode ("STATIC");

	print ("This is a dynamic entry\n") if ($host->dhcpmode () eq "DYNAMIC");


=cut
sub dhcpmode
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue eq "DYNAMIC" or $newvalue eq "STATIC") {
			$self->{dhcpmode} = $newvalue;
		} else {
			$self->set_error ("Invalid dhcpmode '$newvalue'");
			return 0;
		}

		return 1;
	}

	return ($self->{dhcpmode});
}


=head2 dhcpstatus

	Set DHCP status for this host. This can be either ENABLED or DISABLED.
	This effectively controls wheter to generate any DHCP config for this
	host or not.

	# set property
	$host->dhcpstatus ("DISABLED");

	if ($host->dhcpstatus () eq "DISABLED") {
		print ("Will not generate any DHCP config for this host \n");
	}


=cut
sub dhcpstatus
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue eq "ENABLED" or $newvalue eq "DISABLED") {
			$self->{dhcpstatus} = $newvalue;
		} else {
			$self->set_error ("Invalid dhcpstatus '$newvalue'");
			return 0;
		}

		return 1;
	}

	return ($self->{dhcpstatus});
}


=head2 mac_address

	Get or set this hosts MAC address (hardware address).
	Uses clean_mac_address () on supplied value.

	print ("Old MAC address: " . $host->mac_address ());
	$host->mac_address ($new_mac) or warn ("Failed setting value\n");


=cut
sub mac_address
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		return 0 if (! $self->clean_mac_address ($newvalue));
		$self->{mac} = $newvalue;

		return 1;
	}

	return ($self->{mac});
}


=head2 dnsmode

	Set DHCP mode for this host. This can be either A_AND_PTR or A.
	'A_AND_PTR' is for regular hosts, it will generate both A and PTR
	DNS records. 'A' is to just generate an A record and no PTR.


	# set property
	$host->dnsmode ("A");

	print ("This is an alias\n") if ($host->dnsmode () eq "A");


=cut
sub dnsmode
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue eq "A_AND_PTR" or $newvalue eq "A") {
			$self->{dnsmode} = $newvalue;
		} else {
			$self->set_error ("Invalid dnsmode '$newvalue'");
			return 0;
		}

		return 1;
	}

	return ($self->{dnsmode});
}


=head2 dnsstatus

	Set DNS status for this host. This can be either ENABLED or DISABLED.
	This effectively controls wheter to generate any DNS config for this
	host or not.

	# set property
	$host->dnsstatus ("DISABLED");

	if ($host->dnsstatus () eq "DISABLED") {
		print ("Will not generate any DNS config for this host \n");
	}


=cut
sub dnsstatus
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue eq "ENABLED" or $newvalue eq "DISABLED") {
			$self->{dnsstatus} = $newvalue;
		} else {
			$self->set_error ("Invalid dnsstatus '$newvalue'");
			return 0;
		}

		return 1;
	}

	return ($self->{dnsstatus});
}


=head2 hostname

	Get or set this hosts hostname.
	Uses clean_hostname () on supplied value.

	print ("Old hostname: " . $host->hostname ());
	$host->hostname ($new_hostname) or warn ("Failed setting value\n");


=cut
sub hostname
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		return 0 if (! $self->clean_hostname ($newvalue));
		$self->{hostname} = $newvalue;

		return 1;
	}

	return ($self->{hostname});
}


=head2 ip

	Get or set this hosts IP address. This function also updates the
	numerical IP address field n_ip.

	print ("Old IP: " . $host->ip ());
	$host->ip ($new_ip) or warn ("Failed setting value\n");


=cut
sub ip
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		return 0 if (! $self->is_valid_ip ($newvalue));

		# XXX CHECK IP
		# check if IP is
		#
		# 127.0.0.0/8
		# 0.0.0.0/8
		# 255.0.0.0/8
		# 172.16.0.0/12
		# 224.0.0.0/4
		#
		# and ideally the assigned test networks too
		#
		# (10.0.0.0/8 are IP telephones and 192.168.0.0/16 is used)
		#
		
		$self->{ip} = $newvalue;

		# redundantly stored, but this enables us to do much simpler
		# database querys (for hosts in ranges of IPs etc.)
		$self->{n_ip} = $self->aton ($newvalue);
	
		return 1;
	}

	return ($self->{ip});
}


=head2 n_ip

	Read only function that returns this hosts IP address in host order.


=cut
sub n_ip
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by ip()");
		return undef;
	}

	return ($self->{n_ip});
}


=head2 ip

	Get or set this hosts DNS records TTL value.
	XXX it is not defined if this should be a number of seconds or
	numerical IP address field n_ip.

	If you want to use the default TTL value, set to "NULL".

	print ("Old ttl: " . $host->ttl ());
	$host->ttl ($new_ttl) or warn ("Failed setting value\n");


=cut
sub ttl
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{ttl} = undef;
		} else {
			$self->{ttl} = $newvalue;
		}

		return 1;
	}

	return ($self->{ttl});
}


=head2 user

	Get or set this hosts user. Just an informative field.
	XXX this might be changed to a more generic comment field. XXX

	print ("Old user: " . $host->user ());
	$host->user ($new_user) or warn ("Failed setting value\n");


=cut
sub user
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		$self->{user} = $newvalue;
	
		return 1;
	}

	return ($self->{user});
}


=head2 owner

	Get or set this hosts owner. The thoughts for having a owner is
	to control who can update this object.

	print ("Old owner: " . $host->owner ());
	$host->owner ($new_owner) or warn ("Failed setting value\n");


=cut
sub owner
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		$self->{user} = $newvalue;
	
		return 1;
	}

	return ($self->{user});
}


=head2 id

	Get object database ID number. This is read only.

=cut
sub id
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("id is read only");
		return 0;
	}

	return ($self->{id});
}


=head2 partof

	Get or set which other host object this host object is to be
	considered a part of. A host with multiple network interface
	cards (meaning multiple MAC addresses and possibly multiple
	DNS records) will have a primary host id object and one or
	more other host objects which has partof () set to the primary
	host objects id ().

	print ("Old partof: " . $host->partof ());
	$parent = $hostdb->findhostbyname ("server.example.com");
	die ("Failed fetching parent host object\n") unless ($parent);
	$host->partof ($parent->id ()) or warn ("Failed setting value\n");


=cut
sub partof
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ((int($newvalue) == 0) and ($newvalue ne "0")) {
			$self->set_error ("Invalid partof");
			return 0;
		}
		$self->{partof} = int($newvalue);

		return 1;
	}

	return ($self->{partof});
}


=head2 mac_address_ts

	Get or set the MAC address timestamp field of this host object.
	This is intended to be a timestamp of what the time was when this
	hosts IP was seen using this MAC address on the network. This is
	good because it let's network administrators see what IP addresses
	are actually being used and not.

	Valid formats for setting are: yyyy-mm-dd hh:mm:ss
				       NOW
				       unixtime:nnnnnnnnnn

=cut
sub mac_address_ts
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue =~ /^\d{2,4}-\d{1,2}-\d{1,2} \d{1,2}:\d{1,2}:\d{1,2}$/o) {
			$self->{mac_address_ts} = $newvalue;
		} elsif ($newvalue eq "NOW" or $newvalue eq "NOW()") {
			$self->{mac_address_ts} = $self->unixtime_to_datetime (time ());
		} elsif ($newvalue =~ /^unixtime:(\d+)$/oi) {
			$self->{mac_address_ts} = $self->unixtime_to_datetime ($1);
		} else {
			$self->set_error ("Invalid mac_address timestamp format");
			return 0;
		}

		return 1;
	}

	return ($self->{mac_address_ts});
}


=head1 PACKAGE HOSTDB::DB::Object::Host PRIVATE FUNCTIONS

	These functions should NEVER be called by a program using this class,
	but are documented here as well just for the sake of documentation.


=head2 unixtime_to_datetime

	Convert a unix time stamp to localtime () format yyyy-mm-dd hh:mm:ss

	$now_as_string = $self->unixtime_to_datetime (time ());


=cut
sub unixtime_to_datetime
{
	my $self = shift;
	my $time = shift;

	my ($sec, $min, $hour, $mday, $mon, $year, $yday, $isdst) = localtime ($time);
	
	$year += 1900;	# yes, this is Y2K safe (why do you even bother? this was written
			# in the year of 2002)
	
	return (sprintf ("%.4d-%.2d-%.2d %.2d:%.2d:%.2d",
		$year, $mon, $mday, $hour, $min, $sec));
}


##################################################################

package HOSTDB::Object::Zone;
@HOSTDB::Object::Zone::ISA = qw(HOSTDB::Object);

sub init
{
	my $self = shift;
	my $hostdb = $self->{hostdb};

	$self->_debug_print ("creating object");

	if ($hostdb->{_dbh}) {
		$self->{_new_zone} = $hostdb->{_dbh}->prepare ("INSERT INTO $hostdb->{db}.zone (zonename, delegated, default_ttl, ttl, mname, rname, serial, refresh, retry, expiry, minimum, owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
			or die "$DBI::errstr";
		$self->{_update_zone} = $hostdb->{_dbh}->prepare ("UPDATE $hostdb->{db}.zone SET zonename = ?, delegated = ?, default_ttl = ?, ttl = ?, mname = ?, rname = ?, serial = ?, refresh = ?, retry = ?, expiry = ?, minimum = ?, owner = ? WHERE zonename = ?")
			or die "$DBI::errstr";
	}

	# XXX ugly hack to differentiate on zones already in DB
	# (find* sets this to 1) and new zones
	$self->{in_db} = 0;

	return 1;
}

=head1 PACKAGE HOSTDB::Object::Zone


=head2 commit

	$zone->commit () or die ("Could not commit zone object: $zone->{error}\n");

	Commit this zone object to database. Works on new zone objects as well
	as updated ones.


=cut
sub commit
{
	my $self = shift;

	# fields in database order
	my @db_values = ($self->zonename (),
			 $self->delegated (),
			 $self->default_ttl (),
			 $self->ttl (),
			 $self->mname (),
			 $self->rname (),
			 $self->serial (),
			 $self->refresh (),
			 $self->retry (),
			 $self->expiry (),
			 $self->minimum (),
			 $self->owner ()
			);

	my $sth;
	if (defined ($self->{in_db}) and $self->{in_db} >= 1) {
		$sth = $self->{_update_zone};
		$sth->execute (@db_values, $self->{zonename})
			or die "$DBI::errstr";
		
		# XXX check number of rows affected?

		$sth->finish();
	} else {
		# this is a new entry

		$sth = $self->{_new_zone};
		$sth->execute (@db_values) or die "$DBI::errstr";

		$sth->finish ();
	}	

	return 1;
}

sub zonename
{
	my $self = shift;

	if (@_) {
		my $zonename = shift;
	
		return 0 if (! $self->clean_domainname ($zonename));
		$self->{zonename} = $zonename;
		
		return 1;
	}

	return ($self->{zonename});
}


=head2 delegated

	Indicate that this is a delegated zone. The reason to have delegated
	zones in your database is that if it is a subzone of one of your
	non-delegated zones you do not want to put host DNS data into your
	non-delegated zone which belongs to the delegated one. Clear? ;)


	# set property
	$zone->delegated ("Y");	# valid values are "Y" (or 1), "N" (or 0)

	# when used to get the value, always returns "Y" or "N" so you
	# can't just do 'if ($zone->delegated ()) ...'
	#
	print ("Zone is delegated\n") if ($zone->delegated () eq "Y");


=cut
sub delegated
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue =~ /^y/i or $newvalue == 1) {
			$self->{delegated} = "Y";
		} elsif ($newvalue =~ /^n/i or $newvalue == 0) {
			$self->{delegated} = "N";
		} else {
			$self->set_error ("Invalid delegated format");
			return 0;
		}
		
		return 1;
	}

	return ($self->{delegated});
}

# this is the zone default ttl ($TTL)
sub default_ttl
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{default_ttl} = undef;
		} else {
			$self->{default_ttl} = int ($newvalue);
		}
		
		return 1;
	}

	return ($self->{default_ttl});
}

sub serial
{
	my $self = shift;
	if (@_) {
		my $newvalue = shift;

		$self->_debug_print ("Setting SOA serial '$newvalue'");

		if ($newvalue eq "NULL") {
			$self->{serial} = undef;
		} else {
			if ($newvalue !~ /^\d{10,10}$/) {
				$self->_set_error("Invalid serial number (should be 10 digits, todays date and two incrementing)");
				return 0;
			}
			$self->{serial} = int ($newvalue);
		}
		
		return 1;
	}

	return ($self->{serial});
}

sub mname
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{mname} = "NULL";
		} else {
			my $illegal_chars = $newvalue;
			$illegal_chars =~ s/[a-zA-Z0-9\.\-]//og;
			if ($illegal_chars) {
				$self->_set_error ("SOA mname '$newvalue' contains illegal characters ($illegal_chars)");
				return 0;
			}
		}

		$self->{mname} = $newvalue;
		
		return 1;
	}

	return ($self->{mname});
}

sub rname
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{rname} = "NULL";
		} else {
			if ($newvalue =~ /@/) {
				$self->_set_error ("SOA rname ($newvalue) should not contain '\@' signs.");
				return 0;
			}

			my $illegal_chars = $newvalue;
			$illegal_chars =~ s/[a-zA-Z0-9\.\-]//og;
			if ($illegal_chars) {
				$self->_set_error ("SOA rname ($newvalue) contains illegal characters ($illegal_chars)");
				return 0;
			}
		}

		$self->{rname} = $newvalue;
		
		return 1;
	}

	return ($self->{mname});
}

sub refresh
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{refresh} = "NULL";
		} else {
			$self->{refresh} = int ($newvalue);
		}
		
		return 1;
	}

	return ($self->{refresh});
}

# this is the SOA record itselfs TTL
sub ttl
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{ttl} = "NULL";
		} else {
			$self->{ttl} = int ($newvalue);
		}
		
		return 1;
	}

	return ($self->{ttl});
}

sub retry
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{retry} = "NULL";
		} else {
			$self->{retry} = int ($newvalue);
		}
		
		return 1;
	}

	return ($self->{retry});
}

sub expiry
{
	my $self = shift;
	
	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{expiry} = "NULL";
		} else {
			$self->{expiry} = int ($newvalue);
		}
		
		return 1;
	}

	return ($self->{expiry});
}

sub minimum
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq "NULL") {
			$self->{minimum} = "NULL";
		} else {
			$self->{minimum} = int ($newvalue);
		}
		
		return 1;
	}
	
	return ($self->{minimum});
}

sub owner
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		$self->{owner} = $newvalue;
		
		return 1;
	}
		
	return ($self->{owner});
}


##################################################################

package HOSTDB::Object::Subnet;
@HOSTDB::Object::Subnet::ISA = qw(HOSTDB::Object);

sub init
{
	my $self = shift;
	my $hostdb = $self->{hostdb};

	if (! defined ($self->{subnet})) {
		# subnet not defined, this can be because our caller is the _find function
		if (defined ($self->{netaddr}) and
		    defined ($self->{slashnotation})) {
		
			$self->{subnet} = "$self->{netaddr}/$self->{slashnotation}";

			# XXX ugly hack
			$self->{in_db} = 1;
		}
	} else {
		# XXX ugly hack
		$self->{in_db} = 0;
	}
	
	$hostdb->_debug_print ("creating object (IPv$self->{ipver} subnet '$self->{subnet}')");

	return undef if (! $self->subnet ($self->{subnet}));
	delete ($self->{subnet});	# the info is kept in $self->{netaddr} and $self->{slashnotation}
	
	if ($hostdb->{_dbh}) {
		$self->{_new_subnet} = $hostdb->{_dbh}->prepare ("INSERT INTO $hostdb->{db}.subnet " .
			"(ipver, netaddr, slashnotation, netmask, broadcast, addresses, description, " .
			"short_description, n_netaddr, n_netmask, n_broadcast, htmlcolor, dhcpconfig) " .
			"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
			or die "$DBI::errstr";
		$self->{_update_subnet} = $hostdb->{_dbh}->prepare ("UPDATE $hostdb->{db}.subnet SET " .
			"ipver = ?, netaddr = ?, slashnotation = ?, netmask = ?, broadcast = ?, " .
			"addresses = ?, " .
			"description = ?, short_description = ?, n_netaddr = ?, n_netmask = ?, " .
			"n_broadcast = ?, htmlcolor = ?, dhcpconfig = ? WHERE id = ?")
			or die "$DBI::errstr";
		$self->{_delete} = $hostdb->{_dbh}->prepare ("DELETE FROM $hostdb->{db}.subnet WHERE id = ?");
	} else {
		$hostdb->_debug_print ("NOT preparing database stuff");
	}

	return 1;
}

=head1 PACKAGE HOSTDB::Object::Subnet


=head2 commit

	$subnet->commit () or die ("Could not commit subnet object: $subnet->{error}\n");

	Commit this subnet object to database. Works on new subnet objects as well
	as updated ones.


=cut
sub commit
{
	my $self = shift;

	# fields in database order
	my @db_values = ($self->ipver (),
			 $self->netaddr (),
			 $self->slashnotation (),
			 $self->netmask (),
			 $self->broadcast (),
			 $self->addresses (),
			 $self->description (),
			 $self->short_description (),
			 $self->n_netaddr (),
			 $self->n_netmask (),
			 $self->n_broadcast (),
			 $self->htmlcolor (),
			 $self->dhcpconfig ()
			);

	my $sth;
	if (defined ($self->{id})) {
		$sth = $self->{_update_subnet};
		$sth->execute (@db_values, $self->id ()) or die "$DBI::errstr";
		
		# XXX check number of rows affected?

		$sth->finish();
	} else {
		# this is a new entry, first check that it does not overlap
		# with something already in the database

		my $hostdb = $self->{hostdb};
		my @subnets = $hostdb->findsubnetlongerprefix ($self->subnet ());
		
		if ($#subnets != -1) {
			my ($t, @names);
			
			foreach $t (@subnets) {
				push (@names, $t->subnet ());
			}
			
			$self->_set_error ($self->subnet () . " overlaps with subnet(s) " .
					   join (", ", @names));
					   
			return 0;
		}

		$sth = $self->{_new_subnet};
		$sth->execute (@db_values) or die "$DBI::errstr";

		$sth->finish ();
	}	

	return 1;
}

sub delete
{
	my $self = shift;
	my $check = shift;

	return 0 if ($check ne "YES");

	my $sth;
	if (defined ($self->{id})) {
		$sth = $self->{_delete};
		$sth->execute ($self->id ()) or die "$DBI::errstr";
		
		# XXX check number of rows affected?

		$sth->finish();
	} else {
		$self->_set_error ("Subnet not in database");
		return 0;
	}

	return 1;
}

sub subnet
{
	my $self = shift;

	if (@_) {
		my $subnet = shift;

		$self->_debug_print ("setting subnet '$subnet'");

		return undef if (! $self->is_valid_subnet ($subnet));
	
		my ($netaddr, $slash) = split ('/', $subnet);

		$self->{netaddr} = $netaddr;
		$self->{slashnotation} = $slash;

		# All these are redundantly stored. Some people I'm sure
		# calls it database bloat, poor design etcetera but I call
		# it simpler querys, less code (except here), less bugs.
		# In one word - better.
		$self->{n_netaddr} = $self->aton ($netaddr);
		$self->{netmask} = $self->slashtonetmask ($slash);
		$self->{n_netmask} = $self->aton ($self->slashtonetmask ($slash));
		$self->{addresses} = $self->get_num_addresses ($slash);
		$self->{broadcast} = $self->get_broadcast ($subnet);
		$self->{n_broadcast} = $self->aton ($self->{broadcast});

		return 1;
	}
	
	return ($self->netaddr () . "/" . $self->slashnotation ());
}

sub id
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it is a database auto increment");
		return undef;
	}

	return ($self->{id});
}

sub ipver
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue != 4 && $newvalue && 6) {
			$self->_set_error ("IP version " . $self->ipver () . " invalid (let's keep to 4 or 6 please)");
			return 0;
		}
		
		$self->{ipver} = $newvalue;
		
		return 1;
	}

	return ($self->{ipver});
}

sub netaddr
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{netaddr});
}

sub slashnotation
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{slashnotation});
}

sub netmask
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{netmask});
}

sub broadcast
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{broadcast});
}

sub addresses
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{addresses});
}

sub description
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{description} = $newvalue;
		
		return 1;
	}

	return ($self->{description});
}

sub short_description
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{short_description} = $newvalue;
		
		return 1;
	}

	return ($self->{short_description});
}

sub n_netaddr
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{n_netaddr});
}

sub n_netmask
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{n_netmask});
}

sub n_broadcast
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("this is a read-only function, it gets set by subnet()");
		return undef;
	}

	return ($self->{n_broadcast});
}

sub htmlcolor
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{htmlcolor} = $newvalue;
		
		return 1;
	}

	return ($self->{htmlcolor});
}

sub dhcpconfig
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{dhcpconfig} = $newvalue;
		
		return 1;
	}

	return ($self->{dhcpconfig});
}


##################################################################


package HOSTDB;

1;
__END__

=head1 AUTHOR

Fredrik Thulin <ft@it.su.se>, Stockholm University

=head1 SEE ALSO
~
L<perl>.

=cut
