package MojoX::Renderer::Haml;

use warnings;
use strict;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';
use Mojo::Exception;
use Text::Haml;

our $VERSION = '0.990103';

sub build {
    my $self = shift->SUPER::new(@_);

    return sub { $self->_render(@_) }
}

my $ESCAPE = <<'EOF';
    my $v = shift;
    ref $v && ref $v eq 'Mojo::ByteStream'
      ? "$v"
      : Mojo::ByteStream->new($v)->xml_escape->to_string;
EOF

sub _render {
    my ($self, $r, $c, $output, $options) = @_;

    my $path;
    unless ($path = $c->stash->{'template_path'}) {
        $path = $r->template_path($options);
    }
    return unless defined $path;

    my $list = join ', ', sort keys %{$c->stash};
    my $cache = b("$path($list)")->md5_sum->to_string;

    $r->{_haml_cache} ||= {};

    my $t = $r->template_name($options);

    my $haml = $r->{_haml_cache}->{$cache};

    my %args = (app => $c->app, %{$c->stash});

    # Interpret again
    if ( $c->app->mode ne 'development' &&  $haml && $haml->compiled) {
        $haml->helpers_arg($c);

        $c->app->log->debug("Rendering cached $t.");
        $$output = $haml->interpret(%args);
    }

    # No cache
    else {
        $haml ||= Text::Haml->new(escape => $ESCAPE);

        $haml->helpers_arg($c);
        $haml->helpers($r->helpers);

        # Try template
        if (-r $path) {
            $c->app->log->debug("Rendering template '$t'.");
            $$output = $haml->render_file($path, %args);
        }

        # Try DATA section
        elsif (my $d = $r->get_data_template($c, $t)) {
            $c->app->log->debug("Rendering template '$t' from DATA section.");
            $$output = $haml->render($d, %args);
        }

        # No template
        else {
            $c->app->log->debug(qq/Template "$t" missing or not readable./);
            return;
        }
    }

    unless (defined $$output) {
        $$output = '';
        die(qq/Template error in "$t": / . $haml->error);
    }

    $r->{_haml_cache}->{$cache} ||= $haml;

    return ref $$output ? die($$output) : 1;
}

1;

=head2 NAME

MojoX::Renderer::Haml - Mojolicious renderer for HAML templates. 

=head2 SYNOPSIS

   my $haml = MojoX::Renderer::Haml->build(%$args, mojo => $app);

   # Add "haml" handler
   $app->renderer->add_handler(haml => $haml);

=head2 DESCRIPTION

This module is a renderer for L<HTML::Haml> templates. normally, you 
just want to use L<Mojolicious::Plugin::HamlRenderer>.

=head1 CREDITS

Marcus Ramberg

=head1 AUTHOR

Viacheslav Tykhanovskyi, C<viacheslav.t@gmail.com>.

Currently maintained by Breno G. de Oliveira, C<garu@cpan.org>.

=head1 COPYRIGHT

Copyright (C) 2008-2012, Viacheslav Tykhanovskyi.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl 5.10.

=cut
