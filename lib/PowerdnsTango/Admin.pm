package PowerdnsTango::Admin;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Email;
use Crypt::SaltedHash;
use Data::Page;
use Email::Valid;

our $VERSION = '0.1';


sub user_acl
{
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';


        if ($user_type eq 'admin')
        {
                return 0;
        }
        else
        {
                return 1;
        }
};


any ['get', 'post'] => '/admin' => sub
{
        my $perm = user_acl;
        my $load_page = params->{p} || 1;
        my $results_per_page = params->{r} || 25;
        my $search = params->{user_search} || 0;
	my $sth;
	my $page;
	my $display;


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


        if (request->method() eq "POST" && $search ne '0')
        {
                $sth = database->prepare('select count(id) as count from users_tango where (login like ? or name like ? or email like ? or type like ? or status like ?)');
                $sth->execute("%$search%", "%$search%", "%$search%", "%$search%", "%$search%");
                my $count = $sth->fetchrow_hashref;

                $page = Data::Page->new();
                $page->total_entries($count->{'count'});
                $page->entries_per_page($results_per_page);
                $page->current_page($load_page);

                $display = ($page->entries_per_page * ($page->current_page - 1));
                $load_page = $page->last_page if ($load_page > $page->last_page);
                $load_page = $page->first_page if ($load_page == 0);

                $sth = database->prepare('select * from users_tango where (login like ? or name like ? or email like ? or type like ? or status like ?) limit ? offset ?');
                $sth->execute("%$search%", "%$search%", "%$search%", "%$search%", "%$search%", $page->entries_per_page, $display);


                flash error => "User search found no match" if ($count->{'count'} == 0);
                flash message => "User search found $count->{'count'} matches" if ($count->{'count'} >= 1);
	}
	else
	{
        	$sth = database->prepare('select count(id) as count from users_tango');
        	$sth->execute();
        	my $count = $sth->fetchrow_hashref;

        	$page = Data::Page->new();
        	$page->total_entries($count->{'count'});
        	$page->entries_per_page($results_per_page);
        	$page->current_page($load_page);

        	$display = ($page->entries_per_page * ($page->current_page - 1));
        	$load_page = $page->last_page if ($load_page > $page->last_page);
        	$load_page = $page->first_page if ($load_page == 0);

        	$sth = database->prepare('select * from users_tango limit ? offset ?');
        	$sth->execute($page->entries_per_page, $display);
	}


	my $account_signup = database->quick_select('admin_settings_tango', { setting => 'account_signup' });
	my $password_recovery = database->quick_select('admin_settings_tango', { setting => 'password_recovery' });
	my $downtime = database->quick_select('admin_settings_tango', { setting => 'downtime' });
	my $default_domain_limit = database->quick_select('admin_settings_tango', { setting => 'default_domain_limit' });
	my $default_template_limit = database->quick_select('admin_settings_tango', { setting => 'default_template_limit' });
	my $motd = database->quick_select('admin_settings_tango', { setting => 'announcement' });
	my $default_soa = database->quick_select('admin_default_soa_tango', {});


        template 'admin', { users => $sth->fetchall_hashref('id'), page => $load_page, results => $results_per_page, previouspage => ($load_page - 1), nextpage => ($load_page + 1), lastpage => $page->last_page, 
	settings_signup => $account_signup->{value}, settings_recovery => $password_recovery->{value}, settings_downtime => $downtime->{value}, default_domain_limit => $default_domain_limit->{value}, 
	default_template_limit => $default_template_limit->{value}, settings_motd => $motd->{value}, default_soa_name_server => $default_soa->{name_server}, default_soa_contact => $default_soa->{contact},
	default_soa_refresh => $default_soa->{refresh}, default_soa_retry => $default_soa->{retry}, default_soa_expire => $default_soa->{expire}, default_soa_minimum => $default_soa->{minimum}, 
	default_soa_ttl => $default_soa->{ttl} };
};


post '/admin/add/user' => sub
{
        my $perm = user_acl;
	my $login = params->{add_login};
	my $name = params->{add_name};
	my $password1 = params->{add_password1};
	my $password2 = params->{add_password2};
	my $email = params->{add_email};
	my $type = params->{add_type};
	my $status = params->{add_status};
	my $domain_limit = params->{add_domain_limit};
	my $template_limit = params->{add_template_limit};


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


	if ($login =~ m/(\w)+/ && $name =~ m/(\w)+/ && $password1 =~ m/(\w)+/ && $password2 =~ m/(\w)+/ && $email =~ m/(\w)+/ && $type =~ m/(\w)+/ && $status =~ m/(\w+)/ && $domain_limit =~ m/^(\d)+$/ && $template_limit =~ m/^(\d)+$/)
	{

		if ($password1 ne $password2)
		{
			flash error => "Add account failed, password mismatch";	

			return redirect '/admin';
		}


		if (! Email::Valid->address($email))
		{
			flash error => "Add account failed, $email is not a valid email address";

			return redirect '/admin';
		}


		$type = 'user' if ($type ne 'admin' && $type ne 'user');
		$status = 'disabled' if ($status ne 'enabled' && $status ne 'disabled');

	        my $sth = database->prepare('select count(login) as count from users_tango where login = ?');
                $sth->execute($login);
                my $check_login = $sth->fetchrow_hashref;


		if ($check_login->{count} == 0)
		{
        		my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
        		$csh->add($password1);
        		my $new_password = $csh->generate;

			database->quick_insert('users_tango', { login => $login, password => $new_password, name => $name, email => $email, type => $type, status => $status, domain_limit => $domain_limit, template_limit => $template_limit });

			flash message => "Account created";
		}
		else
		{
			flash error => "Add account failed, username $login already exists";
		}
	}
	else
	{
		flash error => "Add account failed, ensure all fields have been filled out correctly";
	}


	return redirect '/admin';
};


get '/admin/delete/user/id/:id' => sub
{
	my $perm = user_acl;
	my $user_id  = params->{id} || 0;


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	if ($user_id != 0)
	{
		database->quick_delete('domains_acl_tango', { user_id => $user_id });
		database->quick_delete('templates_acl_tango', { user_id => $user_id });
		database->quick_delete('signup_activation_tango', { user_id => $user_id });
		database->quick_delete('users_tango', { id => $user_id });

		flash message => "Account deleted";
	}
	else
	{
		flash error => "Account delete failed";		
	}


	return redirect '/admin';
};


ajax '/admin/get/soa' => sub
{
	my $perm = user_acl;


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	my $default_soa = database->quick_select('admin_default_soa_tango', {});


	return { stat => 'ok', name_server => $default_soa->{name_server}, contact => $default_soa->{contact}, refresh => $default_soa->{refresh}, retry => $default_soa->{retry}, expire => $default_soa->{expire},
	minimum => $default_soa->{minimum}, ttl => $default_soa->{ttl} };
};


ajax '/admin/save/soa' => sub
{
        my $perm = user_acl;
	my $name_server = params->{name_server};
	my $contact = params->{contact};
	my $refresh = params->{refresh};
	my $retry = params->{retry};
	my $expire = params->{expire};
	my $minimum = params->{minimum};
	my $ttl = params->{ttl};


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	if (!defined $name_server || $name_server !~ m/(\w)+/)
	{
		return { stat => 'fail', message => "Default SOA update failed, a name server must be entered" };
	}
	elsif (!defined $contact || (! Email::Valid->address($contact)))
	{
		return { stat => 'fail', message => "Default SOA update failed, $contact is not a valid email address" };
	}
	elsif (!defined $refresh || $refresh !~ m/^(\d)+$/)
	{
		return { stat => 'fail', message => "Default SOA update failed, refresh must be a number" };
	}
        elsif (!defined $retry || $retry !~ m/^(\d)+$/)
        {
                return { stat => 'fail', message => "Default SOA update failed, retry must be a number" };
        }
        elsif (!defined $expire || $expire !~ m/^(\d)+$/)
        {
                return { stat => 'fail', message => "Default SOA update failed, expire must be a number" };
        }
        elsif (!defined $minimum || $minimum !~ m/^(\d)+$/)
        {
                return { stat => 'fail', message => "Default SOA update failed, minimum must be a number" };
        }
        elsif (!defined $ttl || $ttl !~ m/^(\d)+$/)
        {
                return { stat => 'fail', message => "Default SOA update failed, ttl must be a number" };
        }


        database->quick_delete('admin_default_soa_tango', {});
	database->quick_insert('admin_default_soa_tango', { name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $ttl });


        return { stat => 'ok', message => "Default SOA updated", name_server => $name_server, contact => $contact, refresh => $refresh, retry => $retry, expire => $expire, minimum => $minimum, ttl => $ttl };
};


ajax '/admin/get/user' => sub
{
        my $user_id = params->{id} || 0;
        my $perm = user_acl;


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	my $user = database->quick_select('users_tango', { id => $user_id });


        return { stat => 'ok', id => $user_id, login => $user->{login}, name => $user->{name}, email => $user->{email}, type => $user->{type}, user_stat => $user->{status}, domain_limit => $user->{domain_limit}, template_limit => $user->{template_limit} };
};


ajax '/admin/save/user' => sub
{
	my $perm = user_acl;
        my $user_id = params->{id} || 0;
	my $login = params->{login};
	my $name = params->{name};
	my $email = params->{email};
	my $type = params->{type};
	my $status = params->{user_stat};
	my $domain_limit = params->{domain_limit};
	my $template_limit = params->{template_limit};


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


        my $user = database->quick_select('users_tango', { id => $user_id });
        my $sth = database->prepare('select count(login) as count from users_tango where login = ?');
        $sth->execute($login);
        my $check_login = $sth->fetchrow_hashref;


        if ($check_login->{count} != 0 && $login ne $user->{login})
        {
                return { stat => 'fail', message => "Account update failed, username $login already exists" };
        }


        if ($login =~ m/(\w)+/ && $name =~ m/(\w)+/ && (Email::Valid->address($email)) && $type =~ m/(\w)+/ && $status =~ m/(\w+)/ && $domain_limit =~ m/^(\d)+$/ && $template_limit =~ m/^(\d)+$/)
        {
        	$sth = database->prepare("select count(user_id) as count from signup_activation_tango where user_id = ?");
        	$sth->execute($user_id);
        	my $check_account = $sth->fetchrow_hashref;


		if ($check_account->{count} != 0 && $status eq 'enabled')
		{
                	my $html = template 'email-confirm-signup', { name => $name }, { layout => undef };
                        my $txt = template 'email-confirm-signup-txt', { name => $name }, { layout => undef };

                        email {
                        	to => $email,
                                type => 'multi',
                                message => {
                                	text => $txt,
                                        html => $html,
                                }
                        };


			database->quick_delete('signup_activation_tango', { user_id => $user_id });
		}


		database->quick_update('users_tango', { id => $user_id }, { login => $login, name => $name, email => $email, type => $type, status => $status, domain_limit => $domain_limit, template_limit => $template_limit  });


		return { stat => 'ok', message => "Account $login updated", id => $user_id, login => $login, name=> $name, email => $email, type => $type, user_stat => $status, domain_limit => $domain_limit, template_limit => $template_limit };
	}
	elsif (! Email::Valid->address($email))
	{
		return { stat => 'fail', message => "Account update failed, $email is not a valid email address" };
	}
	else
	{
		return { stat => 'fail', message => 'Account update failed, ensure all fields have been filled out correctly' };
	}
};


ajax '/admin/get/settings' => sub
{
        my $perm = user_acl;


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


        my $account_signup = database->quick_select('admin_settings_tango', { setting => 'account_signup' });
        my $password_recovery = database->quick_select('admin_settings_tango', { setting => 'password_recovery' });
        my $downtime = database->quick_select('admin_settings_tango', { setting => 'downtime' });
	my $default_domain_limit = database->quick_select('admin_settings_tango', { setting => 'default_domain_limit' });
	my $default_template_limit = database->quick_select('admin_settings_tango', { setting => 'default_template_limit' });
	my $motd = database->quick_select('admin_settings_tango', { setting => 'announcement' });


        return { stat => 'ok', account_signup => $account_signup->{value}, password_recovery => $password_recovery->{value}, downtime => $downtime->{value}, 
	default_domain_limit => $default_domain_limit->{value}, default_template_limit => $default_template_limit->{value}, motd => $motd->{value} };
};


ajax '/admin/save/settings' => sub
{
        my $perm = user_acl;
	my $account_signup = params->{account_signup};
	my $password_recovery = params->{password_recovery};
	my $downtime = params->{downtime};
	my $default_domain_limit = params->{default_domain_limit};
	my $default_template_limit = params->{default_template_limit};
	my $motd = params->{motd};


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	$account_signup = 'admin' if ($account_signup ne 'enabled' && $account_signup ne 'disabled' && $account_signup ne 'admin');
	$password_recovery = 'enabled' if ($password_recovery ne 'enabled' && $password_recovery ne 'disabled');
	$downtime = 'disabled' if ($downtime ne 'enabled' && $downtime ne 'disabled');

	return { stat => 'fail', message => "Default domain limit must be a number" } if $default_domain_limit !~ m/^(\d)+$/;
	return { stat => 'fail', message => "Default template limit must be a number" } if $default_template_limit !~ m/^(\d)+$/;	

        database->quick_delete('admin_settings_tango', { setting => 'account_signup' });
        database->quick_delete('admin_settings_tango', { setting => 'password_recovery' });
        database->quick_delete('admin_settings_tango', { setting => 'downtime' });
	database->quick_delete('admin_settings_tango', { setting => 'default_domain_limit' });
	database->quick_delete('admin_settings_tango', { setting => 'default_template_limit' });
	database->quick_delete('admin_settings_tango', { setting => 'announcement' });
	
	database->quick_insert('admin_settings_tango', { setting => 'account_signup', value => $account_signup });
	database->quick_insert('admin_settings_tango', { setting => 'password_recovery', value => $password_recovery });
	database->quick_insert('admin_settings_tango', { setting => 'downtime', value => $downtime });
	database->quick_insert('admin_settings_tango', { setting => 'default_domain_limit', value => $default_domain_limit });
	database->quick_insert('admin_settings_tango', { setting => 'default_template_limit', value => $default_template_limit });
	database->quick_insert('admin_settings_tango', { setting => 'announcement', value => $motd });


        return { stat => 'ok', message => "System settings updated", account_signup => $account_signup, password_recovery => $password_recovery, downtime => $downtime, 
	default_domain_limit => $default_domain_limit, default_template_limit => $default_template_limit, motd => $motd };
};


true;
