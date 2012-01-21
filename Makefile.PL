use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'PowerdnsTango',
    AUTHOR              => q{Sarah Full <sarah@averna.id.au>},
    VERSION_FROM        => 'lib/PowerdnsTango.pm',
    ABSTRACT            => 'Powerdns Tango is a web frontend for powerdns',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'GPLv3')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
        'JSON'       => 0,
        'Dancer'     => 1.3072,
	'Dancer::Plugin::Database'	=> 0,
	'Dancer::Plugin::FlashMessage'	=> 0,
	'Dancer::Plugin::Ajax'	=> 0,
	'Dancer::Plugin::Email' => 0,
	'Dancer::Session::Storable' => 0,
        'Dancer::Template::TemplateToolkit' => 0,
	'Crypt::SaltedHash'	=> 0,
	'Data::Page' => 0,
	'Date::Calc' => 0,
	'Data::Validate::Domain' => 0,
	'Data::Validate::IP' => 0,
	'Email::Valid'	=> 0,
	'MIME::Base64::URLSafe'	=> 0,
	'Dancer::Plugin::Captcha::SecurityImage' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'PowerdnsTango-*' },
);
