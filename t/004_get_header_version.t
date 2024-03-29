# t/004_config.t

use Test::More tests => 1;
use Alien::VideoLAN::LibVLC;

like( Alien::VideoLAN::LibVLC->get_header_version('vlc/libvlc_version.h'), qr/([0-9]+\.)*[0-9]+/, "Testing libvlc_version.h" );
#like( Alien::SDL->get_header_version('SDL_net.h'), qr/([0-9]+\.)*[0-9]+/, "Testing SDL_net.h" );
#like( Alien::SDL->get_header_version('SDL_image.h'), qr/([0-9]+\.)*[0-9]+/, "Testing SDL_image.h" );

diag 'Core version: '.Alien::VideoLAN::LibVLC->get_header_version('libvlc_version.h');
#diag 'Mixer version: '.Alien::SDL->get_header_version('SDL_mixer.h');
#diag 'GFX version: '.Alien::SDL->get_header_version('SDL_gfxPrimitives.h');
#diag 'Image version: '.Alien::SDL->get_header_version('SDL_image.h');
#diag 'Net version: '.Alien::SDL->get_header_version('SDL_net.h');
#diag 'TTF version: '.Alien::SDL->get_header_version('SDL_ttf.h');
#diag 'Smpeg version: '.Alien::SDL->get_header_version('smpeg.h');


