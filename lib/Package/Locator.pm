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

=attr repository_urls => [ qw(http://somewhere http://somewhere.else) ]

An array reference containing the base URLs of the repositories you
want to search.  These are usually CPAN mirrors, but can be any
website or local directory that is organized in a CPAN-like structure.
For each request, repositories are searched in the order you specified
them here.  This defaults to http://cpan.perl.org.

=cut

has repository_urls => (
    is         => 'ro',
    isa        => 'ArrayRef[URI]',
    auto_deref => 1,
    default    => sub { [URI->new('http://cpan.perl.org')] },
);

#------------------------------------------------------------------------------

=attr user_agent => $user_agent_obj

The L<LWP::UserAgent> object that will fetch index files.  If you do
not provide a user agent, then a default one will be constructed for
you.

=cut

has user_agent => (
   is          => 'ro',
   isa         => 'LWP::UserAgent',
   default     => sub { LWP::UserAgent->new() },
);

#------------------------------------------------------------------------------

=attr cache_dir => '/some/directory/path'

The path (as a string or L<Path::Class::Dir> object) to a directory
where the index file will be cached.  If the directory does not exist,
it will be created for you.  If you do not specify a cache directory,
then a temporary directory will be used.  The temporary directory will
be deleted when your application terminates.

=cut

has cache_dir => (
   is         => 'ro',
   isa        => 'Path::Class::Dir',
   default    => sub { Path::Class::Dir->new( File::Temp::tempdir(CLEANUP => 1) ) },
   coerce     => 1,
);

#------------------------------------------------------------------------------

=attr force => $boolean

Causes any cached index files to be removed, thus forcing a new one to
be downloaded when the object is constructed.  This only has effect if
you specified the C<cache_dir> attribute.  The default is false.

=cut

has force => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);

#------------------------------------------------------------------------------

=attr get_latest => $boolean

Always return the distribution from the repository that has the latest
version of the requested package, instead of just from the first
repository where that package was found.  If you requested a
particular version of package, then the returned distribution will
always contain that package version or greater, regardless of the
C<get_latest> setting.  Default is false.

=cut

has get_latest => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);


#------------------------------------------------------------------------------

=attr indexes()

Returns a list of L<Package::Locator::Index> objects representing the
indexes of each of the repositories.  The indexes are only populated
on-demand when the C<locate> method is called.  The order of the
indexes is the same as the order of the repositories defined by the
C<repository_urls> attribute.

=cut

has indexes => (
   is         => 'ro',
   isa        => 'ArrayRef[Package::Locator::Index]',
   auto_deref => 1,
   lazy_build => 1,
   init_arg   => undef,
);


#------------------------------------------------------------------------------

sub _build_indexes {
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
returns the URL to a distribution containing that package.  If you
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

    if (@args == 2) {
        ($package, $version) = @args;
    }
    elsif ($args[0] =~ m{/}x) {
        $dist = $args[0];
    }
    else {
        ($package, $version) = ($args[0], 0);
    }

    return $self->_locate_package($package, $version) if $package;
    return $self->_locate_dist($dist) if $dist;
    return; #Should never get here!
}

#------------------------------------------------------------------------------

sub _locate_package {
    my ($self, $package, $version) = @_;

    my $wanted_version = version->parse($version);

    my ($latest_found_package, $found_in_index);
    for my $index ( $self->indexes() ) {

        my $found_package = $index->lookup_package($package);
        next if not $found_package;

        my $found_package_version = version->parse( $found_package->version() );
        next if $found_package_version < $wanted_version;

        $found_in_index       ||= $index;
        $latest_found_package ||= $found_package;
        last unless $self->get_latest();

        ($found_in_index, $latest_found_package) = ($index, $found_package)
            if $self->__compare_packages($found_package, $latest_found_package) == 1;
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

    for my $index ( $self->indexes() ) {
        if ( my $found = $index->lookup_dist($dist_path) ) {
            my $base_url = $index->repository_url();
            return URI->new( "$base_url/authors/id/" . $found->prefix() );
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

=head1 SYNOPSIS

  use Package::Locator;

  # Basic search...
  my $locator = Package::Locator->new();
  my $url = locator->locate( 'Test::More' );

  # Search for first within multiple repositories:
  my $repos = [ qw(http://cpan.pair.com http://my.company.com/DPAN) ];
  my $locator = Package::Locator->new( repository_urls => $repos );
  my $url = locator->locate( 'Test::More' );

  # Search for first where version >= 0.34:
  my $repos = [ qw(http://cpan.pair.com http://my.company.com/DPAN) ];
  my $locator = Package::Locator->new( repository_urls => $repos );
  my $url = locator->locate( 'Test::More' => 0.34);

  # Search for latest where version  >= 0.34:
  my $repos = [ qw(http://cpan.pair.com http://my.company.com/DPAN) ];
  my $locator = Package::Locator->new( repository_urls => $repos, get_latest => 1 );
  my $url = locator->locate( 'Test::More' => 0.34);

=head1 DESCRIPTION

L<Package::Locator> attempts to answer the question: "Where can I find
a distribution that will provide this package?"  The answer is divined
by searching the indexes for one or more CPAN-like repositories.  If
you also provide a specific version number, L<Package::Locator> will
attempt to find a distribution with that version of the package, or
higher.

L<Package::Locator> only looks at the index files for each repository,
and those indexes only contain information about the latest versions
of the packages within that repository.  So L<Package::Locator> is not
BackPAN magic -- you cannot use it to find precisely which
distribution a particular package (or file) came from.  For that
stuff, see C<"/See Also">.

=head1 CONSTRUCTOR

=head2 new( %attributes )

All the attributes listed below can be passed to the constructor, and
retrieved via accessor methods with the same name.  All attributes are
read-only, and cannot be changed once the object is constructed.

=head1 MOTIVATION

The L<CPAN> module also provides a mechanism for locating packages or
distributions, much like L<Package::Locator> does.  However, L<CPAN>
assumes that all repositories are CPAN mirrors, so it only searches
the first repository that it can contact.

My secret ambition is to fill the world with lots of DarkPAN
repositories -- each with its own set of distributions.  For that
scenario, I need to search multiple repositories at the same time.

=head1  SEE ALSO

If you need to locate a distribution that contains a precise version
of a file rather than just a version that is "new enough", then look
at some of these:

L<Dist::Surveyor>
L<BackPAN::Index>
L<BackPAN::Version::Discover>

