package Package::Locator;

# ABSTRACT: Find the distribution that provides a given package

use Moose;
use MooseX::Types::Path::Class;

use Carp;
use File::Temp;
use Path::Class;
use LWP::UserAgent;
use URI;

use Package::Locator::Index;

use version;
use namespace::autoclean;

#------------------------------------------------------------------------------

# VERSION

#------------------------------------------------------------------------------

has repository_urls => (
    is         => 'ro',
    isa        => 'ArrayRef[URI]',
    auto_deref => 1,
    default    => sub { [URI->new('http://cpan.perl.org')] },
);


has user_agent => (
   is          => 'ro',
   isa         => 'LWP::UserAgent',
   default     => sub { LWP::UserAgent->new() },
);


has cache_dir => (
   is         => 'ro',
   isa        => 'Path::Class::Dir',
   default    => sub { Path::Class::Dir->new( File::Temp::tempdir(CLEANUP => 1) ) },
   coerce     => 1,
);


has force => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);


has get_any => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);


has _indexes => (
   is         => 'ro',
   isa        => 'ArrayRef[Package::Locator::Index]',
   auto_deref => 1,
   lazy_build => 1,
);


#------------------------------------------------------------------------------

sub _build__indexes {
    my ($self) = @_;

    my @indexes = map { Package::Locator::Index->new( force          => $self->force(),
                                                      cache_dir      => $self->cache_dir(),
                                                      user_agent     => $self->user_agent(),
                                                      repository_url => $_ )
    } $self->repository_urls();

    return \@indexes;
}

#------------------------------------------------------------------------------

=method locate( 'Foo::Bar' )

=method locate( 'Foo::Bar' => '1.2' )

=method locate( '/F/FO/FOO/Bar-1.2.tar.gz' )

Given the name of a package, searches all the repository indexes and
returns the URL to a distribution that contains that package.  If you
specify a version, then you'll always get a distribution that contains
that version of the package or higher.  If the C<get_latest> attribute
is true, then you'll always get the distribution that contains latest
version of the package that can be found on all the indexes.
Otherwise you'll just get the first distribution we can find that
satisfies your request.

If you give a distribution path instead (i.e. anything that has
slashes '/' in it) then you'll just get back the URL to the first
distribution we find at that path in any of the repository indexes.

If neither the package nor the distribution path can be found in any
of the indexes, returns undef.

=cut

sub locate {
    my ($self, @args) = @_;

    croak 'Must specify package, package => version, or dist'
        if @args < 1 or @args > 2;

    my ($package, $version, $dist);

    ($package, $version) = @args         if @args == 2;
    ($package, $version) = ($args[0], 0) if $args[0] !~ m{/}x;
    $dist = $args[0];

    return $self->_locate_package($package, $version) if $package;
    return $self->_locate_dist($dist) if $dist;
    return; #Should never get here!
}

#------------------------------------------------------------------------------

sub _locate_package {
    my ($self, $package, $version) = @_;

    my $wanted_version = version->parse($version);

    my ($latest_found_package, $found_in_index);
    for my $index ( $self->_indexes() ) {

        my $found_package = $index->lookup_package($package);
        next if not $found_package;

        my $found_package_version = version->parse( $found_package->version() );
        next if $found_package_version < $wanted_version;

        $found_in_index       ||= $index;
        $latest_found_package ||= $found_package;
        last if $self->get_any();

        ($found_in_index, $latest_found_package) = ($index, $found_package)
            if $self->__compare_packages($latest_found_package, $found_package) == 1;
    }


    if ($latest_found_package) {
        my $base_url = $found_in_index->repository_url();
        my $latest_dist = $latest_found_package->distribution();
        my $latest_dist_prefix = $latest_dist->prefix();
        return  URI->new( "$base_url/authors/id/" . $latest_dist_prefix );
    }

    return;
}

#------------------------------------------------------------------------------

sub _locate_dist {
    my ($self, $dist_path) = @_;

    for my $index ( $self->_indexes() ) {
        if ( my $found = $index->lookup_dist($dist_path) ) {
            my $base_url = $index->repository_url();
            return URI->new( "$base_url/authors/id" . $found->prefix() );
        }
    }

    return;
}

#------------------------------------------------------------------------------

sub __compare_packages {
    my ($self, $pkg_a, $pkg_b) = @_;

    my $pkg_a_version = version->parse( $pkg_a->version() );
    my $pkg_b_version = version->parse( $pkg_b->version() );

    my $dist_a_name  = $pkg_a->distribution->dist();
    my $dist_b_name  = $pkg_b->distribution->dist();
    my $have_same_dist_name = $dist_a_name eq $dist_b_name;

    my $dist_a_version = $pkg_a->distribution->version();
    my $dist_b_version = $pkg_b->distribution->version();

    return    ($pkg_a_version  <=> $pkg_b_version)
           || ($have_same_dist_name && ($dist_a_version <=> $dist_b_version) );
}

#------------------------------------------------------------------------------

sub __mkpath {
    my ($self, $dir) = @_;

    return if -e $dir;
    $dir = dir($dir) unless eval { $dir->isa('Path::Class::Dir') };
    return $dir->mkpath() or croak "Failed to make directory $dir: $!";
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable();

#------------------------------------------------------------------------------

1;

__END__
