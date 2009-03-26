
package Net::OAuth::Simple;

use warnings;
use strict;
our $VERSION = "0.9";

use URI;
use LWP;
use CGI;
use Carp;
require Net::OAuth::Request;
require Net::OAuth::RequestTokenRequest;
require Net::OAuth::AccessTokenRequest;
require Net::OAuth::ProtectedResourceRequest;


BEGIN {
    eval {  require Math::Random::MT };
    unless ($@) {
        Math::Random::MT->import(qw(srand rand));
    }
}

our @required_constructor_params = qw(consumer_key consumer_secret);
our @access_token_params         = qw(access_token access_token_secret);
our $UNAUTHORIZED                = "Unauthorized.";

=head1 NAME

Net::OAuth::Simple - a simple wrapper round the OAuth protocol

=head1 SYNOPSIS

First create a sub class of C<Net::OAuth::Simple> that will do you requests
for you.

    package Net::AppThatUsesOAuth;

    use strict;
    use base qw(Net::OAuth::Simple);


    sub new {
        my $class  = shift;
        my %tokens = @_;
        return $class->SUPER::new( tokens => \%tokens, 
                                   urls   => {
                                        authorization_url => ...,
                                        request_token_url => ...,
                                        access_token_url  => ...,
                                   });
    }

    sub view_restricted_resource {
        my $self = shift;
        return $self->make_restricted_request($url, 'GET');
    }

    sub update_restricted_resource {
        my $self = shift
        return $self->make_restricted_request($url, 'POST', %extra_params);    
    }
    1;


Then in your main app you need to do

    # Get the tokens from the command line, a config file or wherever 
    my %tokens  = get_tokens(); 
    my $app     = Net::AppThatUsesOAuth->new(%tokens);

    # Check to see we have a consumer key and secret
    unless ($app->consumer_key && $app->consumer_key) {
        die "You must go get a consumer key and secret from App\n";
    } 
    
    # If the app is authorized (i.e has an access token and secret)
    # Then look at a restricted resourse
    if ($app->authorized) {
        my $response = $app->view_restricted_resource;
        print $response->content."\n";
        exit;
    }


    # Otherwise the user needs to go get an access token and secret
    print "Go to ".$app->get_authorization_url."\n";
    print "Then hit return after\n";
    <STDIN>;

    my ($access_token, $access_token_secret) = $app->request_access_token;

    # Now save those values


Note the flow will be somewhat different for web apps since the request token 
and secret will need to be saved whilst the user visits the authorization url.

For examples go look at the C<Net::FireEagle> module and the C<fireeagle> command 
line script that ships with it. Also in the same distribution in the C<examples/>
directory is a sample web app.

=head1 METHODS

=cut

=head2 new [params]

Create a new OAuth enabled app - takes a hash of params.

One of the keys of the hash must be C<tokens>, the value of which
must be a hash ref with the keys:

=over 4

=item consumer_key

=item consumer_secret

=back

Then, when you have your per-use access token and secret you 
can supply

=over 4

=item access_token

=item access_secret

=back

Another key of the hash must be C<urls>, the value of which must 
be a hash ref with the keys 

=over 4

=item authorization_url

=item request_token_url

=item access_token_url

=back

=cut

sub new {
    my $class  = shift;
    my %params = @_;
    my $client = bless \%params, $class;

    # Verify arguments
    $client->_check;

    # Set up LibWWWPerl for HTTP requests
    $client->{browser} = LWP::UserAgent->new;

    # Client Object
    return $client;
}

# Validate required constructor params
sub _check {
    my $self = shift;
    use Data::Dumper;
    #die Dumper ($self);


    foreach my $param ( @required_constructor_params ) {
        unless ( defined $self->{tokens}->{$param} ) {
            die "Missing required parameter '$param'";
        }
    }
}

=head2 authorized

Whether the client has the necessary credentials to be authorized.

Note that the credentials may be wrong and so the request may still fail.

=cut

sub authorized {
    my $self = shift;
    foreach my $param ( @access_token_params ) {
        return 0 unless defined $self->{tokens}->{$param};
    }
    return 1;
}

=head2 signature_method [method]

The signature method to use. 

Defaults to HMAC-SHA1

=cut
sub signature_method {
    my $self = shift;
    $self->{signature_method} = shift if @_;
    return $self->{signature_method} || 'HMAC-SHA1';
}

=head2 tokens

Get all the tokens.

=cut
sub tokens {
    my $self = shift;
    if (@_) {
        my %tokens = @_;
        $self->{tokens} = \%tokens;
    }
    return %{$self->{tokens}||{}};
}

=head2 consumer_key [consumer key]

Returns the current consumer key.

Can optionally set the consumer key.

=cut

sub consumer_key {
    my $self = shift;
    $self->_token('consumer_key', @_);
}

=head2 consumer_secret [consumer secret]

Returns the current consumer secret.

Can optionally set the consumer secret.

=cut

sub consumer_secret {
    my $self = shift;
    $self->_token('consumer_secret', @_);
}


=head2 access_token [access_token]

Returns the current access token.

Can optionally set a new token.

=cut

sub access_token {
    my $self = shift;
    $self->_token('access_token', @_);
}

=head2 access_token_secret [access_token_secret]

Returns the current access token secret.

Can optionally set a new secret.

=cut

sub access_token_secret {
    my $self = shift;
    return $self->_token('access_token_secret', @_);
}

=head2 request_token [request_token]

Returns the current request token.

Can optionally set a new token.

=cut

sub request_token {
    my $self = shift;
    $self->_token('request_token', @_);
}


=head2 request_token_secret [request_token_secret]

Returns the current request token secret.

Can optionally set a new secret.

=cut

sub request_token_secret {
    my $self = shift;
    return $self->_token('request_token_secret', @_);
}

sub _token {
    my $self = shift;
    my $key  = shift;
    $self->{tokens}->{$key} = shift if @_;
    return $self->{tokens}->{$key};
}

=head2 authorization_url

Get the url the user needs to visit to authorize as a URI object.

Note: this is the base url - not the full url with the necessary OAuth params.

=cut
sub authorization_url {
    my $self = shift;
    return $self->_url('authorization_url', @_);
}


=head2 request_token_url 

Get the url to obtain a request token as a URI object.

=cut
sub request_token_url {
    my $self = shift;
    return $self->_url('request_token_url', @_);
}

=head2 access_token_url 

Get the url to obtain an access token as a URI object.

=cut
sub access_token_url {
    my $self = shift;
    return $self->_url('access_token_url', @_);
}

sub _url {
    my $self = shift;
    my $key  = shift;
    $self->{urls}->{$key} = shift if @_;
    my $url  = $self->{urls}->{$key} || return;;
    return URI->new($url);
}

# generate a random number
sub _nonce {
    return int( rand( 2**32 ) );
}

=head2 request_access_token

Request the access token and access token secret for this user.

The user must have authorized this app at the url given by
C<get_authorization_url> first.

Returns the access token and access token secret but also sets
them internally so that after calling this method you can
immediately call C<location> or C<update_location>.

=cut

sub request_access_token {
    my $self = shift;
    my $url  = $self->access_token_url;
    my $access_token_response = $self->_make_request(
        'Net::OAuth::AccessTokenRequest',
        $url, 'GET',
        token            => $self->request_token,
        token_secret     => $self->request_token_secret,
    );

    # Cast response into CGI query for EZ parameter decoding
    my $access_token_response_query =
      new CGI( $access_token_response->content );

    # Split out token and secret parameters from the access token response
    $self->access_token($access_token_response_query->param('oauth_token'));
    $self->access_token_secret($access_token_response_query->param('oauth_token_secret'));

    delete $self->{tokens}->{$_} for qw(request_token request_token_secret);

    die "ERROR: $url did not reply with an access token"
      unless ( $self->access_token && $self->access_token_secret );

    return ( $self->access_token, $self->access_token_secret );
}

=head2 request_request_token

Request the request token and request token secret for this user.

This is called automatically by C<get_authorization_url> if necessary.

=cut


sub request_request_token {
    my $self = shift;
    my $url  = $self->request_token_url;       
    my $request_token_response = $self->_make_request(
        'Net::OAuth::RequestTokenRequest',
        $url, 'GET');

    die "GET for $url failed: ".$request_token_response->status_line
      unless ( $request_token_response->is_success );

    # Cast response into CGI query for EZ parameter decoding
    my $request_token_response_query =
      new CGI( $request_token_response->content );

    # Split out token and secret parameters from the request token response
    $self->request_token($request_token_response_query->param('oauth_token'));
    $self->request_token_secret($request_token_response_query->param('oauth_token_secret'));

}

=head2 get_authorization_url [param[s]]

Get the URL to authorize a user as a URI object.

If you pass in a hash of params then they will added as parameters to the URL.

=cut

sub get_authorization_url {
    my $self   = shift;
    my %params = @_;
    my $url  = $self->authorization_url;
    if (!defined $self->request_token) {
        $self->request_request_token;
    }
    $params{oauth_token} = $self->request_token;
    $url->query_form(%params);
    return $url;
}

=head2 make_restricted_request <url> <HTTP method> [extra[s]]

Make a request to C<url> using the given HTTP method.

Any extra parameters can be passed in as a hash.

=cut
sub make_restricted_request {
    my $self     = shift;

    croak $UNAUTHORIZED unless $self->authorized;

    my $url      = shift;
    my $method   = shift;
    my %extras   = @_;
    my $response = $self->_make_request(
        'Net::OAuth::ProtectedResourceRequest',
        $url, $method,
        token            => $self->access_token,
        token_secret     => $self->access_token_secret,
        extra_params     => \%extras
    );
    return $response;
}

sub _make_request {
    my $self    = shift;

    my $class   = shift;
    my $url     = shift;
    my $method  = lc(shift);
    my %extra   = @_;

    my $uri   = URI->new($url);
    my %query = $uri->query_form;
    $uri->query_form({});

    my $request = $class->new(
        consumer_key     => $self->consumer_key,
        consumer_secret  => $self->consumer_secret,
        request_url      => $uri,
        request_method   => uc($method),
        signature_method => $self->signature_method,
        timestamp        => time,
        nonce            => $self->_nonce,
        extra_params     => \%query,
        %extra,
    );
    $request->sign;
    die "COULDN'T VERIFY! Check OAuth parameters.\n"
      unless $request->verify;

    my $params = $request->to_hash;
    my $request_url = URI->new($url);
    $request_url->query_form(%$params);
    my $response    = $self->{browser}->$method($request_url);
    die "$method on $request_url failed: ".$response->status_line
      unless ( $response->is_success );

    return $response;
}

=head2 load_tokens <file>

A convenience method for loading tokens from a config file.

Returns a hash with the token names suitable for passing to 
C<new()>.

Returns an empty hash if the file doesn't exist.

=cut
sub load_tokens {
    my $class  = shift;
    my $file   = shift;
    my %tokens = ();
    return %tokens unless -f $file;

    open(my $fh, $file) || die "Couldn't open $file: $!\n";
    while (<$fh>) {
        chomp;
        next if /^#/;
        next if /^\s*$/;
        next unless /=/;
        s/(^\s*|\s*$)//g;
        my ($key, $val) = split /\s*=\s*/, $_, 2;
        $tokens{$key} = $val;
    }
    close($fh);
    return %tokens;
}

=head2 save_tokens <file> [token[s]]

A convenience method to save a hash of tokens out to the given file.

=cut
sub save_tokens {
    my $class  = shift;
    my $file   = shift;
    my %tokens = @_;

    open(my $fh, ">$file") || die "Couldn't open $file for writing: $!\n";
    foreach my $key (sort keys %tokens) {
        print $fh "$key = ".$tokens{$key}."\n";
    }
    close($fh);
}

=head1 GOOGLE'S SCOPE PARAMETER

Google's OAuth API requires the non-standard C<scope> parameter to be set 
in C<request_token_url>, and you also explicitly need to pass an C<oauth_callback> 
to C<get_authorization_url()> method, so that you can direct the user to your site 
if you're authenticating users in Web Application mode. Otherwise Google will let 
user grant acesss as a desktop app mode and doesn't redirect users back.

Here's an example class that uses Google's Portable Contacts API via OAuth:

    package Net::AppUsingGoogleOAuth;
    use strict;
    use base qw(Net::OAuth::Simple);

    sub new {
        my $class  = shift;
        my %tokens = @_;
        return $class->SUPER::new(
            tokens => \%tokens, 
            urls   => {
                request_token_url => "https://www.google.com/accounts/OAuthGetRequestToken?scope=http://www-opensocial.googleusercontent.com/api/people",
                authorization_url => "https://www.google.com/accounts/OAuthAuthorizeToken",
                access_token_url  => "https://www.google.com/accounts/OAuthGetAccessToken",
            },
        );
    }

    package main;
    my $oauth = Net::AppUsingGoogleOAuth->new(%tokens);

    # Web application
    $app->redirect( $oauth->get_authorization_url(oauth_callback => "http://you.example.com/oauth/callback") );

    # Desktop application
    print "Open the URL and come back once you're authenticated!\n",
        $oauth->get_authorization_url;

See L<http://code.google.com/apis/accounts/docs/OAuth.html> and other 
services API documentation for the possible list of I<scope> parameter value.

=head1 RANDOMNESS

If C<Math::Random::MT> is installed then any nonces generated will use a 
Mersenne Twiser instead of Perl's built in randomness function.

=head1 BUGS

Non known

=head1 DEVELOPERS

The latest code for this module can be found at

    https://svn.unixbeard.net/simon/Net-OAuth-Simple

=head1 AUTHOR

Simon Wistow, C<<simon@thegestalt.org >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-oauth-simple at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-OAuth-Simple>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::OAuth::Simple


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-OAuth-Simple>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-OAuth-Simple>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-OAuth-Simple>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-OAuth-Simple/>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2009 Simon Wistow, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Net::OAuth::Simple