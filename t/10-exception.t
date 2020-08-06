# vim: set ts=8 sts=2 sw=2 tw=100 et :
use strict;
use warnings;
no if "$]" >= 5.031009, feature => 'indirect';

use Test2::API 'intercept';
use Test::More 0.88;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::Deep;
use Test::JSON::Schema::Acceptance;

my $accepter = Test::JSON::Schema::Acceptance->new(test_dir => 't/tests/bad');

my $events = intercept(
  sub {
    $accepter->acceptance(
      validate_data => sub {
        my ($schema, $data) = @_;
        die 'ach I am slain' if $data->{exception};
        return 1;
      },
      tests => { file => 'invalid-schema.json' },
    );
  }
);

cmp_deeply(
  [ map exists $_->{assert} ? $_->{assert} : (), map $_->facet_data, @$events ],
  [
    superhashof({
      details => 'invalid-schema.json: "exception handling" - "no exception; expect invalid: want test failure"',
      pass => 0,
    }),
    superhashof({
      details => 'invalid-schema.json: "exception handling" - "no exception; expect valid: want test pass"',
      pass => 1,
    }),
    superhashof({
      details => re(qr/^\Qinvalid-schema.json: "exception handling" - "exception; expect invalid: want test failure (via exception)" died: ach I am slain\E/),
      pass => 0,
    }),
    superhashof({
      details => re(qr/^\Qinvalid-schema.json: "exception handling" - "exception; expect valid: want test failure (via exception)" died: ach I am slain\E/),
      pass => 0,
    }),
  ],
  'four tests, all with correct results',
);

done_testing;
