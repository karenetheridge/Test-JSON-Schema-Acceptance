# vim: set ts=8 sts=2 sw=2 tw=100 et :
use strict;
use warnings;
no if "$]" >= 5.031009, feature => 'indirect';

use Test::Tester 0.108;
use Test::More 0.88;
use Test::Warnings 'warnings';
use Test::Deep;
use Test::File::ShareDir -share => { -dist => { 'Test-JSON-Schema-Acceptance' => 'share' } };
use Test::JSON::Schema::Acceptance;
use lib 't/lib';
use SchemaParser;

my $accepter = Test::JSON::Schema::Acceptance->new(test_dir => 't/tests/subset');
my $parser = SchemaParser->new;

foreach my $test (
  # match tests by group description
  { skip_count => 3+3, skip_tests => [ 'true schema' ] },
  { skip_count => 2*(3+3), skip_tests => [ 'true schema', 'false schema' ] },

  # match tests by regexp on test description
  { skip_count => 2*(3+3), skip_tests => [ '(true|false) schema' ] },

  # match tests on both descriptions
  { skip_count => 2*(1+3+1) + 1, skip_tests => [ 'false' ] },

  # match tests on group description and test description
  { skip_count => 3*2, skip_tests => [ 'empty schema.*boolean' ] },
) {
  my $skip_count = delete $test->{skip_count};
  my @warnings;
  my ($premature, @results) = run_tests(
    sub {
      @warnings = warnings {
        $accepter->acceptance(
          validate_data => sub {
            my ($schema, $data) = @_;
            return $parser->validate_data($data, $schema);
          },
          %$test,
        );
      }
    }
  );

  is(scalar(grep $_->{type} eq 'todo_skip', @results), $skip_count, 'skipped the right number of tests');

  cmp_deeply(
    \@warnings,
    [ re(qr/'skip_tests' option is deprecated at /) ],
    'got deprecation warnings for skip_tests feature',
  );
}

done_testing;
