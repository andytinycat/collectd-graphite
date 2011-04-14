Collectd-Graphite Plugin
========================

This plugin acts as bridge between collectd's huge base
of available plugins and graphite's excellent graphing
capabilities.  It sends collectd data directly
to your graphite server.

This plugin was inspired by the great [collectd-to-graphite](https://github.com/loggly/collectd-to-graphite)
tool written by the prolific loggly engineer Jordan Sissel.
Jordan's implementation uses an external process to bridge
collectd to graphite.  I did not want another process to
manage or worry about, so I wrote a plugin for collectd
instead.

It is implemented using the [collectd-perl](http://collectd.org/documentation/manpages/collectd-perl.5.shtml)
interface.


INSTALLATION
------------

Make sure collectd and the collectd-perl module are installed.

This was tested on CentOS 5 using the collectd rpm from EPEL.
Feedback on installing on other platforms is welcome.

To install this module, run the following commands:

	perl Makefile.PL
	make
	make test
	make install


CONFIGURATION
-------------

Add the following to your collectd.conf:

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


NETWORK TRAFFIC
---------------

Metrics are stored in an 8KB buffer before being
sent to graphite in order to take reduce network
overhead.  The buffer size is configurable in the
config file.

Data is sent to graphite on a "best effort" 
basis.  If the graphite server is down or the tcp 
connection fails, you will lose that buffer's worth
of data.
 

GRAPHITE PATHS
--------------

Graphite paths are constructed according to Collectd's standard
serialized form, eg:

	prefix.host_name.plugin[-plugin_instance].type[-type_instance].metric_name

Examples of valid paths:

	collectd.host1_example_com.cpu-0.cpu-idle.value
	collectd.host2_example_com.disk-sda.disk_octets.read
	collectd.host3_example_com.load.load.shortterm
	collectd.host3_example_com.interface.if_octets-eth0.rx

The default prefix is 'collectd'.  This can be overriden in the 
collectd config file.

There are pro and cons to this approach, since different plugins use
a type_instance when they should use plugin_instance.  See here for
further explanation:

    http://collectd.org/wiki/index.php/Naming_schema#Plugin_instance_and_type_instance


SUPPORT AND DOCUMENTATION
-------------------------

After installing, you can find documentation for this module with the
perldoc command.

    perldoc Collectd::Plugins::Graphite

You can also look for information on the github page:

	https://github.com/joemiller/collectd-graphite

Please use the github issues page for bugs and feedback.  Pull
requests are also welcome!

	https://github.com/joemiller/collectd-graphite/issues


FUTURE?
-------

- Support sending data to graphite via AMQP
- Re-write in C if collectd-perl interface proves problematic


LICENSE AND COPYRIGHT
---------------------

Copyright 2011 Joe Miller.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.