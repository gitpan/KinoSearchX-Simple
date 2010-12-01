package KinoSearchX::Simple::Result::Object;

use Moose;
use namespace::autoclean;

sub BUILD{
    my ( $self, $data ) = @_;

    foreach my $key ( keys(%{$data}) ){
        has $key => (
            'is' => 'ro',
            'isa' => 'Any',
            'lazy' => 1,
            'default' => $data->{$key},
        );
    }
}

no Moose;

1;
#don't make immutable coz then we can't add things in BUILD...
