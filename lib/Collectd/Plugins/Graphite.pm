package Collectd::Plugins::Graphite;

use strict;
use warnings;

use IO::Socket;
use threads;
use threads::shared;

use Collectd qw( :all );

=head1 NAME

Collectd::Plugins::Graphite - Send collectd metrics to graphite

=head1 VERSION

Version 1

=cut

our $VERSION = '3';


=head1 SYNOPSIS

This is a collectd plugin for sending collectd metrics to graphite.

In your collectd config:

    <LoadPlugin "perl">
    	Globals true
    </LoadPlugin>

    <Plugin "perl">
      BaseName "Collectd::Plugins"
      LoadPlugin "Graphite"

    	<Plugin "Graphite">
    	  Buffer "256000"
    	  Prefix "servers"
    	  Host   "graphite.example.com"
    	  Port   "2003"
    	</Plugin>
    </Plugin>
   
To have COUNTER datatypes sent as differences between the previous
value and the current value (which is useful for graphing things
where you care about the change in counter value, rather than the
value itself), use the following configuration:

    <LoadPlugin "perl">
        Globals true
    </LoadPlugin>

    <Plugin "perl">
      BaseName "Collectd::Plugins"
      LoadPlugin "Graphite"

        <Plugin "Graphite">
          Buffer "256000"
          Prefix "servers"
          Host   "graphite.example.com"
          Port   "2003"
          DifferentiateCounters "true"
        </Plugin>
    </Plugin>
 
=head1 AUTHOR

Joe Miller, C<< <joeym at joeym.net> >>

=head1 BUGS

Please report any bugs or feature requests in the Issues
section of the github page: L<https://github.com/joemiller/collectd-graphite/issues>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Collectd::Plugins::Graphite


You can also look for more information at:

    L<https://github.com/joemiller/collectd-graphite>

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2011 Joe Miller.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       L<http://www.apache.org/licenses/LICENSE-2.0>

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

=cut


my $buff = '';
my $sock_timeout  = 10;

# Shared between all Perl threads
my %prev_value :shared;

# config vars.  These can be overridden in collectd.conf
my $buffer_size   = 8192;
my $prefix        = 'collectd';
my $graphite_host = 'localhost';
my $graphite_port = 2003;
my $diff_counters = 0;


sub graphite_config {
    my ($ci) = @_;

    foreach my $item (@{$ci->{'children'}}) {
        my $key = $item->{'key'};
        my $val = $item->{'values'}->[0];

        if ( $key =~ /buffer/i ) {
            $buffer_size = $val;
        } elsif ( $key =~ /prefix/i ) {
            $prefix = $val;
        } elsif ( $key =~ /host/i ) {
            $graphite_host = $val;
        } elsif ( $key =~ /port/i ) {
            $graphite_port = $val;
        } elsif ( $key =~ /differentiatecounters/i ) {
            if ($val =~ /true/i) {
                $diff_counters = 1;
                plugin_log(LOG_INFO, "collectd-graphite: DifferentiateCounters set to true");
		        plugin_log(LOG_INFO, "collectd-graphite: DS_TYPE_COUNTER types will be sent as differences from previous value");
            } else {
                $diff_counters = 0;
            }
        }
    }

    return 1;
}

sub graphite_write {
    my ($type, $ds, $vl) = @_;

    my $host = $vl->{'host'};
    $host =~ s/\./_/g;

    my $plugin_str = $vl->{'plugin'};
    my $type_str   = $vl->{'type'};
    
    if ( defined $vl->{'plugin_instance'} ) {
        $plugin_str .=  "-" . $vl->{'plugin_instance'};
    }
    if ( defined $vl->{'type_instance'} ) {
        $type_str .= "-" . $vl->{'type_instance'};
    }
    
    for (my $i = 0; $i < scalar (@$ds); ++$i) {
        my $graphite_path = sprintf "%s.%s.%s.%s.%s",
            $prefix,
            $host,
            $plugin_str,
            $type_str,
            $ds->[$i]->{'name'};
            
        # convert any spaces that may have snuck in
        $graphite_path =~ s/\s+/_/g;
    
        # Send difference between previous + current value for counters/derives 
        if ($diff_counters and $ds->[$i]->{'type'} == DS_TYPE_COUNTER) { 
            {
                # Shared data; lock
                lock %prev_value;
                my $new_value = $vl->{'values'}->[$i];

                # value can apparently be undef, according to the Collectd Perl documentation
                if (defined $prev_value{$graphite_path} and defined $new_value) {
                    my $old_value = $prev_value{$graphite_path};

                    # Overflowed - return value wrapped around max
                    if ($old_value > $new_value) {
                        my $max = $vl->{'values'}->[$i] = $ds->[$i]->{'max'};
                        my $min = $vl->{'values'}->[$i] = $ds->[$i]->{'min'};
                        if (defined $max and defined $min) {
                            $vl->{'values'}->[$i] = ($max - $old_value) + ($new_value - $min); 
                        } else {
                            $vl->{'values'}->[$i] = undef;
                        }
                    } else {
                        $vl->{'values'}->[$i] = $new_value - $old_value;
                    }
                }
                $prev_value{$graphite_path} = $new_value if defined $new_value; 
            }
        }
 
        $buff .= sprintf  "%s %s %d\n",
            $graphite_path,
            $vl->{'values'}->[$i],
            $vl->{'time'};
    }

    # This is a best effort.  If sending to graphite fails, we
    # do not try again, this chunk of data will be lost.
    
    if ( length($buff) >= $buffer_size ) {
        send_to_graphite();
    }
    return 1;
}

sub send_to_graphite {
     return 0 if length($buff) == 0;
     my $sock = IO::Socket::INET->new(PeerAddr => $graphite_host,
                                      PeerPort => $graphite_port,
                                      Proto    => 'tcp',
                                      Timeout  => $sock_timeout);
     unless ($sock) {
         plugin_log(LOG_ERR, "Graphite.pm: failed to connect to " .
                             "$graphite_host:$graphite_port : $!");
         return 0;
     }
     print $sock $buff;
     close($sock);
     $buff = '';
     return 1;
}

sub graphite_flush {
    send_to_graphite();
    return 1;
}

plugin_register (TYPE_CONFIG, "Graphite", "graphite_config");
plugin_register (TYPE_WRITE, "Graphite", "graphite_write");
plugin_register (TYPE_FLUSH, "Graphite", "graphite_flush");

1; # End of Collectd::Plugins::Graphite
