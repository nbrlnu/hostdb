#!/usr/local/bin/perl
#
# $Id$
#
# cgi-script to delete host objects
#

use strict;
use Config::IniFiles;
#use lib 'blib/lib';
use HOSTDB;
use SUCGI;

my $table_blank_line = "<tr><td COLSPAN='2'>&nbsp;</td></tr>\n";
my $table_hr_line = "<tr><td COLSPAN='2'><hr></td></tr>\n";

my $debug = 1;
if (defined($ARGV[0]) and $ARGV[0] eq "-d") {
	shift (@ARGV);
	$debug = 1;
}

my $hostdbini = Config::IniFiles->new (-file => HOSTDB::get_inifile ());
die ("$0: Config file access problem.\n") unless ($hostdbini);

my $hostdb = HOSTDB::DB->new (dsn => $hostdbini->val ('db', 'dsn'),
			  db => $hostdbini->val ('db', 'database'),
			  user => $hostdbini->val ('db', 'user'),
			  password => $hostdbini->val ('db', 'password'),
			  debug => $debug
			 );

my $sucgi_ini;
if (-f $hostdbini->val ('sucgi', 'cfgfile')) {
	$sucgi_ini = Config::IniFiles->new (-file => $hostdbini->val ('sucgi', 'cfgfile'));
} else {
	warn ("No SUCGI config-file ('" . $hostdbini->val ('sucgi', 'cfgfile') . "')");
}

my $q = SUCGI->new ($sucgi_ini);

my $showsubnet_path = $q->state_url($hostdbini->val('subnet','showsubnet_uri'));
my $modifyhost_path = $q->state_url($hostdbini->val('subnet','modifyhost_uri'));

$q->begin (title => 'Delete Host');

$q->print (<<EOH);
	<table BORDER='0' CELLPADDING='0' CELLSPACING='3' WIDTH='600'>
		$table_blank_line
		<tr>
			<td COLSPAN='2' ALIGN='center'>
				<h3>HOSTDB: Delete Host</h3>
			</td>
		</tr>
		$table_blank_line
EOH

my $action = $q->param('action');
$action = 'Search' unless $action;
SWITCH:
{
	my $id = $q->param('id');
	my $host;

	$host = $hostdb->findhostbyid ($id);
	error_line ($q, "$0: Could not find host object with ID '$id'\n"), last SWITCH unless (defined ($host));

	$action eq 'Delete' and do
	{
		my $ip = $host->ip ();
		my $subnet = $hostdb->findsubnetclosestmatch ($host->ip ());
		
		if (delete_host ($hostdb, $host, $q)) {
			$q->print (<<EOH);
				<tr>
					<td COLSPAN='2'><strong><font COLOR='red'>Host deleted</font></strong></td>
				</tr>
EOH
		}

		if (defined ($subnet)) {
			my $s = $subnet->subnet ();
			
			if ($showsubnet_path) {
				$s = "<a HREF='$showsubnet_path;subnet=$s'>$s</a>";
				
				$q->print (<<EOH);
					<tr>
						<td COLSPAN='2'>[$s]<br></td>
					</tr>
EOH
			}
	

		}
		
		$ip = "<a HREF='$modifyhost_path;ip=$ip'>New host</a>";

		$q->print (<<EOH);
			<tr>
				<td COLSPAN='2'>[$ip]</td>
			</tr>
EOH

	},last SWITCH;

	print_host_info ($q, $hostdb, $host);
	delete_form ($q, $host);
}

if ($@) {
	error_line($q, "$@\n");
}

$q->print (<<EOH);
	</table>
EOH

$q->end();


sub delete_host
{
	my $hostdb = shift;
	my $host = shift;
	my $q = shift;
	
	if ($q->param ("_hostdb.deletehost") ne "yes") {
		error_line ($q, "Delete without verification not supported, don't try to trick me.");
		return undef;
	}

	eval {
		die ("No host object") unless ($host);

		$host->delete ("YES");
	};
	if ($@) {
		chomp ($@);
		error_line ($q, "Failed to delete host: $@: $host->{error}");
		return 0;
	}
	
	return 1;
}

sub delete_form
{
	my $q = shift;
	my $host = shift;

	# HTML 
        my $state_field = $q->state_field ();
	my $delete = $q->submit ('action', 'Delete');
	my $me = $q->state_url ();
	my $id = $host->id ();

	$q->print (<<EOH);
		<tr>
			<td ALIGN='right'><font COLOR='red'><strong>Are you SURE you want to delete this host?</strong></font></td>
			<td ALIGN='right'>
			   <form ACTION='$me' METHOD='post'>
				$state_field
		                <input TYPE='hidden' NAME='id' VALUE='$id'>
				<input TYPE='hidden' NAME='_hostdb.deletehost' VALUE='yes'>
				$delete
			   </form>
			</td>
		</tr>
		
		$table_blank_line
EOH

	return 1;
}

sub print_host_info
{
	my $q = shift;
	my $hostdb = shift;
	my $host = shift;
	
	return undef if (! defined ($host));

	# HTML
	my $me = $q->state_url();
	my $id = $host->id ();
	my $parent = $host->partof ()?$host->partof ():'-';
	$parent = "<a href='$me;whoisdatatype=ID;whoisdata=$parent'>$parent</a>";
	my $ip = $host->ip ();
	my $mac = $host->mac_address ();
	my $hostname = $host->hostname ();
	my $user = $host->user ();
	my $owner = $host->owner ();
	
	$q->print (<<EOH);
	   <tr>
		<td>ID</td>
		<td><a HREF="$me;whoisdatatype=ID;whoisdata=$id">$id</a>&nbsp;</td>
	   </tr>	
	   <tr>
		<td>Parent</td>
		<td>$parent</td>
	   </tr>
EOH

	my $t_host;
	foreach $t_host ($hostdb->findhostbypartof ($id)) {
		my $child = $t_host->id ()?$t_host->id ():'-';
		$child = "<a HREF='$me;whoisdatatype=ID;whoisdata=$child'>$child</a>";
		
		$q->print (<<EOH);
			<tr>
				<td>Child</td>
				<td>$child</td>
			</tr>
EOH
	}

	$q->print (<<EOH);
	   <tr>
		<td ALIGN='center'>---</td>
		<td>&nbsp;</td>
	   </tr>
	   <tr>
		<td>IP address</td>
		<td><strong>$ip</strong></td>
	   </tr>	
	   <tr>
		<td>MAC Address</td>
		<td>$mac</td>
	   </tr>	
	   <tr>
		<td>Hostname</td>
		<td><strong>$hostname</strong></td>
	   </tr>	
	   <tr>
		<td>User</td>
		<td>$user</td>
	   </tr>	
	   <tr>
		<td>Owner</td>
		<td>$owner</td>
	   </tr>	
EOH

	return 1;
}



sub error_line
{
	my $q = shift;
	my $error = shift;
	$q->print (<<EOH);
	   <tr>
		<td COLSPAN='2'>
		   <font COLOR='red'>
			<strong>$error</strong>
		   </font>
		</td>
	   </tr>
EOH
}