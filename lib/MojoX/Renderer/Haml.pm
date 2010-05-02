package MojoX::Renderer::Haml;

use warnings;
use strict;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';
use Mojo::Exception;
use Text::Haml;

our $VERSION = '0.990101';

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

    my $list = join ', ', sort keys %{$c->stash};
    my $cache = b("$path($list)")->md5_sum->to_string;

    $r->{_haml_cache} ||= {};

    my $t = $r->template_name($options);

    my $haml = $r->{_haml_cache}->{$cache};

    my %args = (app => $c->app, %{$c->stash});

    # Interpret again
    if ($haml && $haml->compiled) {
        $haml->helpers_arg($c);

        $$output = $haml->interpret(%args);
    }

    # No cache
    else {
        $haml ||= Text::Haml->new(escape => $ESCAPE);

        $haml->helpers_arg($c);
        $haml->helpers($r->helper);

        # Try template
        if (-r $path) {
            $$output = $haml->render_file($path, %args);
        }

        # Try DATA section
        elsif (my $d = $r->get_inline_template($c, $t)) {
            $$output = $haml->render($d, %args);
        }

        # No template
        else {
            $c->app->log->error(qq/Template "$t" missing or not readable./);
            $c->render_not_found;
            return;
        }
    }

    unless (defined $$output) {
        $$output = '';

        my $e = Mojo::Exception->new($haml->error);

        $c->app->log->error( qq/Template error in "$t": / . $haml->error);

        $c->render_exception($e);

        return 0;
    }

    $r->{_haml_cache}->{$cache} ||= $haml;

    return 1;
}

1;