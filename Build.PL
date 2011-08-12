use strict;
use warnings;

use lib "inc";
use File::Spec::Functions qw(catdir catfile);
use My::Utility qw(check_config_script check_pkgconfig check_prebuilt_binaries check_src_build);

#### we need the platform-specific module
my %platforms =(
	# Unix = default, thus not listing all UNIX like systems
	MSWin32 => 'Windows',
);
my $package = 'My::Builder::' . ($platforms{$^O} || 'Unix');
print "Gonna use '$package' class ...\n";
eval "require $package" or die "Require '$package' failed: $@\n";

my $sdl_config;

#### Stadard Module::Builder stuff
my $build = $package->new(
	module_name          => 'Alien::VideoLAN::LibVLC',
	all_from             => 'lib/Alien/VideoLAN/LibVLC.pm',
	dist_abstract        => 'Use VLC libraries',
#	dist_abstract        => 'Get, Build and Use VLC libraries',
	dist_author          => 'Alexey Sokolov <alexey@alexeysokolov.co.cc>',
	license              => 'perl',
	requires             => {
		'File::Spec'       => '0',
		'File::Temp'       => '0',
		'File::ShareDir'   => '0',
		'File::Which'      => '0',
		'ExtUtils::CBuilder' => '0',
		'Capture::Tiny'    => '0.11',
		'ExtUtils::PkgConfig' => '0',
		'Carp'             => '0',
	},
	build_requires       => {  #need to have for running: ./Build (install|test)
		'File::Spec'       => '0',
		'File::Temp'       => '0',
		'File::ShareDir'   => '0',
		'ExtUtils::CBuilder' => '0',
		'File::Path'       => '2.08',
		'File::Fetch'      => '0.24',
		'File::Find'       => '0',
		'File::Which'      => '0',
		'Digest::SHA'      => '0',
		'Archive::Extract' => '0',
		'Archive::Tar'     => '0',
		'Archive::Zip'     => '0',
		'Module::Build'    => '0.36',
		'Text::Patch'      => '1.4',
	},
	configure_requires   => {  #need to have for running: perl Buil.PL
		'File::Spec'       => '0',
		'File::Path'       => '2.08',
		'File::Fetch'      => '0.24',
		'File::Find'       => '0',
		'File::Which'      => '0',
		'Digest::SHA'      => '0',
		'Archive::Extract' => '0',
		'Module::Build'    => '0.36',
		'Text::Patch'      => '1.4',
		'File::ShareDir'   => '0',
		'ExtUtils::PkgConfig' => '0',
		'Capture::Tiny'    => '0.11',
	},
#	meta_merge => {
#		resources  => {
#			bugtracker => 'http://sdlperl.ath.cx/projects/SDLPerl/query?component=Alien%3A%3ASDL&status=!closed',
#			repository => 'http://github.com/PerlGameDev/Alien-SDL'
#		}
#	},
#	get_options => { 'with-sdl-config' => { qw(type :s  store) => \$sdl_config } },
	dynamic_config => 1,
	create_readme => 1,
	share_dir => 'sharedir',
# sharedir is used for storing compiled/prebuilt binaries of SDL lib + related libraries
# avoid using 'share' name as M::B doe not handle well paths like /xx/yy/share/zz/ww/share/xx
);

my $choice;

# Search for possible methods, then prompt:
print "\nWelcome to Alien::VideoLAN::LibVLC module installation";
print "\n------------------------------------------------------\n\n";

#### check what options we have for our platform
my $rv; my @candidates = ();

if($rv=check_pkgconfig("libvlc >= 1.2")) {
	push @candidates, $rv;
};

if($rv=check_prebuilt_binaries($build->os_type)) {
	push @candidates, @{$rv};
};

if($build->can_build_binaries_from_sources() && ($rv=check_src_build($build->os_type))) {
	push @candidates, @{$rv};
};

push @candidates, { title => 'Quit installation' };

#### ask user what way to go
my $i                     = 1;
my $prompt_string         = "\nYou have the following options:\n";
my $recommended_candidate = 1;
foreach my $c (@candidates) {
	$recommended_candidate = $i if $c->{title} =~ /RECOMMENDED/;
	$prompt_string        .= "[" . $i++ . "] " . $c->{title} . "\n"
}
$prompt_string .= "\nWhat way do you wanna go?";
my $ans = $build->prompt($prompt_string, $recommended_candidate);

if(($ans>0) && ($ans<scalar(@candidates))) {
	$choice = $candidates[$ans-1];
}

#### store build params into 'notes'
if($choice) {
	print "Using \l$choice->{title}\n";
	$build->notes('build_params', $choice);
	$build->create_build_script();

	#### clean build_done stamp; force rebuild when running 'Build'
	$build->clean_build_done_marker;
}
else {
	$build->notes('build_params', undef); # just to be sure
	exit(0); # we want no reports from CPAN Testers in this case
}
