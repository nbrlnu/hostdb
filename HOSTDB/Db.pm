# $Id$

use HOSTDB;
use Config::IniFiles;
use strict;

package HOSTDB::DB;
@HOSTDB::DB::ISA = qw(HOSTDB);


=head1 NAME

HOSTDB::Db - Database access routines.

=head1 SYNOPSIS

  use HOSTDB;

  my $hostdb = HOSTDB::DB->new (dsn => $dsn, db => $db, user = $user,
				password => $pw);

  or
  
  my $hostdb = HOSTDB::DB->new (ini => $inifile);

  or

  my $hostdb = HOSTDB::DB->new (inifilename => $filename);


=head1 DESCRIPTION

Database access routines.


=head1 EXPORT

None.

=head1 METHODS

=cut


sub init
{
	my $self = shift;

	if (defined ($self->{inifile})) {
		$self->{ini} = Config::IniFiles->new (-file => $self->{inifile});
			
		unless (defined ($self->{ini})) {
			die ("Could not create HOSTDB object, config file '$self->{inifile}");
		}
	}
		
	if (defined ($self->{ini})) {
		# db settings
		$self->{dsn} = $self->{ini}->val ('db', 'dsn') unless (defined ($self->{dsn}));
		$self->{db} = $self->{ini}->val ('db', 'database') unless (defined ($self->{db}));
		$self->{user} = $self->{ini}->val ('db', 'user') unless (defined ($self->{user}));
		$self->{password} = $self->{ini}->val ('db', 'password') unless (defined ($self->{password}));
		$self->{auto_reconnect} = $self->{ini}->val ('db', 'auto_reconnect') || '' unless (defined ($self->{auto_reconnect}));

		# other misc settings
		$self->{auth_ldap_server} = $self->{ini}->val ('auth', 'ldap_server') unless (defined ($self->{auth_ldap_server}));
		$self->{auth_admins} = $self->{ini}->val ('auth', 'admins') unless (defined ($self->{auth_admins}));
		$self->{auth_helpdesk} = $self->{ini}->val ('auth', 'helpdesk') unless (defined ($self->{auth_helpdesk}));
		unless (defined ($self->{dont_authorize})) {
			my $v = $self->{ini}->val ('auth', 'dont_authorize') || '';
			$self->{auth_disabled} = 'DISABLED' if ($v eq 'YES');
		}
	}

	if (defined ($self->{dsn})) {
		$self->{_dbh} = DBI->connect ($self->{dsn}, $self->{user}, $self->{password}) or die "$DBI::errstr";

		if (lc ($self->{auto_reconnect}) eq 'true' or lc ($self->{auto_reconnect}) eq 'yes') {
		    if ($self->{dsn} =~ /^dbi:mysql:/o) {
			$self->_debug_print ("Requesting DB auto-reconnect\n");
			$self->{_dbh}{'mysql_auto_reconnect'} = 1;
		    } else {
			# do not output DSN in case it contains passwords...
			die ("HOSTDB: Database auto-reconnect requested by configuration, but DSN is not 'dbi:mysql'.\n");
		    }
		}

		##
		## HOST
		##
		my $SELECT_host = "SELECT *, UNIX_TIMESTAMP(mac_address_ts) AS unix_mac_address_ts FROM $self->{db}.host";
		$self->{_hostbyid}		= $self->{_dbh}->prepare ("$SELECT_host WHERE id = ? ORDER BY id")			or die "$DBI::errstr";
		$self->{_hostbypartof}		= $self->{_dbh}->prepare ("$SELECT_host WHERE partof = ? ORDER BY id")			or die "$DBI::errstr";
		$self->{_hostbymac}		= $self->{_dbh}->prepare ("$SELECT_host WHERE mac = ? ORDER BY mac")			or die "$DBI::errstr";
		$self->{_hostbyname}		= $self->{_dbh}->prepare ("$SELECT_host WHERE hostname = ? ORDER BY hostname")		or die "$DBI::errstr";
		$self->{_hostbyzone}		= $self->{_dbh}->prepare ("$SELECT_host WHERE dnszone = ? ORDER BY hostname")		or die "$DBI::errstr";
		$self->{_hostbywildcardname}	= $self->{_dbh}->prepare ("$SELECT_host WHERE hostname LIKE ? ORDER BY hostname")		or die "$DBI::errstr";
		$self->{_hostbyip}		= $self->{_dbh}->prepare ("$SELECT_host WHERE ip = ? ORDER BY n_ip")			or die "$DBI::errstr";
		$self->{_hostbyiprange}		= $self->{_dbh}->prepare ("$SELECT_host WHERE n_ip >= ? AND n_ip <= ? ORDER BY n_ip")	or die "$DBI::errstr";
		$self->{_allhosts}		= $self->{_dbh}->prepare ("$SELECT_host ORDER BY id")					or die "$DBI::errstr";

		##
		## HOSTS BY ATTRIBUTE
		##
		my $SELECT_hostwithattr = "SELECT host.*, UNIX_TIMESTAMP(host.mac_address_ts) AS unix_mac_address_ts FROM $self->{db}.host, $self->{db}.hostattribute WHERE host.id = hostattribute.hostid AND hostattribute.v_key = ? AND hostattribute.v_section = ?";
		$self->{_hostswithattr_streq} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'string' AND hostattribute.v_string = ?");
		$self->{_hostswithattr_strne} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'string' AND hostattribute.v_string != ?");
		$self->{_hostswithattr_strlike} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'string' AND hostattribute.v_string LIKE ?");
		$self->{_hostswithattr_strnotlike} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'string' AND hostattribute.v_string NOT LIKE ?");
		$self->{_hostswithattr_inteq} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'int' AND hostattribute.v_int = ?");
		$self->{_hostswithattr_intne} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'int' AND hostattribute.v_int != ?");
		$self->{_hostswithattr_intgt} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'int' AND hostattribute.v_int > ?");
		$self->{_hostswithattr_intlt} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'int' AND hostattribute.v_int < ?");
		$self->{_hostswithattr_blobeq} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'blob' AND hostattribute.v_blob = ?");
		$self->{_hostswithattr_blobne} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'blob' AND hostattribute.v_blob != ?");
		$self->{_hostswithattr_bloblike} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'blob' AND hostattribute.v_blob LIKE ?");
		$self->{_hostswithattr_blobnotlike} = $self->{_dbh}->prepare ("$SELECT_hostwithattr AND hostattribute.v_type = 'blob' AND hostattribute.v_blob NOT LIKE ?");

		##
		## HOSTS BY ALIAS
		##
		my $SELECT_hostwithalias = "SELECT host.*, UNIX_TIMESTAMP(host.mac_address_ts) AS unix_mac_address_ts FROM $self->{db}.host, $self->{db}.hostalias WHERE host.id = hostalias.hostid";
		$self->{_hostswithaliasname}		= $self->{_dbh}->prepare ("$SELECT_hostwithalias AND hostalias.aliasname = ? ORDER BY host.hostname, hostalias.aliasname");
		$self->{_hostswithaliaswildcardname}	= $self->{_dbh}->prepare ("$SELECT_hostwithalias AND hostalias.aliasname LIKE ? ORDER BY host.hostname, hostalias.aliasname");

		##
		## HOST ATTRIBUTE
		##
		my $SELECT_hostattr = "SELECT *, UNIX_TIMESTAMP(lastmodified) AS unix_lastmodified, UNIX_TIMESTAMP(lastupdated) AS unix_lastupdated FROM $self->{db}.hostattribute";
		$self->{_hostattributebyid}		= $self->{_dbh}->prepare ("$SELECT_hostattr WHERE id = ? ORDER BY id") or die "$DBI::errstr";
		$self->{_hostattributesbyhostid}	= $self->{_dbh}->prepare ("$SELECT_hostattr WHERE hostid = ? ORDER BY v_section, v_key") or die "$DBI::errstr";

		##
		## HOST ALIAS
		##
		my $SELECT_hostalias = "SELECT * FROM $self->{db}.hostalias";
		$self->{_hostaliasbyid}		= $self->{_dbh}->prepare ("$SELECT_hostalias WHERE id = ? ORDER BY id") or die "$DBI::errstr";
		$self->{_hostaliasbyname}	= $self->{_dbh}->prepare ("$SELECT_hostalias WHERE aliasname = ? ORDER BY id") or die "$DBI::errstr";
		$self->{_hostaliasesbyhostid}	= $self->{_dbh}->prepare ("$SELECT_hostalias WHERE hostid = ? ORDER BY aliasname") or die "$DBI::errstr";
		$self->{_hostaliasesbydnszone}	= $self->{_dbh}->prepare ("$SELECT_hostalias WHERE dnszone = ? ORDER BY aliasname") or die "$DBI::errstr";
		$self->{_allhostaliases}	= $self->{_dbh}->prepare ("$SELECT_hostalias ORDER by aliasname, id") or die "$DBI::errstr";

		##
		## ZONE
		##
		my $SELECT_zone = "SELECT * FROM $self->{db}.zone";
		$self->{_zonebyname}	= $self->{_dbh}->prepare ("$SELECT_zone WHERE zonename = ? ORDER BY zonename") or die "$DBI::errstr";
		$self->{_zonebyid}	= $self->{_dbh}->prepare ("$SELECT_zone WHERE id = ? ORDER BY zonename") or die "$DBI::errstr";
		$self->{_allzones}	= $self->{_dbh}->prepare ("$SELECT_zone ORDER BY zonename") or die "$DBI::errstr";

		##
		## SUBNET
		##
		my $SELECT_subnet = "SELECT * FROM $self->{db}.subnet";
		$self->{_subnet}		= $self->{_dbh}->prepare ("$SELECT_subnet WHERE netaddr = ? AND slashnotation = ? ORDER BY n_netaddr") or die "$DBI::errstr";
		$self->{_subnet_longer_prefix}	= $self->{_dbh}->prepare ("$SELECT_subnet WHERE n_netaddr >= ? AND n_netaddr <= ? ORDER BY n_netaddr") or die "$DBI::errstr";
		$self->{_subnetbyip}		= $self->{_dbh}->prepare ("$SELECT_subnet WHERE n_netaddr <= ? AND n_broadcast >= ? ORDER BY n_netaddr DESC LIMIT 1") or die "$DBI::errstr";
		$self->{_subnetbyid}		= $self->{_dbh}->prepare ("$SELECT_subnet WHERE id = ? ORDER BY n_netaddr") or die "$DBI::errstr";
		$self->{_allsubnets}		= $self->{_dbh}->prepare ("$SELECT_subnet ORDER BY n_netaddr") or die "$DBI::errstr";
	} else {
		$self->_debug_print ("DSN not provided, not connecting to database.");
	}

	$self->user (getpwuid("$<"));

	# create an HOSTDB::Auth to be used for authorization
	$self->{auth} = $self->create_auth (authorization => $self->{auth_disabled});
	if (defined ($self->{auth_ldap_server})) {
		if (! $self->auth->ldap_server ($self->{auth_ldap_server})) {
			die ("Could not connect to LDAP server '$self->{auth_ldap_server}'\n");
		}
	}
	$self->auth->admin_list (split (',', $self->{auth_admins})) if (defined ($self->{auth_admins}));
	$self->auth->helpdesk_list (split (',', $self->{auth_helpdesk})) if (defined ($self->{auth_helpdesk}));
	$self->{auth_ldap_server} = undef;
	$self->{auth_admins} = undef;
	$self->{auth_helpdesk} = undef;
	$self->{auth_disabled} = undef;

	return 1;
}

sub DESTROY
{
	my $self = shift;

	$self->{_dbh}->disconnect() if (defined ($self->{_dbh}));
}


####################
# PUBLIC FUNCTIONS #
####################


=head1 PUBLIC FUNCTIONS


=head2 inifile

	my $inifile = $hostdb->inifile ();
	
	Fetch the Config::IniFiles object that was supplied to the new ()
	function (this is a read only function).


=cut
sub inifile
{
	my $self = shift;

	if (defined ($_[0])) {
		$self->_set_error ("inifile () is a read only function");
		
		return undef;
	}
	
	return $self->{ini};
}
	

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

		if (defined ($self->{localuser})) {
			$self->_debug_print ("Changing username from '$self->{localuser}' to $user");
		} else {
			$self->_debug_print ("Initializing username: $user");
		}
		$self->{localuser} = $user;

		return 1;
	}

	return ($self->{localuser});
}


=head2 auth

	Read only function. Returns the HOSTDB::Auth object created at init ().
	
	XXX write example.

=cut
sub auth
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("auth () is a read-only function");
		return undef;
	}

	return ($self->{auth});
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


=head2 create_auth

	$auth = $hostdb->create_auth();

	Gets you a brand new HOSTDB::Auth object.


=cut
sub create_auth
{
	my $self = shift;
	
	my $o = bless {}, "HOSTDB::Auth";
	$o->{ini} = $self->{ini};
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


=head2 findhostbyaliasname

	Find hosts with aliases matching a certain name.

	foreach my $host ($hostdb->findhostbyaliasname ($searchhost)) {
		printf ("%-5s %-20s %s\n", $host->id (), $host->ip (), $host->hostname ());
	}


=cut
sub findhostbyaliasname
{
	my $self = shift;
	my @res;

	$self->_debug_print ("Find host with alias name '$_[0]'");
	
	if (! $self->is_valid_fqdn ($_[0]) and ! $self->is_valid_domainname ($_[0])) {
		$self->_set_error ("findhostbyaliasname: '$_[0]' is not a valid FQDN or domain name");
		return undef;
	}
	
	$self->_find(_hostswithaliasname => 'HOSTDB::Object::Host', $_[0]);
}


=head2 findhostbyaliaswildcardname

	Find hosts with aliases matching a certain name.

	foreach my $host ($hostdb->findhostbyaliaswildcardname ($searchhost)) {
		printf ("%-5s %-20s %s\n", $host->id (), $host->ip (), $host->hostname ());
	}


=cut
sub findhostbyaliaswildcardname
{
	my $self = shift;
	my $searchfor = shift;

	$searchfor =~ s/\*/%/go;

	$self->_debug_print ("Find host with alias hostname LIKE '$searchfor'");

	$self->_find(_hostswithaliaswildcardname => 'HOSTDB::Object::Host', $searchfor);
}


=head2 findhostbyzone

	foreach my $host ($hostdb->findhostbyzone ($zone)) {
		printf ("%-5s %s\n", $host->id (), $host->hostname ());
	}


=cut
sub findhostbyzone
{
	my $self = shift;
	my @res;

	$self->_debug_print ("Find hosts by zone '$_[0]'");
	
	if (! $self->is_valid_domainname ($_[0])) {
		$self->_set_error ("findhostbyzone: '$_[0]' is not a valid domain name");
		return undef;
	}
	
	$self->_find(_hostbyzone => 'HOSTDB::Object::Host', $_[0]);
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
	my $searchfor = shift;

	$searchfor =~ s/\*/%/g;
	
	$self->_debug_print ("Find host with hostname LIKE '$searchfor'");
	
	$self->_find(_hostbywildcardname => 'HOSTDB::Object::Host', $searchfor);
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

	if (! defined ($_[0]) or ! defined ($_[1])) {
		$self->_set_error ("findhostbyiprange: bad arguments\n");
		return undef;
	}

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


=head2 findhost

	Tries to find one or more host objects, with or without a clearly defined
	datatype for the search criteria.

	@hosts = $hostdb->findhost ("guess", $user_input);

	or

	@hosts = $hostdb->findhost ("IP", $ip);

	Valid datatypes (not case sensitive) are :
		Guess
		IP
		FQDN
		MAC
		ZONE

	Note that 'Guess' can\'t recognize a zone (it looks for FQDN).

=cut
sub findhost
{
	my $self = shift;
	my $datatype = lc (shift);
	my $search_for = shift;

	if (! defined ($datatype) or ! $datatype or ! defined ($search_for) or ! $search_for) {
	    my $dt = $datatype || 'undef';
	    my $sf = $search_for || 'undef';
	    die ("$0: HOSTDB findhost () called with wrong arguments (datatype = '$dt', search for = '$sf')\n");
	}

	$self->_set_error ('');
	
	if ($datatype eq 'guess' or ! $datatype) {
		my $t = $search_for;
		if ($self->clean_mac_address ($t)) {
			$search_for = $t;
			$datatype = 'mac';
		} elsif ($search_for =~ /^[+-]*(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.in-addr\.arpa\.*$/i) {
			$datatype = 'ip';
			$search_for = "$4.$3.$2.$1";
		} elsif ($self->is_valid_ip ($search_for)) {
			$datatype = 'ip';
		} elsif ($self->clean_hostname ($t)) {
			$datatype = 'fqdn';
			$search_for = $t;
		} elsif ($search_for =~ /^\d+$/) { 
			$datatype = 'id';
		} else {
			$self->_set_error ("findhost () search failed: could not guess data type of '$search_for'");
			return undef;
		}
	}

	my @host_refs;
			
	if ($datatype eq 'ip') {
		if ($self->is_valid_ip ($search_for)) {
			@host_refs = $self->findhostbyip ($search_for);
		} else {
			$self->_set_error ("findhost () search failed: '$search_for' is not a valid IP address");
			return undef;
		}
	} elsif ($datatype eq 'fqdn') {
		my $t = $search_for;
		if ($self->clean_hostname ($t)) {
			$search_for = $t;
			@host_refs = HOSTDB::unique_id ($self->findhostbyname ($search_for),
							$self->findhostbyaliasname ($search_for)
							);
		} else {
			$self->_set_error ("findhost () search failed: '$search_for' is not a valid FQDN");
			return undef;
		}
	} elsif ($datatype eq 'mac') {
		my $t = $search_for;
		if ($self->clean_mac_address ($t)) {
			$search_for = $t;
			@host_refs = $self->findhostbymac ($search_for);
		} else {
			$self->_set_error ("findhost () search failed: '$search_for' is not a valid MAC address");
			return undef;
		}
	} elsif ($datatype eq 'id') {
		if ($search_for =~ /^\d+$/) { 
			@host_refs = $self->findhostbyid ($search_for);
		} else {
			$self->_set_error ("findhost () search failed: '$search_for' is not a valid ID");
			return undef;
		}
	} else {
		$self->_set_error ("findhost () search failed: don't recognize whois datatype '$datatype'");
		return undef;
	}
	
	return @host_refs;
}


=head2 findhostswithattr_streq

	@hosts = $hostdb->findhostswithattr_streq($attribute, $section, $match);


=cut
sub findhostswithattr_streq
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') string matching '$match'");
	
	$self->_find(_hostswithattr_streq => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_strne

	@hosts = $hostdb->findhostswithattr_strne($attribute, $section, $match);


=cut
sub findhostswithattr_strne
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') string NOT matching '$match'");
	
	$self->_find(_hostswithattr_strne => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_strlike

	@hosts = $hostdb->findhostswithattr_strlike($attribute, $section, $match);


=cut
sub findhostswithattr_strlike
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') string matching wildcard pattern '$match'");
	
	$self->_find(_hostswithattr_strlike => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_strnotlike

	@hosts = $hostdb->findhostswithattr_strnotlike($attribute, $section, $match);


=cut
sub findhostswithattr_strnotlike
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') string NOT matching wildcard pattern '$match'");
	
	$self->_find(_hostswithattr_strnotlike => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_inteq

	@hosts = $hostdb->findhostswithattr_inteq($attribute, $section, $match);


=cut
sub findhostswithattr_inteq
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') integer == '$match'");
	
	$self->_find(_hostswithattr_inteq => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_intne

	@hosts = $hostdb->findhostswithattr_intne($attribute, $section, $match);


=cut
sub findhostswithattr_intne
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') integer != '$match'");
	
	$self->_find(_hostswithattr_intne => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_intgt

	@hosts = $hostdb->findhostswithattr_intgt($attribute, $section, $match);


=cut
sub findhostswithattr_intgt
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') integer == '$match'");
	
	$self->_find(_hostswithattr_intgt => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_intlt

	@hosts = $hostdb->findhostswithattr_intlt($attribute, $section, $match);


=cut
sub findhostswithattr_intlt
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') integer != '$match'");
	
	$self->_find(_hostswithattr_intlt => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_blobeq

	@hosts = $hostdb->findhostswithattr_blobeq($attribute, $section, $match);


=cut
sub findhostswithattr_blobeq
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') blob matching '$match'");
	
	$self->_find(_hostswithattr_blobeq => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_blobne

	@hosts = $hostdb->findhostswithattr_blobne($attribute, $section, $match);


=cut
sub findhostswithattr_blobne
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') blob NOT matching '$match'");
	
	$self->_find(_hostswithattr_blobne => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_bloblike

	@hosts = $hostdb->findhostswithattr_bloblike($attribute, $section, $match);


=cut
sub findhostswithattr_bloblike
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') blob matching wildcard pattern '$match'");
	
	$self->_find(_hostswithattr_bloblike => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostswithattr_blobnotlike

	@hosts = $hostdb->findhostswithattr_blobnotlike($attribute, $section, $match);


=cut
sub findhostswithattr_blobnotlike
{
	my $self = shift;
	my $attribute = shift;
	my $section = shift;
	my $match = shift;

	$self->_debug_print ("Find hosts with attribute '$attribute' (section '$section') blob NOT matching wildcard pattern '$match'");
	
	$self->_find(_hostswithattr_blobnotlike => 'HOSTDB::Object::Host', $attribute, $section, $match);
}


=head2 findhostattributebyid

        $attr = $hostdb->findhostattributebyid ($attribute_id);


=cut
sub findhostattributebyid
{
	my $self = shift;

	$self->_debug_print ("Find host attribute with id '$_[0]'");
	
	$self->_find(_hostattributebyid => 'HOSTDB::Object::HostAttribute', $_[0]);
}



=head2 findhostattributesbyhostid

	@attrs = $hostdb->findhostattributesbyhostid ($host->id ());


=cut
sub findhostattributesbyhostid
{
	my $self = shift;

	$self->_debug_print ("Find host attributes for host with id '$_[0]'");
	
	$self->_find(_hostattributesbyhostid => 'HOSTDB::Object::HostAttribute', $_[0]);
}


=head2 findhostaliasbyid

	$alias = $hostdb->findhostaliasbyid ($alias_id);


=cut
sub findhostaliasbyid
{
	my $self = shift;

	$self->_debug_print ("Find host alias with id '$_[0]'");
	
	$self->_find(_hostaliasbyid => 'HOSTDB::Object::HostAlias', $_[0]);
}



=head2 findhostaliasbyname

	$alias = $hostdb->findhostaliasbyname ($alias_name);


=cut
sub findhostaliasbyname
{
	my $self = shift;

	$self->_debug_print ("Find host alias with name '$_[0]'");
	
	$self->_find(_hostaliasbyname => 'HOSTDB::Object::HostAlias', $_[0]);
}



=head2 findhostaliasesbyhostid

	@aliases = $hostdb->findhostaliasesbyhostid ($host->id ());


=cut
sub findhostaliasesbyhostid
{
	my $self = shift;

	$self->_debug_print ("Find host aliases for host with id '$_[0]'");
	
	$self->_find(_hostaliasesbyhostid => 'HOSTDB::Object::HostAlias', $_[0]);
}


=head2 findhostaliasbyzone

	foreach my $alias ($hostdb->findhostaliasbyzone ($zone)) {
		printf ("%-5s %s\n", $alias->id (), $alias->aliasname ());
	}


=cut
sub findhostaliasbyzone
{
	my $self = shift;
	my @res;

	$self->_debug_print ("Find aliases with zone '$_[0]'");
	
	if (! $self->is_valid_domainname ($_[0])) {
		$self->_set_error ("findaliasbyzone: '$_[0]' is not a valid domain name");
		return undef;
	}
	
	$self->_find(_hostaliasesbydnszone => 'HOSTDB::Object::HostAlias', $_[0]);
}


=head2 findallhostaliases

	@aliases = $hostdb->findallhostaliases ();


=cut
sub findallhostaliases
{
	my $self = shift;

	$self->_debug_print ("Find all aliases");
	
	$self->_find(_allhostaliases => 'HOSTDB::Object::HostAlias');
}


=head2 findzonebyname

	$zone = $hostdb->findzonebyname ($zonename);


=cut
sub findzonebyname
{
	my $self = shift;

	$self->_debug_print ("Find zone with name '$_[0]'");
	
	if (! $self->is_valid_domainname ($_[0])) {
		$self->_set_error ("findzonebyname: '$_[0]' is not a valid domain name");
		return undef;
	}

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


=head2 findzonebyhostname

	Finds the zone for the specified hostname.

	$zone = $hostdb->findzonebyhostname ('min.it.su.se');


=cut
sub findzonebyhostname
{
	my $self = shift;
	my $hostname = shift;

	my $checkzone = $hostname;

	if (! defined ($hostname)) {
		$self->_set_error ("findzonebyhostname: hostname cannot be undefined");
		return undef;
	}

	if (! $self->clean_hostname ($hostname)) {
		$self->_set_error ("findzonebyhostname: '$hostname' is not a valid hostname");
		return undef;
	}

	while ($checkzone) {
		my $zone = $self->findzonebyname ($checkzone);
		if (defined ($zone)) {
			# we have a match
			$self->_debug_print ("Hostname $hostname belongs to zone $checkzone");
			return $zone;
		}

		last if (index ($checkzone, '.') == -1);

		# strip up to and including the first dot (min.it.su.se -> it.su.se)
		$checkzone =~ s/^.+?\.(.*)/$1/;
	}

	$self->_debug_print ("No zone found for hostname '$hostname'");
	return undef;

}


=head2 findzonenamebyhostname

	This is another variant of findzonebyhostname (). The
	difference is that this function does not fetch data from
	the database, but just provides the logic. You provide
	the hostname and zonenames.


	foreach my $zone ($hostdb->findallzones ()) {
		push (@all_zonenames, $zone->zonename ());
	} 
	printf "Host %s belongs to zone %s\n", $hostname,
		$hostdb->findzonenamebyhostname ($hostname, @all_zonenames);


=cut
sub findzonenamebyhostname
{
	my $self = shift;
	my $hostname = shift;
	my @all_zones = @_;

	my $checkzone = $hostname;

	if (! $self->clean_hostname ($hostname)) {
		$self->_set_error ("findzonenamebyhostname: '$hostname' is not a valid hostname");
		return undef;
	}

	while ($checkzone) {
		if (grep (/^$checkzone$/, @all_zones)) {
			# we have a match
			$self->_debug_print ("Hostname $hostname belongs to zone $checkzone");
			return $checkzone;
		}

		last if (index ($checkzone, '.') == -1);

		# strip up to and including the first dot (min.it.su.se -> it.su.se)
		$checkzone =~ s/^.+?\.(.*)/$1/;
	}

	$self->_debug_print ("No zonename found for hostname '$hostname' in list supplied to findzonenamebyhostname ()");
	return undef;
}


=head2 findzonebyid

	Finds the zone with the ID you supplied

	$zone = $hostdb->findzonebyid ($id);


=cut
sub findzonebyid
{
	my $self = shift;

	$self->_debug_print ("Find zone with ID '$_[0]'");

	if ($_[0] !~ /^\d+$/) {
		$self->_set_error ("findzonebyid: '$_[0]' is not a valid ID");
		return undef;
	}
	
	$self->_find(_zonebyid => 'HOSTDB::Object::Zone', $_[0]);
}


=head2 findsubnet

	$subnet = $hostdb->findsubnet("192.168.1.1/24");

	Finds a subnet exactly matching what you asked for.


=cut
sub findsubnet
{
	my $self = shift;

	$self->_debug_print ("Find subnet '$_[0]'");

	if (! $self->is_valid_subnet ($_[0])) {
		$self->_set_error ("findsubnet: '$_[0]' is not a valid subnet");
		return undef;
	}

	my ($netaddr, $slash) = split('/', $_[0]);

	$self->_find(_subnet => 'HOSTDB::Object::Subnet', $netaddr, $slash);
}


=head2 findsubnetbyip

	Finds the most specific subnet for the IP you supplied

	$subnet = $hostdb->findsubnetbyip ("192.168.1.1");


=cut
sub findsubnetbyip
{
	my $self = shift;

	$self->_debug_print ("Find subnet for IP '$_[0]'");

	if (! $self->is_valid_ip ($_[0])) {
		$self->_set_error ("findsubnetbyip: '$_[0]' is not a valid IP adress");
		return undef;
	}
	
	$self->_find(_subnetbyip => 'HOSTDB::Object::Subnet',
		     $self->aton ($_[0]), $self->aton ($_[0]));
}


=head2 findsubnetbyid

	Finds the subnet with the ID you supplied

	$subnet = $hostdb->findsubnetbyip ($id);


=cut
sub findsubnetbyid
{
	my $self = shift;

	$self->_debug_print ("Find subnet with ID '$_[0]'");

	if ($_[0] !~ /^\d+$/) {
		$self->_set_error ("findsubnetbyid: '$_[0]' is not a valid ID");
		return undef;
	}
	
	$self->_find(_subnetbyid => 'HOSTDB::Object::Subnet', $_[0]);
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

	if (! $self->is_valid_subnet ($supernet)) {
		$self->_set_error ("findsubnet: '$supernet' is not a valid subnet");
		return undef;
	}

	my ($netaddr, $slash) = split('/', $supernet);
	my $broadcast = $self->get_broadcast ($supernet);

	$self->_find(_subnet_longer_prefix => 'HOSTDB::Object::Subnet',
		$self->aton ($netaddr), $self->aton ($broadcast));
}


=head2 findallsubnets

	foreach my $subnet ($hostdb->findallsubnets ()) {
		print $subnet->subnet () . "\n";
	}

	Finds all subnets.


=cut
sub findallsubnets
{
	my $self = shift;

	$self->_debug_print ('Find all subnets');

	$self->_find(_allsubnets => 'HOSTDB::Object::Subnet');
}



#####################
# PRIVATE FUNCTIONS #
#####################


=head1 PRIVATE FUNCTIONS

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

	unless (defined ($sth)) {
		die ("SQL statement undefined, have you provied a DSN?\n");
	}
	
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
			$hr->{$k} =~ s/^\s*(.*?)\s*$/$1/ if (defined ($hr->{$k}));
		}
		$o->{hostdb} = $self;
		$o->{debug} = $self->{debug};
		$o->init();
		push(@retval,$o);
	}
	$sth->finish();
	wantarray ? @retval : $retval[0];
}




1;
__END__

=head1 AUTHOR

Fredrik Thulin <ft@it.su.se>, Stockholm University

=head1 SEE ALSO

L<HOSTDB>


=cut
