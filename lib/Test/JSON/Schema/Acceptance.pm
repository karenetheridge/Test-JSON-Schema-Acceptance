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
use Moo;
use MooX::TypeTiny 0.002002;
use Types::Standard qw(Str InstanceOf ArrayRef HashRef Dict Any HasMethods);
use Path::Tiny;
use namespace::clean;

has specification => (
  is => 'ro',
  isa => Str,
  lazy => 1,
  default => 'draft2019-09',
);

has test_dir => (
  is => 'ro',
  isa => InstanceOf['Path::Tiny'],
  coerce => sub { path($_[0])->absolute('.') },
  lazy => 1,
  default => sub { path(dist_dir('Test-JSON-Schema-Acceptance'),'tests', $_[0]->specification) },
);

around BUILDARGS => sub {
  my ($orig, $class, @args) = @_;
  my %args = @args % 2 ? ( specification => 'draft'.$args[0] ) : @args;
  $args{specification} = 'draft2019-09' if ($args{specification} // '') eq 'latest';
  $class->$orig(\%args);
};

sub BUILD {
  my $self = shift;
  -d $self->test_dir or die 'test_dir does not exist: '.$self->test_dir;
}

sub acceptance {
  my $self = shift;
  my $options = +{ ref $_[0] eq 'CODE' ? (validate_json_string => @_) : @_ };

  die 'require one or the other of "validate_data", "validate_json_string"'
    if not $options->{validate_data} and not $options->{validate_json_string};

  die 'cannot provide both "validate_data" and "validate_json_string"'
    if $options->{validate_data} and $options->{validate_json_string};

  $self->_run_tests($self->_test_data, $options);

}

sub _run_tests {
  my ($self, $tests, $options) = @_;

  Test::More::note('running tests in '.$self->test_dir.'...');

  foreach my $one_file (@$tests) {
    foreach my $test_group (@{$one_file->{json}}){
      foreach my $test (@{$test_group->{tests}}) {
        $self->_run_test($one_file, $test_group, $test, $options);
      }
    }
  }
}

sub _run_test {
  my ($self, $one_file, $test_group, $test, $options) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 3;

  TODO: {
    my $subtest_name = $test_group->{description} . ' - ' . $test->{description};
    if (ref $options->{skip_tests} eq 'ARRAY'){
        Test::More::todo_skip 'Test explicitly skipped. - '  . $subtest_name, 1
        if (grep { $subtest_name =~ /$_/} @{$options->{skip_tests}});
    }

    my $result;
    my $exception = Test::Fatal::exception{
      $result = $options->{validate_data}
        ? $options->{validate_data}->($test_group->{schema}, $test->{data})
        : $options->{validate_json_string}->($test_group->{schema}, $self->_json_decoder->encode($test->{data}));
    };

    my $got = $result ? 'true' : 'false';
    my $expected = $test->{valid} ? 'true' : 'false';

    Test::More::is($got, $expected, $one_file->{file}.': "'.$test_group->{description}.'" - "'.$test->{description}.'"');
    Test::More::fail($exception) if $exception;
  }
}

has _json_decoder => (
  is => 'ro',
  isa => HasMethods[qw(encode decode)],
  lazy => 1,
  default => sub { JSON::MaybeXS->new(allow_nonref => 1) },
);

has _test_data => (
  is => 'lazy',
  isa => ArrayRef[
          Dict[
            file => Str,
            json => ArrayRef[Dict[
              description => Str,
              schema => InstanceOf['JSON::PP::Boolean']|HashRef,
              tests => ArrayRef[Dict[
                data => Any,
                description => Str,
                valid => InstanceOf['JSON::PP::Boolean'],
              ]],
            ]],
           ]],
);

sub _build__test_data {
  my $self = shift;

  my $draft_dir = $self->test_dir . "/";

  opendir (my $dir, $draft_dir) ;
  my @test_files = grep { -f "$draft_dir/$_"} readdir $dir;
  closedir $dir;
  # warn Dumper(\@test_files);

  my @test_groups;

  foreach my $file (@test_files) {
    next if $file !~ /\.json$/;

    my $fn = $draft_dir . $file;
    open ( my $fh, '<', $fn ) or die ("Could not open schema file $fn for read");
    my $raw_json = '';
    $raw_json .= $_ while (<$fh>);
    close($fh);
    my $parsed_json = $self->_json_decoder->decode($raw_json);

    push @test_groups, { file => $file, json => $parsed_json };
  }

  return \@test_groups;
}

1;
__END__

=pod

=for :header
=for stopwords validators Schemas

=for :footer
=for Pod::Coverage BUILDARGS BUILD

=head1 SYNOPSIS

This module allows the L<JSON Schema Test Suite|https://github.com/json-schema/JSON-Schema-Test-Suite> tests to be used in perl to test a module that implements the JSON Schema specification ("json-schema").
These are the same tests that many modules (libraries, plugins, packages, etc.) use to confirm support of json-schema.
Using this module to confirm support gives assurance of interoperability with other modules that run the same tests in different languages.

In the JSON::Schema module, a test could look like the following:

  use Test::More;
  use JSON::Schema;
  use Test::JSON::Schema::Acceptance;

  my $accepter = Test::JSON::Schema::Acceptance->new(specification => 'draft3');

  # Skip tests which are known not to be supported or which cause problems.
  my $skip_tests = ['multiple extends', 'dependencies', 'ref'];

  $accepter->acceptance(
    validate_data => sub {
      my ($schema, $input_data) = @_;
      return JSON::Schema->new($schema)->validate($input_data);
    },
    skip_tests => $skip_tests,
  );

  done_testing();

This would determine if JSON::Schema's C<validate> method returns the right result for all of the cases in the JSON Schema Test Suite, except for those listed in C<$skip_tests>.

=head1 DESCRIPTION

L<JSON Schema|http://json-schema.org> is an IETF draft (at time of writing) which allows you to define the structure of JSON.

From the overview of the L<draft 2019-09 version of the
specification|https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.3>:

=over 4

This document proposes a new media type "application/schema+json" to identify a JSON Schema for
describing JSON data. It also proposes a further optional media type,
"application/schema-instance+json", to provide additional integration features. JSON Schemas are
themselves JSON documents. This, and related specifications, define keywords allowing authors to
describe JSON data in several ways.

JSON Schema uses keywords to assert constraints on JSON instances or annotate those instances with
additional information. Additional keywords are used to apply assertions and annotations to more
complex JSON data structures, or based on some sort of condition.

=back


This module allows other perl modules (for example JSON::Schema) to test that they are JSON Schema-compliant, by running the tests from the official test suite, without having to manually convert them to perl tests.

You are unlikely to want this module, unless you are attempting to write a module which implements JSON Schema the specification, and want to test your compliance.

=head1 CONSTRUCTOR

  Test::JSON::Schema::Acceptance->new(specification => $specification_version)

Create a new instance of Test::JSON::Schema::Acceptance.

Available options are:

=head2 specification

This determines the draft version of the schema to confirm compliance to.
Possible values are:

=for :list
* C<draft3>
* C<draft4>
* C<draft6>
* C<draft7>
* C<draft2019-09>
* C<latest> (alias for C<draft2019-09>)

The default is C<latest>, but in the synopsis example, L<JSON::Schema> is testing draft 3 compliance.

(For backwards compatibility, C<new> can be called with a single numeric argument of 3 to 7, which maps to
C<draft3> through C<draft7>.)

=head2 test_dir

Instead of specifying a draft specification to test against, which will select the most appropriate tests,
you can pass in the name of a directory of tests to run directly.  Files in this directory should be F<.json>
files following the format described in
L<https://github.com/json-schema-org/JSON-Schema-Test-Suite/blob/master/README.md>.

=head1 SUBROUTINES/METHODS

=head2 acceptance

=for stopwords truthy falsey

Accepts a hash of options as its arguments.

(Backwards-compatibility mode: accepts a subroutine which is used as C<validate_json_string>,
and a hashref of arguments.)

Available options are:

=head3 validate_data

A subroutine reference, which is passed two arguments: the JSON Schema, and the B<inflated> data
structure to be validated.

The subroutine should return truthy or falsey depending on if the schema was valid for the input or
not.

Either C<validate_data> or C<validate_json_string> is required.

=head3 validate_json_string

A subroutine reference, which is passed two arguments: the JSON Schema, and the B<JSON string>
containing the data to be validated.

The subroutine should return truthy or falsey depending on if the schema was valid for the input or
not.

Either C<validate_data> or C<validate_json_string> is required.

=head3 skip_tests

Optional.

This should be an array ref of tests you want to skip.
You can skip a whole section of tests or individual tests.
Any test name that contains any of the array refs items will be skipped, using grep.

=head1 ACKNOWLEDGEMENTS

=for stopwords Signes

Daniel Perrett <perrettdl@cpan.org> for the concept and help in design.

Ricardo Signes <rjbs@cpan.org> for direction to and creation of Test::Fatal.

Various others in #perl-help.

=cut
