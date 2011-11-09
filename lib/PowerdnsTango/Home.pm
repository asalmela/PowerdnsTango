package PowerdnsTango::Home;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Plugin::FlashMessage;
use Dancer::Session::Storable;
use Dancer::Template::TemplateToolkit;
use Dancer::Plugin::Ajax;
use Data::Page;
use Data::Validate::Domain qw(is_domain);

our $VERSION = '0.1';


get '/' => sub
{
        my $user_type = session 'user_type';
        my $user_id = session 'user_id';
	my $user_limit = database->quick_select('users_tango', { id => $user_id });
	my $motd = database->quick_select('admin_settings_tango', { setting => 'announcement' });
	$motd->{value} = 'No announcements at this time.' if ((!defined $motd->{value}) || ($motd->{value} !~ m/(\w)+/));

        my $sth = database->prepare("select count(id) as count from domains");
        $sth->execute();
        my $system_domains = $sth->fetchrow_hashref;

        $sth = database->prepare("select count(id) as count from domains_acl_tango where user_id = ?");
        $sth->execute($user_id);
        my $user_domains = $sth->fetchrow_hashref;

        $sth = database->prepare("select count(id) as count from templates_acl_tango where user_id = ?");
        $sth->execute($user_id);
        my $user_templates = $sth->fetchrow_hashref;


	if ($user_type eq 'admin')
	{
		$sth = database->prepare('select * from domains order by id desc limit ?');
		$sth->execute('5');
	}
	else
	{
		$sth = database->prepare('select domains.* from domains, domains_acl_tango where (domains.id = domains_acl_tango.domain_id) and domains_acl_tango.user_id = ? order by id desc limit ?');
		$sth->execute($user_id, '5');
	}


	my $latest_domains = $sth->fetchall_hashref('id');


        if ($user_type eq 'admin')
        {
                $sth = database->prepare('select * from templates_tango order by id desc limit ?');
                $sth->execute('5');
        }
        else
        {
                $sth = database->prepare('select templates_tango.* from templates_tango, templates_acl_tango where (templates_tango.id = templates_acl_tango.template_id) and templates_acl_tango.user_id = ? limit ?');
                $sth->execute($user_id, '5');
        }


	my $latest_templates = $sth->fetchall_hashref('id');

	$user_limit->{domain_limit} = 'unlimited' if ($user_type eq 'admin');
	$user_limit->{template_limit} = 'unlimited' if ($user_type eq 'admin');
	$system_domains->{count} = 0 if ($user_type ne 'admin');


        template 'index', { user_domains => $user_domains->{count}, user_templates => $user_templates->{count}, user_domain_limit => $user_limit->{domain_limit}, user_template_limit => $user_limit->{template_limit},
	system_domains => $system_domains->{count}, latest_domains => $latest_domains, latest_templates => $latest_templates, motd => $motd->{value} };
};
