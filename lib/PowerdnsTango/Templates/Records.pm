package PowerdnsTango::Templates::Records;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use Email::Valid;
use Data::Page;
use PowerdnsTango::Acl qw(user_acl);
use PowerdnsTango::Validate::Records qw(check_soa check_record calc_serial);

our $VERSION = '0.3';


any ['get', 'post'] => '/templates/edit/records/id/:id' => sub
{
	my $template_id = params->{id} || 0;
        my $load_page = params->{p} || 1;
        my $results_per_page = params->{r} || 25;
	my $search = params->{record_search} || 0;
	my $template = database->quick_select('templates_tango', { id => $template_id });
	my $sth;
	my $count;
	my $perm = user_acl($template_id, 'template');


	if ($perm == 1)
	{
        	flash error => "Permission denied";

                return redirect '/templates';
	}


        if (request->method() eq "POST" && $search ne '0')
        {
		$sth = database->prepare('select count(id) as count from templates_records_tango where template_id = ? and type != ? and (name like ? or content like ? or ttl like ?)');
		$sth->execute($template_id, 'SOA', "%$search%", "%$search%", "%$search%");
		$count = $sth->fetchrow_hashref;
	}
	else
	{
                $sth = database->prepare('select count(id) as count from templates_records_tango where template_id = ? and type != ?');
                $sth->execute($template_id, 'SOA');
                $count = $sth->fetchrow_hashref;
	}


        $sth = database->prepare('select * from templates_records_tango where template_id = ? and type = ?');
        $sth->execute($template_id, 'SOA');
        my $soa = $sth->fetchrow_hashref;

	my ($name_server, $contact, undef, $refresh, $retry, $expire, $minimum) = (split /\s/, $soa->{content}) if (defined $soa->{content});
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
        	$sth = database->prepare('select * from templates_records_tango where template_id = ? and type != ? and (name like ? or content like ? or ttl like ?) limit ? offset ?');
        	$sth->execute($template_id, 'SOA', "%$search%", "%$search%", "%$search%", $page->entries_per_page, $display);

                flash error => "Record search found no match" if ($count->{'count'} == 0);
                flash message => "Record search found $count->{'count'} matches" if ($count->{'count'} >= 1);
	}
	else
	{
                $sth = database->prepare('select * from templates_records_tango where template_id = ? and type != ? limit ? offset ?');
                $sth->execute($template_id, 'SOA', $page->entries_per_page, $display);
	}


        template 'templates-records', { template_id => $template_id, template_name => $template->{name}, records => $sth->fetchall_hashref('id'), page => $load_page, results => $results_per_page, 
	previouspage => ($load_page - 1), nextpage => ($load_page + 1), lastpage => $page->last_page, soa_id => $soa->{id}, name_server => $name_server, contact => $contact, refresh => $refresh, 
	retry => $retry, expire => $expire, minimum => $minimum, ttl => $soa->{ttl} };
};


post '/templates/edit/records/id/:id/add' => sub
{
	my $template_id = params->{id} || 0;
        my $name = params->{add_record_host};
        my $type = params->{add_record_type};
        my $prio = params->{add_record_prio} || undef;
	my $ttl = params->{add_record_ttl};
	my $content = params->{add_record_content};
        my $perm = user_acl($template_id, 'template');


        if ($perm == 1)
        {       
                flash error => "Permission denied";

                return redirect '/templates';
        }   


        $name =~ s/(%zone%)|(%domain%)|(%host%)//i;


        if ((! defined $name) || ($name !~ m/(\w)+/))
        {
                $name = '%zone%';
        }
        else
        {
                $name = $name . "." . '%zone%';
        }


        $name =~ s/\.\./\./gi;


        my ($stat, $message) = check_record('dummy.com', $ttl, $type, $content, $prio, 'template');


        if ($stat == 1)
        {
                flash error => "Add record failed, $message";

                return redirect "/templates/edit/records/id/$template_id";
        }


        my $sth = database->prepare("select count(id) as count from templates_records_tango where template_id = ? and type = ? and name = ?");
        $sth->execute($template_id, 'CNAME', $name);
        my $count = $sth->fetchrow_hashref;


        if ($type eq 'CNAME' && ($name eq '%zone%' || $count->{count} != 0))
        {
                flash error => "Add record failed, CNAME record must be unique and contain a valid domain name";

                return redirect "/templates/edit/records/id/$template_id";
        }


	if (($template_id != 0 && ! defined $prio) && (defined $name && defined $type && defined $ttl && defined $content))
	{
		database->quick_insert('templates_records_tango', { template_id => $template_id, name => $name, type => $type, ttl => $ttl, content => $content });
		flash message => "Record added";
	}
	elsif (($template_id != 0) && (defined $name && defined $type && defined $ttl && defined $content && defined $prio))
	{
                database->quick_insert('templates_records_tango', { template_id => $template_id, name => $name, type => $type, ttl => $ttl, content => $content, prio => $prio });
		flash message => "Record added";
	}
	else
	{
                flash error => "Add record failed";
	}


        return redirect "/templates/edit/records/id/$template_id";
};


get '/templates/edit/records/id/:id/delete/recordid/:recordid' => sub
{
        my $template_id = params->{id} || 0;
	my $record_id = params->{recordid} || 0;
        my $perm = user_acl($template_id, 'template');


        if ($perm == 1)
        {       
                flash error => "Permission denied";

                return redirect '/templates';
        }


        if ($template_id != 0 && $record_id != 0)
        {
                database->quick_delete('templates_records_tango', { id => $record_id });
                flash message => "Record deleted";
        }
        else
        {
                flash error => "Record delete failed";
        }


        return redirect "/templates/edit/records/id/$template_id";
};


post '/templates/edit/records/id/:id/find/replace' => sub
{
        my $template_id = params->{id} || 0;
        my $find = params->{find_search};
        my $find_in = params->{find_in};
	my $find_type = params->{find_type};
        my $replace = params->{find_replace};
        my $perm = user_acl($template_id, 'template');
        my $default_ttl_minimum = database->quick_select('admin_settings_tango', { setting => 'default_ttl_minimum' });
        $default_ttl_minimum->{value} = 3600 if (!defined $default_ttl_minimum->{value} || $default_ttl_minimum->{value} !~ m/^(\d)+$/);


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/templates';
        }


        if ($find_in eq 'ttl')
        {
                if ($replace !~ m/^(\d)+$/ || $replace < $default_ttl_minimum->{value})
                {
                        flash error => "Failed to update records, TTL must be a number equal or greater than $default_ttl_minimum->{value}";


                        return redirect "/templates/edit/records/id/$template_id";
                }
        }
        elsif ($find_in eq 'prio')
        {
                if ($replace !~ m/^(\d)+$/ || $replace < 1 || $replace >= 65535)
                {
                        flash error => "Failed to update records, Priority must be a number";


                        return redirect "/templates/edit/records/id/$template_id";
                }
        }
        elsif ($find_in eq 'content')
        {
                my ($stat, $message) = check_record('dummy.com', $default_ttl_minimum->{value}, $find_type, $replace, undef, 'template');


                if ($stat == 1)
                {
                        flash error => "Failed to update records, Content must match record type";

			return redirect "/templates/edit/records/id/$template_id";
                }
        }


        if ($find_in eq 'content' || $find_in eq 'ttl' || $find_in eq 'prio')
        {
		database->quick_update('templates_records_tango', { template_id => $template_id, $find_in => $find }, { $find_in => $replace });

                flash message => "Records updated";
        }
        else
        {
                flash error => "Failed to update records";
        }


        return redirect "/templates/edit/records/id/$template_id";
};


ajax '/templates/edit/records/get/soa' => sub
{
	my $template_id = params->{id} || 0;
	my $soa = database->quick_select('templates_records_tango', { template_id => $template_id, type => 'SOA' });
        my $perm = user_acl($template_id, 'template');


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


	my ($name_server, $contact, undef, $refresh, $retry, $expire, $minimum) = (split /\s/, $soa->{content}) if (defined $soa->{content});
        $name_server = '' if (! defined $name_server);
        $contact = '' if (! defined $contact);
        $refresh = '' if (! defined $refresh);
        $retry = '' if (! defined $retry);
        $expire = '' if (! defined $expire);
        $minimum = '' if (! defined $minimum);


	return { stat => 'ok', name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $soa->{ttl} };
};


ajax '/templates/edit/records/update/soa' => sub
{
        my $id = params->{id} || 0;
	my $template_id = params->{template_id} || 0;
	my $domain = params->{domain};
	my $name_server = params->{name_server};
	my $contact = params->{contact};
	my $refresh = params->{refresh};
	my $retry = params->{retry};
	my $expire = params->{expire};
	my $minimum = params->{minimum};
	my $ttl = params->{ttl} || 3600;
        my $perm = user_acl($template_id, 'template');


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


        my ($stat, $message) = check_soa($name_server, $contact, $refresh, $retry, $expire, $minimum, $ttl);


        if ($stat == 1)
        {
                return { stat => 'fail', message => "Failed to update SOA, $message" };
        }


        my $sth = database->prepare('select count(id) as count from templates_records_tango where template_id = ? and type = ?');
        $sth->execute($template_id, 'SOA');
        my $count = $sth->fetchrow_hashref;


	if (($count->{count} == 0 || $count->{count} > 1) && (defined $name_server && defined $contact && defined $refresh && defined $retry && defined $expire && defined $minimum && defined $ttl))
	{
		database->quick_delete('templates_records_tango', { template_id => $template_id, type => 'SOA' }) if ($count->{count} > 1);
		database->quick_insert('templates_records_tango', { name => '%zone%', template_id => $template_id, type => 'SOA', content => "$name_server $contact 0 $refresh $retry $expire $minimum", ttl => $ttl });

		return { stat => 'ok', message => 'SOA Updated', name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $ttl };
	}
	elsif (($count->{count} == 1 && $id != 0) && (defined $name_server && defined $contact && defined $refresh && defined $retry && defined $expire && defined $minimum && defined $ttl))
	{
		database->quick_update('templates_records_tango', { id => $id, type => 'SOA' }, { name => '%zone%', content => "$name_server $contact 0 $refresh $retry $expire $minimum", ttl => $ttl });

		return { stat => 'ok', message => 'SOA Updated', name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $ttl };
	}
	else
	{
		return { stat => 'fail', message => 'Failed to update SOA' };
	}
};


ajax '/templates/edit/records/get/record' => sub
{
        my $id = params->{id} || 0;
	my $template_id = database->quick_select('templates_records_tango', { id => $id });
	my $perm = user_acl($template_id->{template_id}, 'template');
	my $record = database->quick_select('templates_records_tango', { id => $id });


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


        $record->{name} =~ s/(%zone%)|(%domain%)|(%host%)//i;
        $record->{name} =~ s/\.$//;


        return { stat => 'ok', id => $id, name => $record->{name}, type => $record->{type}, ttl => $record->{ttl}, prio => $record->{prio}, content => $record->{content} };
};


ajax '/templates/edit/records/update/record' => sub
{
	my $id = params->{id} || 0;
        my $name = params->{name};
	my $type = params->{type};
	my $ttl = params->{ttl};
	my $prio = params->{prio} || '';
	my $content = params->{content};
	my $template_id = database->quick_select('templates_records_tango', { id => $id });
        my $perm = user_acl($template_id->{template_id}, 'template');


        if ($perm == 1)
        {
                return { stat => 'fail', message => "Permission denied"};
        }


        $name =~ s/(%zone%)|(%domain%)|(%host%)//i;


        if ((! defined $name) || ($name !~ m/(\w)+/))
        {
                $name = '%zone%';
        }
        else
        {
                $name = $name . "." . '%zone%';
        }


        $name =~ s/\.\./\./gi;


        my ($stat, $message) = check_record('dummy.com', $ttl, $type, $content, $prio, 'template');


        if ($stat == 1)
        {
                return { stat => 'fail', message => "Failed to update record, $message" };
        }


        my $sth = database->prepare("select count(id) as count from templates_records_tango where template_id = ? and type = ? and name = ? and id != ?");
        $sth->execute($template_id->{template_id}, 'CNAME', $name, $id);
        my $count = $sth->fetchrow_hashref;


        if ($type eq 'CNAME' && ($name eq '%zone%' || $count->{count} != 0))
        {
                return { stat => 'fail', message => "Failed to update record, CNAME record must be unique and contain a valid domain name" };
        }


	if ($id != 0 && (defined $name && defined $type && defined $ttl && defined $prio && defined $content))
	{
		if (($type eq 'MX' || $type eq 'SRV'))
		{
			database->quick_update('templates_records_tango', { id => $id }, { name => $name, type => $type, ttl => $ttl, prio => $prio, content => $content });
		}
		else
		{
                	database->quick_update('templates_records_tango', { id => $id }, { name => $name, type => $type, ttl => $ttl, content => $content });
		}


        	$name =~ s/%zone%//i;
        	$name =~ s/\.$//;


		return { id => $id, stat => 'ok', message => 'Record updated', name => $name, type => $type, ttl => $ttl, prio => $prio, content => $content };
	}
	else
	{
		return { stat => 'fail', message => 'Failed to update record' };
	}

};


true;
