# $Id$

use strict;
use HOSTDB::Object;

package HOSTDB::Object::HostAlias;
@HOSTDB::Object::HostAlias::ISA = qw(HOSTDB::Object);


=head1 NAME

HOSTDB::Object::HostAlias - Host object aliases.

=head1 SYNOPSIS

  use HOSTDB;

  my $hostdb = HOSTDB::DB->new (dsn => $dsn, db => $db, user = $user,
				password => $pw);

  my $host = $hostdb->findhostbyname ($hostname);

  my $attr;
  if ($create_new) {
	$attr = $host->create_hostattribute ();
  } else {
	$attr = $hostdb->findhostattributebyid ($searchfor);
  }


=head1 DESCRIPTION

Host object alias routines. A host alias object has the following attributes :


=head1 EXPORT

None.

=head1 METHODS

=cut



sub init
{
	my $self = shift;
	my $hostdb = $self->{hostdb};

	$self->_debug_print ("creating object");

	if (! defined ($self->{hostid}) or int ($self->{hostid}) < 1) {
		die ("Cannot create host alias object with hostid '$self->{hostid}'\n");
	}

	if ($hostdb->{_dbh}) {
		$self->{_new_hostalias} = $hostdb->{_dbh}->prepare ("INSERT INTO $hostdb->{db}.hostalias (hostid, aliasname, ttl, dnszone, dnsstatus, lastmodified, lastupdated, comment) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
			or die ("$DBI::errstr");
		$self->{_update_hostattribute} = $hostdb->{_dbh}->prepare ("UPDATE $hostdb->{db}.hostalias SET hostid = ?, aliasname = ?, ttl = ?, dnszone = ?, dnsstatus = ?, lastmodified = ?, lastupdated = ?, comment = ? WHERE id = ?")
			or die ("$DBI::errstr");
		$self->{_delete_hostattribute} = $hostdb->{_dbh}->prepare ("DELETE FROM $hostdb->{db}.hostalias WHERE id = ?")
			or die ("$DBI::errstr");

		$self->{_get_last_id} = $hostdb->{_dbh}->prepare ("SELECT LAST_INSERT_ID()")
			or die ("$DBI::errstr");
	} else {
		$hostdb->_debug_print ("NOT preparing database stuff");
	}
	
	return 1;
}

=head1 PACKAGE HOSTDB::Object::HostAlias


=head2 commit

	$host->alias->commit () or die ("Could not commit host alias object: $host->{error}\n");

	Commit this hosts attribute object to database.


=cut
sub commit
{
	my $self = shift;

	# fields in database order
	my @db_values = ($self->hostid (),
			 $self->aliasname (),
			 $self->ttl (),
			 $self->dnszone (),
			 $self->dnsstatus (),
			 $self->lastmodified (),
			 $self->lastupdated (),
			 $self->comment (),
			);
	my $sth;
	if (defined ($self->id ()) and $self->id () >= 0) {
		$sth = $self->{_update_hostalias};
		$sth->execute (@db_values, $self->id ())
			or die "$DBI::errstr\n";
		
		# XXX check number of rows affected?

		$sth->finish();
	} else {
		# this is a new entry

		$sth = $self->{_new_hostalias};
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


=head2 delete

	Not yet documented, saving that for a rainy day.


=cut
sub delete
{
	my $self = shift;
	my $check = shift;

	if (! defined ($check) or $check ne 'YES') {
		$self->_set_error ('Delete function invoked with incorrect magic cookie');
		return 0;
	}

	my $sth;
	if (defined ($self->{id})) {
		$sth = $self->{_delete_hostalias};
		$sth->execute ($self->id ()) or die ("$DBI::errstr");
		
		my $rowcount = $sth->rows ();

		$sth->finish();
		
		if ($rowcount != 1) {
			$self->_set_error ("Delete operation of host attribute with id '$self->{id}' did not affect the expected number of database rows ($rowcount, not 1)");
			return 0;
		}
	} else {
		$self->_set_error ("Host has no attributes in database");
		return 0;
	}

	return 1;
}


=head2 id

	Get object database ID number. This is read only.

=cut
sub id
{
	my $self = shift;

	if (@_) {
		$self->_set_error ('id is read only');
		return 0;
	}

	return ($self->{id});
}


=head2 hostid

	Get the ID number of the host object this attribute
	belongs to. This is read only (only settable through
	$host->create_attribute ()).

=cut
sub hostid
{
	my $self = shift;

	if (@_) {
		$self->_set_error ('hostid is read only');
		return 0;
	}

	return ($self->{hostid});
}


=head2 aliasname

	Get or set this aliases name.
	Uses clean_hostname () on supplied value.

	print ("Old alias name : " . $alias->aliasname ());
	$host->aliasname ($new_aliasname) or warn ("Failed setting value\n");


=cut
sub aliasname
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq 'NULL') {
			$self->{aliasname} = undef;
			return 1;
		}
	
		if (! $self->clean_hostname ($newvalue)) {
			$self->_set_error ("Invalid hostname '$newvalue'");
			return 0;
		}
		$self->{aliasname} = $newvalue;

		return 1;
	}

	return ($self->{aliasname});
}


=head2 ttl

	Get or set this hosts DNS records TTL value. This should be
	either a number of seconds, or something that
	is_valid_nameserver_time () validates (the default function
	validates things parseable by BIND9, such as 1d or 1w2d3h4m5s).

	If you want to use the default TTL value, set to "NULL".

	print ("Old ttl: " . $host->ttl ());
	$host->ttl ($new_ttl) or warn ("Failed setting value\n");


=cut
sub ttl
{
	my $self = shift;

	if (@_) {
		my $newvalue = lc (shift);

		if ($newvalue eq 'null') {
			$self->{ttl} = undef;
		} else {
			if (! $self->is_valid_nameserver_time ($newvalue)) {
				$self->_set_error ("Invalid TTL time value '$newvalue'");
				return 0;
			}
			$self->{ttl} = $self->_nameserver_time_to_seconds ($newvalue);
		}

		return 1;
	}

	return ($self->{ttl});
}


=head2 dnszone

	Get or set this hosts DNS zonename.
	Uses clean_domainname () on supplied value.

	print ("Old zonename: " . $host->dnszone ());
	$host->dnszone ($new_zonename) or warn ("Failed setting value\n");


=cut
sub dnszone
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if ($newvalue eq 'NULL') {
			$self->{dnszone} = undef;
			return 1;
		}
	
		if (! $self->clean_domainname ($newvalue)) {
			$self->_set_error ("Invalid dnszone '$newvalue'");
			return 0;
		}
		$self->{dnszone} = $newvalue;

		return 1;
	}

	return ($self->{dnszone});
}


=head2 dnsstatus

	Set DNS status for this alias. This can be either ENABLED or DISABLED.
	This effectively controls wheter to generate any DNS config for this
	alias or not.

	# set property
	$alias->dnsstatus ('DISABLED');

	if ($alias->dnsstatus () eq 'DISABLED') {
		print ("Will not generate any DNS config for this alias\n");
	}


=cut
sub dnsstatus
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue eq 'ENABLED' or $newvalue eq 'DISABLED') {
			$self->{dnsstatus} = $newvalue;
		} else {
			$self->_set_error ("Invalid dnsstatus '$newvalue'");
			return 0;
		}

		return 1;
	}

	return ($self->{dnsstatus});
}


=head2 comment

	Get or set this aliases comment. Just an informative field.

	print ("Old comment: " . $alias->comment ());
	$alias->comment ($new_comment) or warn ("Failed setting comment\n");


=cut
sub comment
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		if (length ($newvalue) > 255) {
			$self->_set_error ('Comment too long (max 255 chars)');
			return 0;
		}

		$self->{comment} = $newvalue;
	
		return 1;
	}

	return ($self->{comment});
}



=head1 PACKAGE HOSTDB::DB::Object::HostAlias PRIVATE FUNCTIONS

	These functions should NEVER be called by a program using this class,
	but are documented here as well just for the sake of documentation.


=head2 lastmodified

	Blah


=cut
sub lastmodified
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		my $fmtvalue = $self->_format_datetime ($newvalue);
		if (defined ($fmtvalue)) {
			if ($fmtvalue eq 'NULL') {
				$self->{lastmodified} = undef;
			} else {
				$self->{lastmodified} = $fmtvalue;
			}

			return 1;
		} else {
			$self->_set_error ("Invalid lastmodified timestamp format");
			return 0;
		}

		return 1;
	}

	return ($self->{lastmodified});
}


=head2 unix_lastmodified

	unix_lastmodified is lastmodified but expressed as a UNIX
	timestamp. It is not stored in the database, but calculated at
	the time a host attribute object is fetched from the database. The only
	purpose of this is to make it easier for applications using
	host attribute objects to perform date calculations.

	printf "The attribute was last modified %i seconds ago.\n",
	       time () - $attr->unix_lastmodified ();


=cut
sub unix_lastmodified
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("unix_lastmodified is read only");
		return 0;
	}

	return ($self->{unix_lastmodified});
}


=head2 lastupdated

	Blah


=cut
sub lastupdated
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		my $fmtvalue = $self->_format_datetime ($newvalue);
		if (defined ($fmtvalue)) {
			if ($fmtvalue eq 'NULL') {
				$self->{lastupdated} = undef;
			} else {
				$self->{lastupdated} = $fmtvalue;
			}

			return 1;
		} else {
			$self->_set_error ("Invalid lastupdated timestamp format");
			return 0;
		}

		return 1;
	}

	return ($self->{lastupdated});
}


=head2 unix_lastupdated

	unix_lastupdated is lastupdated but expressed as a UNIX
	timestamp. It is not stored in the database, but calculated at
	the time a host attribute object is fetched from the database. The only
	purpose of this is to make it easier for applications using
	host attribute objects to perform date calculations.

	printf "The attribute was last updated %i seconds ago.\n",
	       time () - $attr->unix_lastupdated ();


=cut
sub unix_lastupdated
{
	my $self = shift;

	if (@_) {
		$self->_set_error ("unix_lastupdated is read only");
		return 0;
	}

	return ($self->{unix_lastupdated});
}




1;
__END__

=head1 AUTHOR

Fredrik Thulin <ft@it.su.se>, Stockholm University

=head1 SEE ALSO

L<HOSTDB>


=cut
