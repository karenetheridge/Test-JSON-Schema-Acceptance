package JSON::Schema::Test::Acceptance;

use 5.006;
use strict;
use warnings;

use Test::More;
use Cwd 'abs_path';
use JSON;

use Data::Dumper;

=head1 NAME

JSON::Schema::Test::Acceptance - Acceptance testing for JSON-Schema based validators like JSON::Schema

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

plan tests => 1;

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use JSON::Schema::Test::Acceptance;

    my $foo = JSON::Schema::Test::Acceptance->new();
    ...

=head1 SUBROUTINES/METHODS

# =head2 function1

=cut

sub acceptance {
  my ($self, $code) = @_;
  foreach my $case (@{$self->cases}) {
    my $input  = $case->{input};
    my $schema = $case->{schema};
    my $output = $case->{output};
    my $result = $code->($input, $schema);
    # Don't think this is the correct test method to use. Check this.
    # is_deeply $result, $output, $case->{name};

  }
}

sub _load_tests {

  my $mod_dir = abs_path(__FILE__) =~ s~Acceptance\.pm~/test_suite~r; # Find the modules directory... ~

  my $draft_dir = $mod_dir . '/tests/draft3/';

  # opendir (my $dir, $draft_dir) ;
  # my @tests = grep { -f "$draft_dir/$_"} readdir $dir;
  # closedir $dir;

  # warn Dumper(\@tests);
  # foreach my $file (@tests) {
  #   #some stuff
  #   # open ( my $fh, '<', $file ) or die ("Could not open schema file $fn for read");
  # }

  my $fn = $draft_dir . "required.json";
  open ( my $fh, '<', $fn ) or die ("Could not open schema file $fn for read");
  my $raw_json = '';
  $raw_json .= $_ while (<$fh>);
  my $parsed_json = JSON::from_json($raw_json);

  warn 'the json';
  warn Dumper($parsed_json);

  my @test_tests = @{$parsed_json};

  my $test = $test_tests[0];
  warn 'the test';
  warn Dumper($test);

  my $t_description = $test->{description};
  my $test_test_cases = $test->{tests};
  my $schema = $test->{schema};

  # Just while developing...
  use JSON::Schema;

  my $validator = JSON::Schema->new($schema);
  my $result = $validator->validate($test_test_cases->[0]->{data});

  warn 'results';
  warn Dumper($result);
  warn 'test test case';
  warn Dumper($test_test_cases->[0]);


  warn 'is OK?';
  ok(!($test_test_cases->[0]->{valid} xor $result));

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
