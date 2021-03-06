package FixMyStreet::App::Controller::Dashboard;
use Moose;
use namespace::autoclean;

use DateTime;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

FixMyStreet::App::Controller::Dashboard - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 check_page_allowed

Checks if we can view this page, and if not redirect to 404.

=cut

sub check_page_allowed : Private {
    my ( $self, $c ) = @_;

    $c->detach( '/auth/redirect' ) unless $c->user_exists;

    $c->detach( '/page_error_404_not_found' )
        unless $c->user_exists && $c->user->from_council;

    return $c->user->from_council;
}

=head2 index

Show the dashboard table.

=cut

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;

    my $council = $c->forward('check_page_allowed');

    # Set up the data for the dropdowns

    my $children = mySociety::MaPit::call('area/children', $council,
        type => $mySociety::VotingArea::council_child_types,
    );
    $c->stash->{children} = $children;

    # XXX Hmm, this is probably the best way to go
    $c->stash->{all_councils} = { $council => { id => $council } };
    $c->forward( '/report/new/setup_categories_and_councils' );

    # See if we've had anything from the dropdowns

    $c->stash->{ward} = $c->req->param('ward');
    $c->stash->{category} = $c->req->param('category');
    $c->stash->{q_state} = $c->req->param('state');

    my %where = (
        council => $council, # XXX This will break in a two tier council. Restriction needs looking at...
        'problem.state' => [ FixMyStreet::DB::Result::Problem->visible_states() ],
    );
    $where{areas} = { 'like', '%,' . $c->stash->{ward} . ',%' }
        if $c->stash->{ward};
    $where{category} = $c->stash->{category}
        if $c->stash->{category};
    if ( $c->stash->{q_state} eq 'fixed' ) {
        $where{'problem.state'} = [ FixMyStreet::DB::Result::Problem->fixed_states() ];
    } elsif ( $c->stash->{q_state} ) {
        $where{'problem.state'} = $c->stash->{q_state}
    }

    my %counts;
    my $t = DateTime->today;

    $counts{wtd} = $c->forward( 'updates_search', [ {
        %where,
        'me.confirmed' => { '>=', $t->subtract( days => $t->dow - 1 )
    } } ] );

    $counts{week} = $c->forward( 'updates_search', [ {
        %where,
        'me.confirmed' => { '>=', DateTime->now->subtract( weeks => 1 )
    } } ] );

    $counts{weeks} = $c->forward( 'updates_search', [ {
        %where,
        'me.confirmed' => { '>=', DateTime->now->subtract( weeks => 4 )
    } } ] );

    $counts{ytd} = $c->forward( 'updates_search', [ {
        %where,
        'me.confirmed' => { '>=', DateTime->today->set( day => 1, month => 1 )
    } } ] );

    $c->stash->{problems} = \%counts;
}

sub updates_search : Private {
    my ( $self, $c, $params ) = @_;

    my $comments = $c->model('DB::Comment')->search(
        $params,
        {
            group_by => [ 'problem_state' ],
            select   => [ 'problem_state', { count => 'me.id' } ],
            as       => [ qw/state state_count/ ],
            join     => 'problem'
        }
    );

    my %counts =
      map { ($_->state||'-') => $_->get_column('state_count') } $comments->all;
    %counts =
      map { $_ => $counts{$_} || 0 }
      ('confirmed', 'investigating', 'in progress', 'closed', 'fixed - council',
          'fixed - user', 'fixed', 'unconfirmed', 'hidden',
          'partial', 'planned');

    $counts{fixed_user} = $c->model('DB::Comment')->search(
        { %$params, mark_fixed => 1 }, { join     => 'problem' }
    )->count;

    $params->{state} = $params->{'problem.state'};
    delete $params->{'problem.state'};
    $counts{total} = $c->cobrand->problems->search( $params )->count;

    return \%counts;
}

=head1 AUTHOR

Matthew Somerville

=head1 LICENSE

Copyright (c) 2012 UK Citizens Online Democracy. All rights reserved.
Licensed under the Affero GPL.

=cut

__PACKAGE__->meta->make_immutable;

1;

