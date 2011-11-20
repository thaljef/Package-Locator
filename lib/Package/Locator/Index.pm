package Package::Locator::Index;

# ABSTRACT: The package index of a repository

use Moose;
use Carp;
use Path::Class;
use Parse::CPAN::Packages::Fast;
use LWP::UserAgent;
use URI::Escape;

use namespace::autoclean;

#------------------------------------------------------------------------

# VERSION

#------------------------------------------------------------------------

has repository_url => (
    is        => 'ro',
    isa       => 'URI',
    required  => 1,
);


has user_agent => (
   is          => 'ro',
   isa         => 'LWP::UserAgent',
   required    => 1,
);


has cache_dir => (
   is         => 'ro',
   isa        => 'Path::Class::Dir',
   required   => 1,
);


has force => (
   is         => 'ro',
   isa        => 'Bool',
   required   => 1,
);


has _index_file => (
    is         => 'ro',
    isa        => 'Path::Class::File',
    init_arg   => undef,
    lazy_build => 1,
);


has _index => (
    is         => 'ro',
    isa        => 'Parse::CPAN::Packages::Fast',
    init_arg   => undef,
    lazy_build => 1,
);

#------------------------------------------------------------------------------

sub _build__index_file {
    my ($self) = @_;

    my $url = $self->repository_url();

    my $cache_dir = $self->cache_dir->subdir( URI::Escape::uri_escape($url) );
    $self->__mkpath($cache_dir);

    my $destination = $cache_dir->file('02packages.details.txt.gz');
    $destination->remove() if -e $destination and $self->force();

    my $source = URI->new( $url . '/modules/02packages.details.txt.gz' );
    $self->_debug("Fetching $source");

    my $response = $self->user_agent->mirror($source, $destination);
    $self->__handle_ua_response($response, $source, $destination);

    return $destination;
}

#------------------------------------------------------------------------------

sub _build__index {
    my ($self) = @_;

    my $index_file = $self->_index_file();

    $self->_debug("Parsing $index_file");
    return Parse::CPAN::Packages::Fast->new($index_file->stringify());
}

#------------------------------------------------------------------------------

sub __handle_ua_response {
    my ($self, $response, $source, $destination) = @_;

    return 1 if $response->is_success();   # Ok
    return 1 if $response->code() == 304;  # Not modified
    croak sprintf 'Request to %s failed: %s', $source, $response->status_line();
}

sub __mkpath {
    my ($self, $dir) = @_;

    return if -e $dir;
    $dir = dir($dir) unless eval { $dir->isa('Path::Class::Dir') };
    return $dir->mkpath() or croak "Failed to make directory $dir: $!";
}

#------------------------------------------------------------------------

sub lookup_package {
    my ($self, $package_name) = @_;

    return $self->_index->package($package_name);
}

#------------------------------------------------------------------------

sub lookup_dist {
    my ($self, $dist_path) = @_;

    my @dists = $self->_index->distributions();

    my @found = grep { $_->prefix() eq $dist_path } @dists;

    croak "Found multiple versions of $dist_path" if @found > 1;

    return pop @found;
}

#------------------------------------------------------------------------

sub _debug {
    my ($self, $message) = @_;
    print "$message\n";
    return 1;
}

#------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable();

#------------------------------------------------------------------------
1;

__END__

