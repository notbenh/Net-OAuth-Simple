use strict;
use Module::Build;

my $build = Module::Build
  ->new( module_name  => "Net::OAuth::Simple",
         license      => 'perl',
         script_files => [ ],
         requires     => {
                          'Crypt::SSLeay'        => 0,
                          'CGI'                  => 0,
                          'LWP::UserAgent'       => 0,
                          'Net::OAuth'           => 0,
                          'Test::More'           => 0.06,
                          'URI'                  => 0,
                        },
         create_makefile_pl => 'traditional',
       );

$build->create_build_script;

