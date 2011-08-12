package Alien::VideoLAN::LibVLC;
use strict;
use warnings;
use Alien::VideoLAN::LibVLC::ConfigData;
use File::ShareDir qw(dist_dir);
use File::Spec;
use File::Find;
use File::Spec::Functions qw(catdir catfile rel2abs);
use File::Temp;
use Capture::Tiny;
use Config;
use Carp;
use ExtUtils::PkgConfig;

=head1 NAME

Alien::VideoLAN::LibVLC - building, finding and using VLC binaries

=head1 VERSION

Version 0.0_5

=cut

our $VERSION = '0.0_5';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

Alien::VideoLAN::LibVLC tries (in given order) during its installation:

=over

=item * Locate an already installed VLC via pkg-config.

=item * Download prebuilt VLC binaries (if available for your platform). Not implemented.

=item * Build VLC binaries from source codes (if possible on your system). Not implemented.

=back

Later you can use Alien::VideoLAN::LibVLC in your module that needs to link agains LibVLC
and/or related libraries like this:

	# Sample Makefile.pl
	use ExtUtils::MakeMaker;
	use Alien::VideoLAN::LibVLC;

	WriteMakefile(
	  NAME         => 'Any::VLC::Module',
	  VERSION_FROM => 'lib/Any/VLC/Module.pm',
	  LIBS         => Alien::VideoLAN::LibVLC->config('libs', [-lAdd_Lib]),
	  INC          => Alien::VideoLAN::LibVLC->config('cflags'),
	  # + additional params
	);

=head1 DESCRIPTION

Please see L<Alien> for the manifesto of the Alien namespace.

In short C<Alien::LibVLC> can be used to detect and get
configuration settings from an installed VLC and related libraries.
Based on your platform it (doesn't currently) offers the possibility to download and
install prebuilt binaries or to build VLC & co. from source codes.

The important facts:

=over

=item * The module does not modify in any way the already existing VLC
installation on your system.

=item * If you reinstall VLC libs on your system you do not need to
reinstall Alien::VideoLAN::LibVLC (providing that you use the same directory for
the new installation).

=item * The prebuild binaries and/or binaries built from sources are always
installed into perl module's 'share' directory.

=item * If you use prebuild binaries and/or binaries built from sources
it happens that some of the dynamic libraries (*.so, *.dll) will not
automaticly loadable as they will be stored somewhere under perl module's
'share' directory. To handle this scenario Alien::VideoLAN::LibVLC offers some special
functionality (see below).

=back

=head1 METHODS

=head2 config()

This function is the main public interface to this module. These functions
return string:

	Alien::VideoLAN::LibVLC->config('prefix');
	Alien::VideoLAN::LibVLC->config('version');
	Alien::VideoLAN::LibVLC->config('includedir');

These functions return lists of strings:

	Alien::VideoLAN::LibVLC->config('ldflags');
	Alien::VideoLAN::LibVLC->config('cflags');

On top of that this function supports special parameters:

	Alien::VideoLAN::LibVLC->config('ld_shared_libs');

Returns a reference to a list of full paths to shared libraries (*.so, *.dll) that will be
required for running the resulting binaries you have linked with VLC libs.

	Alien::VideoLAN::LibVLC->config('ld_paths');

Returns a reference to a list of full paths to directories with shared libraries (*.so, *.dll)
that will be required for running the resulting binaries you have linked with
VLC libs.

NOTE: config('ld_<something>') return an empty list/hash if you have decided to
use VLC libraries already installed on your system. This concerns pkg-config usage.

=head2 check_header()

This function checks the availability of given header(s) when using compiler
options provided by "Alien::VideoLAN::LibVLC->config('cflags')".

	Alien::VideoLAN::LibVLC->check_header('vlc.h');
	Alien::VideoLAN::LibVLC->check_header('vlc.h', 'libvlc_media.h');

Returns 1 if all given headers are available, 0 otherwise.

=head2 get_header_version()

Tries to find a header file specified as a param in VLC prefix direcotry and
based on "#define" macros inside this header file tries to get a version triplet.
Only C<libvlc_version.h> makes sense.

	Alien::VideoLAN::LibVLC->get_header_version('libvlc_version.h');

Returns string like '1.2.3' or undef if not able to find and parse version info.

=head2 C<find_libvlc> I<(deprecated)>

    Alien::VideoLAN::LibVLC->find_libvlc();
    Alien::VideoLAN::LibVLC->find_libvlc(version => '>= 1.1.9');
    Alien::VideoLAN::LibVLC->find_libvlc(version => '= 1.1.10',
                                         suppress_error_message => 1);

Finds installed libvlc.

If C<version> parameter is specified, required version is needed.
Check documentation of C<pkg-config> for format of version.

If C<suppress_error_message> parameter is specified and is true,
nothing will be put to STDERR if libvlc is not found.

Returns hash with following fields:

=over 4

=item * B<version>

a string with version.

=item * B<cflags>

arrayref of strings, e.g. C<['-I/foo/bar']>

=item * B<ldflags>

arrayref of strings, e.g. C<['-L/foo/baz', '-lvlc']>

=back

If libvlc of specified version isn't found, croaks.

=head1 BUGS

Please post issues and bugs at L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Alien-VideoLAN-LibVLC>

=head1 ACKNOWLEDGEMENTS

	Thanks to authors of other Alien modules.
	Since 0.05 this module is based on L<Alien::SDL>.

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut

### get config params
sub config
{
	my $package = shift;
	my @params  = @_;
	my $bt = Alien::VideoLAN::LibVLC::ConfigData->config('build_params')->{buildtype};
	return &_libvlc_config_via_pkgconfig if $bt eq 'use_pkgconfig';
	return _libvlc_config_via_script(@params)      if(Alien::VideoLAN::LibVLC::ConfigData->config('script'));# there is not such script...
	return _libvlc_config_via_config_data(@params) if(Alien::VideoLAN::LibVLC::ConfigData->config('config'));# need to install vlc by ours, to use it.
}

### get version info from given header file
sub get_header_version {
	my ($package, $header) = @_;
	return unless $header;

	# try to find header
	my $include = Alien::VideoLAN::LibVLC->config('includedir');
	my @files;
	find({ wanted => sub { push @files, rel2abs($_) if /\Q$header\E$/ }, follow => 1, no_chdir => 1, follow_skip => 2 }, $include);
	return unless @files;

	# get version info
	open(DAT, $files[0]) || return;
	my @raw=<DAT>;
	close(DAT);
	print for @raw;

	# generic magic how to get version major/minor/patchlevel
	my ($v_maj) = grep(/^#[ \t]*define[ \t]+[A-Z_]+?MAJOR[A-Z_]*[ \t]+\([0-9]+\)/, @raw);
	$v_maj =~ s/^#[ \t]*define[ \t]+[A-Z_]+[ \t]+\(([0-9]+)\)[.\r\n]*$/$1/;
	my ($v_min) = grep(/^#[ \t]*define[ \t]+[A-Z_]+MINOR[A-Z_]*[ \t]+\([0-9]+\)/, @raw);
	$v_min =~ s/^#[ \t]*define[ \t]+[A-Z_]+[ \t]+\(([0-9]+)\)[.\r\n]*$/$1/;
	my ($v_pat) = grep(/^#[ \t]*define[ \t]+[A-Z_]+REVISION[A-Z_]*[ \t]+\([0-9]+\)/, @raw);
	$v_pat =~ s/^#[ \t]*define[ \t]+[A-Z_]+[ \t]+\(([0-9]+)\)[.\r\n]*$/$1/;
	my ($v_ext) = grep(/^#[ \t]*define[ \t]+[A-Z_]+EXTRA[A-Z_]*[ \t]+\([0-9]+\)/, @raw);
	$v_ext =~ s/^#[ \t]*define[ \t]+[A-Z_]+[ \t]+\(([0-9]+)\)[.\r\n]*$/$1/;
	return if (($v_maj eq '')||($v_min eq '')||($v_pat eq '')||($v_ext eq ''));
	my $ver = "$v_maj.$v_min.$v_pat";
	$ver .= ".$v_ext" if $v_ext ne '0';
	return $ver;
}

### check presence of header(s) specified as params
sub check_header {
	my ($package, @header) = @_;
	print STDERR "[$package] Testing header(s): " . join(', ', @header);

	require ExtUtils::CBuilder; # PAR packer workaround

	my $config  = {};
	if($^O eq 'cygwin') {
		my $ccflags = $Config{ccflags};
		$ccflags    =~ s/-fstack-protector//;
		$config     = { ld => 'gcc', cc => 'gcc', ccflags => $ccflags };
	}

	my $cb = ExtUtils::CBuilder->new( quiet => 1, config => $config );
	my ($fs, $src) = File::Temp->tempfile('XXXXaa', SUFFIX => '.c', UNLINK => 1);
	my $inc = '';
	$inc .= "#include <$_>\n" for @header;
	syswrite($fs, <<MARKER); # write test source code
#if defined(_WIN32) && !defined(__CYGWIN__)
/* GL/gl.h on Win32 requires windows.h being included before */
#include <windows.h>
#endif
$inc
int demofunc(void) { return 0; }

MARKER
	close($fs);
	my $obj;
	my $stdout = '';
	my $stderr = '';
	($stdout, $stderr) = Capture::Tiny::capture {
		$obj = eval { $cb->compile( source => $src, extra_compiler_flags => Alien::VideoLAN::LibVLC->config('cflags')); };
	};
	if($obj) {
		print STDERR "\n";
		unlink $obj;
		return 1;
	}
	else {
		$stderr =~ s/[\r\n]$//;
		$stderr =~ s/^\Q$src\E[\d\s:]*//;

		print STDERR " NOK: ($stderr)\n";
		return 0;
	}
}

### internal functions
sub _libvlc_config_via_pkgconfig {
	my $PKGNAME = 'libvlc >= 1.2';
	my $param = shift;
	my $path = Alien::VideoLAN::LibVLC::ConfigData->config('build_params')->{pkg_config_path};
	$path = "" unless $path;
	$path = "$path:$ENV{PKG_CONFIG_PATH}" if $ENV{PKG_CONFIG_PATH};
	local $ENV{PKG_CONFIG_PATH} = $path;
	return ExtUtils::PkgConfig->modversion($PKGNAME) if $param eq 'version';
	return grep { $_ ne '' } split /\s/, ExtUtils::PkgConfig->cflags($PKGNAME) if $param eq 'cflags';
	return grep { $_ ne '' } split /\s/, ExtUtils::PkgConfig->libs($PKGNAME) if $param eq 'ldflags';
	return [] if $param =~ /^ld_/;
	return ExtUtils::PkgConfig->variable($PKGNAME, $param);
}

sub _libvlc_config_via_script
{
	croak "there's no libvlc-config script around";
	my $param    = shift;
	my @add_libs = @_;
	my $devnull = File::Spec->devnull();
	my $script = Alien::SDL::ConfigData->config('script');
	return unless ($script && ($param =~ /[a-z0-9_]*/i));
	my $val = `$script --$param 2>$devnull`;
	$val =~ s/[\r\n]*$//;
	if($param eq 'cflags') {
		$val .= ' ' . Alien::SDL::ConfigData->config('additional_cflags');
	}
	elsif($param eq 'libs') {
		$val .= ' ' . join(' ', @add_libs) if scalar @add_libs;
		$val .= ' ' . Alien::SDL::ConfigData->config('additional_libs');
	}
	return $val;
}

sub _libvlc_config_via_config_data
{
	croak "vlc installation by ourselves isn't supported yet";
	my $param    = shift;
	my @add_libs = @_;
	my $share_dir = dist_dir('Alien-VideoLAN-LibVLC');
	my $subdir = Alien::VideoLAN::LibVLC::ConfigData->config('share_subdir');
	return unless $subdir;
	my $real_prefix = catdir($share_dir, $subdir);
	return unless ($param =~ /[a-z0-9_]*/i);
	my $val = Alien::VideoLAN::LibVLC::ConfigData->config('config')->{$param};
	return unless $val;
	# handle additional flags
	if($param eq 'cflags') {
		$val .= ' ' . Alien::VideoLAN::LibVLC::ConfigData->config('additional_cflags');
	}
	elsif($param eq 'libs') {
		$val .= ' ' . join(' ', @add_libs) if scalar @add_libs;
		$val .= ' ' . Alien::VideoLAN::LibVLC::ConfigData->config('additional_libs');
	}  
	# handle @PrEfIx@ replacement
	if ($param =~ /^(ld_shared_libs|ld_paths)$/) {
		s/\@PrEfIx\@/$real_prefix/g foreach (@{$val});
	}
	elsif ($param =~ /^(ld_shlib_map)$/) {
		while (my ($k, $v) = each %$val ) {
			$val->{$k} =~ s/\@PrEfIx\@/$real_prefix/g;
		}
	}
	else {
		$val =~ s/\@PrEfIx\@/$real_prefix/g;
	}
	return $val;
}

### deprecated stuff
sub _find {
	my $self = shift;
	my $lib = shift;
	my %a = @_;

	my $version = $a{version};
	$version = '' unless defined $version;
	my %p;

	if ($a{suppress_error_message}) {
		my $str;
		open my $fh, '>', \$str;
		local *STDERR = $fh;
		%p = ExtUtils::PkgConfig->find("$lib $version");
	} else {
		%p = ExtUtils::PkgConfig->find("$lib $version");
	}

	my @cflags = grep { $_ ne '' } split /\s/, $p{cflags};
	$p{cflags} = \@cflags;
	my @ldflags = grep { $_ ne '' } split /\s/, $p{libs};
	delete $p{libs};
	$p{ldflags} = \@ldflags;
	$p{version} = $p{modversion};
	delete $p{modversion};
	return %p;
}
sub find_libvlc {
	my $self = shift;
	my %a = @_;
	return $self->_find('libvlc', %a);
}


1;
