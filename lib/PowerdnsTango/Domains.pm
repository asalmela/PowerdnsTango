package PowerdnsTango::Domains;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Date::Calc qw(:all);
use Data::Page;
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use PowerdnsTango::Acl qw(user_acl);

our $VERSION = '0.3';


any ['get', 'post'] => '/domains' => sub
{
	my $load_page = params->{p} || 1;
	my $results_per_page = params->{r} || 25;
	my $search = params->{domain_search} || 0;
	my $sth;
	my $page;
	my $display;
	my $count;
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';


	if (request->method() eq "POST" && $search ne '0')
	{
		if ($user_type eq 'admin')
		{
                        $sth = database->prepare('select count(id) as count from domains where name like ?');
                        $sth->execute("%$search%");
		}
		else
		{
                        $sth = database->prepare('select count(domains.id) as count from domains, domains_acl_tango where (domains.id = domains_acl_tango.domain_id) and domains_acl_tango.user_id = ? and name like ?');
                        $sth->execute($user_id, "%$search%");
		}


        	$count = $sth->fetchrow_hashref;
        	$page = Data::Page->new();
        	$page->total_entries($count->{'count'});
        	$page->entries_per_page($results_per_page);
        	$page->current_page($load_page);

        	$display = ($page->entries_per_page * ($page->current_page - 1));
        	$load_page = $page->last_page if ($load_page > $page->last_page);
        	$load_page = $page->first_page if ($load_page == 0);


		if ($user_type eq 'admin')
		{
                        $sth = database->prepare('select * from domains where name like ? limit ? offset ?');
                        $sth->execute("%$search%", $page->entries_per_page, $display);
		}
		else
		{
                        $sth = database->prepare('select domains.* from domains, domains_acl_tango where (domains.id = domains_acl_tango.domain_id) and domains_acl_tango.user_id = ? and name like ? limit ? offset ?');
                        $sth->execute($user_id, "%$search%", $page->entries_per_page, $display);
		}


		flash error => "Domain search found no match" if ($count->{'count'} == 0);
		flash message => "Domain search found $count->{'count'} matches" if ($count->{'count'} >= 1);
	}
	else
	{
		if ($user_type eq 'admin')
		{
                        $sth = database->prepare('select count(id) as count from domains');
                        $sth->execute();
		}
		else
		{
                        $sth = database->prepare('select count(domains.id) as count from domains, domains_acl_tango where (domains.id = domains_acl_tango.domain_id) and domains_acl_tango.user_id = ?');
                        $sth->execute($user_id);
		}

	
        	$count = $sth->fetchrow_hashref;

        	$page = Data::Page->new();
        	$page->total_entries($count->{'count'});
        	$page->entries_per_page($results_per_page);
        	$page->current_page($load_page);

        	$display = ($page->entries_per_page * ($page->current_page - 1));
        	$load_page = $page->last_page if ($load_page > $page->last_page);
        	$load_page = $page->first_page if ($load_page == 0);


		if ($user_type eq 'admin')
		{
                        $sth = database->prepare('select * from domains limit ? offset ?');
                        $sth->execute($page->entries_per_page, $display);
		}
		else
		{
                        $sth = database->prepare('select domains.* from domains, domains_acl_tango where (domains.id = domains_acl_tango.domain_id) and domains_acl_tango.user_id = ? limit ? offset ?');
                        $sth->execute($user_id, $page->entries_per_page, $display);
		}


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


        template 'domains', { domains => $sth->fetchall_hashref('name'), templates => $templates->fetchall_hashref('id'), page => $load_page, results => $results_per_page, previouspage => ($load_page - 1), 
	nextpage => ($load_page + 1), lastpage => $page->last_page };
};


post '/domains/add' => sub
{
	my $domain = params->{add_domain_name} || 0;
	my $type = params->{add_domain_type} || 0;
	my $master = params->{add_master_addr};
	my $template_id = params->{add_domain_template} || 0;
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';
	my ($year,$month,$day) = Today();
	my $success = 0;
	my $sth;

	$domain =~ s/\s//g;
	$master =~ s/\s//g if (defined $master);


	if (! is_domain($domain))
	{
		flash error => "Domain $domain is not a valid domain name";

		return redirect '/domains';
	}


	if ($user_type ne 'admin')
	{
		my $user_domain_limit = database->quick_select('users_tango', { id => $user_id });
		$sth = database->prepare("select count(id) as count from domains_acl_tango where user_id = ?");
        	$sth->execute($user_id);
        	my $owned_domains = $sth->fetchrow_hashref;


		if ($owned_domains->{count} >= $user_domain_limit->{domain_limit})
		{
			flash error => "You have reached your domain limit";

			return redirect '/domains';
		}
	}


        $sth = database->prepare("select count(name) as count from domains where name = ?");
        $sth->execute($domain);
        my $count = $sth->fetchrow_hashref;


	if ($count->{count} != 0)
	{
		
		flash error => "Domain $domain already exists";
	} 
	elsif (is_domain($domain) && ($type =~ m/^NATIVE$/i || $type =~ /^MASTER$/i))
	{
		database->quick_insert('domains', { name => $domain, type => $type, notified_serial => ($year . $month . $day . 1) });
		my $get_id = database->quick_select('domains', { name => $domain });
		database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $get_id->{id} });
		$success++;

		flash message => "Domain $domain added";
	}
	elsif (is_domain($domain) && $type =~ m/^SLAVE$/i && (defined $master) && ((is_domain($master)) || (is_ipv4($master)) || (is_ipv6($master))))
	{
                database->quick_insert('domains', { name => $domain, type => $type, master => $master, notified_serial => ($year . $month . $day . 1) });
                my $get_id = database->quick_select('domains', { name => $domain });
                database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $get_id->{id} });
		$success++;

                flash message => "Domain $domain added";
	}
	elsif (is_domain($domain) && $type =~ m/^SLAVE$/i && (! defined $master) || ((! is_domain($master)) && (! is_ipv4($master)) && (! is_ipv6($master))))
	{
		flash error => "A vaild master address must be provided";
	}

	
	if ($template_id != 0 && $success != 0 && $type !~ m/^SLAVE$/i)
	{
		my $domain_id = database->quick_select('domains', { name => $domain });
	        my $templates_records = database->prepare('select * from templates_records_tango where template_id = ?');
        	$templates_records->execute($template_id);


		while (my $template_row = $templates_records->fetchrow_hashref)
		{
			$template_row->{name} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
			$template_row->{name} =~ s/\%(\s)?(.+?)(\s)?\%//i;
                        $template_row->{content} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
                        $template_row->{content} =~ s/\%(\s)?(.+?)(\s)?\%//i;

			database->quick_insert('records', { domain_id => $domain_id->{id}, name => $template_row->{name}, type => $template_row->{type}, content => $template_row->{content}, 
			ttl => $template_row->{ttl}, prio => $template_row->{prio}, change_date => ($year . $month . $day . 1) });
		}
	}
	elsif ($type !~ m/^SLAVE$/)
	{
		my $domain_id = database->quick_select('domains', { name => $domain });
		my $default_soa = database->quick_select('admin_default_soa_tango', {});

                if (defined $default_soa->{name_server} && defined $default_soa->{contact} && defined $default_soa->{refresh} && defined $default_soa->{retry} && defined $default_soa->{expire} && defined
                $default_soa->{minimum} && defined $default_soa->{ttl})
		{
			my $content = ($default_soa->{name_server} . " " . $default_soa->{contact} . " " . $default_soa->{refresh} . " " . $default_soa->{retry} . " " . $default_soa->{expire} . " " . $default_soa->{minimum});
			database->quick_insert('records', { domain_id => $domain_id->{id}, name => $domain, type => 'SOA', content => $content, ttl => $default_soa->{ttl}, change_date => ($year . $month . $day . 1) });
		}
	}


	return redirect '/domains';
};


post '/domains/add/bulk' => sub
{
	my @domain = do {local $_ = params->{add_bulk_domain_name}; split};
	my $type = params->{add_bulk_domain_type} || 0;
	my $master = params->{add_bulk_master_addr};
	my $template_id = params->{add_bulk_domain_template} || 0;
	my $count = @domain;
        my $success = 0;
        my $error = 0;
	my $status;
	my ($year,$month,$day) = Today();
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';


	for my $domain (@domain)
	{
		my $msg;
		my $err;

                $domain =~ s/\s//g;
                $master =~ s/\s//g if (defined $master);


		if (! is_domain($domain))
        	{
			$err = template 'error-format', { error => "Domain $domain is not a valid domain name" }, { layout => undef };
			$status .= $err;
			$error++;

			next;
		}


        	my $sth = database->prepare("select count(name) as count from domains where name = ?");
        	$sth->execute($domain);
        	my $count = $sth->fetchrow_hashref;


        	if ($user_type ne 'admin')
        	{
                	my $user_domain_limit = database->quick_select('users_tango', { id => $user_id });
                	$sth = database->prepare("select count(id) as count from domains_acl_tango where user_id = ?");
                	$sth->execute($user_id);
                	my $owned_domains = $sth->fetchrow_hashref;


                	if ($owned_domains->{count} >= $user_domain_limit->{domain_limit})
                	{
                        	$err = template 'error-format', { error => "Domain $domain was not added, you have reached your domain limit" }, { layout => undef };
                        	$status .= $err;
                        	$error++;
				next;
                	}
        	}


		if ($count->{count} != 0)   
        	{
			$err = template 'error-format', { error => "Domain $domain already exists" }, { layout => undef };
			$status .= $err;
			$error++;
        	}
        	elsif (is_domain($domain) && ($type =~ m/^NATIVE$/i || $type =~ m/^MASTER$/i))
        	{
                	database->quick_insert('domains', { name => $domain, type => $type, notified_serial => ($year . $month . $day . 1) });
                	my $get_id = database->quick_select('domains', { name => $domain });
                	database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $get_id->{id} });
                        $msg = template 'message-format', { message => "Domain $domain added" }, { layout => undef };
                        $status .= $msg;
			$success++;
        	}
        	elsif (is_domain($domain) && ($type =~ m/^SLAVE$/i) && (defined $master) && ((is_domain($master)) || (is_ipv4($master)) || (is_ipv6($master))))
        	{
                	database->quick_insert('domains', { name => $domain, type => $type, master => $master, notified_serial => ($year . $month . $day . 1) });
                	my $get_id = database->quick_select('domains', { name => $domain });
                	database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $get_id->{id} });
                        $msg = template 'message-format', { message => "Domain $domain added" }, { layout => undef };
                        $status .= $msg;
			$success++;
        	}
        	elsif (is_domain($domain) && ($type =~ m/^SLAVE$/i) && (! defined $master) || ((! is_domain($master)) && (! is_ipv4($master)) && (! is_ipv6($master))))
        	{
                        $err = template 'error-format', { error => "Domain $domain was not added, a valid master address must be provided" }, { layout => undef };
                        $status .= $err;
			$error++;
        	}

        
		if ($template_id != 0 && $success != 0 && $type !~ m/^SLAVE$/i)
        	{
                	my $domain_id = database->quick_select('domains', { name => $domain });
                	my $templates_records = database->prepare('select * from templates_records_tango where template_id = ?');
                	$templates_records->execute($template_id);


                	while (my $template_row = $templates_records->fetchrow_hashref)
                	{
                       		$template_row->{name} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
                       		$template_row->{name} =~ s/\%(\s)?(.+?)(\s)?\%//i;
                       		$template_row->{content} =~ s/\%(\s)?(zone|domain|host)(\s)?\%/$domain/i;
                       		$template_row->{content} =~ s/\%(\s)?(.+?)(\s)?\%//i;

                       		database->quick_insert('records', { domain_id => $domain_id->{id}, name => $template_row->{name}, type => $template_row->{type}, content => $template_row->{content},
                       		ttl => $template_row->{ttl}, prio => $template_row->{prio}, change_date => ($year . $month . $day . 1) });
               		}
       		}
		elsif ($type !~ m/^SLAVE$/i)
		{	
                	my $domain_id = database->quick_select('domains', { name => $domain });
                	my $default_soa = database->quick_select('admin_default_soa_tango', {});

			if (defined $default_soa->{name_server} && defined $default_soa->{contact} && defined $default_soa->{refresh} && defined $default_soa->{retry} && defined $default_soa->{expire} && defined 
			$default_soa->{minimum} && defined $default_soa->{ttl})
			{
                		my $content = ($default_soa->{name_server} . " " . $default_soa->{contact} . " " . $default_soa->{refresh} . " " . $default_soa->{retry} . " " . $default_soa->{expire} . " " . $default_soa->{minimum});
                		database->quick_insert('records', { domain_id => $domain_id->{id}, name => $domain, type => 'SOA', content => $content, ttl => $default_soa->{ttl}, change_date => ($year . $month . $day . 1) });
			}
        	}
	}


	if (($success == $count) && ($count ne 0))
	{
		flash message => "Domains added";
	}
	elsif ($success >= 1)
	{
		flash error => "Domainis added with some failures";
	}
	else
	{
		flash error => "Failed to add domains, please ensure the domain(s) provided are valid";
	}


	flash detail => $status;


	return redirect '/domains';
};


get '/domains/delete/id/:id' => sub
{
	my $id = params->{id} || 0;
        my $perm = user_acl($id, 'domain');


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


	if ($id != 0)
	{
		database->quick_delete('domains', { id => $id });
		database->quick_delete('records', { domain_id => $id });
		database->quick_delete('domains_acl_tango', { domain_id => $id });


		flash message => "Domain deleted";
	}
	else
	{
		flash error => "Domain deleted failed";
	}


	return redirect '/domains';
};


ajax '/domains/update' => sub
{
	my $id = params->{id} || 0;
	my $domain = params->{name} || 0;
	my $type = params->{type} || 0;
	my $master = params->{master};
        my $perm = user_acl($id, 'domain');
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


        my $sth = database->prepare("select count(name) as count from domains where name = ?");
        $sth->execute($domain);
        my $count = $sth->fetchrow_hashref;

	$sth = database->prepare("select name from domains where id = ?");
	$sth->execute($id);
	my $old_domain = $sth->fetchrow_hashref;


	if (($count->{count} != 0) && ($old_domain->{name} ne $domain))
	{
		return { stat => 'fail', message => "Domain $domain already exists" };
	}
	elsif (is_domain($domain) && ($type =~ m/^NATIVE$/i || $type =~ m/^MASTER$/i))
        {
		database->quick_update('domains', { id => $id }, { name => $domain, type => $type, master => undef });
		$sth = database->prepare("select * from records where domain_id = ?");
		$sth->execute($id);

                while (my $row = $sth->fetchrow_hashref)
                {
                        $row->{name} =~ s/$old_domain->{name}/$domain/i;
                        $row->{content} =~ s/$old_domain->{name}/$domain/i;

			database->quick_update('records', { id => $row->{id} }, { name => $row->{name}, content => $row->{content} });
                }
        }
        elsif (is_domain($domain) && ($type =~ m/^SLAVE$/i) && (defined $master) && ((is_domain($master)) || (is_ipv4($master)) || (is_ipv6($master))))
        {
		database->quick_update('domains', { id => $id }, { name => $domain, type => $type, master => $master });
                database->quick_delete('records', { domain_id => $id });
        }
	elsif ((! defined $master) || ((! is_domain($master)) && (! is_ipv4($master)) && (! is_ipv6($master))))
	{
		return { stat => 'fail', message => 'Domain update failed, a valid master address is required' };
	}
        else
        {
		return { stat => 'fail', message => 'Domain update failed' };
        }


	return { stat => 'ok', message => 'Domain updated', id => $id, name => $domain, type => $type, master => $master };
};


ajax '/domains/get' => sub
{
        my $id = params->{id} || 0;
	my $perm = user_acl($id, 'domain');


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	my $domain = database->quick_select('domains', { id => $id });


        return { stat => 'ok', id => $id, name => $domain->{name}, type => $domain->{type}, master => $domain->{master} };
};


true;
