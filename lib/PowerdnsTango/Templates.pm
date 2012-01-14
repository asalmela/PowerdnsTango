package PowerdnsTango::Templates;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Data::Page;
use PowerdnsTango::Acl qw(user_acl);

our $VERSION = '0.2';


any ['get', 'post'] => '/templates' => sub
{
        my $load_page = params->{p} || 1;
        my $results_per_page = params->{r} || 25;
        my $search = params->{template_search} || 0;
        my $sth;
        my $page;
        my $display;
        my $count;
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';


        if (request->method() eq "POST" && $search ne '0')
        {
		if ($user_type ne 'admin')
		{
                	$sth = database->prepare('select count(templates_tango.id) as count from templates_tango, templates_acl_tango where (templates_tango.id = templates_acl_tango.template_id) and templates_acl_tango.user_id = ?
			and name like ?');
                	$sth->execute($user_id, "%$search%");
		}
		else
		{
                        $sth = database->prepare('select count(id) as count from templates_tango where name like ?');
                        $sth->execute("%$search%");
		}


                $count = $sth->fetchrow_hashref;

                $page = Data::Page->new();
                $page->total_entries($count->{'count'});
                $page->entries_per_page($results_per_page);
                $page->current_page($load_page);

                $display = ($page->entries_per_page * ($page->current_page - 1));
                $load_page = $page->last_page if ($load_page > $page->last_page);
                $load_page = $page->first_page if ($load_page == 0);


		if ($user_type ne 'admin')
		{
                	$sth = database->prepare('select templates_tango.* from templates_tango, templates_acl_tango where (templates_tango.id = templates_acl_tango.template_id) 
			and templates_acl_tango.user_id = ? and name like ? limit ? offset ?');
                	$sth->execute($user_id, "%$search%", $page->entries_per_page, $display);
		}
		else
		{
                        $sth = database->prepare('select * from templates_tango where name like ? limit ? offset ?');
                        $sth->execute("%$search%", $page->entries_per_page, $display);
		}


                flash error => "Template search found no match" if ($count->{'count'} == 0);
                flash message => "Template search found $count->{'count'} matches" if ($count->{'count'} >= 1);
	}
	else
	{
		if ($user_type ne 'admin')
		{
        		$sth = database->prepare('select count(templates_tango.id) as count from templates_tango, templates_acl_tango where (templates_tango.id = templates_acl_tango.template_id) and templates_acl_tango.user_id = ?');
        		$sth->execute($user_id);
		}
		else
		{
                        $sth = database->prepare('select count(id) as count from templates_tango');
                        $sth->execute();
		}


        	$count = $sth->fetchrow_hashref;

        	$page = Data::Page->new();
        	$page->total_entries($count->{'count'});
        	$page->entries_per_page($results_per_page);
        	$page->current_page($load_page);

        	$display = ($page->entries_per_page * ($page->current_page - 1));
        	$load_page = $page->last_page if ($load_page > $page->last_page);
        	$load_page = $page->first_page if ($load_page == 0);


		if ($user_type ne 'admin')
		{
        		$sth = database->prepare('select templates_tango.* as count from templates_tango, templates_acl_tango where (templates_tango.id = templates_acl_tango.template_id) and templates_acl_tango.user_id = ? limit ? offset ?');
        		$sth->execute($user_id, $page->entries_per_page, $display);
		}
		else
		{
                        $sth = database->prepare('select * from templates_tango limit ? offset ?');
                        $sth->execute($page->entries_per_page, $display);
		}
	}


        template 'templates', { templates => $sth->fetchall_hashref('name'), page => $load_page, results => $results_per_page, previouspage => ($load_page - 1), nextpage => ($load_page + 1), lastpage => $page->last_page };
};


post '/templates/add' => sub
{
        my $name = params->{add_template_name} || 0;
        my $sth = database->prepare("select count(name) as count from templates_tango where name = ?");
        $sth->execute($name);
        my $count = $sth->fetchrow_hashref;
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';


        if ($user_type ne 'admin')
        {
                my $user_template_limit = database->quick_select('users_tango', { id => $user_id });
                $sth = database->prepare("select count(id) as count from templates_acl_tango where user_id = ?");
                $sth->execute($user_id);
                my $owned_templates = $sth->fetchrow_hashref;


                if ($owned_templates->{count} >= $user_template_limit->{template_limit})
                {
                        flash error => "You have reached your template limit";

                        return redirect '/templates';
                }
        }


        if ($count->{count} != 0)
        {

                flash error => "A template with the name $name already exists";
        }
        elsif ($name ne 0)
        {
                database->quick_insert('templates_tango', { name => $name });
                my $get_id = database->quick_select('templates_tango', { name => $name });
                database->quick_insert('templates_acl_tango', { user_id => $user_id, template_id => $get_id->{id} });
                my $template_id = database->quick_select('templates_tango', { name => $name });
                my $default_soa = database->quick_select('admin_default_soa_tango', {});

		if (defined $default_soa->{name_server} && defined $default_soa->{contact} && defined $default_soa->{refresh} && defined $default_soa->{retry} && defined $default_soa->{expire} && defined $default_soa->{minimum}
		&& defined $default_soa->{ttl})
		{
                	my $content = ($default_soa->{name_server} . " " . $default_soa->{contact} . " " . $default_soa->{refresh} . " " . $default_soa->{retry} . " " . $default_soa->{expire} . " " . $default_soa->{minimum});
                	database->quick_insert('templates_records_tango', { template_id => $template_id->{id}, name => '%zone%', type => 'SOA', content => $content, ttl => $default_soa->{ttl} });
		}


                flash message => "Template $name added";
        }
	else
	{
		flash error => "Adding template failed";
	}


        return redirect '/templates';
};


get '/templates/delete/id/:id' => sub
{
        my $id = params->{id} || 0;
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';
        my $perm = user_acl($id, 'template');


        if ($perm == 1)
        {
                flash error => "Permission denied";

                return redirect '/templates';
        }


        if ($id != 0)
        {
                database->quick_delete('templates_tango', { id => $id });
		database->quick_delete('templates_acl_tango', { template_id => $id });

                flash message => "Template deleted";
        }
        else
        {
                flash error => "Template delete failed";
        }


        return redirect '/templates';
};


ajax '/templates/get' => sub
{
        my $id = params->{id} || 0;
	my $perm = user_acl($id, 'template');
        my $sth = database->prepare('select name from templates_tango where id = ?');
        $sth->execute($id);
        my $domain = $sth->fetchrow_hashref;


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


        return { stat => 'ok', id => $id, name => $domain->{name} };
};


ajax '/templates/update' => sub
{
        my $id = params->{id} || 0;
        my $name = params->{name} || 0;
        my $perm = user_acl($id, 'template');


        if ($perm == 1)
        {
                return { stat => 'fail', message => 'Permission denied' };
        }


        my $sth = database->prepare("select count(name) as count from templates_tango where name = ?");
        $sth->execute($name);
        my $count = $sth->fetchrow_hashref;

        $sth = database->prepare("select name from templates_tango where id = ?");
        $sth->execute($id);
        my $old_name = $sth->fetchrow_hashref;


        if (($count->{count} != 0) && ($old_name->{name} ne $name))
        {
                return { stat => 'fail', message => "A template with the name $name already exists", id => $id, name => $name };
        }
        elsif ($id != 0 && $name ne 0)
        {
                database->quick_update('templates_tango', { id => $id }, { name => $name });
        }
        else
        {
                return { stat => 'fail', message => 'Template update failed', id => $id, name => $name };
        }


        return { stat => 'ok', message => 'Template updated', id => $id, name => $name };
};


true;
