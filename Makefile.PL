use inc::Module::Install;
  
  # Define metadata
name           'KinoSearchX-Simple';
all_from       'lib/KinoSearchX/Simple.pm';
  
# Specific dependencies
requires       'Moose';
requires       'KinoSearch1';
test_requires 'Test::More' => '0.94';

auto_install;
WriteAll;
