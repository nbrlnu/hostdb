#!/usr/local/bin/perl
#
# $Id$
#
# cgi-script to search for different things in the database
#

use strict;
use Config::IniFiles;
#use lib 'blib/lib';
use HOSTDB;
use SUCGI;

my $table_blank_line = "<tr><td COLSPAN='2'>&nbsp;</td></tr>\n";
my $table_hr_line = "<tr><td COLSPAN='2'><hr></td></tr>\n";

my $debug = 0;
if ($ARGV[0] eq "-d") {
	shift (@ARGV);
	$debug = 1;
}

my $hostdbini = Config::IniFiles->new (-file => HOSTDB::get_inifile ());

my $http_base = $hostdbini->val ('subnet', 'http_base');
my $showsubnet_path = $hostdbini->val ('subnet', 'showsubnet_path');
if ($showsubnet_path !~ '^https*://') {
	# path appears to be relative to http_base
	$showsubnet_path = "$http_base/$showsubnet_path";
}

$showsubnet_path =~ s!([^:])//!$1/!go;	# replace double slashes, but not the ones in http://

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

$q->begin (title => "Whois");

$q->print ("<table BORDER='0' CELLPADDING='0' CELLSPACING='0' WIDTH='600'>\n" .
	   "$table_blank_line");

$q->print ("<tr><td COLSPAN='2' ALIGN='center'><h3>Web-based whois</h3></td></tr>\n" .
	   "$table_blank_line");

whois_form ($q);

$q->print ($table_hr_line);

perform_search ($hostdb, $q);

$q->print ("</table>\n");

$q->end ();


sub whois_form
{
	my $q = shift;

	# HTML 
        my $state_field = $q->state_field;
        my $popup = $q->popup_menu (-name => "whoisdatatype", -values => ['Guess', 'IP', 'FQDN', 'MAC', 'ID']);
	my $datafield = $q->textfield ("whoisdata");
	my $submit = $q->submit ("Search");

	$q->print (<<EOH);
	   <form>
		<tr>
		   <td COLSPAN='2'>
			<table BORDER='0' CELLSPACING='0' CELLPADDING='0' WIDTH='600'>
			   <tr>
				<td>
					Search for &nbsp;
					$popup &nbsp;
					$datafield &nbsp;
					$submit
				</td>
			   </tr>
			   $table_blank_line
			</table>
		</tr>
	   </form>	   
EOH
}

sub perform_search
{
	my $hostdb = shift;
	my $q = shift;

	if ($q->param ('whoisdata')) {
		# get type of data

		my $search_for = $q->param ('whoisdata');
		my $whoisdatatype = $q->param ('whoisdatatype');

		if ($whoisdatatype eq "Guess" or ! $whoisdatatype) {
			my $t = $search_for;
			if ($hostdb->clean_mac_address ($t)) {
				$search_for = $t;
				$whoisdatatype = "MAC";
			} elsif ($hostdb->check_valid_ip ($search_for)) {
				$whoisdatatype = "IP";
			} elsif ($hostdb->valid_fqdn ($search_for)) {
				$whoisdatatype = "FQDN";
			} elsif ($search_for =~ /^\d+$/) { 
				$whoisdatatype = "ID";
			} else {
				error_line ($q, "Search failed: could not guess data type");
				return undef;
			}
		}

		my @host_refs;
			
		if ($whoisdatatype eq "IP") {
			my $host = $hostdb->findhostbyip ($search_for);
			my @gaah;
			push (@gaah, $host);
			push (@host_refs, \@gaah);
		} elsif ($whoisdatatype eq "FQDN") {
			@host_refs = $hostdb->findhostbyname ($search_for);
		} elsif ($whoisdatatype eq "MAC") {
			my $host = $hostdb->findhostbymac ($search_for);
			my @gaah;
			push (@gaah, $host);
			push (@host_refs, \@gaah);
		} elsif ($whoisdatatype eq "ID") {
			my $host = $hostdb->findhostbyid ($search_for);
			my @gaah;
			push (@gaah, $host);
			push (@host_refs, \@gaah);

		} else {
			error_line ($q, "Search failed: don't recognize whois datatype '$whoisdatatype'");
			return undef;
		}

		if (@host_refs) {
			foreach my $host_ref (@host_refs) {
				foreach my $host (@$host_ref) {
					$q->print ("<tr><th COLSPAN='2' ALIGN='left'>Host :</th></tr>");
					$q->print ("<tr><td COLSPAN='2'>&nbsp;</td></tr>\n");
		
					print_host_info ($q, $host);

					$q->print ($table_blank_line);
		
					my $subnet = $hostdb->findsubnetclosestmatch ($host->ip ());
		
					if ($subnet) {
						print_subnet_info ($q, $subnet);
					} else {
						error_line ($q, "Search failed: could not find subnet in database");
						return undef;
					}
					$q->print ($table_blank_line);	
				}

				$q->print ($table_hr_line);
			}

			return 1;
		}

		return 0;
	} else {
		$q->print ("<!-- no whoisdata, not searching -->\n");
		return undef;
	}
}

sub print_host_info
{
	my $q = shift;
	my $host = shift;
	
	return undef if (! defined ($host));

	# HTML
	my $me = $q->state_url ();
	my $id = $host->id ();
	$id = "<a href='$me&whoisdatatype=ID&whoisdata=$id'>$id</a>";
	my $parent = $host->partof ()?$host->partof ():'-';
	$parent = "<a href='$me&whoisdatatype=ID&whoisdata=$parent'>$parent</a>";
	my $ip = $host->ip ();
	my $mac = $host->mac_address ();
	my $hostname = $host->hostname ();
	my $user = $host->user ();
	my $owner = $host->owner ();
	
	$q->print (<<EOH);
	   <tr>
		<td>ID</td>
		<td>$id</td>
	   </tr>	
	   <tr>
		<td>Parent</td>
		<td>$parent</td>
	   </tr>
	   <tr>
		<td ALIGN='center'>---</td>
		<td>&nbsp;</td>
	   </tr>
	   <tr>
		<td>IP address</td>
		<td>$ip</td>
	   </tr>	
	   <tr>
		<td>MAC Address</td>
		<td>$mac</td>
	   </tr>	
	   <tr>
		<td>Hostname</td>
		<td>$hostname</td>
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

sub print_subnet_info
{
	my $q = shift;
	my $subnet = shift;
	
	return undef if (! defined ($subnet));
	
	# HTML
	my $s = $subnet->subnet ();
	my $netmask = $subnet->netmask ();
	my $desc = $subnet->description ();
	
	if ($showsubnet_path) {
		$s = "<a href='" . $showsubnet_path . "?subnet=$s" . "'>$s</a>";
	}
	
	$q->print (<<EOH);
		<tr>
		   <td><strong>Subnet</td>
		   <td>$s</td>
		</tr>
		<tr>
		   <td>Netmask</td>
		   <td>$netmask</td>
		</tr>
		   <td>Description</td>
		   <td>$desc</td>
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
