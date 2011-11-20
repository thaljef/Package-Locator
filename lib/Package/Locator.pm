package Package::Locator;

# ABSTRACT: Find the distribution that provides a given package

use Moose;
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


has get_any => (
   is         => 'ro',
   isa        => 'Bool',
   default    => 0,
);


has verbose   => (
    is        => 'ro',
    isa       => 'Bool',
    default   => 0,
);


has _indexes => (
   is         => 'ro',
   isa        => 'ArrayRef[Package::Locator::Index]',
   auto_deref => 1,
   lazy_build => 1,
);


#------------------------------------------------------------------------------

sub BUILDARGS {
    my ($class, %args) = @_;

    if (my $cache_dir = $args{cache_dir}) {
        # Manual coercion here...
        $cache_dir = dir($cache_dir);
        $class->__mkpath($cache_dir);
        $args{cache_dir} = $cache_dir;
    }

    return \%args;
}

#------------------------------------------------------------------------------

sub _build__indexes {
    my ($self) = @_;

    my @indexes = map { Package::Locator::Index->new( cache_dir      => $self->cache_dir(),
                                                      user_agent     => $self->user_agent(),
                                                      force          => $self->force(),
                                                      repository_url => $_ )
    } $self->repository_urls();

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

    my ($latest_found_package, $found_in_index);
    for my $index ( $self->_indexes() ) {

        my $found_package = $index->lookup_package($package);
        next if not $found_package;

        my $found_package_version = version->parse( $found_package->version() );
        next if $found_package_version < $wanted_version;

        $found_in_index       ||= $index;
        $latest_found_package ||= $found_package;
        last if $self->get_any();;

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
      $DB::single = 1;
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
