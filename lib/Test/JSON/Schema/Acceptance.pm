use strict;
use warnings;
package Test::JSON::Schema::Acceptance;
# vim: set ts=8 sts=2 sw=2 tw=100 et :
# ABSTRACT: Acceptance testing for JSON-Schema based validators like JSON::Schema

our $VERSION = '0.991';

no if "$]" >= 5.031009, feature => 'indirect';
use Test::More ();
use Test::Fatal ();
use JSON::MaybeXS;
use File::ShareDir 'dist_dir';
use namespace::clean;

=for :header =for stopwords validators

=head1 SYNOPSIS

This module allows the L<JSON Schema Test Suite|https://github.com/json-schema/JSON-Schema-Test-Suite> tests to be used in perl to test a module that implements json-schema.
These are the same tests that many modules (libraries, plugins, packages, etc.) use to confirm support of json-schema.
Using this module to confirm support gives assurance of interoperability with other modules that run the same tests in different languages.

In the JSON::Schema module, a test could look like the following:

  use Test::More;
  use JSON::Schema;
  use Test::JSON::Schema::Acceptance;

  my $accepter = Test::JSON::Schema::Acceptance->new(3);

  # Skip tests which are known not to be supported or which cause problems.
  my $skip_tests = ['multiple extends', 'dependencies', 'ref'];

  $accepter->acceptance( sub{
    my ( $schema, $input ) = @_;
    return JSON::Schema->new($schema)->validate($input);
  }, {
    skip_tests => $skip_tests
  } );

  done_testing();

This would determine if JSON::Schema's C<validate> method returns the right result for all of the cases in the JSON Schema Test Suite, except for those listed in C<$skip_tests>.

=head1 DESCRIPTION

L<JSON Schema|http://json-schema.org> is an IETF draft (at time of writing) which allows you to define the structure of JSON.

The abstract from L<draft 4|https://tools.ietf.org/html/draft-zyp-json-schema-04> of the specification:

=over 4

JSON Schema defines the media type "application/schema+json",
a JSON based format for defining the structure of JSON data.
JSON Schema provides a contract for what JSON data is required
for a given application and how to interact with it.
JSON Schema is intended to define validation, documentation,
hyperlink navigation, and interaction control of JSON data.

=back

L<JSON::Schema|https://metacpan.org/pod/JSON::Schema> is a perl module created independently of the specification, which aims to implement the json-schema specification.

This module allows other perl modules (for example JSON::Schema) to test that they are json-schema compliant, by running the tests from the official test suite, without having to manually convert them to perl tests.

You are unlikely to want this module, unless you are attempting to write a module which implements json-schema the specification, and want to test your compliance.


=head1 CONSTRUCTOR

=over 1

=item C<< Test::JSON::Schema::Acceptance->new($schema_version) >>

Create a new instance of Test::JSON::Schema::Acceptance.

Accepts optional argument of $schema_version.
This determines the draft version of the schema to confirm compliance to.
Default is draft 4 (current), but in the synopsis example, JSON::Schema is testing draft 3 compliance.

=back

=cut

sub new {
  my $class = shift;
  return bless { draft => shift || 4 }, $class;
}

=head1 SUBROUTINES/METHODS

=head2 acceptance

=for stopwords truthy falsey

Accepts a sub and optional options in the form of a hash.
The sub should return truthy or falsey depending on if the schema was valid for the input or not.

=head3 options

The only option which is currently accepted is skip_tests, which should be an array ref of tests you want to skip.
You can skip a whole section of tests or individual tests.
Any test name that contains any of the array refs items will be skipped, using grep.
You can also skip a test by its number.

=cut

sub acceptance {
  my ($self, $code, $options) = @_;
  my $tests = $self->_load_tests;

  my $skip_tests = $options->{skip_tests} // {};
  my $only_test = $options->{only_test} // undef;

  $self->_run_tests($code, $tests, $skip_tests, $only_test);

}

sub _run_tests {
  my ($self, $code, $tests, $skip_tests, $only_test) = @_;
  my $json = JSON::MaybeXS->new(allow_nonref => 1);

  local $Test::Builder::Level = $Test::Builder::Level + 2;

  my $test_no = 0;
  foreach my $test_group (@{$tests}) {

    foreach my $test_group_test (@{$test_group->{json}}){

      my $test_group_cases = $test_group_test->{tests};

      foreach my $test (@{$test_group_cases}) {
        $test_no++;
        next if defined $only_test && $test_no != $only_test;
        my $subtest_name = $test_group_test->{description} . ' - ' . $test->{description};

        TODO: {
          if (ref $skip_tests eq 'ARRAY'){
              Test::More::todo_skip 'Test explicitly skipped. - '  . $subtest_name, 1
              if (grep { $subtest_name =~ /$_/} @$skip_tests) ||
                grep $_ eq "$test_no", @$skip_tests;
          }

          my $result;
          my $exception = Test::Fatal::exception{
            $result = $code->($test_group_test->{schema}, $json->encode($test->{data}));
          };

          my $test_desc = $test_group_test->{description} . ' - ' . $test->{description} . ($exception ? ' - and died!!' : '');
          Test::More::ok(!$exception && _eq_bool($test->{valid}, $result), $test_desc) or
            Test::More::diag(
              "#$test_no \n" .
              'Test file "' . $test_group->{file} . "\"\n" .
              'Test schema - ' . $test_group_test->{description} . "\n" .
              'Test data - ' . $test->{description} . "\n" .
              ($exception ? "$exception " : "") . "\n"
            );
        }
      }
    }
  }
}

sub _load_tests {
  my $self = shift;

  my $mod_dir = dist_dir('Test-JSON-Schema-Acceptance');

  my $draft_dir = $mod_dir . "/tests/draft" . $self->{draft} . "/";

  opendir (my $dir, $draft_dir) ;
  my @test_files = grep { -f "$draft_dir/$_"} readdir $dir;
  closedir $dir;
  # warn Dumper(\@test_files);

  my $json = JSON::MaybeXS->new(allow_nonref => 1);
  my @test_groups;

  foreach my $file (@test_files) {
    my $fn = $draft_dir . $file;
    open ( my $fh, '<', $fn ) or die ("Could not open schema file $fn for read");
    my $raw_json = '';
    $raw_json .= $_ while (<$fh>);
    close($fh);
    my $parsed_json = $json->decode($raw_json);

    push @test_groups, { file => $file, json => $parsed_json };
  }

  return \@test_groups;
}


# Forces the two variables passed, into boolean context.
sub _eq_bool {
  return !(shift xor shift);
}

=head1 ACKNOWLEDGEMENTS

=for stopwords Signes

Daniel Perrett <perrettdl@cpan.org> for the concept and help in design.

Ricardo Signes <rjbs@cpan.org> for direction to and creation of Test::Fatal.

Various others in #perl-help.

=cut

1; # End of Test::JSON::Schema::Acceptance
