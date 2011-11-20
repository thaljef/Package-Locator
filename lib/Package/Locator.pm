package Package::Locator;

# ABSTRACT: Find the distribution that provides a given package

use Moose;
use Moose::Util::TypeConstraints;

use Carp;
use File::Temp;
use Path::Class;
use Parse::CPAN::Packages;
use LWP::UserAgent;
use URI::Escape;
use URI;

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
);


has force => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);


has fallback => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);


has policy => (
   is         => 'ro',
   isa        => enum( [qw(LATEST ANY)] ),
   default    => 'LATEST',
);


has _index_files => (
   is         => 'ro',
   isa        => 'ArrayRef[Path::Class::File]',
   auto_deref => 1,
   lazy_build => 1,
);


has _indexes => (
   is         => 'ro',
   isa        => 'ArrayRef[ArrayRef]',
   auto_deref => 1,
   lazy_build => 1,
);


#------------------------------------------------------------------------------

sub _build__index_files {
    my ($self) = @_;

    my @index_files;
    for my $url ( $self->repository_urls() ) {

        my $cache_dir = $self->cache_dir->subdir( URI::Escape::uri_escape($url) );
        $self->__mkpath($cache_dir);

        my $destination = $cache_dir->file('02packages.details.txt.gz');
        $destination->remove() if -e $destination and $self->force();

        my $source = URI->new( $url . '/modules/02packages.details.txt.gz' );
        my $response = $self->user_agent->mirror($source, $destination);

        push @index_files, $destination if $self->__handle_ua_response($response);
    }

    croak 'No index files available' if not @index_files;

    return \@index_files;
}

#------------------------------------------------------------------------------

sub _build__indexes {
    my ($self) = @_;

    my @indexes;
    for my $index_file ( $self->_index_files() ) {
         my $index = Parse::CPAN::Packages->new( $index_file->stringify() );
         push @indexes, [$index_file => $index];
    }

    return \@indexes;
}

#------------------------------------------------------------------------------


sub locate {
    my ($self, @args) = @_;

    croak 'Must specify package, package => version, or dist'
        if @args < 1 or @args > 2;

    my ($package, $version, $dist);

    ($package, $version) = @args         if @args == 2;
    ($package, $version) = ($args[0], 0) if $args[0] !~ m{/};
    $dist = $args[0];

    return $self->_locate_package($package, $version) if $package;
    return $self->_locate_dist($dist) if $dist;
}

#------------------------------------------------------------------------------

sub _locate_package {
    my ($self, $package, $version) = @_;

    my $wanted_version = version->parse($version);

    my ($latest_found_package, $base_url);
    for my $index ( $self->_indexes() ) {

        my $found_package = $index->[1]->package($package);
        next if not $found_package;

        my $found_package_version = version->parse( $found_package->version() );
        next if $found_package_version < $wanted_version;

        $base_url             ||= $index->[0];
        $latest_found_package ||= $found_package;
        last if $self->policy() eq 'ANY';

        ($base_url, $latest_found_package) = ($index->[0], $found_package)
            if $self->__compare_packages($latest_found_package, $found_package) == 1;
    }


    if ($latest_found_package) {
        my $latest_dist = $latest_found_package->distribution();
        my $latest_dist_prefix = $latest_dist->prefix();
        return  URI->new( "$base_url/authors/id/" . $latest_dist_prefix );
    }

    return;
}

#------------------------------------------------------------------------------

sub _locate_dist {}

#------------------------------------------------------------------------------

sub __handle_ua_response {
   my ($self, $response) = @_;

   return 1 if $response->is_success();
   return 0 if not $self->fallback() and $self->repository_urls() > 1;
   croak sprintf 'Request to %s failed: %s', $response->base(), $response->status_line();
}

#------------------------------------------------------------------------------

sub __mkpath {
    my ($self, $dir) = @_;;

    return if -e $dir;
    $dir = dir($dir) unless eval { $dir->isa('Path::Class::Dir') };
    return $dir->mkpath() or croak "Failed to make directory $dir: $!";
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

__PACKAGE__->meta->make_immutable();

#------------------------------------------------------------------------------

1;

__END__
