package KinoSearchX::Simple::Result;
use Moose;
use namespace::autoclean;

sub BUILD{
    my ( $self, $config ) = @_;

    foreach my $key ( keys(%{$config}) ){
        has $key => (
            'is' => 'ro',
            'isa' => 'Any',
            'lazy' => 1,
            'default' => $config->{$key},
        );
    }
}

no Moose;

1;
#don't make immutable coz then we can't add things in BUILD...
