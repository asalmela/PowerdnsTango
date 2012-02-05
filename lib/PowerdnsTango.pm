package PowerdnsTango;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Crypt::SaltedHash;
use PowerdnsTango::Home;
use PowerdnsTango::Domains;
use PowerdnsTango::Domains::Records;
use PowerdnsTango::Password;
use PowerdnsTango::Templates;
use PowerdnsTango::Templates::Records;
use PowerdnsTango::Supermasters;
use PowerdnsTango::Account;
use PowerdnsTango::Admin;
use PowerdnsTango::Admin::Account;
use PowerdnsTango::Signup;
use PowerdnsTango::Acl qw(user_acl);
use PowerdnsTango::Validate::Records qw(check_soa check_record calc_serial);
 
our $VERSION = '0.3';


before sub
{
	if (! session('logged_in') && (request->path_info !~ m{^/login} && request->path_info !~ m{^/password} && request->path_info !~ m{^/signup} ))
	{
		var requested_path => request->path_info;
		request->path_info('/login');
	}
};


any ['get', 'post'] => '/login' => sub
{
	my $recover_password = 0;
	my $account_signup = database->quick_select('admin_settings_tango', { setting => 'account_signup' }) || 'disabled';
	my $account_password_recovery = database->quick_select('admin_settings_tango', { setting => 'password_recovery' }) || 'disabled';


        if ( request->method() eq "POST" )
        {
		my $sth = database->prepare("select count(id) as count from users_tango where login=?");
	        $sth->execute(params->{login});
                my $data = $sth->fetchrow_hashref;


		if (!defined $data->{count} || $data->{count} != 1)
		{
			$recover_password = 1 if ($account_password_recovery->{value} eq 'enabled') || 0;

                        flash error => 'Login has failed';
			
		}
		else
		{
                	$sth = database->prepare("select * from users_tango where login=?");
               		$sth->execute(params->{login});
                	$data = $sth->fetchrow_hashref;
			my $valid = Crypt::SaltedHash->validate($data->{password}, params->{password});
			my $downtime = database->quick_select('admin_settings_tango', { setting => 'downtime' });

                	if (defined $valid && $valid == 1)
                	{
				if ((defined $data->{status}) && ($data->{status} ne 'enabled'))
				{
					flash error => 'Your account is currently disabled';


					return redirect '/login';
				}
				elsif ((defined $downtime->{value}) && ($downtime->{value} eq 'enabled') && ($data->{type} eq 'user'))
				{
				        flash error => 'System is currently down for maintenance, please try again later';


                                        return redirect '/login';
				}
				else
				{
					session->destroy;
                        		session 'logged_in' => true;
					session 'user_id' => $data->{id};
					session 'user_login' => $data->{login};
					session 'user_name' => $data->{name};
					session 'user_email' => $data->{email};
					session 'user_type' => $data->{type} || 'user';
					session->flush();

					flash message => 'Welcome ' . params->{login} . ', you are logged in';


                        		return redirect '/';
				}
                	}
                	else
                	{
				$recover_password = 1 if ((defined $account_password_recovery->{value}) && ($account_password_recovery->{value} eq 'enabled'));

                        	flash error => 'Login has failed';
                	}
		}
        }


	template 'login.tt', { recover_password => $recover_password, account_signup => $account_signup->{value} };
};


get '/logout' => sub
{
        session->destroy;
	flash message => 'You have been logged out';


        redirect '/';
};


any qr{.*} => sub
{
        status 'not_found';


        template '404', { path => request->path };
};


true;
