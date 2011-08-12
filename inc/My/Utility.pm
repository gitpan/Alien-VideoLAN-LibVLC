package My::Utility;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK = qw(check_config_script check_pkgconfig check_prebuilt_binaries check_prereqs_libs check_prereqs_tools check_src_build find_SDL_dir find_file check_header sed_inplace get_dlext);
use Config;
use ExtUtils::CBuilder;
use File::Spec::Functions qw(splitdir catdir splitpath catpath rel2abs);
use File::Find qw(find);
use File::Which;
use File::Copy qw(cp);
use Cwd qw(realpath);
use Capture::Tiny qw(capture);
use ExtUtils::PkgConfig;

our $cc = $Config{cc};
#### packs with prebuilt binaries
# - all regexps has to match: arch_re ~ $Config{archname}, cc_re ~ $Config{cc}, os_re ~ $^O
# - the order matters, we offer binaries to user in the same order (1st = preffered)
my $prebuilt_binaries = [
];

#### tarballs with source codes
my $source_packs = [
## the first set for source code build will be a default option
];

sub check_config_script
{
	my $script = shift || 'sdl-config';
	print "Gonna check config script...\n";
	print "(scriptname=$script)\n";
	my $devnull = File::Spec->devnull();
	my $version = `$script --version 2>$devnull`;
	return if($? >> 8);
	my $prefix = `$script --prefix 2>$devnull`;
	return if($? >> 8);
	$version =~ s/[\r\n]*$//;
	$prefix =~ s/[\r\n]*$//;
	#returning HASHREF
	return {
		title     => "Already installed SDL ver=$version path=$prefix",
		buildtype => 'use_config_script',
		script    => $script,
		prefix    => $prefix,
	};
}

sub check_pkgconfig {
	my $pkgname = shift;
	print "Gonna check pkg-config...\n";
	my %p;
	eval {
		capture {
			%p = ExtUtils::PkgConfig->find($pkgname);
		};
	};
	return if $@;
	my $prefix = ExtUtils::PkgConfig->variable($pkgname, 'prefix');
	return {
		title     => "Already installed VLC ver=$p{modversion} path=$prefix",
		buildtype => 'use_pkgconfig',
		pkg_config_path => $ENV{PKG_CONFIG_PATH},
	};
}

sub check_prebuilt_binaries
{
	print "Gonna check availability of prebuilt binaries ...\n";
	print "(os=$^O cc=$cc archname=$Config{archname})\n";
	my @good = ();
	foreach my $b (@{$prebuilt_binaries}) {
		if ( ($^O =~ $b->{os_re}) &&
			($Config{archname} =~ $b->{arch_re}) &&
			($cc =~ $b->{cc_re}) ) {
			$b->{buildtype} = 'use_prebuilt_binaries';
			push @good, $b;
		}
	}
	#returning ARRAY of HASHREFs (sometimes more than one value)
	return \@good;
}

sub check_src_build
{
	print "Gonna check possibility for building from sources ...\n";
	print "(os=$^O cc=$cc)\n";
	my @good = ();
	foreach my $p (@{$source_packs}) {
		$p->{buildtype} = 'build_from_sources';
		print "CHECKING prereqs for:\n\t$p->{title}\n";
		push @good, $p if check_prereqs($p);
	}
	return \@good;
}

sub check_prereqs_libs {
	my @libs = @_;
	my $ret  = 1;

	foreach my $lib (@libs) {
		my $found_lib          = '';
		my $found_inc          = '';
		my $inc_lib_candidates = {
			'/usr/local/include' => '/usr/local/lib',
			'/usr/include'       => '/usr/lib',
			'/usr/X11R6/include' => '/usr/X11R6/lib',
			'/usr/pkg/include'   => '/usr/pkg/lib',
		};

		if( -e '/usr/lib64'  && $Config{'myarchname'} =~ /64/) {
			$inc_lib_candidates->{'/usr/include'} = '/usr/lib64'
		}

		if( exists $ENV{SDL_LIB} && exists $ENV{SDL_INC} ) {
			$inc_lib_candidates->{$ENV{SDL_INC}} = $ENV{SDL_LIB};
		}

		my $header_map         = {
			'z'    => 'zlib',
			'jpeg' => 'jpeglib',
		};
		my $header             = (defined $header_map->{$lib}) ? $header_map->{$lib} : $lib;

		my $dlext = get_dlext();
		foreach (keys %$inc_lib_candidates) {
			my $ld = $inc_lib_candidates->{$_};
			next unless -d $_ && -d $ld;
			($found_lib) = find_file($ld, qr/[\/\\]lib\Q$lib\E[\-\d\.]*\.($dlext[\d\.]*|a|dll.a)$/);
			($found_inc) = find_file($_,  qr/[\/\\]\Q$header\E[\-\d\.]*\.h$/);
			last if $found_lib && $found_inc;
		}

		if($found_lib && $found_inc) {
			$ret &= 1;
		}
		else {
			my $reason = 'no-h+no-lib';
			$reason = 'no-lib' if !$found_lib && $found_inc;
			$reason = 'no-h' if $found_lib && !$found_inc;
			print "WARNING: required lib(-dev) '$lib' not found, disabling affected option ($reason)\n";
			$ret = 0;
		}
	}

	return $ret;
}

sub check_prereqs {
	my $bp  = shift;
	my $ret = 1;

	$ret &= check_prereqs_libs(@{$bp->{prereqs}->{libs}}) if defined $bp->{prereqs}->{libs};

	return $ret;
}

sub check_prereqs_tools {
	my @tools = @_;
	my $ret  = 1;

	foreach my $tool (@tools) {

		if((File::Which::which($tool) && -x File::Which::which($tool))
			|| ('pkg-config' eq $tool && defined $ENV{PKG_CONFIG} && $ENV{PKG_CONFIG}
				&& File::Which::which($ENV{PKG_CONFIG})
				&& -x File::Which::which($ENV{PKG_CONFIG}))) {
			$ret &= 1;
		}
		else {
			print "WARNING: required '$tool' not found\n";
			$ret = 0;
		}
	}

	return $ret;
}

sub find_file {
	my ($dir, $re) = @_;
	my @files;
	$re ||= qr/.*/;
	{
		#hide warning "Can't opendir(...): Permission denied - fix for http://rt.cpan.org/Public/Bug/Display.html?id=57232
		no warnings;
		find({ wanted => sub { push @files, rel2abs($_) if /$re/ }, follow => 1, no_chdir => 1 , follow_skip => 2}, $dir);
	};
	return @files;
}

sub find_SDL_dir {
	my $root = shift;
	my ($version, $prefix, $incdir, $libdir);
	return unless $root;

	# try to find SDL_version.h
	my ($found) = find_file($root, qr/SDL_version\.h$/i ); # take just the first one
	return unless $found;

	# get version info
	open(DAT, $found) || return;
	my @raw=<DAT>;
	close(DAT);
	my ($v_maj) = grep(/^#define[ \t]+SDL_MAJOR_VERSION[ \t]+[0-9]+/, @raw);
	$v_maj =~ s/^#define[ \t]+SDL_MAJOR_VERSION[ \t]+([0-9]+)[.\r\n]*$/$1/;
	my ($v_min) = grep(/^#define[ \t]+SDL_MINOR_VERSION[ \t]+[0-9]+/, @raw);
	$v_min =~ s/^#define[ \t]+SDL_MINOR_VERSION[ \t]+([0-9]+)[.\r\n]*$/$1/;
	my ($v_pat) = grep(/^#define[ \t]+SDL_PATCHLEVEL[ \t]+[0-9]+/, @raw);
	$v_pat =~ s/^#define[ \t]+SDL_PATCHLEVEL[ \t]+([0-9]+)[.\r\n]*$/$1/;
	return if (($v_maj eq '')||($v_min eq '')||($v_pat eq ''));
	$version = "$v_maj.$v_min.$v_pat";

	# get prefix dir
	my ($v, $d, $f) = splitpath($found);
	my @pp = reverse splitdir($d);
	shift(@pp) if(defined($pp[0]) && $pp[0] eq '');
	shift(@pp) if(defined($pp[0]) && $pp[0] eq 'SDL');
	if(defined($pp[0]) && $pp[0] eq 'include') {
		shift(@pp);
		@pp = reverse @pp;
		return (
			$version,
			catpath($v, catdir(@pp), ''),
			catpath($v, catdir(@pp, 'include'), ''),
			catpath($v, catdir(@pp, 'lib'), ''),
		);
	}
}

sub check_header {
	my ($cflags, @header) = @_;
	print STDERR "Testing header(s): " . join(', ', @header) . "\n";
	my $cb = ExtUtils::CBuilder->new(quiet => 1);
	my ($fs, $src) = File::Temp->tempfile('XXXXaa', SUFFIX => '.c', UNLINK => 1);
	my $inc = '';
	$inc .= "#include <$_>\n" for @header;  
	syswrite($fs, <<MARKER); # write test source code
#if defined(_WIN32) && !defined(__CYGWIN__)
#include <stdio.h>
/* GL/gl.h on Win32 requires windows.h being included before */
#include <windows.h>
#endif
$inc
int demofunc(void) { return 0; }

MARKER
close($fs);
my $obj = eval { $cb->compile( source => $src, extra_compiler_flags => $cflags); };
if($obj) {
	unlink $obj;
	return 1;
}
else {
	print STDERR "###TEST FAILED### for: " . join(', ', @header) . "\n";
	return 0;
}
}

sub sed_inplace {
	# we expect to be called like this:
	# sed_inplace("filename.txt", 's/0x([0-9]*)/n=$1/g');
	my ($file, $re) = @_;
	if (-e $file) {
		cp($file, "$file.bak") or die "###ERROR### cp: $!";
		open INPF, "<", "$file.bak" or die "###ERROR### open<: $!";
		open OUTF, ">", $file or die "###ERROR### open>: $!";
		binmode OUTF; # we do not want Windows newlines
		while (<INPF>) {
			eval( "$re" );
			print OUTF $_;
		}
		close INPF;
		close OUTF;
	}
}

sub get_dlext {
	if($^O =~ /darwin/) { # there can be .dylib's on a mac even if $Config{dlext} is 'bundle'
		return 'so|dylib|bundle';
	}
	elsif( $^O =~ /cygwin/)
	{  
		return 'la';
	}
	else {
		return $Config{dlext};
	}
}

1;
