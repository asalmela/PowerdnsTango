#!/usr/bin/env perl

=pod
This script is used to generate encrypted passwords for someone wishing to install Powerdns Tango.
Once installed the web app does not rely on this script at all. Therefore this script can be removed should you wish to do so.
=cut

use warnings;
use strict;
use Crypt::SaltedHash;

print "\nPassword generator\n\n";

print "Choose a initial password: ";
chomp(my $password = <STDIN>);

my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-1');
$csh->add($password);
my $new_password = $csh->generate;

print "Your new encrypted password: $new_password\n";
