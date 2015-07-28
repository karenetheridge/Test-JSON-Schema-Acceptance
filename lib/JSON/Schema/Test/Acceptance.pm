package JSON::Schema::Test::Acceptance;

use 5.006;
use strict;
use warnings;

use Test::More;
use Cwd 'abs_path';
use JSON;

use JSON::Schema;
use Data::Dumper;

use Carp::Always;

=head1 NAME

JSON::Schema::Test::Acceptance - Acceptance testing for JSON-Schema based validators like JSON::Schema

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use JSON::Schema::Test::Acceptance;

    my $foo = JSON::Schema::Test::Acceptance->new();
    ...

=head1 SUBROUTINES/METHODS

# =head2 function1

=cut

sub new {
  my $class = shift;
  return bless {}, $class;
}

sub acceptance {
  my ($self, $code, $options) = @_;
  my $tests = $self->_load_tests;

  my $skip_tests = $options->{skip_tests} // {};

  $self->_run_tests($code, $tests, $skip_tests);


  # foreach my $case (@{$self->cases}) {
  #   my $input  = $case->{input};
  #   my $schema = $case->{schema};
  #   my $output = $case->{output};
  #   my $result = $code->($input, $schema);
  # }


}


sub _test_testing {
  my $accepter = shift->new();

  #Skip tests which are known not to be supported and cause problems.
  my $skip_tests = ['multiple extends'];

  $accepter->acceptance(sub{
    my $schema = shift;
    my $input = shift;
    my $return;



    # my $json = JSON->new;

    # my $test_case = from_json('
    #   {
    #     "schema": {
    #         "additionalProperties": {"type": "boolean"}
    #     },
    #     "data": {"foo" : true}
    #   }'
    # );
    # $schema = $test_case->{schema};
    # $input = $json->encode($test_case->{data});

    # warn "input";
    # warn Dumper($input);
    # warn "schema";
    # warn Dumper($schema);

    # eval{$return = JSON::Schema->new($schema)->validate($input)};
    $return = JSON::Schema->new($schema)->validate($input);
    # warn Dumper($input) if $@;
    # warn Dumper($input) if $@;
    # fail $@ if $@;
    # warn Dumper($return);
    return $return;
  }, {skip_tests => $skip_tests});

  done_testing();
}

sub _validate {}

sub _run_tests {
  my $self = shift;
  my $code = shift;
  my $tests = shift;
  my $skip_tests = shift;

  my $json = JSON->new;

  foreach my $test_group (@{$tests}) {

    foreach my $test_group_test (@{$test_group}){

      my $test_group_cases = $test_group_test->{tests};
      my $schema = $test_group_test->{schema};

      foreach my $test (@{$test_group_cases}) {

        my $subtest_name = $test_group_test->{description} . ' - ' . $test->{description};

        TODO: {
          todo_skip 'Test explicitly skipped. - '  . $subtest_name, 1
            if grep { $subtest_name =~ /$_/} @$skip_tests;

        subtest $subtest_name, sub {
          # Current workaround for dealing with data which is not a json object or array
          # https://github.com/json-schema/JSON-Schema-Test-Suite/issues/102

          my $result;
          if(ref($test->{data}) eq 'ARRAY' || ref($test->{data}) eq 'HASH'){
            $result = $code->($schema, $json->encode($test->{data}));
          } else {
            $result = $code->($schema, $json->encode([$test->{data}]));
          }

            ok(_eq_bool($test->{valid}, $result), $test_group_test->{description} . ' - ' . $test->{description});
          }

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
    # my $parsed_json = JSON->new->allow_nonref->decode($raw_json);
    my $parsed_json = JSON::from_json($raw_json);

    push @test_groups, $parsed_json;
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

Please report any bugs or feature requests to C<bug-json-schema-test-acceptance at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=JSON-Schema-Test-Acceptance>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc JSON::Schema::Test::Acceptance


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=JSON-Schema-Test-Acceptance>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/JSON-Schema-Test-Acceptance>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/JSON-Schema-Test-Acceptance>

=item * Search CPAN

L<http://search.cpan.org/dist/JSON-Schema-Test-Acceptance/>

=back


=head1 ACKNOWLEDGEMENTS


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
