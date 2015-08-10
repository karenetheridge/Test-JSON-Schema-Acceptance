package JSON::Schema::Test::Acceptance;

use 5.006;
use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Cwd 'abs_path';
use JSON;

=head1 NAME

JSON::Schema::Test::Acceptance - Acceptance testing for JSON-Schema based validators like JSON::Schema

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1_001';

=head1 SYNOPSIS

This module allows the JSON Schema Test Suite tests to be used in perl to test a module that implements json-schema.
These are the same tests that many modules (libraries, plugins, packages, etc.) use to confirm support of json-scheam.
Using this module to confirm support gives assurance of interoperability with other modules that run the same tests in differnet languages.

In the JSON::Schema module, a test could look like the following

  use Test::More;
  use JSON::Schema;
  use JSON::Schema::Test::Acceptance;

  my $accepter = JSON::Schema::Test::Acceptance->new();

  #Skip tests which are known not to be supported or cause problems.
  my $skip_tests = ['multiple extends', 'dependencies', 'ref'];

  $accepter->acceptance(sub{
    my $schema = shift;
    my $input = shift;
    my $return;

    $return = JSON::Schema->new($schema)->validate($input);
    return $return;
  }, {skip_tests => $skip_tests});

  done_testing();

=head1 SUBROUTINES/METHODS

=cut

sub new {
  my $class = shift;
  return bless {}, $class;
}

=head2 acceptance

Accepts a sub and optional options in the form of a hash.
The sub should return truthy or falsey depending on if the schema was valid for the input or not.

=head3 options

The only option which is currently accepted is skip_tests, which should be an array ref of tests you want to skip.
You can skip a whole section of tests or individual tests.
Any test name that contains any of the array refs items will be skipped, using grep.

=cut

sub acceptance {
  my ($self, $code, $options) = @_;
  my $tests = $self->_load_tests;

  my $skip_tests = defined $options->{skip_tests} ? $options->{skip_tests} : {};
  my $only_test = $options->{only_test};

  $self->_run_tests($code, $tests, $skip_tests, $only_test);

}

sub _run_tests {
  my ($self, $code, $tests, $skip_tests, $only_test) = @_;

  my $json = JSON->new;

  local $Test::Builder::Level = $Test::Builder::Level + 2;

  my $test_no = 0;
  foreach my $test_group (@{$tests}) {

    foreach my $test_group_test (@{$test_group->{json}}){

      my $test_group_cases = $test_group_test->{tests};
      my $schema = $test_group_test->{schema};

      foreach my $test (@{$test_group_cases}) {
        $test_no++;
        next if defined $only_test && $test_no != $only_test;
        my $subtest_name = $test_group_test->{description} . ' - ' . $test->{description};

        TODO: {
          todo_skip 'Test explicitly skipped. - '  . $subtest_name, 1
            if grep { $subtest_name =~ /$_/} @$skip_tests;

          my $result;
          my $exception = exception{
            if(ref($test->{data}) eq 'ARRAY' || ref($test->{data}) eq 'HASH'){
              $result = $code->($schema, $json->encode($test->{data}));
            } else {
              # $result = $code->($schema, $json->encode([$test->{data}]));
              $result = $code->($schema, JSON->new->allow_nonref->encode($test->{data}));
            }
          };

          my $test_desc = $test_group_test->{description} . ' - ' . $test->{description} . ($exception ? ' - and died!!' : '');
          ok(!$exception && _eq_bool($test->{valid}, $result), $test_desc) or
            diag(
              'Test file "' . $test_group->{file} . "\"\n" .
              'Test schema - ' . $test_group_test->{description} . "\n" .
              'Test data - ' . $test->{description} . "\n" . "\n"
            );
        }
      }
    }
  }
}

sub _load_tests {

  my $mod_dir = abs_path(__FILE__) =~ s~Acceptance\.pm~/test_suite~r; # Find the modules directory... ~

  my $draft_dir = $mod_dir . '/tests/draft3/';

  opendir (my $dir, $draft_dir) ;
  my @test_files = grep { -f "$draft_dir/$_"} readdir $dir;
  closedir $dir;
  # warn Dumper(\@test_files);

  my @test_groups;

  foreach my $file (@test_files) {
    my $fn = $draft_dir . $file;
    open ( my $fh, '<', $fn ) or die ("Could not open schema file $fn for read");
    my $raw_json = '';
    $raw_json .= $_ while (<$fh>);
    close($fh);
    my $parsed_json = JSON->new->allow_nonref->decode($raw_json);
    # my $parsed_json = JSON::from_json($raw_json);

    push @test_groups, { file => $file, json => $parsed_json };
  }

  return \@test_groups;
}


# Forces the two variables passed, into boolean context.
sub _eq_bool {
  return !(shift xor shift);
}

=head1 AUTHOR

Ben Hutton (@relequestual), C<< <relequest at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to via github at L<https://github.com/Relequestual/JSON-Schema-Test-Acceptance/issues>.

=head1 SUPPORT

Users' IRC: #json-schema on irc.perl.org

=for :html
L<(click for instant chatroom login)|http://chat.mibbit.com/#json-schema@irc.perl.org>

For questions about json-schema in general IRC: #json-schema on chat.freenode.net

=for :html
L<(click for instant chatroom login)|http://chat.mibbit.com/#json-schema@chat.freenode.net>

You can also look for information at:

=over 3

=item * Github issues (report bugs here)

L<https://github.com/Relequestual/JSON-Schema-Test-Acceptance/issues>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/JSON-Schema-Test-Acceptance>

=item * Search Meta CPAN

L<http://search.cpan.org/pod/JSON::Schema::Test::Acceptance/>

=back


=head1 ACKNOWLEDGEMENTS

Daniel Perrett <perrettdl@cpan.org> for the concept and help in design.

Ricardo SIGNES <rjbs@cpan.org> for direction to and creation of Test::Fatal.

Various others in #perl-help.

=head1 LICENSE AND COPYRIGHT

Copyright 2015 Ben Hutton (@relequestual).

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.


=cut

1; # End of JSON::Schema::Test::Acceptance
