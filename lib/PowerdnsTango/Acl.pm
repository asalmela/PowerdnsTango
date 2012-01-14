package PowerdnsTango::Acl;
use Dancer ':syntax';
use Dancer::Plugin::Database;
use Dancer::Session::Storable;
use base "Exporter";

our @EXPORT = qw(user_acl);
our $VERSION = '0.1';


sub user_acl
{
	my $obj_id = shift;
	my $obj_type = shift;
	my $user_type = session 'user_type';
	my $user_id = session 'user_id';
	my $acl;
	my $check_acl;


	return 0 if ($user_type eq 'admin');


	if ((defined $obj_id && $obj_id =~ m/^(\d)+$/x) && (defined $obj_type && $obj_type eq 'domain'))
	{
		$acl = database->prepare("select count(id) as count from domains_acl_tango where domain_id = ? and user_id = ?");
		$acl->execute($obj_id, $user_id);
		$check_acl = $acl->fetchrow_hashref;
	}
	elsif ((defined $obj_id && $obj_id =~ m/^(\d)+$/x) && (defined $obj_type && $obj_type eq 'template'))
	{
		$acl = database->prepare("select count(id) as count from templates_acl_tango where template_id = ? and user_id = ?");
		$acl->execute($obj_id, $user_id);
		$check_acl = $acl->fetchrow_hashref;
	}


	if ($check_acl->{count} == 0)
	{
		return 1;
	}
	else
	{
		return 0;
	}
};


