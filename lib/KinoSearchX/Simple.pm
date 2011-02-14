package KinoSearchX::Simple;

our $VERSION = '0.08';
$VERSION = eval $VERSION;

use 5.008;

use Moose;
use namespace::autoclean;

use Moose::Util::TypeConstraints;

subtype 'LoadClass' 
    => as 'ClassName';

coerce 'LoadClass' 
    => from 'Str'
    => via { Class::MOP::load_class($_); $_ };

no Moose::Util::TypeConstraints;

use KinoSearch1::InvIndexer;
use KinoSearch1::Searcher;
use KinoSearch1::Analysis::PolyAnalyzer;
use KinoSearch1::Index::Term;
use KinoSearch1::QueryParser::QueryParser;
use KinoSearch1::Search::TermQuery;

use Data::Page;

has _language => (
    'is' => 'ro',
    'isa' => 'Str',
    'default' => 'en',
    'init_arg' => 'language',
);

has _index_path => (
    'is' => 'ro',
    'isa' => 'Str',
    'required' => 1,
    'init_arg' => 'index_path',
);

has _analyser => (
    'is' => 'ro',
    'init_arg' => undef,
    'default' => sub { return KinoSearch1::Analysis::PolyAnalyzer->new( language => shift->_language ) },
);

has schema => (
    'is' => 'ro',
    'isa' => 'ArrayRef[HashRef]',
    'required' => 1,
);

has _indexer => (
    'is' => 'ro',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__indexer{
    my $self = shift;

    my $indexer = KinoSearch1::InvIndexer->new(
        'invindex' => $self->_index_path,
        'create'   => ( -f $self->_index_path . '/segments' ) ? 0 : 1,
        'analyzer' => $self->_analyser,
    );

    foreach my $spec ( @{$self->schema} ){
        $indexer->spec_field( %{$spec} );
    }

    return $indexer;
}

has _searcher => (
    'is' => 'ro',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__searcher{
    my $self = shift;

    return KinoSearch1::Searcher->new(
        'invindex' => $self->_index_path,
        'analyzer' => $self->_analyser,
    );
}

has search_fields => (
    'is' => 'ro',
    'isa' => 'ArrayRef[Str]',
    'required' => 1,
);

has search_boolop => (
    'is' => 'ro',
    'isa' => 'Str',
    'default' => 'OR',
);

has _query_parser => (
    'is' => 'ro',
    'init_arg' => undef,
    'lazy_build' => 1,
);

sub _build__query_parser{
    my $self = shift;

    return KinoSearch1::QueryParser::QueryParser->new(
        'analyzer'       => $self->_analyser,
        'fields'         => $self->search_fields,
        'default_boolop' => $self->search_boolop,
    );
}

has resultclass => (
    'is' => 'rw',
    'isa' => 'LoadClass',
    'coerce' => 1,
    'lazy' => 1,
    'default' => 'KinoSearchX::Simple::Result::Object',
);

has entries_per_page => (
    'is' => 'rw',
    'isa' => 'Num',
    'lazy' => 1,
    'default' => 100,
);

sub search{
    my ( $self, $query_string, $page ) = @_;

    return undef if ( !$query_string );
    $page ||= 1;

    my $query = $self->_query_parser->parse( $query_string );

    my $hits = $self->_searcher->search( 'query' => $query );
    my $pager = Data::Page->new($hits->total_hits, $self->entries_per_page, $page);
    $hits->seek( $pager->skipped, $pager->entries_on_this_page );

    my @results;
    while ( my $hit = $hits->fetch_hit_hashref ) {
        push( @results, $self->resultclass->new($hit) );
    }

    return ( \@results, $pager ) if scalar(@results);
    return undef;
}

sub create{
    my ( $self, $document ) = @_;

    return undef if ( !$document );

    my $doc = $self->_indexer->new_doc;

    foreach my $key ( keys(%{$document}) ){
        $doc->set_value(
            $key => $document->{$key},
        );
    }
    $self->_indexer->add_doc($doc);
}

sub update_or_create{
    my ( $self, $document, $pk ) = @_;

    return undef if ( !$document );
    $pk ||= 'id';
    my $pv = $document->{ $pk };

    return undef if ( !$pv );
    $self->delete( $pk, $pv );
    $self->commit;

    $self->create( $document );
}

sub delete{
    my ( $self, $key, $value ) = @_;

    return undef if ( !$key || !$value );

    #delete only works on finished indexes
    $self->commit;
    my $term = KinoSearch1::Index::Term->new( $key => $value );
    $self->_indexer->delete_docs_by_term($term);
}

sub commit{
    my ( $self ) = @_;

    $self->_indexer->finish( 'optimize' => 1 );

    #clear the searcher and indexer
    # they're lazy so they get rebuilt on next call...
    $self->_clear_indexer;
    $self->_clear_searcher;
}

__PACKAGE__->meta->make_immutable;

=head1 NAME

KinoSearchX::Simple - Simple L<KinoSearch1> Interface

=head1 SYNOPSIS

    use KinoSearchX::Simple;

    my $searcher = KinoSearchX::Simple->new(
        'index_path' => '/tmp/search_index',
        'schema' => [
            {
                'name' => 'title',
                'boost' => 3,
            },{
                'name' => 'description',
            },{
                'name' => 'id',
                'analysed' => 0, #you don't want the analyser to adjust your id do you?
            },
        ],
        'search_fields' => ['title', 'description'],
        'search_boolop' => 'AND',
    );

    $searcher->create({
        'id' => 1,
        'title' => 'fibble',
        'description' => 'wibble',
    });

    #important - always commit after updating the index!
    $searcher->commit;

    my ( $results, $pager ) = $searcher->search( 'fibble' );

=head1 DESCRIPTION

Simple interface to L<KinoSearch1>. Use if you want to use L<KinoSearch1> and are lazy :p

=head1 METHODS

=head2 B<search>( $query_string, $page ) - search index

    my ( $results, $pager ) = $searcher->search( $query, $page );

=head2 B<create>( $document ) - add item to index

    $searcher->create({
        'id' => 1,
        'title' => 'this is the title',
        'description' => 'this is the description',
    });

not that it has to be, but its highly recommended that I<id> is a unique identifier for this document 

or you'll have to pass $pk to update_or_create

=head2 B<update_or_create>( $document, $pk ) - updates or creates document in the index

    $searcher->update_or_create({
        'id' => 1,
        'title' => 'this is the updated title',
        'description' => 'this is the description',
    }, 'id');

$pk is the unique key to lookup by, defaults to 'id'

=head2 B<delete>( $key, $value ) - remove document from the index

    $searcher->delete( 'id', 1 );

finds $key with $value and removes from index

=head2 B<commit>() - commits and optimises index after adding documents

    $searcher->commit();

you must call this after you have finished doing things to the index

=head1 ADVANCED

when creating the KinoSearchX::Simple object you can specify some advanced options

=head2 language

set's language for default _analyser of L<KinoSearch1::Analysis::PolyAnalyzer>

=head2 _analyser

set analyser, defualts to L<KinoSearch1::Analysis::PolyAnalyzer>

=head2 search_fields

fields to search by default, takes an arrayref

=head2 search_boolop

can be I<OR> or I<AND>

search boolop, defaults to or. e.g the following query

    "this is search query"

becomes

    "this OR is OR search OR query"

can be changed to I<AND>, in which case the above becomes

    "this AND is AND search AND query"

=head2 resultclass

resultclass for results, defaults to L<KinoSearchX::Simple::Result::Object> which creates acessors for each key => value returned

could be changed tp KinoSearchX::Simple::Result::Hash for a plain old, hashref or a custom class

=head2 entries_per_page

default is 100

=head1 SUPPORT

Bugs should always be submitted via the CPAN bug tracker

For other issues, contact the maintainer

=head1 AUTHORS

n0body E<lt>n0body@thisaintnews.comE<gt>

=head1 SEE ALSO

L<http://thisaintnews.com>, L<Image::Info>

=head1 LICENSE

Copyright (C) 2011 by n0body L<http://thisaintnews.com/>

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
