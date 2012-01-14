package PowerdnsTango::Domains::Records;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Email::Valid;
use Date::Calc qw(:all);
use Data::Page;
use PowerdnsTango::Acl qw(user_acl);

our $VERSION = '0.2';


sub check_soa
{
        my ($name_server, $contact, $refresh, $retry, $expire, $minimum, $ttl) = @_;
        my $stat = 1;
        my $message = "ok";


        if (!defined $name_server || ! is_domain($name_server))
        {
                $message = "SOA update failed, a name server must be a valid domain";
        }
        elsif (!defined $contact || (! Email::Valid->address($contact)))
        {
                $message = "SOA update failed, $contact is not a valid email address";
        }
        elsif (!defined $refresh || $refresh !~ m/^(\d)+$/ || $refresh < 1200)
        {
                $message = "SOA update failed, refresh must be a number equal or greater than 1200";
        }
        elsif (!defined $retry || $retry !~ m/^(\d)+$/ || $retry < 180)
        {
                $message = "SOA update failed, retry must be a number equal or greater than 180";
        }
        elsif (!defined $expire || $expire !~ m/^(\d)+$/ || $expire < 180)
        {
                $message = "SOA update failed, expire must be a number equal or greater than 180";
        }
        elsif (!defined $minimum || $minimum !~ m/^(\d)+$/ || $minimum < 3600 || $minimum >= 10800)
        {
                $message = "SOA update failed, minimum must be a number between 3600 and 10800";
        }
        elsif (!defined $ttl || $ttl !~ m/^(\d)+$/ || $ttl < 3600)
        {
                $message = "SOA update failed, ttl must be a number equal or greater than 3600";
        }
        else
        {
                $stat = 0;
        }



        return ($stat, $message);
};


sub check_record
{
        my ($name, $ttl, $type, $content, $prio) = @_;
        my $stat = 1;
        my $message = "ok";
	my $sth;
	my $count;
	my $default_ttl_minimum = database->quick_select('admin_settings_tango', { setting => 'default_ttl_minimum' });
	$default_ttl_minimum->{value} = 3600 if (!defined $default_ttl_minimum->{value} || $default_ttl_minimum->{value} !~ m/^(\d)+$/);


	if (!defined || ! is_domain($name))
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
        elsif ($type eq 'CNAME' && ! is_domain($content))
        {
                $message = "CNAME record must be unique and contain a valid domain name";
        }
        elsif ($type eq 'LOC' && $content !~ m/(\w)+/)
        {
                $message = "LOC record must contain a geographical location";
        }
        elsif ($type eq 'MX' && (!defined $prio || $prio !~ m/^(\d)+$/ || $prio < 1 || $prio >= 65535 || ! is_domain($content)))
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


any ['get', 'post'] => '/domains/edit/records/id/:id' => sub
{
	my $domain_id = params->{id} || 0;
        my $load_page = params->{p} || 1;
        my $results_per_page = params->{r} || 25;
	my $search = params->{record_search} || 0;
	my $domain = database->quick_select('domains', { id => $domain_id });
	my $sth;
	my $count;
        my $perm = user_acl($domain_id, 'domain');
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


        if (request->method() eq "POST" && $search ne '0')
        {
		$sth = database->prepare('select count(id) as count from records where domain_id = ? and type != ? and (name like ? or content like ? or ttl like ?)');
		$sth->execute($domain_id, 'SOA', "%$search%", "%$search%", "%$search%");
		$count = $sth->fetchrow_hashref;
	}
	else
	{
                $sth = database->prepare('select count(id) as count from records where domain_id = ? and type != ?');
                $sth->execute($domain_id, 'SOA');
                $count = $sth->fetchrow_hashref;
	}


        $sth = database->prepare('select * from records where domain_id = ? and type = ?');
        $sth->execute($domain_id, 'SOA');
        my $soa = $sth->fetchrow_hashref;

	my ($name_server, $contact, $refresh, $retry, $expire, $minimum) = (split /\s/, $soa->{content}) if (defined $soa->{content});
	$name_server = '' if (! defined $name_server);
	$contact = '' if (! defined $contact);
	$refresh = '' if (! defined $refresh);
	$retry = '' if (! defined $retry);
	$expire = '' if (! defined $expire);
	$minimum = '' if (! defined $minimum);

        my $page = Data::Page->new();
        $page->total_entries($count->{'count'});
        $page->entries_per_page($results_per_page);
        $page->current_page($load_page);

        my $display = ($page->entries_per_page * ($page->current_page - 1));
        $load_page = $page->last_page if ($load_page > $page->last_page);
        $load_page = $page->first_page if ($load_page == 0);


	if (request->method() eq "POST" && $search ne '0')
        {
        	$sth = database->prepare('select * from records where domain_id = ? and type != ? and (name like ? or content like ? or ttl like ?) limit ? offset ?');
        	$sth->execute($domain_id, 'SOA', "%$search%", "%$search%", "%$search%", $page->entries_per_page, $display);

                flash error => "Record search found no match" if ($count->{'count'} == 0);
                flash message => "Record search found $count->{'count'} matches" if ($count->{'count'} >= 1);
	}
	else
	{
                $sth = database->prepare('select * from records where domain_id = ? and type != ? limit ? offset ?');
                $sth->execute($domain_id, 'SOA', $page->entries_per_page, $display);
	}


	my $users;
	my $owner_id;
	my $owner_login;


	if ($user_type eq 'admin')
	{
                $users = database->prepare('select * from users_tango');
                $users->execute();

		my $check_owner = database->quick_select('domains_acl_tango', { domain_id => $domain_id });
		$owner_id = $check_owner->{user_id} || 0;
	
		if ($owner_id != 0)
		{
			my $check_owner = database->quick_select('users_tango', { id => $owner_id });
			$owner_login = $check_owner->{login};
		}
		else
		{
			$owner_login = "nobody";
		}
	}
	else
	{
                $users = database->prepare('select * from users_tango where id = ?');
                $users->execute($user_id);
		$owner_id = $user_id;
		$owner_login = session 'user_login';
	}


        my $templates;


        if ($user_type eq 'admin')
        {
		$templates = database->prepare('select * from templates_tango');
		$templates->execute();
        }
        else
        {
		$templates = database->prepare('select templates_tango.* from templates_tango, templates_acl_tango where (templates_tango.id = templates_acl_tango.template_id) and templates_acl_tango.user_id = ?');
		$templates->execute($user_id);
        }


        template 'records', { domain_id => $domain_id, domain_name => $domain->{name}, domain_type => $domain->{type}, domain_master => $domain->{master}, records => $sth->fetchall_hashref('id'), 
	templates => $templates->fetchall_hashref('id'), page => $load_page, results => $results_per_page,  previouspage => ($load_page - 1), nextpage => ($load_page + 1),
	lastpage => $page->last_page, soa_id => $soa->{id}, name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $soa->{ttl},
	users => $users->fetchall_hashref('id'), domain_owner_id => $owner_id, domain_owner_login => $owner_login };
};


post '/domains/edit/records/id/:id/update/domain' => sub
{
        my $domain_id = params->{id} || 0;
        my $domain = params->{edit_name} || 0;
	my $user_id = session 'user_id';
	my $user_type = session 'user_type';
        my $type = params->{edit_type} || 0;
        my $master = params->{edit_master};
	my $owner_id = params->{edit_owner};
	my ($year,$month,$day) = Today();
        my $perm = user_acl($domain_id, 'domain');

	$owner_id = $user_id if ($user_type ne 'admin');


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


        my $domain_info = database->quick_select('domains', { id => $domain_id });
        my $domain_old_serial = $domain_info->{notified_serial} || 0;
        my $domain_serial = ($year . $month . $day . 1);


        for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
        {
                $domain_serial = ($year . $month . $day . $i);
        }


        my $record_change_date = ($year . $month . $day . 1);


        my $sth = database->prepare("select count(name) as count from domains where name = ?");
        $sth->execute($domain);
        my $count = $sth->fetchrow_hashref;

        $sth = database->prepare("select name from domains where id = ?");
        $sth->execute($domain_id);
        my $old_domain = $sth->fetchrow_hashref;


        if (($count->{count} != 0) && ($old_domain->{name} ne $domain))
        {
		flash error => "Domain $domain already exists";
        }
        elsif (is_domain($domain) && ($type =~ m/^NATIVE$/i || $type =~ m/^MASTER$/i))
        {
                database->quick_update('domains', { id => $domain_id }, { name => $domain, type => $type, notified_serial => $domain_serial, master => undef });
		database->quick_delete('domains_acl_tango', { domain_id => $domain_id });
		database->quick_insert('domains_acl_tango', { user_id => $owner_id, domain_id => $domain_id });

                $sth = database->prepare("select * from records where domain_id = ?");
                $sth->execute($domain_id);


                while (my $row = $sth->fetchrow_hashref)
                {
                        $row->{name} =~ s/$old_domain->{name}/$domain/i;
                        $row->{content} =~ s/$old_domain->{name}/$domain/i;

                        database->quick_update('records', { id => $row->{id} }, { name => $row->{name}, content => $row->{content}, change_date => $record_change_date });
                }


		flash message => "Domain updated";
        }
        elsif (is_domain($domain) && ($type =~ m/^SLAVE$/i) && (defined $master) && ((is_domain($master)) || (is_ipv4($master)) || (is_ipv6($master))))
        {
                database->quick_update('domains', { id => $domain_id }, { name => $domain, type => $type, master => $master, notified_serial => $domain_serial });
                database->quick_delete('domains_acl_tango', { domain_id => $domain_id });
                database->quick_insert('domains_acl_tango', { user_id => $owner_id, domain_id => $domain_id });
		database->quick_delete('records', { domain_id => $domain_id });


		flash message => "Domain updated";
        }
	elsif ((! defined $master) || ((! is_domain($master)) && (! is_ipv4($master)) && (! is_ipv6($master))))
	{
		flash error => "Domain update failed, a valid master address must be provided";
	}
        else
        {
        	flash error => "Domain update failed";
        }


        return redirect "/domains/edit/records/id/$domain_id";
};


post '/domains/edit/records/id/:id/add' => sub
{
	my $domain_id = params->{id} || 0;
        my $name = params->{add_record_host};
        my $type = params->{add_record_type};
        my $prio = params->{add_record_prio} || undef;
	my $ttl = params->{add_record_ttl};
	my $content = params->{add_record_content};
        my $perm = user_acl($domain_id, 'domain');
	my ($year,$month,$day) = Today();


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


        my $domain = database->quick_select('domains', { id => $domain_id });
        my $domain_old_serial = $domain->{notified_serial} || 0;
        my $domain_serial = ($year . $month . $day . '1');

	$name =~ s/$domain->{name}$//i;


	if ((! defined $name) || ($name !~ m/(\w)+/))
	{
		$name = $domain->{name};
	}
	else
	{
		$name = $name . "." . $domain->{name};
	}


	$name =~ s/\.\./\./gi;


        my ($stat, $message) = check_record($name, $ttl, $type, $content, $prio);


        if ($stat == 1)
        {
                flash error => "Add record failed, $message";

                return redirect "/domains/edit/records/id/$domain_id";
        }


	my $sth = database->prepare("select count(id) as count from records where domain_id = ? and type = ? and name = ?");
        $sth->execute($domain_id, 'CNAME', $name);
	my $count = $sth->fetchrow_hashref;


	if ($type eq 'CNAME' && ($name eq $domain->{name} || $count->{count} != 0))
	{
		flash error => "Add record failed, CNAME record must be unique and contain a valid domain name";

		return redirect "/domains/edit/records/id/$domain_id";
	}


        for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
        {
                $domain_serial = ($year . $month . $day . $i);
        }


        my $record_change_date = ($year . $month . $day . 1);


	if (($domain_id != 0 && ! defined $prio) && (defined $name && defined $type && defined $ttl && defined $content && $domain->{type} !~ m/^SLAVE$/i))
	{
		database->quick_insert('records', { domain_id => $domain_id, name => $name, type => $type, ttl => $ttl, content => $content, change_date => $record_change_date });
		database->quick_update('domains', { id => $domain_id }, { notified_serial => $domain_serial });

		flash message => "Record added";
	}
	elsif (($domain_id != 0) && (defined $name && defined $type && defined $ttl && defined $content && defined $prio && $domain->{type} !~ m/^SLAVE$/i))
	{
                database->quick_insert('records', { domain_id => $domain_id, name => $name, type => $type, ttl => $ttl, content => $content, prio => $prio, change_date => $record_change_date });
		database->quick_update('domains', { id => $domain_id }, { notified_serial => $domain_serial });

		flash message => "Record added";
	}
	elsif ($domain->{type} =~ m/^SLAVE$/i)
	{
		flash error => "Add record failed, can't modify slave domain";
	}
	else
	{
                flash error => "Add record failed";
	}


        return redirect "/domains/edit/records/id/$domain_id";
};


post '/domains/edit/records/id/:id/add/template' => sub
{
        my $domain_id = params->{id} || 0;
	my $template_id = params->{apply_template} || 0;
	my ($year,$month,$day) = Today();
        my $perm = user_acl($domain_id, 'domain');


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


        my $domain = database->quick_select('domains', { id => $domain_id });


	if ($domain->{type} !~ m/^SLAVE$/i)
	{
        	my $domain_old_serial = $domain->{notified_serial} || 0;
        	my $domain_serial = ($year . $month . $day. 1);


        	for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
        	{
                	$domain_serial = ($year . $month . $day . $i);
        	}


		database->quick_update('domains', { id => $domain_id }, { notified_serial => $domain_serial });
        	my $record_change_date = ($year . $month . $day . 1);


        	database->quick_delete('records', { domain_id => $domain_id });
        	my $template = database->quick_select('templates_tango', { id => $template_id });
        	my $templates_records = database->prepare('select * from templates_records_tango where template_id = ?');
        	$templates_records->execute($template_id);


		while (my $template_row = $templates_records->fetchrow_hashref)
		{
			$template_row->{name} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain->{name}/i;
                	$template_row->{name} =~ s/\%(\s)?(.+?)(\s)?\%//i;
                	$template_row->{content} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain->{name}/i;
                	$template_row->{content} =~ s/\%(\s)?(.+?)(\s)?\%//i;

                	database->quick_insert('records', { domain_id => $domain_id, name => $template_row->{name}, type => $template_row->{type}, content => $template_row->{content},
                	ttl => $template_row->{ttl}, prio => $template_row->{prio}, change_date => $record_change_date });
        	}


		flash message => "All records replaced using template $template->{name}";
	}
	else
	{
		flash error => "Apply template failed, can't modify slave domain";
	}


        return redirect "/domains/edit/records/id/$domain_id";
};


get '/domains/edit/records/id/:id/delete/recordid/:recordid' => sub
{
        my $domain_id = params->{id} || 0;
	my $record_id = params->{recordid} || 0;
        my $perm = user_acl($domain_id, 'domain');
	my $domain = database->quick_select('domains', { id => $domain_id });


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


        if ($domain_id != 0 && $record_id != 0 && $domain->{type} !~ m/^SLAVE$/)
        {
                database->quick_delete('records', { id => $record_id });

                flash message => "Record deleted";
        }
	elsif ($domain->{type} =~ m/^SLAVE$/)
	{
		flash error => "Record delete failed, can't modify slave domain";
	}
        else
        {
                flash error => "Record delete failed";
        }


        return redirect "/domains/edit/records/id/$domain_id";
};


post '/domains/edit/records/id/:id/find/replace' => sub
{
	my $domain_id = params->{id} || 0;
	my $find = params->{find_search};
	my $find_in = params->{find_in};
	my $find_type = params->{find_type};
	my $replace = params->{find_replace};
	my ($year,$month,$day) = Today();
	my $perm = user_acl($domain_id, 'domain');
	my $domain = database->quick_select('domains', { id => $domain_id });
        my $default_ttl_minimum = database->quick_select('admin_settings_tango', { setting => 'default_ttl_minimum' });
        $default_ttl_minimum->{value} = 3600 if (!defined $default_ttl_minimum->{value} || $default_ttl_minimum->{value} !~ m/^(\d)+$/);



        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


	if ($domain->{type} =~ m/^SLAVE$/i)
	{
		flash error => "Failed to update records, can't modify slave domain";

		return redirect "/domains/edit/records/id/$domain_id";
	}


	if (! defined $find || ! defined $replace || ! defined $find_in || ! defined $find_type)
	{
		flash error => "Failed to update records, ensure all fields are complete";

		return redirect "/domains/edit/records/id/$domain_id";
	}


	if ($find_in eq 'ttl')
	{
		if ($replace !~ m/^(\d)+$/ || $replace < $default_ttl_minimum->{value})
		{
                        flash error => "Failed to update records, TTL must be a number equal or greater than $default_ttl_minimum->{value}";


                        return redirect "/domains/edit/records/id/$domain_id";
		}
	}
	elsif ($find_in eq 'prio')
	{
		if ($replace !~ m/^(\d)+$/ || $replace < 1 || $replace >= 65535)
		{
                        flash error => "Failed to update records, Priority must be a number";


                        return redirect "/domains/edit/records/id/$domain_id";
		}
	}
	elsif ($find_in eq 'content')
	{
        	my ($stat, $message) = check_record('null.com', "$default_ttl_minimum->{value}", $find_type, $replace);


        	if ($stat == 1)
        	{
			flash error => "Failed to update records, Content must match record type";

			return redirect "/domains/edit/records/id/$domain_id";
        	}
	}


        my $serial = database->quick_select('domains', { id => $domain_id });
        my $domain_old_serial = $serial->{notified_serial} || 0;
        my $domain_serial = ($year . $month . $day. 1);


        for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
        {
                $domain_serial = ($year . $month . $day . $i);
        }


        my $record_change_date = ($year . $month . $day);


	if ($find_in eq 'content' || $find_in eq 'ttl' || $find_in eq 'prio')
	{
		database->quick_update('records', { domain_id => $domain_id, $find_in => $find }, { $find_in => $replace, change_date => $record_change_date });

		flash message => "Records updated";
	}
	else
	{
		flash error => "Failed to update records";
	}


	return redirect "/domains/edit/records/id/$domain_id";
};


ajax '/domains/edit/records/get/soa' => sub
{
	my $domain_id = params->{id} || 0;
	my $soa = database->quick_select('records', { domain_id => $domain_id, type => 'SOA' });
        my $perm = user_acl($domain_id, 'domain');

        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied" };
        }


	my ($name_server, $contact, $refresh, $retry, $expire, $minimum) = (split /\s/, $soa->{content}) if (defined $soa->{content});
        $name_server = '' if (! defined $name_server);
        $contact = '' if (! defined $contact);
        $refresh = '' if (! defined $refresh);
        $retry = '' if (! defined $retry);
        $expire = '' if (! defined $expire);
        $minimum = '' if (! defined $minimum);


	return { stat => 'ok', name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $soa->{ttl} };
};


ajax '/domains/edit/records/update/soa' => sub
{
        my $id = params->{id} || 0;
	my $domain_id = params->{domain_id} || 0;
	my $domain = params->{domain};
	my $name_server = params->{name_server};
	my $contact = params->{contact};
	my $refresh = params->{refresh};
	my $retry = params->{retry};
	my $expire = params->{expire};
	my $minimum = params->{minimum};
	my $ttl = params->{ttl} || 3600;
	my ($year,$month,$day) = Today();
        my $sth = database->prepare('select count(id) as count from records where domain_id = ? and type = ?');
        $sth->execute($domain_id, 'SOA');
        my $count = $sth->fetchrow_hashref;
        my $perm = user_acl($domain_id, 'domain');
	my $domain_info = database->quick_select('domains', { id => $domain_id });


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


	if ($domain_info->{type} =~ m/^SLAVE$/i)
	{
		return { stat => 'fail', message => "SOA update failed, can't modify slave domain" };
	}


	my ($stat, $message) = check_soa($name_server, $contact, $refresh, $retry, $expire, $minimum, $ttl);


        if ($stat == 1)
        {
                return { stat => 'fail', message => $message };
        }



	my $domain_old_serial = $domain_info->{notified_serial} || 0;
	my $domain_serial = ($year . $month . $day. 1);


        for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
        {
                $domain_serial = ($year . $month . $day . $i);
        }


	my $soa = database->quick_select('records', { domain_id => $domain_id, type => 'SOA' });
	my $record_old_change_date = $soa->{change_date} || 0;
	my $record_change_date = ($year . $month . $day . 1);


	for (my $i = 1; $record_old_change_date >= $record_change_date; $i++)
	{
		$record_change_date = ($year . $month . $day . $i);
	}


	if ($count->{count} == 0 || $count->{count} > 1)
	{
		database->quick_delete('records', { domain_id => $domain_id, type => 'SOA' }) if ($count->{count} > 1);
		database->quick_insert('records', { name => $domain, domain_id => $domain_id, type => 'SOA', content => "$name_server $contact $refresh $retry $expire $minimum", ttl => $ttl, change_date => $record_change_date });
		database->quick_update('domains', { id => $domain_id }, { notified_serial => $domain_serial });


		return { stat => 'ok', message => 'SOA Updated', name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $ttl };
	}
	elsif ($count->{count} == 1 && $id != 0)
	{
		database->quick_update('records', { id => $id, type => 'SOA' }, { content => "$name_server $contact $refresh $retry $expire $minimum", ttl => $ttl, change_date => $record_change_date });
		database->quick_update('domains', { id => $domain_id }, { notified_serial => $domain_serial });


		return { stat => 'ok', message => 'SOA Updated', name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $ttl };
	}
	else
	{
		return { stat => 'fail', message => 'Failed to update SOA' };
	}

};


ajax '/domains/edit/records/get/record' => sub
{
        my $id = params->{id} || 0;
	my $record = database->quick_select('records', { id => $id });
	my $domain_id = database->quick_select('records', { id => $id });
	my $perm = user_acl($domain_id->{domain_id}, 'domain');
	my $domain = database->quick_select('domains', { id => $domain_id->{domain_id} });


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


	$record->{name} =~ s/$domain->{name}//;
	$record->{name} =~ s/\.$//;


        return { stat => 'ok', id => $id, name => $record->{name}, type => $record->{type}, ttl => $record->{ttl}, prio => $record->{prio}, content => $record->{content} };
};


ajax '/domains/edit/records/update/record' => sub
{
	my $id = params->{id} || 0;
        my $name = params->{name};
	my $type = params->{type};
	my $ttl = params->{ttl};
	my $prio = params->{prio} || '';
	my $content = params->{content};
	my $domain_id = database->quick_select('records', { id => $id });
        my $perm = user_acl($domain_id->{domain_id}, 'domain');
	my ($year,$month,$day) = Today();


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


        my $domain = database->quick_select('domains', { id => $domain_id->{domain_id} });

	
	if ($domain->{type} =~ m/^SLAVE$/i)
	{
		return { stat => 'fail', message => "Record update failed, can't modify slave domain"};
	}


        $name =~ s/$domain->{name}$//i;


        if ((! defined $name) || ($name !~ m/(\w)+/))
        {
                $name = $domain->{name};
        }
        else
        {
                $name = $name . "." . $domain->{name};
        }


        $name =~ s/\.\./\./gi;


        my ($stat, $message) = check_record($name, $ttl, $type, $content, $prio);


        if ($stat == 1)
        {
                return { stat => 'fail', message => "Failed to update record, $message" };
        }


        my $sth = database->prepare("select count(id) as count from records where domain_id = ? and type = ? and name = ? and id != ?");
        $sth->execute($domain_id->{domain_id}, 'CNAME', $name, $id);
        my $count = $sth->fetchrow_hashref;


        if ($type eq 'CNAME' && ($name eq $domain->{name} || $count->{count} != 0))
        {
		return { stat => 'fail', message => "Failed to update record, CNAME record must be unique and contain a valid domain name" };
        }


        my $domain_old_serial = $domain->{notified_serial} || 0;
        my $domain_serial = ($year . $month . $day . 1);


        for (my $i = 1; $domain_old_serial >= $domain_serial; $i++)
        {
                $domain_serial = ($year . $month . $day . $i);
        }


        my $soa = database->quick_select('records', { id => $id });
        my $record_old_change_date = $soa->{change_date} || 0;
        my $record_change_date = ($year . $month . $day . 1);


        for (my $i = 1; $record_old_change_date >= $record_change_date; $i++)
        {
                $record_change_date = ($year . $month . $day . $i);
        }


	if ($id != 0 && (defined $name && defined $type && defined $ttl && defined $prio && defined $content))
	{
		if (($type eq 'MX' || $type eq 'SRV'))
		{
			database->quick_update('records', { id => $id }, { name => $name, type => $type, ttl => $ttl, prio => $prio, content => $content, change_date => $record_change_date });
			database->quick_update('domains', { id => $domain_id->{domain_id} }, { notified_serial => $domain_serial });			
		}
		else
		{
                	database->quick_update('records', { id => $id }, { name => $name, type => $type, ttl => $ttl, content => $content, change_date => $record_change_date });
			database->quick_update('domains', { id => $domain_id->{domain_id} }, { notified_serial => $domain_serial });
		}


        	$name =~ s/$domain->{name}//;
        	$name =~ s/\.$//;


		return { id => $id, stat => 'ok', message => 'Record updated', name => $name, type => $type, ttl => $ttl, prio => $prio, content => $content };
	}
	else
	{
		return { stat => 'fail', message => 'Failed to update record' };
	}
};


true;
