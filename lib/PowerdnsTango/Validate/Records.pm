package PowerdnsTango::Validate::Records;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Email::Valid;
use DateTime;

use base "Exporter";

our @EXPORT = qw(check_soa check_record calc_serial);
our $VERSION = '0.1';


sub check_soa
{
	my ($name_server, $contact, $refresh, $retry, $expire, $minimum, $ttl) = @_;
	my $stat = 1;
	my $message = "ok";


	if (!defined $name_server || ! is_domain($name_server))
	{
		$message = "a name server must be a valid domain";
	}
	elsif (!defined $contact || (! Email::Valid->address($contact)))
	{
		$message = "$contact is not a valid email address";
	}
	elsif (!defined $refresh || $refresh !~ m/^(\d)+$/ || $refresh < 1200 || $refresh > 43200)
	{
		$message = "refresh must be a number between 1200 and 43200";
	}
	elsif (!defined $retry || $retry !~ m/^(\d)+$/ || $retry < 180 || $retry > 900)
	{
		$message = "retry must be a number between 180 and 900";
	}
	elsif (!defined $expire || $expire !~ m/^(\d)+$/ || $expire < 1209600 || $expire > 2419200)
	{
	$message = "expire must be a number between 1209600 and 2419200";
	}
	elsif (!defined $minimum || $minimum !~ m/^(\d)+$/ || $minimum < 3600 || $minimum >= 10800)
	{
		$message = "minimum must be a number between 3600 and 10800";
	}
	elsif (!defined $ttl || $ttl !~ m/^(\d)+$/ || $ttl < 3600)
	{
		$message = "ttl must be a number equal or greater than 3600";
	}
	else
	{
		$stat = 0;
	}


	return ($stat, $message);
};


sub check_record
{
	my ($name, $ttl, $type, $content, $prio, $record_type) = @_;
	my $stat = 1;
	my $message = "ok";
	my $sth;
	my $count;
        my $default_ttl_minimum = database->quick_select('admin_settings_tango', { setting => 'default_ttl_minimum' });
	$default_ttl_minimum->{value} = 3600 if (!defined $default_ttl_minimum->{value} || $default_ttl_minimum->{value} !~ m/^(\d)+$/);

	$record_type = 'live' if (!defined $record_type && ($record_type ne 'live' || $record_type ne 'template'));
	$name = 'null.com' if (!defined $name);


	if ($record_type eq 'live' && ($content =~ m/%zone%/ || $name =~ m/%zone%/))
	{
		$message = "Use of %zone% is only allowed in templates";
	}
	elsif (!defined || ! is_domain($name))
	{
		$message = "Name is invalid";
	}
	elsif (!defined $content)
	{
		$message = "Content must have a value";
	}
	elsif (!defined $type)
	{
		$message = "Type must have a value";
	}
	elsif ($type ne 'A' && $type ne 'AAAA' && $type ne 'CNAME' && $type ne 'LOC' && $type ne 'MX' && $type ne 'NS' && $type ne 'PTR' && $type ne 'SPF' && $type ne 'SRV' && $type ne 'TXT')
	{
		$message = "Type is unknown";
	}
	elsif (!defined $ttl || $ttl !~ m/^(\d)+$/ || $ttl < $default_ttl_minimum->{value})
	{
		$message = "TTL must be a number equal or greater than $default_ttl_minimum->{value}";
	}
	elsif ($type eq 'A' && ! is_ipv4($content))
	{
		$message = "A record must be a valid ipv4 address";
	}
	elsif ($type eq 'AAAA' && ! is_ipv6($content))
	{
		$message = "AAAA record must be a valid ipv6 address";
	}
	elsif ($type eq 'CNAME' && ! is_domain($content) && $content !~ m/%zone%$/)
	{
		$message = "CNAME record must be unique and contain a valid domain name";
	}
	elsif ($type eq 'LOC' && $content !~ m/(\w)+/)
	{
		$message = "LOC record must contain a geographical location";
	}
	elsif ($type eq 'MX' && (!defined $prio || $prio !~ m/^(\d)+$/ || $prio < 1 || $prio >= 65535 || (! is_domain($content) && $content !~ m/%zone%$/)))
	{
		$message = "MX record must have a priority number and contain a valid domain name";
	}
	elsif ($type eq 'NS' && ! is_domain($content))
	{
		$message = "NS record must contain a valid domain name";
	}
	elsif ($type eq 'PTR' && (! is_ipv4($content) && ! is_ipv6($content)))
	{
		$message = "PTR record must be a valid ip address";
	}
	elsif ($type eq 'SPF' && $content !~ m/(\w)+/)
	{
		$message = "SPF record must contain alphanumeric characters";
	}
	elsif ($type eq 'SRV' && (!defined $prio || $prio !~ m/^(\d)+$/ || $prio < 1 || $prio >= 65535 || $content !~ m/(\w)+/))
	{
		$message = "SRV record must have a priority number and contain a alphanumeric characters";
	}
	elsif ($type eq 'TXT' && $content !~ m/(\w)+/)
	{
		$message = "TXT record must contain a alphanumeric characters";
	}
	else
	{
		$stat = 0;
	}


	return ($stat, $message);
};


sub calc_serial 
{
	my $domain_old_serial = shift;

	my $dt = DateTime->now;
	my ($year, $month, $day) = split(/-/, $dt->ymd('-'));
	my $domain_serial = ($year . $month . $day . 0 . 1);


	for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
	{
		if ($i >= 100)
		{
			# Can't go any higher in one day without breaking RFC
			return ($year . $month . $day . 99);
		}
		elsif ($i >= 10)
		{
			$domain_serial = ($year . $month . $day . $i);
		}
		else
		{
			$domain_serial = ($year . $month . $day . 0 . $i);
		}
	}


	return ($domain_serial);
};


1;
