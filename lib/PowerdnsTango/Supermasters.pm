package PowerdnsTango::Supermasters;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Data::Page;
use Data::Validate::Domain qw(is_domain);
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use PowerdnsTango::Acl qw(user_acl);

our $VERSION = '0.2';


any ['get', 'post'] => '/supermasters' => sub
{
	my $perm = user_acl;
	my $load_page = params->{p} || 1;
	my $results_per_page = params->{r} || 25;
	my $search = params->{supermaster_search} || 0;
	my $sth;
	my $page;
	my $display;
	my $count;


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


	if (request->method() eq "POST" && $search ne '0')
	{
                $sth = database->prepare('select count(ip) as count from supermasters where nameserver like ? or ip like ?');
                $sth->execute("%$search%", "%$search%");

        	$count = $sth->fetchrow_hashref;
        	$page = Data::Page->new();
        	$page->total_entries($count->{'count'});
        	$page->entries_per_page($results_per_page);
        	$page->current_page($load_page);

        	$display = ($page->entries_per_page * ($page->current_page - 1));
        	$load_page = $page->last_page if ($load_page > $page->last_page);
        	$load_page = $page->first_page if ($load_page == 0);


                $sth = database->prepare('select * from supermasters where nameserver like ? or ip like ? limit ? offset ?');
                $sth->execute("%$search%", "%$search%", $page->entries_per_page, $display);


		flash error => "Supermaster search found no match" if ($count->{'count'} == 0);
		flash message => "Supermaster search found $count->{'count'} matches" if ($count->{'count'} >= 1);
	}
	else
	{
                $sth = database->prepare('select count(ip) as count from supermasters');
                $sth->execute();
	
        	$count = $sth->fetchrow_hashref;

        	$page = Data::Page->new();
        	$page->total_entries($count->{'count'});
        	$page->entries_per_page($results_per_page);
        	$page->current_page($load_page);

        	$display = ($page->entries_per_page * ($page->current_page - 1));
        	$load_page = $page->last_page if ($load_page > $page->last_page);
        	$load_page = $page->first_page if ($load_page == 0);


                $sth = database->prepare('select * from supermasters limit ? offset ?');
                $sth->execute($page->entries_per_page, $display);
	}


        template 'supermasters', { supermasters => $sth->fetchall_hashref('ip'), page => $load_page, results => $results_per_page, previouspage => ($load_page - 1), 
	nextpage => ($load_page + 1), lastpage => $page->last_page };
};


get '/supermasters/delete/ip/:ip' => sub
{
	my $perm = user_acl;
        my $ip = params->{ip} || 0;


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/domains';
        }


        if ($ip ne 0)
        {
                database->quick_delete('supermasters', { ip => $ip });

                flash message => "Supermaster deleted";
        }
        else
        {
                flash error => "Supermaster deleted failed";
        }


	return redirect '/supermasters';
};


post '/supermasters/add' => sub
{
	my $perm = user_acl;
        my $ip = params->{add_ipaddr} || 0;
        my $nameserver = params->{add_nameserver} || 0;


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/';
        }


        if ((! is_ipv4($ip)) && (! is_ipv6($ip)))
        {
		flash error => "Add supermaster failed, $ip is not a valid ip address";

		return redirect '/supermasters';
        }
        elsif (! is_domain($nameserver))
        {
		flash error => "Add supermaster failed, $nameserver is not a valid domain name";

		return redirect '/supermasters';
        }


        my $sth = database->prepare('select count(ip) as count from supermasters where ip = ?');
        $sth->execute($ip);
        my $count = $sth->fetchrow_hashref;


        if ($count->{count} != 0)
        {
		flash error => "Add supermaster failed, a supermaster with ip $ip already exists";

		return redirect '/supermasters';
        }


	database->quick_insert('supermasters', { ip => $ip, nameserver => $nameserver });
	flash message => "Supermaster added";


	return redirect '/supermasters';
};


ajax '/supermasters/get' => sub
{
	my $perm = user_acl;
	my $id = params->{id};
	my $ip = params->{ip};


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	my $supermaster = database->quick_select('supermasters', { ip => $ip });


	return { stat => 'ok', id => $id, nameserver => $supermaster->{nameserver}, ip => $supermaster->{ip} };
};


ajax '/supermasters/update' => sub
{
        my $perm = user_acl;
        my $id = params->{id};
        my $ip = params->{ip};
	my $nameserver = params->{nameserver};
	my $old_ip = params->{old_ip};
	my $old_nameserver = params->{old_nameserver};


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


	if ((! is_ipv4($ip)) && (! is_ipv6($ip)))
	{
		return { stat => 'fail', message => "Supermaster update failed, $ip is not a valid ip address" };
	}
	elsif (! is_domain($nameserver))
	{
		return { stat => 'fail', message => "Supermaster update failed, $nameserver is not a valid domain name" };
	}


        my $sth = database->prepare('select count(ip) as count from supermasters where ip = ?');
	$sth->execute($ip);
        my $count = $sth->fetchrow_hashref;


	if (($count->{count} != 0) && ($old_ip ne $ip))
	{
		return { stat => 'fail', message => "Supermaster update failed, a supermaster with ip $ip already exists" };
	}


	database->quick_update('supermasters', { ip => $old_ip, nameserver => $old_nameserver }, { ip => $ip, nameserver => $nameserver });
 

        return { stat => 'ok', message => 'Supermaster updated', id => $id, nameserver => $nameserver, ip => $ip };
};

