# t/003_check_headers.t - test check_header() functionality

use Test::More tests => 1;
use Alien::VideoLAN::LibVLC;

diag("Testing basic header vlc/vlc.h");
is( Alien::VideoLAN::LibVLC->check_header('vlc/vlc.h'), 1, "Testing availability of 'vlc/vlc.h'" );
