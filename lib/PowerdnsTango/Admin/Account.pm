package PowerdnsTango::Admin::Account;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Plugin::Ajax;
use Crypt::SaltedHash;
use Data::Page;

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


get '/admin/user/id/:id' => sub
{
	my $user_id = params->{id} || 0;
	my $perm = user_acl;


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


	my $sth = database->prepare('select * from users_tango where id = ?');
	$sth->execute($user_id);
	my $user = $sth->fetchrow_hashref;

        $sth = database->prepare('select domains.* from domains, domains_acl_tango where (domains.id = domains_acl_tango.domain_id) and domains_acl_tango.user_id = ?');
        $sth->execute($user_id);
	my $user_domains = $sth->fetchall_hashref('name');

        $sth = database->prepare('select * from domains');
        $sth->execute();
        my $system_domains = $sth->fetchall_hashref('name');


	template 'admin-user', { user_id => $user_id, user_domains => $user_domains, system_domains => $system_domains, login => $user->{login}, name => $user->{name}, email => $user->{email}, 
	type => $user->{type}, status => $user->{status}, domain_limit => $user->{domain_limit}, template_limit => $user->{template_limit} };
};


post '/admin/user/id/:id/reset/password' => sub
{
	my $perm = user_acl;
        my $user_id = params->{id} || 0;
        my $password1 = params->{password1};
        my $password2 = params->{password2};


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


	if ($user_id != 0 && ($password1 =~ m/(\w)+/ && $password2 =~ m/(\w)+/) && ($password1 eq $password2))
        {
		my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
                $csh->add($password1);
                my $new_password = $csh->generate;
                database->quick_update('users_tango', { id => $user_id }, { password => $new_password });


                flash message => 'Password reset';
	}
        else
        {
		flash error => 'Password mismatch, please try again';
	}


	return redirect "/admin/user/id/$user_id";
};


post '/admin/user/id/:id/update/ownership' => sub
{
	my $user_id = params->{id} || 0;
	my $perm = user_acl;
	my @domain_owner;
	my @domain_system;
	my $check = 0;


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


	if (ref(params->{domain_owner}) eq 'ARRAY')
	{
		@domain_owner = @{ params->{domain_owner} };
        }
	else
	{
		push (@domain_owner, params->{domain_owner});
	}


        if (ref(params->{domain_system}) eq 'ARRAY')
        {
                @domain_system = @{ params->{domain_system} };
        }
        else
        {
                push (@domain_system, params->{domain_system});
        }


	if ($user_id != 0 && defined $domain_owner[0])
	{
		for (@domain_owner)
		{
			database->quick_delete('domains_acl_tango', { domain_id => $_ });
		}

		$check++;
	}


	if ($user_id != 0 && defined $domain_system[0])
	{
		for (@domain_system)
		{
			database->quick_insert('domains_acl_tango', { user_id => $user_id, domain_id => $_ });
		}

		$check++;
	}


	if ($check != 0)
	{
		flash message => 'Ownership updated';
	}
	else
	{
		flash error => 'Ownership update failed';
	}


	return redirect "/admin/user/id/$user_id";
};


true;
