package PowerdnsTango::Signup;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Email;
use Dancer::Plugin::Captcha::SecurityImage;
use Crypt::SaltedHash;
use MIME::Base64::URLSafe;
use Date::Calc qw(:all);
use Email::Valid;
use PowerdnsTango::Acl qw(user_acl);

our $VERSION = '0.3';


get '/signup/captcha' => sub
{
	my @security_key = (map { ("a".."z")[rand 26] } 1..5);

	create_captcha { 	new => { width => 120, height => 50, lines => 25, gd_font => 'giant', bgcolor  => '#eae6ea', },
				create     => [ normal => 'circle', '#604977', '#80C0F0' ],
				particle   => [ 100 ],
				out        => { force => 'jpeg' },
				random     => "@security_key",
			};
};


any ['get', 'post'] => '/signup' => sub
{
	my $login = params->{login} || '';
	my $name = params->{name} || '';
	my $password1 = params->{password1} || '';
	my $password2 = params->{password2} || '';
	my $email = params->{email} || '';
	my $img_key = params->{captcha_input} || '';
	my @security_key;
	my $captcha = '';


	if (request->method() eq "POST")
	{
		@security_key = split(//, $img_key);
		map { $captcha .= $_ . ' ' if ($_ !~ m/^(\s)+$/) } @security_key;
		chop ($captcha);
	}


        my $account_signup = database->quick_select('admin_settings_tango', { setting => 'account_signup' });
	

	if ($account_signup->{value} ne 'enabled' && $account_signup->{value} ne 'admin')
	{
		flash error => "Account signup is disabled";

		return redirect '/login';
	}


        if (request->method() eq "POST")
        {

		if ($login =~ m/(\w)+/ && $name =~ m/(\w)+/ && $password1 =~ m/(\w)+/ && $password2 =~ m/(\w)+/ && $email =~ m/(\w)+/ && validate_captcha $captcha)
		{
                	my $sth = database->prepare('select count(login) as count from users_tango where login = ?');
                	$sth->execute($login);
                	my $check_login = $sth->fetchrow_hashref;

			$sth = database->prepare('select count(email) as count from users_tango where email = ?');
			$sth->execute($email);
			my $check_email = $sth->fetchrow_hashref;


			if ($check_login->{count} != 0)
			{
				flash error => "Signup failed, account with login $login already exists";
			}
			elsif ($check_email->{count} != 0)
			{
				flash error => "Signup failed, account with email $email already exists";
			}
	        	elsif ($password1 ne $password2)
                	{
                        	flash error => "Signup failed, passwords don't match";
			}
			elsif (! Email::Valid->address($email))
                	{
                        	flash error => "Signup failed, $email is not a valid email address";
			}
			else
			{
				my $default_domain_limit = database->quick_select('admin_settings_tango', { setting => 'default_domain_limit' });
				my $default_template_limit = database->quick_select('admin_settings_tango', { setting => 'default_template_limit' });
                        	my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
                        	$csh->add($password1);
                        	my $new_password = $csh->generate;

                        	database->quick_insert('users_tango', { login => $login, password => $new_password, name => $name, email => $email, type => 'user', 
				status => 'disabled', domain_limit => $default_domain_limit->{value}, template_limit => $default_template_limit->{value} });

				my $user_id = database->quick_select('users_tango', { login => $login });
                        	my $security_key = int(rand(49))+1;


                        	for (3 .. 6)
                        	{
                                	my $number_list = int(rand(112))*2;
                                	my @letter_list = (("a".."z"),("A".."Z"),("@"),(")"),("]"),("_"),("-"),("!"),("#"),("("),("["),("{"),("}"),("~"),("`"),("*"),(">"),("<"));
                                	srand;

                                	for (3 .. 6)
                                	{
                                        	my $random = int(rand scalar(@letter_list));
                                        	$security_key .= $letter_list[$random];
                                        	$security_key .= ((int(rand(6))+1) + ($number_list + (int(rand(7))+1) + (int(rand(5))+1)));
                                        	splice(@letter_list,$random,1);
                                	}

                                	$security_key .= $number_list;
                        	}


                        	database->quick_insert('signup_activation_tango', { user_id => $user_id->{id}, user_key => $security_key });

                        	$csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
                        	$csh->add($security_key);
                        	my $salted = $csh->generate;
                        	my ($year,$month,$day) = Today();
                        	my $url = 'signup/confirm/' . urlsafe_b64encode($user_id->{id}) . '/r/' . urlsafe_b64encode($salted) . '/d/' . urlsafe_b64encode("$year-$month-$day");


        			if ($account_signup->{value} eq 'enabled')
        			{
                                	my $html = template 'email-signup', { login => $login, name => $name, email => $email, url => $url }, { layout => undef };
                                        my $txt = template 'email-signup-txt', { login => $login, name => $name, email => $email, url => $url }, { layout => undef };

                                        email {
                                        	to => $email,
                                                type => 'multi',
                                                message => {
                                                	text => $txt,
                                                        html => $html,
                                                }
                                        };


					flash message => "Account created, you will be emailed conformation to activate your account";
      				}
				elsif ($account_signup->{value} eq 'admin')
				{
                			$sth = database->prepare("select * from users_tango where type = ?");
                			$sth->execute('admin');


                			while (my $row = $sth->fetchrow_hashref)
                			{
						my $html = template 'email-admin-signup', { admin => $row->{name}, login => $login, name => $name, email => $email, url => $url }, { layout => undef };
						my $txt = template 'email-admin-signup-txt', { admin => $row->{name}, login => $login, name => $name, email => $email, url => $url }, { layout => undef };

                                		email {
                                        		to => $row->{email},
                                        		type => 'multi',
                                        		message => {
                                                		text => $txt,
                                                		html => $html,
                                        		}
                                		};
                			}


					flash message => "Account created, pending administrative approval. You will be emailed once your account is active";
				}
				else
				{
					flash error => "Account signup is disabled";
				}


				return redirect '/login';
			}
		}
		elsif (!validate_captcha $captcha)
		{
			clear_captcha;

			flash error => "Signup failed, image captcha did not match";
                }
		else
		{
			flash error => "Signup failed, please ensure all fields have been filled out correctly";
		}
	}


	template 'signup', { login => $login, name => $name, email => $email };
};


get '/signup/confirm/:id/r/:rand/d/:date' => sub
{
       	my $url_id = params->{'id'};
        my $url_rand = params->{'rand'};
        my $url_date = params->{'date'};

        my $user_id = urlsafe_b64decode($url_id) || 0;
        my $salted = urlsafe_b64decode($url_rand);
        my $date = urlsafe_b64decode($url_date);

        my ($request_year,$request_month,$request_day) = (split /-/, $date);
        my ($current_year,$current_month,$current_day) = Today();
        my $days = Delta_Days($request_year,$request_month,$request_day,$current_year,$current_month,$current_day);
        my $match = 'fail';

        my $sth = database->prepare("select count(id) as count from users_tango where id = ?");
        $sth->execute($user_id);
        my $data = $sth->fetchrow_hashref;


        if (!defined $data->{count} || $data->{count} != 1)
        {
                database->quick_delete('signup_activation_tango', { user_id => $user_id });
                flash error => 'User no longer exists';


                return redirect '/login';
        }


        $sth = database->prepare("select user_id, user_key from signup_activation_tango where user_id = ?");
        $sth->execute($user_id);
        $data = $sth->fetchrow_hashref;


        if (!defined $data->{user_key} || $data->{user_key} !~ /(\w)+/)
        {
                database->quick_delete('signup_activation_tango', { user_id => $user_id });
                flash error => 'Activation link has expired, please contact your administrator for assistance';


                return redirect '/login';
        }


        my $valid = Crypt::SaltedHash->validate($salted, $data->{user_key});


        if (defined $valid && $valid == 1)
        {
                $match = 'ok';
        }


        if ($user_id != 0 && $match eq 'ok' && request->method() eq "GET" && $days < 2)
        {
		database->quick_update('users_tango', { id => $user_id}, { status => 'enabled' });
		database->quick_delete('signup_activation_tango', { user_id => $user_id });
		my $account = database->quick_select('users_tango', { id => $user_id });

                my $html = template 'email-confirm-signup', { name => $account->{name} }, { layout => undef };
                my $txt = template 'email-confirm-signup-txt', { name => $account->{name} }, { layout => undef };


                email {
                	to => $account->{email},
                        type => 'multi',
                        message => {
                        	text => $txt,
                                html => $html,
                        }
                };


		flash message => 'Account activated';


		return redirect '/login';
        }
        elsif ($user_id != 0 && $match eq 'ok' && $days >= 2)
        {
                database->quick_delete('signup_activation_tango', { user_id => $user_id });
                flash error => 'Activation link has expired, please contact your administrator for assistance';


                return redirect '/login';
        }
        else
        {
		database->quick_delete('signup_activation_tango', { user_id => $user_id });
                flash error => 'Activation link has expired, please contact your administrator for assistance';


                return redirect '/login';
        }

};
