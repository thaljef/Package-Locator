#!perl

use strict;
use warnings;

use Test::More (tests => 4);
use Test::Exception;

use Package::Locator;

#------------------------------------------------------------------------------

my $class = 'Package::Locator';

#------------------------------------------------------------------------------

throws_ok { $class->new()->locate() }
    qr/Must specify package, package => version, or dist/;


throws_ok { $class->new()->locate('Foo', 'Bar', 2.3) }
    qr/Must specify package, package => version, or dist/;


throws_ok { $class->new()->locate('Foo', '2.3-RC') }
    qr/Invalid version/;


throws_ok { $class->new( repository_urls => [ URI->new('http://bogus') ] )->locate('Foo') }
    qr/Can't connect to bogus/;
