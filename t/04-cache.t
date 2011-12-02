#!perl

use strict;
use warnings;

use Path::Class;
use FindBin qw($Bin);
use URI::Escape qw(uri_escape);
use File::Temp qw(tempdir);
use PerlIO::gzip;

use Test::More (tests => 6);

use Package::Locator;

#------------------------------------------------------------------------------

my $found;
my $temp_dir  = tempdir(CLEANUP => 1);
my $repos_dir = dir($Bin)->as_foreign('Unix')->stringify() . '/repos';
my @repos_urls = map { URI->new("file://$repos_dir/$_") } qw(a b);

#------------------------------------------------------------------------------

my $locator = Package::Locator->new( repository_urls => \@repos_urls,
                                           cache_dir => $temp_dir );

$found = $locator->locate(package => 'Foo', version => 1.0);
is($found, "file://$repos_dir/a/authors/id/A/AU/AUTHOR/Foo-1.0.tar.gz", 'Located Foo-1.0');

$found = $locator->locate(package => 'Foo', version => 2.0);
is($found, "file://$repos_dir/b/authors/id/A/AU/AUTHOR/Foo-2.0.tar.gz", 'Located Foo-2.0');

for my $url (@repos_urls) {
    my $cache_file = file( $temp_dir, uri_escape($url), '02packages.details.txt.gz' );
    ok( -e $cache_file, "Cache file $cache_file exists" );

    # Erase contents of cache file.  But we still need the standard gzip header
    # or else there will be an exception when we try to open the file later.
    open my $fh, '>:gzip', $cache_file;
    print $fh '';
    close $fh;
}


$locator = Package::Locator->new( repository_urls => \@repos_urls,
                                        cache_dir => $temp_dir );

$found = $locator->locate(package => 'Foo', version => 1.0);
is($found, undef, 'Did not find Foo-1.0 in empty cache');

$found = $locator->locate(package => 'Foo', version => 2.0);
is($found, undef, 'Did not find Foo-2.0 in empty cache');





