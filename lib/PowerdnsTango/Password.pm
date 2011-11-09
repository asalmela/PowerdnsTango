package PowerdnsTango::Password;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Plugin::Email;
use Crypt::SaltedHash;
use MIME::Base64::URLSafe;
use Date::Calc qw(:all);
 
our $VERSION = '0.1';


any ['get', 'post'] => '/password/recover' => sub
{
	my $password_recovery = database->quick_select('admin_settings_tango', { setting => 'password_recovery' });


	if ($password_recovery->{value} eq 'disabled')
        {
        	flash error => 'Password recovery disabled, please contact your Administrator for assistance';


                return redirect '/login';
	}


	if ( request->method() eq "POST" )
	{
	        my $email = params->{email};
		my $login_name = params->{login};
        	my $name = 'user';
                my $sth = database->prepare("select count(email) as count from users_tango where login = ? and email = ?");
                $sth->execute($login_name, $email);
                my $data = $sth->fetchrow_hashref;


		if ($data->{count} != 1)
		{
			flash error => 'Account not found, please contact your Administrator for assistance';


			return redirect '/password/recover';
		}
		else
		{
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


			$sth = database->prepare("select id, login, name, email from users_tango where email = ?");
			$sth->execute($email);
			$data = $sth->fetchrow_hashref;

			database->quick_delete('password_recovery_tango', { user_id => $data->{id} });
			database->quick_insert('password_recovery_tango', { user_id => $data->{id}, user_key => $security_key });
			$name = $data->{name} if (defined $data->{name});
			my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
			$csh->add($security_key);
			my $salted = $csh->generate;
			my ($year,$month,$day) = Today();
			my $url = 'password/reset/' . urlsafe_b64encode($data->{id}) . '/r/' . urlsafe_b64encode($salted) . '/d/' . urlsafe_b64encode("$year-$month-$day");

        		my $html = template 'email-password', { name => $name, login => $data->{login}, url => $url }, { layout => undef };
        		my $txt = template 'email-password-txt', { name => $name, login => $data->{login}, url =>  $url }, { layout => undef };

        		email {
                		to => $email,
                		type => 'multi',
                		message => {
                        		text => $txt,
                        		html => $html,
                		}
        		};


			flash message => 'Password recovery email sent';


			return redirect '/login';
		}
	}


	template 'password-recover';
};


any ['get', 'post'] => '/password/reset/:id/r/:rand/d/:date' => sub
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
		database->quick_delete('password_recovery_tango', { user_id => $user_id });
		flash error => 'User no longer exists';


                return redirect '/login';
	}


        $sth = database->prepare("select user_id, user_key from password_recovery_tango where user_id = ?");
        $sth->execute($user_id);
        $data = $sth->fetchrow_hashref;


	if (!defined $data->{user_key} || $data->{user_key} !~ /(\w)+/)
	{
		database->quick_delete('password_recovery_tango', { user_id => $user_id });
                flash error => 'Password reset link has expired';


                return redirect '/login';
	}


	my $valid = Crypt::SaltedHash->validate($salted, $data->{user_key});


	if (defined $valid && $valid == 1)
	{
		$match = 'ok';
	}


	if ($user_id != 0 && $match eq 'ok' && request->method() eq "GET" && $days < 2)
	{
		template 'password-reset', { id => $url_id, rand => $url_rand, date => $url_date };
	}
	elsif ($user_id != 0 && $match eq 'ok' && request->method() eq "POST" && $days < 2)
	{
		if ((defined params->{'password1'} && defined params->{'password2'}) && (params->{'password1'} eq params->{'password2'}))
		{
			my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
			$csh->add(params->{'password1'});
			my $new_password = $csh->generate;

			database->quick_update('users_tango', { id => $user_id }, { password => $new_password });
			database->quick_delete('password_recovery_tango', { user_id => $user_id });

			flash message => 'Password reset';


			return redirect '/login';
		}
		else
		{
			flash error => 'Password mismatch, please try again';


			template 'password-reset', { id => $url_id, rand => $url_rand, date => $url_date };
		}
	}
	elsif ($user_id != 0 && $match eq 'ok' && $days >= 2)
	{
		database->quick_delete('password_recovery_tango', { user_id => $user_id });
		flash error => 'Password reset link has expired';


		return redirect '/login';	
	}
	else
	{
		database->quick_delete('password_recovery_tango', { user_id => $user_id });
		flash error => 'Password reset link has expired';


		return redirect '/login';
	}
};


true;
