# t/001_load.t - test module loading and basic functionality

use Test::More tests => 1;

BEGIN { use_ok( 'Alien::VideoLAN::LibVLC' ); }

diag( "Testing Alien::VideoLAN::LibVLC $Alien::VideoLAN::LibVLC::VERSION, Perl $], $^X" );

diag( "Build type: " . (Alien::VideoLAN::LibVLC::ConfigData->config('build_params')->{buildtype} || 'n.a.') );
#diag( "Detected sdl-config script: " . (Alien::SDL::ConfigData->config('build_params')->{script} || 'n.a.') );
diag( "Build option used:\n\t" . (Alien::VideoLAN::LibVLC::ConfigData->config('build_params')->{title} || 'n.a.') );
my $urls = Alien::VideoLAN::LibVLC::ConfigData->config('build_params')->{url} || [ 'n.a.' ];
diag( "URL:\n\t" . join("\n\t", @$urls));
diag( "SHA1: " . (Alien::VideoLAN::LibVLC::ConfigData->config('build_params')->{sha1sum} || 'n.a.') );
