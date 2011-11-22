#!perl

use strict;
use warnings;

use FindBin qw($Bin);
use Path::Class;
use Test::More (tests => 10);

use Package::Locator;

#------------------------------------------------------------------------------

my $found;
my $repos_dir = dir($Bin)->as_foreign('Unix')->stringify() . '/repos';
my @repos_urls = map { URI->new("file://$repos_dir/$_") } qw(a b);

#------------------------------------------------------------------------------

my $first_locator = Package::Locator->new( repository_urls => \@repos_urls );

$found = $first_locator->locate('Foo');
is($found, "file://$repos_dir/a/authors/id/A/AU/AUTHOR/Foo-1.0.tar.gz",
   'Locate by package name');

$found = $first_locator->locate('Bar');
is($found, undef, 'Locate non-existant package name');

$found = $first_locator->locate('A/AU/AUTHOR/Foo-1.0.tar.gz');
is($found, "file://$repos_dir/a/authors/id/A/AU/AUTHOR/Foo-1.0.tar.gz",
    'Locate by dist path');

$found = $first_locator->locate('A/AU/AUTHOR/Bar-1.0.tar.gz');
is($found, undef, 'Locate non-existant dist path');

$found = $first_locator->locate('Foo' => 2.0);
is($found, "file://$repos_dir/b/authors/id/A/AU/AUTHOR/Foo-2.0.tar.gz",
    'Locate by package name and decimal version');

$found = $first_locator->locate('Foo' => 'v1.2.0');
is($found, "file://$repos_dir/b/authors/id/A/AU/AUTHOR/Foo-2.0.tar.gz",
    'Locate by package name and vstring');

$found = $first_locator->locate('Foo' => 3.0);
is($found, undef, 'Locate non-existant version');

#------------------------------------------------------------------------------

my $latest_locator = Package::Locator->new( repository_urls => \@repos_urls,
                                            get_latest      => 1 );

$found = $latest_locator->locate('Foo');
is($found, "file://$repos_dir/b/authors/id/A/AU/AUTHOR/Foo-2.0.tar.gz",
   'Locate latest by package name');

$found = $latest_locator->locate('Foo' => 1.0);
is($found, "file://$repos_dir/b/authors/id/A/AU/AUTHOR/Foo-2.0.tar.gz",
   'Locate latest by package name and decimal version');

$found = $latest_locator->locate('Foo' => 'v1.0.5');
is($found, "file://$repos_dir/b/authors/id/A/AU/AUTHOR/Foo-2.0.tar.gz",
   'Locate latest by package name and vstring');





