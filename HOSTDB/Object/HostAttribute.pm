# $Id$

use strict;
use HOSTDB::Object;

package HOSTDB::Object::HostAttribute;
@HOSTDB::Object::HostAttribute::ISA = qw(HOSTDB::Object);


=head1 NAME

HOSTDB::Object::HostAttribute - Host object attributes.

=head1 SYNOPSIS

  use HOSTDB;

  my $hostdb = HOSTDB::DB->new (dsn => $dsn, db => $db, user = $user,
				password => $pw);

  my $host;
  if ($create_new) {
	$host = $hostdb->create_host ();
  } else {
	$host = $hostdb->findhostbyname ($searchfor);
  }


=head1 DESCRIPTION

Host object attribute routines. A host attribute object has the following attributes :


=head1 EXPORT

None.

=head1 METHODS

=cut



sub init
{
	my $self = shift;
	my $hostdb = $self->{hostdb};

	$self->_debug_print ("creating object");

	if ($hostdb->{_dbh}) {
		$self->{_new_hostattribute} = $hostdb->{_dbh}->prepare ("INSERT INTO $hostdb->{db}.hostattribute (hostid, v_key, v_section, v_type, v_string, v_int, v_blob, lastmodified, lastupdated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
			or die "$DBI::errstr";
		$self->{_update_hostattribute} = $hostdb->{_dbh}->prepare ("UPDATE $hostdb->{db}.hostattribute SET hostid = ?, v_key = ?, v_section = ?, v_type = ?, v_string = ?, v_int =  ?, v_blob = ? WHERE id = ?")
			or die "$DBI::errstr";
		$self->{_delete_hostattribute} = $hostdb->{_dbh}->prepare ("DELETE FROM $hostdb->{db}.hostattribute WHERE id = ?")
			or die "$DBI::errstr";

		$self->{_get_last_id} = $hostdb->{_dbh}->prepare ("SELECT LAST_INSERT_ID()")
			or die "$DBI::errstr";
	} else {
		$hostdb->_debug_print ("NOT preparing database stuff");
	}
	
	return 1;
}

=head1 PACKAGE HOSTDB::Object::HostAttribute


=head2 commit

	$host->attribute->commit () or die ("Could not commit host object: $host->{error}\n");

	Commit this hosts attribute object to database.


=cut
sub commit
{
	my $self = shift;

	# fields in database order
	my @db_values = ($self->hostid (),
			 $self->key (),
			 $self->section (),
			 $self->v_type (),
			 $self->v_string (),
			 $self->v_int (),
			 $self->v_blob (),
			 $self->lastmodified (),
			 $self->lastupdated ()
			);
	my $sth;
	if (defined ($self->id ()) and $self->id () >= 0) {
		$sth = $self->{_update_hostattribute};
		$sth->execute (@db_values, $self->id ())
			or die "$DBI::errstr\n";
		
		# XXX check number of rows affected?

		$sth->finish();
	} else {
		# this is a new entry

		$sth = $self->{_new_hostattribute};
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

	return 0 if ($check ne "YES");

	my $sth;
	if (defined ($self->{id})) {
		$sth = $self->{_delete_hostattribute};
		$sth->execute ($self->id ()) or die "$DBI::errstr";
		
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


=head2 key

	# blah


=cut
sub key
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{v_key} = $newvalue;

		return 1;
	}

	return ($self->{v_key});
}


=head2 section

	# blah


=cut
sub section
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{v_section} = $newvalue;

		return 1;
	}

	return ($self->{v_section});
}


=head2 type

	# blah


=cut
sub type
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		if ($newvalue eq 'string' or
		    $newvalue eq 'int' or
		    $newvalue eq 'blob') {
			$self->{v_type} = $newvalue;
		} else {
			$self->_set_error ("Invalid type '$newvalue'");
			return 0;
		}

		return 1;
	}

	return ($self->{v_type});
}


=head2 get

	# blah


=cut
sub get
{
	my $self = shift;
	
	if ($self->{v_type} eq 'string') {
		return $self->v_string ();
	} elsif ($self->{v_type} eq 'int') {
		return $self->v_int ();
	} elsif ($self->{v_type} eq 'blob') {
		return $self->v_blob ();
	} else {
		$self->_set_error ("Invalid attribute type '$self->{v_type}'");
		# this will not work very well, but it should never happen...
		return -1;
	}
}

=head2 set

	# blah


=cut
sub set
{
	my $self = shift;

	if (@_) {
		my $type = shift;
		my $newvalue = shift;

		if ($type eq 'string') {
			$self->v_type ('string');
			$self->v_string ($newvalue);
		} elsif ($self->{v_type} eq 'int') {
			$self->v_type ('int');
			$self->v_int ($newvalue);
		} elsif ($self->{v_type} eq 'blob') {
			$self->v_type ('blob');
			$self->v_blob ($newvalue);
		} else {
			$self->_set_error ("Invalid attribute type '$self->{v_type}'");
			return 0;
		}

		return 1;
	}

	return 0;
}




=head1 PACKAGE HOSTDB::DB::Object::HostAttribute PRIVATE FUNCTIONS

	These functions should NEVER be called by a program using this class,
	but are documented here as well just for the sake of documentation.


=head2 v_string

	# blah


=cut
sub v_string
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;
	
		$self->{v_int} = undef;
		$self->{v_blob} = undef;

		if ($newvalue eq 'NULL') {
			$self->{v_string} = undef;
			return 1;
		}

		$self->{v_string} = $newvalue;

		return 1;
	}

	return ($self->{v_string});
}


=head2 v_int

	# blah


=cut
sub v_int
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		$self->{v_string} = undef;
		$self->{v_blob} = undef;
	
		if ($newvalue eq 'NULL') {
			$self->{v_int} = undef;
			return 1;
		}

		$self->{v_int} = $newvalue;

		return 1;
	}

	return ($self->{v_int});
}


=head2 v_blob

	# blah


=cut
sub v_blob
{
	my $self = shift;

	if (@_) {
		my $newvalue = shift;

		$self->{v_int} = undef;
		$self->{v_string} = undef;
	
		if ($newvalue eq 'NULL') {
			$self->{v_blob} = undef;
			return 1;
		}

		$self->{v_blob} = $newvalue;

		return 1;
	}

	return ($self->{v_blob});
}



1;
__END__

=head1 AUTHOR

Fredrik Thulin <ft@it.su.se>, Stockholm University

=head1 SEE ALSO

L<HOSTDB>


=cut