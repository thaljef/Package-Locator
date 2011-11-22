#!perl

use strict;
use warnings;

use Test::More (tests => 2);
use Test::Exception;

use Package::Locator;

#------------------------------------------------------------------------------

my $class = 'Package::Locator';

#------------------------------------------------------------------------------

throws_ok { $class->new()->locate() }
    qr/Must specify package, package => version, or dist/;


throws_ok { $class->new()->locate('Foo', 'Bar', 2.3) }
    qr/Must specify package, package => version, or dist/;
