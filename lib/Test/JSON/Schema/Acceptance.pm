use strict;
use warnings;
package Test::JSON::Schema::Acceptance;
# vim: set ts=8 sts=2 sw=2 tw=100 et :
# ABSTRACT: Acceptance testing for JSON-Schema based validators

our $VERSION = '1.028';

use 5.020;
use Moo;
use strictures 2;
use stable 0.031 'postderef';
use experimental 'signatures';
no if "$]" >= 5.031009, feature => 'indirect';
no if "$]" >= 5.033001, feature => 'multidimensional';
no if "$]" >= 5.033006, feature => 'bareword_filehandles';
use Test2::API ();
use Test2::Todo;
use Test2::Tools::Compare ();
use Mojo::JSON ();  # for JSON_XS, MOJO_NO_JSON_XS environment variables
use File::ShareDir 'dist_dir';
use Feature::Compat::Try;
use MooX::TypeTiny 0.002002;
use Types::Standard 1.016003 qw(Str InstanceOf ArrayRef HashRef Dict Any HasMethods Bool Optional Slurpy Enum);
use Types::Common::Numeric 'PositiveOrZeroInt';
use Path::Tiny 0.069;
use List::Util 1.33 qw(any max sum0);
use Ref::Util qw(is_plain_arrayref is_plain_hashref is_ref);
use Git::Wrapper;
use namespace::clean;

# specification version => metaschema URI
use constant METASCHEMA => {
  'draft-next'    => 'https://json-schema.org/draft/next/schema',
  'draft2020-12'  => 'https://json-schema.org/draft/2020-12/schema',
  'draft2019-09'  => 'https://json-schema.org/draft/2019-09/schema',
  'draft7'        => 'http://json-schema.org/draft-07/schema#',
  'draft6'        => 'http://json-schema.org/draft-06/schema#',
  'draft4'        => 'http://json-schema.org/draft-04/schema#',
  'draft3'        => 'http://json-schema.org/draft-03/schema#',
};

has specification => (
  is => 'ro',
  isa => Enum[keys METASCHEMA->%*],
  lazy => 1,
  default => 'draft2020-12',
  predicate => '_has_specification',
);

has supported_specifications => (
  is => 'ro',
  isa => ArrayRef[Enum[keys METASCHEMA->%*]],
  lazy => 1,
  default => sub { [ shift->specification ] },
);

# this comes from the tests/<spec version> directories in the JSON-Schema-Test-Suite repository
has test_dir => (
  is => 'ro',
  isa => InstanceOf['Path::Tiny'],
  coerce => sub { path($_[0])->absolute('.') },
  lazy => 1,
  builder => '_build_test_dir',
  predicate => '_has_test_dir',
);
sub _build_test_dir { path(dist_dir('Test-JSON-Schema-Acceptance'), 'tests', $_[0]->specification) };

# this comes from the remotes/ directory in the JSON-Schema-Test-Suite repository
has additional_resources => (
  is => 'ro',
  isa => InstanceOf['Path::Tiny'],
  coerce => sub { path($_[0])->absolute('.') },
  lazy => 1,
  default => sub { $_[0]->test_dir->parent->parent->child('remotes') },
);

has verbose => (
  is => 'ro',
  isa => Bool,
  default => 0,
);

has include_optional => (
  is => 'ro',
  isa => Bool,
  default => 0,
);

has skip_dir => (
  is => 'ro',
  isa => ArrayRef[Str],
  coerce => sub { ref($_[0]) ? $_[0] : [ $_[0] ] },
  lazy => 1,
  default => sub { [] },
);

has test_schemas => (
  is => 'ro',
  isa => Bool,
);

has results => (
  is => 'rwp',
  init_arg => undef,
  isa => ArrayRef[Dict[
           file => InstanceOf['Path::Tiny'],
           map +($_ => PositiveOrZeroInt), qw(pass todo_fail fail),
         ]],
);

has results_text => (
  is => 'ro',
  init_arg => undef,
  isa => Str,
  lazy => 1,
  builder => '_build_results_text',
);

around BUILDARGS => sub ($orig, $class, @args) {
  my %args = @args % 2 ? ( specification => 'draft'.$args[0] ) : @args;
  $args{specification} = 'draft2020-12' if ($args{specification} // '') eq 'latest';
  $class->$orig(\%args);
};

sub BUILD ($self, @) {
  -d $self->test_dir or die 'test_dir does not exist: '.$self->test_dir;
}

sub acceptance {
  my $self = shift;
  my $options = +{ ref $_[0] eq 'CODE' ? (validate_json_string => @_) : @_ };

  die 'require one or the other of "validate_data", "validate_json_string"'
    if not $options->{validate_data} and not $options->{validate_json_string};

  die 'cannot provide both "validate_data" and "validate_json_string"'
    if $options->{validate_data} and $options->{validate_json_string};

  warn "'skip_tests' option is deprecated" if $options->{skip_tests};

  my $ctx = Test2::API::context;

  if ($options->{add_resource} and -d $self->additional_resources) {
    # this is essentially what `bin/jsonschema_suite remote` does: resolves the filename against the
    # base uri to determine the absolute schema location of each resource.
    my $base = 'http://localhost:1234';
    $ctx->note('adding resources from '.$self->additional_resources.' with the base URI "'.$base.'"...');
    $self->additional_resources->visit(
      sub ($path, @) {
        return if not $path->is_file or $path !~ /\.json$/;

        # skip resource files that are marked as being for an unsupported draft
        my $relative_path = $path->relative($self->additional_resources);
        my ($topdir) = split qr{/}, $relative_path, 2;
        return if $topdir =~ /^draft/ and not grep $topdir eq $_, $self->supported_specifications->@*;

        my $data = $self->json_deserialize($path->slurp_raw);
        my $file = $path->relative($self->additional_resources);
        my $uri = $base.'/'.$file;
        $options->{add_resource}->($uri => $data);
      },
      { recurse => 1 },
    );
  }

  $ctx->note('running tests in '.$self->test_dir.' against '
    .($self->_has_specification ? $self->specification : 'unknown version').'...');
  my $tests = $self->_test_data;

  # [ { file => .., pass => .., fail => .. }, ... ]
  my @results;

  foreach my $one_file (@$tests) {
    my %results;
    next if $options->{tests} and $options->{tests}{file}
      and not grep $_ eq $one_file->{file},
        (ref $options->{tests}{file} eq 'ARRAY'
          ? $options->{tests}{file}->@* : $options->{tests}{file});

    $ctx->note('');

    foreach my $test_group ($one_file->{json}->@*) {
      next if $options->{tests} and $options->{tests}{group_description}
        and not grep $_ eq $test_group->{description},
          (ref $options->{tests}{group_description} eq 'ARRAY'
            ? $options->{tests}{group_description}->@* : $options->{tests}{group_description});

      my $todo;
      $todo = Test2::Todo->new(reason => 'Test marked TODO via "todo_tests"')
        if $options->{todo_tests}
          and any {
            my $o = $_;
            (not $o->{file} or grep $_ eq $one_file->{file}, (ref $o->{file} eq 'ARRAY' ? $o->{file}->@* : $o->{file}))
              and
            (not $o->{group_description} or grep $_ eq $test_group->{description}, (ref $o->{group_description} eq 'ARRAY' ? $o->{group_description}->@* : $o->{group_description}))
              and not $o->{test_description}
          }
          $options->{todo_tests}->@*;

      my $schema_fails;
      if ($self->test_schemas) {
        die 'specification_version unknown: cannot evaluate schema against metaschema'
          if not $self->_has_specification;

        my $metaschema_uri = is_plain_hashref($test_group->{schema}) && $test_group->{schema}{'$schema'}
          ? $test_group->{schema}{'$schema'}
          : METASCHEMA->{$self->specification};
        my $metaschema_schema = { '$ref' => $metaschema_uri };
        my $result = $options->{validate_data}
          ? $options->{validate_data}->($metaschema_schema, $test_group->{schema})
          : $options->{validate_json_string}->($metaschema_schema, $self->json_serialize($test_group->{schema}));
        if (not $result) {
          $ctx->fail('schema for '.$one_file->{file}.': "'.$test_group->{description}.'" fails to validate against '.$metaschema_uri.':');
          $ctx->note($self->json_prettyprint($result));
          $schema_fails = 1;
        }
      }

      foreach my $test ($test_group->{tests}->@*) {
        next if $options->{tests} and $options->{tests}{test_description}
          and not grep $_ eq $test->{description},
            (ref $options->{tests}{test_description} eq 'ARRAY'
              ? $options->{tests}{test_description}->@* : $options->{tests}{test_description});

        my $todo;
        $todo = Test2::Todo->new(reason => 'Test marked TODO via deprecated "skip_tests"')
          if ref $options->{skip_tests} eq 'ARRAY'
            and grep +(($test_group->{description}.' - '.$test->{description}) =~ /$_/),
              $options->{skip_tests}->@*;

        $todo = Test2::Todo->new(reason => 'Test marked TODO via "todo_tests"')
          if $options->{todo_tests}
            and any {
              my $o = $_;
              (not $o->{file} or grep $_ eq $one_file->{file}, (ref $o->{file} eq 'ARRAY' ? $o->{file}->@* : $o->{file}))
                and
              (not $o->{group_description} or grep $_ eq $test_group->{description}, (ref $o->{group_description} eq 'ARRAY' ? $o->{group_description}->@* : $o->{group_description}))
                and
              (not $o->{test_description} or grep $_ eq $test->{description}, (ref $o->{test_description} eq 'ARRAY' ? $o->{test_description}->@* : $o->{test_description}))
            }
            $options->{todo_tests}->@*;

        my $result = $self->_run_test($one_file, $test_group, $test, $options);
        $result = 0 if $schema_fails;

        ++$results{ $result ? 'pass' : $todo ? 'todo_fail' : 'fail' };
      }
    }

    push @results, { file => $one_file->{file}, pass => 0, 'todo_fail' => 0, fail => 0, %results };
  }

  $self->_set_results(\@results);

  my $diag = $self->verbose ? 'diag' : 'note';
  $ctx->$diag("\n".$self->results_text."\n");

  if ($self->test_dir !~ m{\boptional\b}
      and grep +($_->{file} !~ m{^optional/} && $_->{todo_fail} + $_->{fail}), @results) {
    # non-optional test failures will always be visible, even when not in verbose mode.
    $ctx->diag('WARNING: some non-optional tests are failing! This implementation is not fully compliant with the specification!');
    $ctx->diag('');
  }
  else {
    $ctx->$diag('Congratulations, all non-optional tests are passing!');
    $ctx->$diag('');
  }

  $ctx->release;
}

sub _run_test ($self, $one_file, $test_group, $test, $options) {
  my $test_name = $one_file->{file}.': "'.$test_group->{description}.'" - "'.$test->{description}.'"';

  my $pass; # ignores TODO status

  Test2::API::run_subtest($test_name,
    sub {
      my ($result, $schema_before, $data_before, $schema_after, $data_after);
      try {
        ($schema_before, $data_before) = map $self->json_serialize($_),
          $test_group->{schema}, $test->{data};

        $result = $options->{validate_data}
          ? $options->{validate_data}->($test_group->{schema}, $test->{data})
          : $options->{validate_json_string}->($test_group->{schema}, $self->json_serialize($test->{data}));

        ($schema_after, $data_after) = map $self->json_serialize($_),
          $test_group->{schema}, $test->{data};

        my $ctx = Test2::API::context;

        # skip the ugly matrix comparison
        my $expected = $test->{valid} ? 'true' : 'false';
        if ($result xor $test->{valid}) {
          $ctx->fail('evaluation result is incorrect', 'expected '.$expected.'; got '.($result ? 'true' : 'false'));
          $ctx->${ $self->verbose ? \'diag' : \'note' }('schema: '.$self->json_prettyprint($test_group->{schema}));
          $ctx->${ $self->verbose ? \'diag' : \'note' }('data: '.$self->json_prettyprint($test->{data}));

          $ctx->${ $self->verbose ? \'diag' : \'note' }('result: '.$self->json_prettyprint($result));
          $pass = 0;
        }
        else {
          $ctx->ok(1, 'test passes: data is valid: '.$expected);
          $pass = 1;
        }

        my @mutated_data_paths = $self->_mutation_check($test->{data});
        my @mutated_schema_paths = $self->_mutation_check($test_group->{schema});

        # string check   path check    behaviour
        #            0            0    ::is(), and note. $pass = 0
        #            0            1    ::is().           $pass = 0
        #            1            0    ->fail and note.  $pass = 0
        #            1            1    no test. $pass does not change.

        if ($data_before ne $data_after) {
          Test2::Tools::Compare::is($data_after, $data_before, 'evaluator did not mutate data');
          $pass = 0;
        }
        elsif (@mutated_data_paths) {
          $ctx->fail('evaluator did not mutate data');
          $pass = 0
        }

        $ctx->note('mutated data at location'.(@mutated_data_paths > 1 ? 's' : '').': '.join(', ', @mutated_data_paths)) if @mutated_data_paths;

        if ($schema_before ne $schema_after) {
          Test2::Tools::Compare::is($schema_after, $schema_before, 'evaluator did not mutate schema');
          $pass = 0;
        }
        elsif (@mutated_schema_paths) {
          $ctx->fail('evaluator did not mutate schema');
          $pass = 0;
        }

        $ctx->note('mutated schema at location'.(@mutated_schema_paths > 1 ? 's' : '').': '.join(', ', @mutated_schema_paths)) if @mutated_schema_paths;

        $ctx->release;
      }
      catch ($e) {
        chomp(my $exception = $e);
        my $ctx = Test2::API::context;
        $ctx->fail('died: '.$exception);
        $ctx->release;
      };
    },
    { buffered => 1, inherit_trace => 1 },
  );

  return $pass;
}

sub _mutation_check ($self, $data) {
  my @error_paths;

  # [ path => data ]
  my @nodes = ([ '', $data ]);
  while (my $node = shift @nodes) {
    if (not defined $node->[1]) {
      next;
    }
    if (is_plain_arrayref($node->[1])) {
      push @nodes, map [ $node->[0].'/'.$_, $node->[1][$_] ], 0 .. $node->[1]->$#*;
      push @error_paths, $node->[0] if tied($node->[1]->@*);
    }
    elsif (is_plain_hashref($node->[1])) {
      push @nodes, map [ $node->[0].'/'.(s/~/~0/gr =~ s!/!~1!gr), $node->[1]{$_} ], keys $node->[1]->%*;
      push @error_paths, $node->[0] if tied($node->[1]->%*);
    }
    elsif (is_ref($node->[1])) {
      next; # boolean or bignum
    }
    else {
      my $flags = B::svref_2object(\$node->[1])->FLAGS;
      push @error_paths, $node->[0]
        if not ($flags & B::SVf_POK xor $flags & (B::SVf_IOK | B::SVf_NOK));
    }
  }

  return @error_paths;
}

use constant _JSON_BACKEND => Mojo::JSON::JSON_XS ? 'Cpanel::JSON::XS' : 'JSON::PP';

# used for internal serialization/deserialization; does not prettify the string.
has _json_serializer => (
  is => 'ro',
  isa => HasMethods[qw(encode decode)],
  handles => {
    json_serialize => 'encode',
    json_deserialize => 'decode',
  },
  lazy => 1,
  default => sub { _JSON_BACKEND->new->allow_nonref(1)->utf8(1)->allow_blessed(1)->allow_bignum(1)->canonical(1) },

);

# used for displaying diagnostics only
has _json_prettyprinter => (
  is => 'ro',
  isa => HasMethods['encode'],
  lazy => 1,
  handles => {
    json_prettyprint => 'encode',
  },
  default => sub {
    my $encoder = _JSON_BACKEND->new->allow_nonref(1)->utf8(0)->allow_blessed(1)->allow_bignum(1)->canonical(1)->convert_blessed(1)->pretty(1)->space_before(0);
    $encoder->indent_length(2) if $encoder->can('indent_length');
    $encoder;
  },
);

# backcompat shims
sub _json_decoder { shift->_json_serializer(@_) }
sub json_decoder { shift->_json_serializer(@_) }
sub _json_encoder { shift->_json_prettyprinter(@_) }
sub json_encoder { shift->_json_prettyprinter(@_) }

# see JSON::MaybeXS::is_bool
my $json_bool = InstanceOf[qw(JSON::XS::Boolean Cpanel::JSON::XS::Boolean JSON::PP::Boolean)];

has _test_data => (
  is => 'lazy',
  isa => ArrayRef[Dict[
           file => InstanceOf['Path::Tiny'],
           json => ArrayRef[Dict[
             # id => Optional[Str],
             # specification => Optional[Str],
             description => Str,
             comment => Optional[Str],
             schema => $json_bool|HashRef,
             tests => ArrayRef[Dict[
               # id => Optional[Str],
               data => Any,
               description => Str,
               comment => Optional[Str],
               valid => $json_bool,
               Slurpy[Any],
             ]],
             Slurpy[Any],
           ]],
         ]],
);

sub _build__test_data ($self) {
  my @test_groups;

  $self->test_dir->visit(
    sub {
      my ($path) = @_;
      return if any { $self->test_dir->child($_)->subsumes($path) } $self->skip_dir->@*;
      return if not $path->is_file;
      return if $path !~ /\.json$/;
      my $data = $self->json_deserialize($path->slurp_raw);
      return if not @$data; # placeholder files for renamed tests
      my $file = $path->relative($self->test_dir);
      push @test_groups, [
        scalar(split('/', $file)),
        {
          file => $file,
          json => $data,
        },
      ];
    },
    { recurse => $self->include_optional },
  );

  return [
    map $_->[1],
      sort { $a->[0] <=> $b->[0] || $a->[1]{file} cmp $b->[1]{file} }
      @test_groups
  ];
}

sub _build_results_text ($self) {
  my @lines;
  sub _pad ($s, $rest) { sprintf('%-29s', $s) . $rest }
  push @lines, _pad('generated with:', ref($self).' '.$self->VERSION);

  my $test_dir = $self->test_dir;
  my $orig_dir = $self->_build_test_dir;

  my $submodule_status = path(dist_dir('Test-JSON-Schema-Acceptance'), 'submodule_status');
  if ($submodule_status->exists and $submodule_status->parent->subsumes($self->test_dir)) {
    chomp(my ($commit, $url) = $submodule_status->lines);
    push @lines, _pad('with commit:', $commit);
    push @lines, _pad('from repository:', $url);
  }
  elsif ($test_dir eq $orig_dir and not -d '.git') {
    die 'submodule_status file is missing - packaging error? cannot continue';
  }

  push @lines, _pad('specification version:', $self->specification//'unknown');

  if ($test_dir ne $orig_dir) {
    my $local;
    if ($orig_dir->subsumes($test_dir)) {
      $test_dir = '<base test directory>/'.substr($test_dir, length($orig_dir)+1);
    }
    elsif (Path::Tiny->cwd->subsumes($test_dir)) {
      $test_dir = $test_dir->relative;
      $local = 1;
    }
    push @lines, _pad('using custom test directory:', $test_dir);

    eval {
      my $git  = Git::Wrapper->new($test_dir);
      my @ref = $git->describe({ all => 1, long => 1, always => 1 });
      push @lines, _pad('at ref:', $ref[0]);
    } if not $local;
  }
  push @lines, _pad('optional tests included:', $self->include_optional ? 'yes' : 'no');
  push @lines, map _pad('skipping directory:', $_), $self->skip_dir->@*;

  push @lines, '';
  my $length = max(40, map length $_->{file}, $self->results->@*);

  push @lines, sprintf('%-'.$length.'s  pass  todo-fail  fail', 'filename');
  push @lines, '-'x($length + 23);
  push @lines, map sprintf('%-'.$length.'s % 5d       % 4d  % 4d', $_->@{qw(file pass todo_fail fail)}),
    $self->results->@*;

  my $total = +{ map { my $type = $_; $type => sum0(map $_->{$type}, $self->results->@*) } qw(pass todo_fail fail) };
  push @lines, '-'x($length + 23);
  push @lines, sprintf('%-'.$length.'s % 5d      % 5d % 5d', 'TOTAL', $total->@{qw(pass todo_fail fail)});

  return join("\n", @lines, '');
}

1;
__END__

=pod

=for :header
=for stopwords validators Schemas ANDed ORed TODO

=for :footer
=for Pod::Coverage BUILDARGS BUILD json_decoder

=head1 SYNOPSIS

This module allows the
L<JSON Schema Test Suite|https://github.com/json-schema/JSON-Schema-Test-Suite> tests to be used in
perl to test a module that implements the JSON Schema specification ("json-schema"). These are the
same tests that many modules (libraries, plugins, packages, etc.) use to confirm support of
json-schema. Using this module to confirm support gives assurance of interoperability with other
modules that run the same tests in different languages.

In the JSON::Schema::Modern module, a test could look like the following:

  use Test::More;
  use JSON::Schema::Modern;
  use Test::JSON::Schema::Acceptance;

  my $accepter = Test::JSON::Schema::Acceptance->new(specification => 'draft7');

  $accepter->acceptance(
    validate_data => sub ($schema, $input_data) {
      return JSON::Schema::Modern->new($schema)->validate($input_data);
    },
    todo_tests => [ { file => 'dependencies.json' } ],
  );

  done_testing();

This would determine if JSON::Schema::Modern's C<validate> method returns the right result for all
of the cases in the JSON Schema Test Suite, except for those listed in C<skip_tests>.

=head1 DESCRIPTION

L<JSON Schema|http://json-schema.org> is an IETF draft (at time of writing) which allows you to
define the structure of JSON.

From the overview of the L<draft 2020-12 version of the
specification|https://json-schema.org/draft/2020-12/json-schema-core.html#rfc.section.3>:

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

This module allows other perl modules (for example JSON::Schema::Modern) to test that they are JSON
Schema-compliant, by running the tests from the official test suite, without having to manually
convert them to perl tests.

You are unlikely to want this module, unless you are attempting to write a module which implements
JSON Schema the specification, and want to test your compliance.

=head1 CONSTRUCTOR

  Test::JSON::Schema::Acceptance->new(specification => $specification_version)

Create a new instance of Test::JSON::Schema::Acceptance.

Available options (which are also available as accessor methods on the object) are:

=head2 specification

This determines the draft version of the schema to confirm compliance to.
Possible values are:

=for :list
* C<draft3>
* C<draft4>
* C<draft6>
* C<draft7>
* C<draft2019-09>
* C<draft2020-12>
* C<latest> (alias for C<draft2020-12>)
* C<draft-next>

The default is C<latest>, but in the synopsis example, L<JSON::Schema::Modern> is testing draft 7
compliance.

(For backwards compatibility, C<new> can be called with a single numeric argument of 3 to 7, which
maps to C<draft3> through C<draft7>.)

=head2 supported_specifications

The version(s) that the implementation supports; used to skip adding remote resources that reference
unsupported schema versions (for cross-schema tests). Defaults to C<< [ $self->specification ] >>.

=head2 test_dir

Instead of specifying a draft specification to test against, which will select the most appropriate
tests, you can pass in the name of a directory of tests to run directly. Files in this directory
should be F<.json> files following the format described in
L<https://github.com/json-schema-org/JSON-Schema-Test-Suite/blob/main/README.md>.

=head2 additional_resources

A directory of additional resources which should be made available to the implementation under the
base URI C<http://localhost:1234>. This dataset is automatically provided if you did not override
L</test_dir>; otherwise, you need to supply it yourself, if any tests require it (for example by
containing C<< {"$ref": "http://localhost:1234/foo.json/#a/b/c"} >>). If you supply an
L</add_resource> value to L</acceptance> (see below), this will be done for you.

=head2 verbose

Optional. When true, prints version information and the test result table such that it is visible
during C<make test> or C<prove>.

=head2 include_optional

Optional. When true, tests in subdirectories (most notably F<optional/> are also included.

=head2 skip_dir

Optional. Pass a string or arrayref consisting of relative path name(s) to indicate directories
(within the test directory as specified above with L</specification> or L</test_dir>) which will be
skipped. Note that this is only useful currently with C<< include_optional => 1 >>, as otherwise all
subdirectories would be skipped anyway.

=head2 results

After calling L</acceptance>, a list of test results are provided here. It is an arrayref of
hashrefs with four keys:

=for :list
* file - the filename
* pass - the number of pass results for that file
* todo_fail - the number of fail results for that file that were marked TODO
* fail - the number of fail results for that file (not including TODO tests)

=head2 results_text

After calling L</acceptance>, a text string tabulating the test results are provided here. This is
the same table that is printed at the end of the test run.

=head2 test_schemas

=for stopwords metaschema

Optional. A boolean that, when true, will test every schema against its
specification metaschema. (When set, L</specification> must also be set.)

This normally should not be set as the official test suite has already been
sanity-tested, but you may want to set this in development environments if you
are using your own test files.

Defaults to false.

=head1 SUBROUTINES/METHODS

=head2 acceptance

=for stopwords truthy falsey

Accepts a hash of options as its arguments.

(Backwards-compatibility mode: accepts a subroutine which is used as L</validate_json_string>,
and a hashref of arguments.)

Available options are:

=head3 validate_data

A subroutine reference, which is passed two arguments: the JSON Schema, and the B<inflated> data
structure to be validated. This is the main entry point to your JSON Schema library being tested.

The subroutine should return truthy or falsey depending on if the schema was valid for the input or
not (an object with a boolean overload is acceptable).

Either L</validate_data> or L</validate_json_string> is required.

=head3 validate_json_string

A subroutine reference, which is passed two arguments: the JSON Schema, and the B<JSON string>
containing the data to be validated. This is an alternative to L</validate_data> above, if your
library only accepts JSON strings.

The subroutine should return truthy or falsey depending on if the schema was valid for the input or
not (an object with a boolean overload is acceptable).

Exactly one of L</validate_data> or L</validate_json_string> is required.

=head3 add_resource

Optional. A subroutine reference, which will be called at the start of L</acceptance> multiple
times, with two arguments: a URI (string), and a data structure containing schema data to be
associated with that URI, for use in some tests that use additional resources (see above). If you do
not provide this option, you will be responsible for ensuring that those additional resources are
made available to your implementation for the successful execution of the tests that rely on them.

For more information, see <https://json-schema.org/draft/2020-12/json-schema-core.html#rfc.section.9.1.2>.

=head3 tests

Optional. Restricts tests to just those mentioned (the conditions are ANDed together, not ORed).
The syntax can take one of many forms:

  # run tests in this file
  tests => { file => 'dependencies.json' }

  # run tests in these files
  tests => { file => [ 'dependencies.json', 'refRemote.json' ] }

  # run tests in this file with this group description
  tests => {
    file => 'refRemote.json',
    group_description => 'remote ref',
  }

  # run tests in this file with these group descriptions
  tests => {
    file => 'const.json',
    group_description => [ 'const validation', 'const with object' ],
  }

  # run tests in this file with this group description and test description
  tests => {
    file => 'const.json',
    group_description => 'const validation',
    test_description => 'another type is invalid',
  }

  # run tests in this file with this group description and these test descriptions
  tests => {
    file => 'const.json',
    group_description => 'const validation',
    test_description => [ 'same value is valid', 'another type is invalid' ],
  }

=head3 todo_tests

Optional. Mentioned tests will run as L<"TODO"|Test::More/TODO: BLOCK>. Uses arrayrefs of
the same hashref structure as L</tests> above, which are ORed together.

  todo_tests => [
    # all tests in this file are TODO
    { file => 'dependencies.json' },
    # just some tests in this file are TODO
    { file => 'boolean_schema.json', test_description => 'array is invalid' },
    # .. etc
  ]

=head2 json_prettyprint

JSON-encodes a data structure in a format suitable for human view, used for printing test diagnostics.

=head2 json_encoder

Provides access to the object that provides the L</json_prettyprint> method.

=head1 ACKNOWLEDGEMENTS

=for stopwords Perrett Signes

Daniel Perrett <perrettdl@cpan.org> for the concept and help in design.

Ricardo Signes <rjbs@cpan.org> for direction to and creation of Test::Fatal.

Various others in #perl-help.

=head1 SUPPORT

You can also find me on the L<JSON Schema Slack server|https://json-schema.slack.com> and L<OpenAPI Slack
server|https://open-api.slack.com>, which are also great resources for finding help.

=for stopwords OpenAPI

=head1 COPYRIGHT AND LICENCE

This distribution includes data from the L<https://json-schema.org> test suite, which carries its own
licence (see F<share/LICENSE>).

Permission is explicitly B<NOT> granted to repackage or redistribute this distribution with any
files altered or added (such as with a different set of test data) than what was originally
published to the Perl Programming Authors Upload Server (PAUSE), as dependencies of this
distribution have specific expectations as to the contents of this test data depending on version.
If it is desired to use a different dataset at runtime, please refer to the L</test_dir>
configuration option.

=cut
