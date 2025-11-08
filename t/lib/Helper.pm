# vim: set ft=perl ts=8 sts=2 sw=2 tw=100 et :
# no package, so things defined here appear in the namespace of the parent.
use strictures 2;
use 5.020;
use stable 0.031 'postderef';
use experimental 'signatures';
no autovivification warn => qw(fetch store exists delete);
use if "$]" >= 5.022, experimental => 're_strict';
no if "$]" >= 5.031009, feature => 'indirect';
no if "$]" >= 5.033001, feature => 'multidimensional';
no if "$]" >= 5.033006, feature => 'bareword_filehandles';
no if "$]" >= 5.041009, feature => 'smartmatch';
no feature 'switch';
use open ':std', ':encoding(UTF-8)'; # force stdin, stdout, stderr into utf8

sub failing_test_names ($events) {
  my $sub = sub (@events) {
    map +(
      ($_->{pass}//1) ? () : (
        $_->{name},
        $_->{subevents}
          ? (map +('  '.$_), __SUB__->($_->{subevents}->@*))
          : (),
      )
    ),
    @events
  };

  $sub->($events->flatten(args => [ include_subevents => 1 ])->@*);
}

1;
