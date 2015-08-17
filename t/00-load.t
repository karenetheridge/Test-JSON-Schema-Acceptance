#!perl -T
use 5.010;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'JSON::Schema::Test::Acceptance' ) || print "Bail out!\n";
}

diag( "Testing JSON::Schema::Test::Acceptance $JSON::Schema::Test::Acceptance::VERSION, Perl $], $^X" );
