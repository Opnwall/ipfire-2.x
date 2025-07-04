#!/usr/bin/perl
# Generate Graphs exported from Makegraphs to minimize system load an only generate the Graphs when displayed
###############################################################################
#                                                                             #
# IPFire.org - A linux based firewall                                         #
# Copyright (C) 2005-2021  IPFire Team                                        #
#                                                                             #
# This program is free software: you can redistribute it and/or modify        #
# it under the terms of the GNU General Public License as published by        #
# the Free Software Foundation, either version 3 of the License, or           #
# (at your option) any later version.                                         #
#                                                                             #
# This program is distributed in the hope that it will be useful,             #
# but WITHOUT ANY WARRANTY; without even the implied warranty of              #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
# GNU General Public License for more details.                                #update.sh
#                                                                             #
# You should have received a copy of the GNU General Public License           #
# along with this program.  If not, see <http://www.gnu.org/licenses/>.       #
#                                                                             #
###############################################################################

package Graphs;

use strict;
use RRDs;
use experimental 'smartmatch';

require '/var/ipfire/general-functions.pl';
require "${General::swroot}/lang.pl";
require "${General::swroot}/header.pl";

# Approximate size of the final graph image including canvas and labeling (in pixels, mainly used for placeholders)
our %image_size = ('width' => 900, 'height' => 400);

# Size of the actual data area within the image, without labeling (in pixels)
our %canvas_size = ('width' => 800, 'height' => 290);

# List of all available time ranges
our @time_ranges = ("hour", "day", "week", "month", "year");

my $ERROR;

my @GRAPH_ARGS = (
	# Output format
	"--imgformat", "SVG",

	# No border
	"--border", "0",

	# For a more 'organic' look
	"--slope-mode",

	# Watermark
	"-W www.ipfire.org",

	# Canvas width/height
	"-w $canvas_size{'width'}",
	"-h $canvas_size{'height'}",

	# Use alternative grid
	"--alt-y-grid",
);


my %color = ();
my %mainsettings = ();
my %sensorsettings = ();
&General::readhash("${General::swroot}/main/settings", \%mainsettings);
&General::readhash("/srv/web/ipfire/html/themes/ipfire/include/colors.txt", \%color);

if ( $mainsettings{'RRDLOG'} eq "" ){
	$mainsettings{'RRDLOG'}="/var/log/rrd";
	&General::writehash("${General::swroot}/main/settings", \%mainsettings);
}

# If the collection deamon is working and collecting lm_sensors data there will be
# some data source named after a common scheme, with the sensorssettingsfile
# the user is able to deactivate some of this parameters, in case not to show
# false collected values may be disable. The user has the ability to enter
# custom graph names in order to change temp0 to cpu or motherboard

my $count = 0;
my @sensorsgraphs = ();
my @sensorsdir = `ls -dA $mainsettings{'RRDLOG'}/collectd/localhost/sensors-*/ 2>/dev/null`;
foreach (@sensorsdir){
	chomp($_);chop($_);
	foreach (`ls $_/*`){
		chomp($_);
		push(@sensorsgraphs,$_);
		$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
		my $label = $2.$3;$label=~ s/-//g;
		$sensorsettings{'LABEL-'.$label}="$label";
		$sensorsettings{'LINE-'.$label}="checked";
	}
}

&General::readhash("${General::swroot}/sensors/settings", \%sensorsettings);

# Generate a nice box for selection of time range in graphs
# this will generate a nice div box for the cgi every klick for
# the graph will be handled by javascript
# 0 is the cgi refering to
# 1 is the graph name
# 2 is the time range for the graph (optional)

sub makegraphbox {
	my ($origin, $name, $default_range) = @_;

	# Optional time range: Default to "day" unless otherwise specified
	$default_range = "day" unless ($default_range ~~ @time_ranges);

	print <<END;
		<div class="graph" id="rrdimg-$name" data-origin="$origin" data-graph="$name" data-default-range="$default_range">
			<img src="/cgi-bin/getrrdimage.cgi?origin=${origin}&graph=${name}&range=${default_range}" alt="$Lang::tr{'graph'} ($name)">

			<ul>
END

	# Print range select buttons
	foreach my $range (@time_ranges) {
		my $selected = ($range eq $default_range) ? "class=\"selected\"" : "";

		print <<END;
				<li>
					<button data-range="$range" onclick="rrdimage_selectRange(this)" $selected>
						$Lang::tr{$range}
					</button>
				</li>
END
	}

	print <<END;
			</ul>
		</div>
END
}

# Generate the CPU Graph for the current period of time for values given by
# collectd we are now able to handle any kind of cpucount

sub updatecpugraph {
	my $cpucount = `ls -dA $mainsettings{'RRDLOG'}/collectd/localhost/cpu-*/ 2>/dev/null | wc -l`;
	my $period    = $_[0];
	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-l 0",
		"-u 100",
		"-r",
		"-v ".$Lang::tr{'percentage'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-29s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

	my $nice = "CDEF:nice=";
	my $interrupt = "CDEF:interrupt=";
	my $steal = "CDEF:steal=";
	my $user = "CDEF:user=";
	my $system = "CDEF:system=";
	my $idle = "CDEF:idle=";
	my $iowait = "CDEF:iowait=";
	my $irq = "CDEF:irq=";
	my $addstring = "";

	for(my $i = 0; $i < $cpucount; $i++) {
		push(@command,"DEF:iowait".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-wait.rrd:value:AVERAGE"
				,"DEF:nice".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-nice.rrd:value:AVERAGE"
				,"DEF:interrupt".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-interrupt.rrd:value:AVERAGE"
				,"DEF:steal".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-steal.rrd:value:AVERAGE"
				,"DEF:user".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-user.rrd:value:AVERAGE"
				,"DEF:system".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-system.rrd:value:AVERAGE"
				,"DEF:idle".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-idle.rrd:value:AVERAGE"
				,"DEF:irq".$i."=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpu-".$i."/cpu-softirq.rrd:value:AVERAGE");

		$nice .= "nice".$i.",";
		$interrupt .= "interrupt".$i.",";
		$steal .= "steal".$i.",";
		$user .= "user".$i.",";
		$system .= "system".$i.",";
		$idle .= "idle".$i.",";
		$iowait .= "iowait".$i.",";
		$irq .= "irq".$i.",";
	}

	for(my $i = 2; $i < $cpucount; $i++) {
		$addstring .= "ADDNAN,";
	}

	if ( $cpucount > 1){
		$addstring .= "+";
		push(@command,$nice.$addstring
			,$interrupt.$addstring
			,$steal.$addstring
			,$user.$addstring
			,$system.$addstring
			,$idle.$addstring
			,$iowait.$addstring
			,$irq.$addstring);
	}else{
		chop($nice),chop($interrupt),chop($steal),chop($user),chop($system),chop($idle),chop($iowait),chop($irq);
		push(@command,$nice,$interrupt,$steal,$user,$system,$idle,$iowait,$irq);
	}

	push(@command,"CDEF:total=user,system,idle,iowait,irq,nice,interrupt,steal,ADDNAN,ADDNAN,ADDNAN,ADDNAN,ADDNAN,ADDNAN,ADDNAN"
			,"CDEF:userpct=100,user,total,/,*"
			,"CDEF:nicepct=100,nice,total,/,*"
			,"CDEF:interruptpct=100,interrupt,total,/,*"
			,"CDEF:stealpct=100,steal,total,/,*"
			,"CDEF:systempct=100,system,total,/,*"
			,"CDEF:idlepct=100,idle,total,/,*"
			,"CDEF:iowaitpct=100,iowait,total,/,*"
			,"CDEF:irqpct=100,irq,total,/,*"
			,"AREA:iowaitpct".$color{"color14"}.":".sprintf("%-25s",$Lang::tr{'cpu iowait usage'})
			,"GPRINT:iowaitpct:MAX:%3.2lf%%"
			,"GPRINT:iowaitpct:AVERAGE:%3.2lf%%"
			,"GPRINT:iowaitpct:MIN:%3.2lf%%"
			,"GPRINT:iowaitpct:LAST:%3.2lf%%\\j"
			,"STACK:irqpct".$color{"color23"}."A0:".sprintf("%-25s",$Lang::tr{'cpu irq usage'})
			,"GPRINT:irqpct:MAX:%3.2lf%%"
			,"GPRINT:irqpct:AVERAGE:%3.2lf%%"
			,"GPRINT:irqpct:MIN:%3.2lf%%"
			,"GPRINT:irqpct:LAST:%3.2lf%%\\j"
			,"STACK:nicepct".$color{"color16"}."A0:".sprintf("%-25s",$Lang::tr{'cpu nice usage'})
			,"GPRINT:nicepct:MAX:%3.2lf%%"
			,"GPRINT:nicepct:AVERAGE:%3.2lf%%"
			,"GPRINT:nicepct:MIN:%3.2lf%%"
			,"GPRINT:nicepct:LAST:%3.2lf%%\\j"
			,"STACK:interruptpct".$color{"color15"}."A0:".sprintf("%-25s",$Lang::tr{'cpu interrupt usage'})
			,"GPRINT:interruptpct:MAX:%3.2lf%%"
			,"GPRINT:interruptpct:AVERAGE:%3.2lf%%"
			,"GPRINT:interruptpct:MIN:%3.2lf%%"
			,"GPRINT:interruptpct:LAST:%3.2lf%%\\j"
			,"STACK:stealpct".$color{"color18"}."A0:".sprintf("%-25s",$Lang::tr{'cpu steal usage'})
			,"GPRINT:stealpct:MAX:%3.2lf%%"
			,"GPRINT:stealpct:AVERAGE:%3.2lf%%"
			,"GPRINT:stealpct:MIN:%3.2lf%%"
			,"GPRINT:stealpct:LAST:%3.2lf%%\\j"
			,"STACK:userpct".$color{"color11"}."A0:".sprintf("%-25s",$Lang::tr{'cpu user usage'})
			,"GPRINT:userpct:MAX:%3.1lf%%"
			,"GPRINT:userpct:AVERAGE:%3.2lf%%"
			,"GPRINT:userpct:MIN:%3.2lf%%"
			,"GPRINT:userpct:LAST:%3.2lf%%\\j"
			,"STACK:systempct".$color{"color13"}."A0:".sprintf("%-25s",$Lang::tr{'cpu system usage'})
			,"GPRINT:systempct:MAX:%3.2lf%%"
			,"GPRINT:systempct:AVERAGE:%3.2lf%%"
			,"GPRINT:systempct:MIN:%3.2lf%%"
			,"GPRINT:systempct:LAST:%3.2lf%%\\j"
			,"STACK:idlepct".$color{"color12"}."A0:".sprintf("%-25s",$Lang::tr{'cpu idle usage'})
			,"GPRINT:idlepct:MAX:%3.2lf%%"
			,"GPRINT:idlepct:AVERAGE:%3.2lf%%"
			,"GPRINT:idlepct:MIN:%3.2lf%%"
			,"GPRINT:idlepct:LAST:%3.2lf%%\\j");

	RRDs::graph (@command);
	$ERROR = RRDs::error;
	return "Error in RRD::graph for cpu: ".$ERROR."\n" if $ERROR;
}

# Generate the Load Graph for the current period of time for values given by collecd

sub updateloadgraph {
	my $period    = $_[0];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-l 0",
		"-r",
		"-v ".$Lang::tr{'processes'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:load1=".$mainsettings{'RRDLOG'}."/collectd/localhost/load/load.rrd:shortterm:AVERAGE",
		"DEF:load5=".$mainsettings{'RRDLOG'}."/collectd/localhost/load/load.rrd:midterm:AVERAGE",
		"DEF:load15=".$mainsettings{'RRDLOG'}."/collectd/localhost/load/load.rrd:longterm:AVERAGE",
		"AREA:load1".$color{"color13"}."A0:1 ".$Lang::tr{'minute'},
		"GPRINT:load1:LAST:%5.2lf",
		"AREA:load5".$color{"color18"}."A0:5 ".$Lang::tr{'minutes'},
		"GPRINT:load5:LAST:%5.2lf",
		"AREA:load15".$color{"color14"}."A0:15 ".$Lang::tr{'minutes'},
		"GPRINT:load15:LAST:%5.2lf\\j",
		"LINE1:load5".$color{"color13"},
		"LINE1:load1".$color{"color18"},
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for load: ".$ERROR."\n" if $ERROR;
}

# Generate the Memory Graph for the current period of time for values given by collecd

sub updatememorygraph {
	my $period    = $_[0];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-l 0",
		"-u 100",
		"-r",
		"-v ".$Lang::tr{'percentage'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:used=".$mainsettings{'RRDLOG'}."/collectd/localhost/memory/memory-used.rrd:value:AVERAGE",
		"DEF:free=".$mainsettings{'RRDLOG'}."/collectd/localhost/memory/memory-free.rrd:value:AVERAGE",
		"DEF:buffer=".$mainsettings{'RRDLOG'}."/collectd/localhost/memory/memory-buffered.rrd:value:AVERAGE",
		"DEF:cache=".$mainsettings{'RRDLOG'}."/collectd/localhost/memory/memory-cached.rrd:value:AVERAGE",
		"CDEF:total=used,free,cache,buffer,+,+,+",
		"CDEF:usedpct=used,total,/,100,*",
		"CDEF:bufferpct=buffer,total,/,100,*",
		"CDEF:cachepct=cache,total,/,100,*",
		"CDEF:freepct=free,total,/,100,*",
		"COMMENT:".sprintf("%-29s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"AREA:usedpct".$color{"color11"}."A0:".sprintf("%-25s",$Lang::tr{'used memory'}),
		"GPRINT:usedpct:MAX:%3.2lf%%",
		"GPRINT:usedpct:AVERAGE:%3.2lf%%",
		"GPRINT:usedpct:MIN:%3.2lf%%",
		"GPRINT:usedpct:LAST:%3.2lf%%\\j",
		"STACK:bufferpct".$color{"color23"}."A0:".sprintf("%-25s",$Lang::tr{'buffered memory'}),
		"GPRINT:bufferpct:MAX:%3.2lf%%",
		"GPRINT:bufferpct:AVERAGE:%3.2lf%%",
		"GPRINT:bufferpct:MIN:%3.2lf%%",
		"GPRINT:bufferpct:LAST:%3.2lf%%\\j",
		"STACK:cachepct".$color{"color14"}."A0:".sprintf("%-25s",$Lang::tr{'cached memory'}),
		"GPRINT:cachepct:MAX:%3.2lf%%",
		"GPRINT:cachepct:AVERAGE:%3.2lf%%",
		"GPRINT:cachepct:MIN:%3.2lf%%",
		"GPRINT:cachepct:LAST:%3.2lf%%\\j",
		"STACK:freepct".$color{"color12"}."A0:".sprintf("%-25s",$Lang::tr{'free memory'}),
		"GPRINT:freepct:MAX:%3.2lf%%",
		"GPRINT:freepct:AVERAGE:%3.2lf%%",
		"GPRINT:freepct:MIN:%3.2lf%%",
		"GPRINT:freepct:LAST:%3.2lf%%\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for memory: ".$ERROR."\n" if $ERROR;
}

# Generate the Swap Graph for the current period of time for values given by collecd

sub updateswapgraph {
	my $period    = $_[0];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-l 0",
		"-u 100",
		"-r",
		"-v ".$Lang::tr{'percentage'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:free=".$mainsettings{'RRDLOG'}."/collectd/localhost/swap/swap-free.rrd:value:AVERAGE",
		"DEF:used=".$mainsettings{'RRDLOG'}."/collectd/localhost/swap/swap-used.rrd:value:AVERAGE",
		"DEF:cached=".$mainsettings{'RRDLOG'}."/collectd/localhost/swap/swap-cached.rrd:value:AVERAGE",
		"CDEF:total=used,free,cached,+,+",
		"CDEF:usedpct=100,used,total,/,*",
		"CDEF:freepct=100,free,total,/,*",
		"CDEF:cachedpct=100,cached,total,/,*",
		"COMMENT:".sprintf("%-29s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"AREA:usedpct".$color{"color11"}."A0:".sprintf("%-25s",$Lang::tr{'used swap'}),
		"GPRINT:usedpct:MAX:%3.2lf%%",
		"GPRINT:usedpct:AVERAGE:%3.2lf%%",
		"GPRINT:usedpct:MIN:%3.2lf%%",
		"GPRINT:usedpct:LAST:%3.2lf%%\\j",
		"STACK:cachedpct".$color{"color13"}."A0:".sprintf("%-25s",$Lang::tr{'cached swap'}),
		"GPRINT:cachedpct:MAX:%3.2lf%%",
		"GPRINT:cachedpct:AVERAGE:%3.2lf%%",
		"GPRINT:cachedpct:MIN:%3.2lf%%",
		"GPRINT:cachedpct:LAST:%3.2lf%%\\j",
		"STACK:freepct".$color{"color12"}."A0:".sprintf("%-25s",$Lang::tr{'free swap'}),
		"GPRINT:freepct:MAX:%3.2lf%%",
		"GPRINT:freepct:AVERAGE:%3.2lf%%",
		"GPRINT:freepct:MIN:%3.2lf%%",
		"GPRINT:freepct:LAST:%3.2lf%%\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for memory: ".$ERROR."\n" if $ERROR;
}

# Generate the Disk Graph for the current period of time for values given by collecd

sub updatediskgraph {
	my $disk    = $_[0];
	my $period    = $_[1];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v ".$Lang::tr{'bytes per second'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:read=".$mainsettings{'RRDLOG'}."/collectd/localhost/disk-$disk/disk_octets.rrd:read:AVERAGE",
		"DEF:write=".$mainsettings{'RRDLOG'}."/collectd/localhost/disk-$disk/disk_octets.rrd:write:AVERAGE",
		"CDEF:writen=write,-1,*",
		"DEF:standby=".$mainsettings{'RRDLOG'}."/hddshutdown-".$disk.".rrd:standby:AVERAGE",
		"CDEF:st=standby,INF,*",
		"CDEF:st1=standby,NEGINF,*",
		"COMMENT:".sprintf("%-25s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"AREA:st".$color{"color20"}."A0:",
		"AREA:st1".$color{"color20"}."A0:standby\\j",
		"AREA:read".$color{"color12"}."A0:".sprintf("%-25s",$Lang::tr{'read bytes'}),
		"GPRINT:read:MAX:%8.1lf %sBps",
		"GPRINT:read:AVERAGE:%8.1lf %sBps",
		"GPRINT:read:MIN:%8.1lf %sBps",
		"GPRINT:read:LAST:%8.1lf %sBps\\j",
		"AREA:writen".$color{"color13"}."A0:".sprintf("%-25s",$Lang::tr{'written bytes'}),
		"GPRINT:write:MAX:%8.1lf %sBps",
		"GPRINT:write:AVERAGE:%8.1lf %sBps",
		"GPRINT:write:MIN:%8.1lf %sBps",
		"GPRINT:write:LAST:%8.1lf %sBps\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for ".$disk.": ".$ERROR."\n" if $ERROR;
}

# Generate the Interface Graph for the current period of time for values given by collecd

sub updateifgraph {
	my $interface = $_[0];
	my $period    = $_[1];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v ".$Lang::tr{'bytes per second'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:incoming=".$mainsettings{'RRDLOG'}."/collectd/localhost/interface-".$interface."/if_octets.rrd:rx:AVERAGE",
		"DEF:outgoing=".$mainsettings{'RRDLOG'}."/collectd/localhost/interface-".$interface."/if_octets.rrd:tx:AVERAGE",
		"CDEF:outgoingn=outgoing,-1,*",
		"COMMENT:".sprintf("%-20s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"AREA:incoming".$color{"color12"}."A0:".sprintf("%-20s",$Lang::tr{'incoming traffic in bytes per second'}),
		"GPRINT:incoming:MAX:%8.1lf %sBps",
		"GPRINT:incoming:AVERAGE:%8.1lf %sBps",
		"GPRINT:incoming:MIN:%8.1lf %sBps",
		"GPRINT:incoming:LAST:%8.1lf %sBps\\j",
		"AREA:outgoingn".$color{"color13"}."A0:".sprintf("%-20s",$Lang::tr{'outgoing traffic in bytes per second'}),
		"GPRINT:outgoing:MAX:%8.1lf %sBps",
		"GPRINT:outgoing:AVERAGE:%8.1lf %sBps",
		"GPRINT:outgoing:MIN:%8.1lf %sBps",
		"GPRINT:outgoing:LAST:%8.1lf %sBps\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for ".$interface.": ".$ERROR."\n" if $ERROR;
}

sub updatevpngraph {
	my $interface = $_[0];
	my $period    = $_[1];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v ".$Lang::tr{'bytes per second'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:incoming=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/if_octets.rrd:rx:AVERAGE",
		"DEF:outgoing=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/if_octets.rrd:tx:AVERAGE",
		"CDEF:outgoingn=outgoing,-1,*",
		"COMMENT:".sprintf("%-20s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"AREA:incoming#00dd00:".sprintf("%-20s",$Lang::tr{'incoming traffic in bytes per second'}),
		"GPRINT:incoming:MAX:%8.1lf %sBps",
		"GPRINT:incoming:AVERAGE:%8.1lf %sBps",
		"GPRINT:incoming:MIN:%8.1lf %sBps",
		"GPRINT:incoming:LAST:%8.1lf %sBps\\j",
		"AREA:outgoingn#dd0000:".sprintf("%-20s",$Lang::tr{'outgoing traffic in bytes per second'}),
		"GPRINT:outgoing:MAX:%8.1lf %sBps",
		"GPRINT:outgoing:AVERAGE:%8.1lf %sBps",
		"GPRINT:outgoing:MIN:%8.1lf %sBps",
		"GPRINT:outgoing:LAST:%8.1lf %sBps\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for ".$interface.": ".$ERROR."\n" if $ERROR;
}

sub updatevpnn2ngraph {
	my $interface = $_[0];
	my $period    = $_[1];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v ".$Lang::tr{'bytes per second'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:incoming=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/if_octets-traffic.rrd:rx:AVERAGE",
		"DEF:outgoing=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/if_octets-traffic.rrd:tx:AVERAGE",
		"DEF:overhead_in=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/if_octets-overhead.rrd:rx:AVERAGE",
		"DEF:overhead_out=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/if_octets-overhead.rrd:tx:AVERAGE",
		"DEF:compression_in=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/compression-data_in.rrd:uncompressed:AVERAGE",
		"DEF:compression_out=".$mainsettings{'RRDLOG'}."/collectd/localhost/openvpn-$interface/compression-data_out.rrd:uncompressed:AVERAGE",
		"CDEF:outgoingn=outgoing,-1,*",
		"CDEF:overhead_outn=overhead_out,-1,*",
		"CDEF:compression_outn=compression_out,-1,*",
		"COMMENT:".sprintf("%-20s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"AREA:incoming#00dd00:".sprintf("%-23s",$Lang::tr{'incoming traffic in bytes per second'}),
		"GPRINT:incoming:MAX:%8.1lf %sBps",
		"GPRINT:incoming:AVERAGE:%8.1lf %sBps",
		"GPRINT:incoming:MIN:%8.1lf %sBps",
		"GPRINT:incoming:LAST:%8.1lf %sBps\\j",
		"STACK:overhead_in#116B11:".sprintf("%-23s",$Lang::tr{'incoming overhead in bytes per second'}),
		"GPRINT:overhead_in:MAX:%8.1lf %sBps",
		"GPRINT:overhead_in:AVERAGE:%8.1lf %sBps",
		"GPRINT:overhead_in:MIN:%8.1lf %sBps",
		"GPRINT:overhead_in:LAST:%8.1lf %sBps\\j",
		"LINE1:compression_in#ff00ff:".sprintf("%-23s",$Lang::tr{'incoming compression in bytes per second'}),
		"GPRINT:compression_in:MAX:%8.1lf %sBps",
		"GPRINT:compression_in:AVERAGE:%8.1lf %sBps",
		"GPRINT:compression_in:MIN:%8.1lf %sBps",
		"GPRINT:compression_in:LAST:%8.1lf %sBps\\j",
		"AREA:outgoingn#dd0000:".sprintf("%-23s",$Lang::tr{'outgoing traffic in bytes per second'}),
		"GPRINT:outgoing:MAX:%8.1lf %sBps",
		"GPRINT:outgoing:AVERAGE:%8.1lf %sBps",
		"GPRINT:outgoing:MIN:%8.1lf %sBps",
		"GPRINT:outgoing:LAST:%8.1lf %sBps\\j",
		"STACK:overhead_outn#870C0C:".sprintf("%-23s",$Lang::tr{'outgoing overhead in bytes per second'}),
		"GPRINT:overhead_out:MAX:%8.1lf %sBps",
		"GPRINT:overhead_out:AVERAGE:%8.1lf %sBps",
		"GPRINT:overhead_out:MIN:%8.1lf %sBps",
		"GPRINT:overhead_out:LAST:%8.1lf %sBps\\j",
		"LINE1:compression_outn#000000:".sprintf("%-23s",$Lang::tr{'outgoing compression in bytes per second'}),
		"GPRINT:compression_out:MAX:%8.1lf %sBps",
		"GPRINT:compression_out:AVERAGE:%8.1lf %sBps",
		"GPRINT:compression_out:MIN:%8.1lf %sBps",
		"GPRINT:compression_out:LAST:%8.1lf %sBps\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for ".$interface.": ".$ERROR."\n" if $ERROR;
}

# Generate the Firewall Graph for the current period of time for values given by collecd

sub updatefwhitsgraph {
	my $period    = $_[0];
	if ( -e "$mainsettings{'RRDLOG'}/collectd/localhost/iptables-filter-HOSTILE_DROP/ipt_bytes-DROP_HOSTILE.rrd" ) {
		RRDs::graph(
			@GRAPH_ARGS,
			"-",
			"--start",
			"-1".$period,
			"-r",
			"-v ".$Lang::tr{'bytes per second'},
			"--color=SHADEA".$color{"color19"},
			"--color=SHADEB".$color{"color19"},
			"--color=BACK".$color{"color21"},
			"DEF:output=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-POLICYOUT/ipt_bytes-DROP_OUTPUT.rrd:value:AVERAGE",
			"DEF:input=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-POLICYIN/ipt_bytes-DROP_INPUT.rrd:value:AVERAGE",
			"DEF:forward=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-POLICYFWD/ipt_bytes-DROP_FORWARD.rrd:value:AVERAGE",
			"DEF:newnotsyn=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-NEWNOTSYN/ipt_bytes-DROP_NEWNOTSYN.rrd:value:AVERAGE",
			"DEF:portscan=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-PSCAN/ipt_bytes-DROP_PScan.rrd:value:AVERAGE",
			"DEF:spoofedmartian=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-SPOOFED_MARTIAN/ipt_bytes-DROP_SPOOFED_MARTIAN.rrd:value:AVERAGE",
			"DEF:hostilein=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-HOSTILE_DROP_IN/ipt_bytes-DROP_HOSTILE.rrd:value:AVERAGE",
			"DEF:hostileout=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-HOSTILE_DROP_OUT/ipt_bytes-DROP_HOSTILE.rrd:value:AVERAGE",
			"DEF:hostilelegacy=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-HOSTILE_DROP/ipt_bytes-DROP_HOSTILE.rrd:value:AVERAGE",

			# This creates a new combined hostile segment.
			# Previously we did not split into incoming/outgoing, but we cannot go back in time. This CDEF will take the values
			# from the old RRD database if it exists and if those values are UNKNOWN (time period after Hostile was split into In and Out),
			# we replace them with the sum of IN + OUT.
			"CDEF:hostile=hostilelegacy,UN,hostilein,hostileout,+,hostilelegacy,IF",

			"COMMENT:".sprintf("%-26s",$Lang::tr{'caption'}),
			"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
			"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
			"COMMENT:".sprintf("%14s",$Lang::tr{'minimal'}),
			"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
			"AREA:output".$color{"color25"}."A0:".sprintf("%-25s",$Lang::tr{'firewallhits'}." (OUTPUT)"),
			"GPRINT:output:MAX:%8.1lf %sBps",
			"GPRINT:output:AVERAGE:%8.1lf %sBps",
			"GPRINT:output:MIN:%8.1lf %sBps",
			"GPRINT:output:LAST:%8.1lf %sBps\\j",
			"STACK:forward".$color{"color23"}."A0:".sprintf("%-25s",$Lang::tr{'firewallhits'}." (FORWARD)"),
			"GPRINT:forward:MAX:%8.1lf %sBps",
			"GPRINT:forward:AVERAGE:%8.1lf %sBps",
			"GPRINT:forward:MIN:%8.1lf %sBps",
			"GPRINT:forward:LAST:%8.1lf %sBps\\j",
			"STACK:input".$color{"color24"}."A0:".sprintf("%-25s",$Lang::tr{'firewallhits'}." (INPUT)"),
			"GPRINT:input:MAX:%8.1lf %sBps",
			"GPRINT:input:AVERAGE:%8.1lf %sBps",
			"GPRINT:input:MIN:%8.1lf %sBps",
			"GPRINT:input:LAST:%8.1lf %sBps\\j",
			"STACK:newnotsyn".$color{"color14"}."A0:".sprintf("%-25s","NewNotSYN"),
			"GPRINT:newnotsyn:MAX:%8.1lf %sBps",
			"GPRINT:newnotsyn:AVERAGE:%8.1lf %sBps",
			"GPRINT:newnotsyn:MIN:%8.1lf %sBps",
			"GPRINT:newnotsyn:LAST:%8.1lf %sBps\\j",
			"STACK:portscan".$color{"color16"}."A0:".sprintf("%-25s",$Lang::tr{'portscans'}),
			"GPRINT:portscan:MAX:%8.1lf %sBps",
			"GPRINT:portscan:AVERAGE:%8.1lf %sBps",
			"GPRINT:portscan:MIN:%8.1lf %sBps",
			"GPRINT:portscan:LAST:%8.1lf %sBps\\j",
			"STACK:spoofedmartian".$color{"color12"}."A0:".sprintf("%-25s",$Lang::tr{'spoofed or martians'}),
			"GPRINT:spoofedmartian:MAX:%8.1lf %sBps",
			"GPRINT:spoofedmartian:AVERAGE:%8.1lf %sBps",
			"GPRINT:spoofedmartian:MIN:%8.1lf %sBps",
			"GPRINT:spoofedmartian:LAST:%8.1lf %sBps\\j",
			"STACK:hostilein".$color{"color13"}."A0:".sprintf("%-25s",$Lang::tr{'hostile networks in'}),
			"GPRINT:hostilein:MAX:%8.1lf %sBps",
			"GPRINT:hostilein:AVERAGE:%8.1lf %sBps",
			"GPRINT:hostilein:MIN:%8.1lf %sBps",
			"GPRINT:hostilein:LAST:%8.1lf %sBps\\j",
			"STACK:hostileout".$color{"color25"}."A0:".sprintf("%-25s",$Lang::tr{'hostile networks out'}),
			"GPRINT:hostileout:MAX:%8.1lf %sBps",
			"GPRINT:hostileout:AVERAGE:%8.1lf %sBps",
			"GPRINT:hostileout:MIN:%8.1lf %sBps",
			"GPRINT:hostileout:LAST:%8.1lf %sBps\\j",
			"LINE:hostile#000000A0:".sprintf("%-25s",$Lang::tr{'hostile networks total'}),
			"GPRINT:hostile:MAX:%8.1lf %sBps",
			"GPRINT:hostile:AVERAGE:%8.1lf %sBps",
			"GPRINT:hostile:MIN:%8.1lf %sBps",
			"GPRINT:hostile:LAST:%8.1lf %sBps\\j",
			);
	}else{
		RRDs::graph(
			@GRAPH_ARGS,
			"-",
			"--start",
			"-1".$period,
			"-r",
			"-v ".$Lang::tr{'bytes per second'},
			"--color=SHADEA".$color{"color19"},
			"--color=SHADEB".$color{"color19"},
			"--color=BACK".$color{"color21"},
			"DEF:output=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-POLICYOUT/ipt_bytes-DROP_OUTPUT.rrd:value:AVERAGE",
			"DEF:input=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-POLICYIN/ipt_bytes-DROP_INPUT.rrd:value:AVERAGE",
			"DEF:forward=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-POLICYFWD/ipt_bytes-DROP_FORWARD.rrd:value:AVERAGE",
			"DEF:newnotsyn=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-NEWNOTSYN/ipt_bytes-DROP_NEWNOTSYN.rrd:value:AVERAGE",
			"DEF:portscan=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-PSCAN/ipt_bytes-DROP_PScan.rrd:value:AVERAGE",
			"DEF:spoofedmartian=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-SPOOFED_MARTIAN/ipt_bytes-DROP_SPOOFED_MARTIAN.rrd:value:AVERAGE",
			"DEF:hostilein=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-HOSTILE_DROP_IN/ipt_bytes-DROP_HOSTILE.rrd:value:AVERAGE",
			"DEF:hostileout=".$mainsettings{'RRDLOG'}."/collectd/localhost/iptables-filter-HOSTILE_DROP_OUT/ipt_bytes-DROP_HOSTILE.rrd:value:AVERAGE",

			# This creates a new combined hostile segment.
			# If we started collecting IN/OUT, ie the old single Hostile RRD database is not available then this CDEF will take the values
			# from the sum of IN + OUT.
			"CDEF:hostile=hostilein,hostileout,+",

			"COMMENT:".sprintf("%-26s",$Lang::tr{'caption'}),
			"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
			"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
			"COMMENT:".sprintf("%14s",$Lang::tr{'minimal'}),
			"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
			"AREA:output".$color{"color25"}."A0:".sprintf("%-25s",$Lang::tr{'firewallhits'}." (OUTPUT)"),
			"GPRINT:output:MAX:%8.1lf %sBps",
			"GPRINT:output:AVERAGE:%8.1lf %sBps",
			"GPRINT:output:MIN:%8.1lf %sBps",
			"GPRINT:output:LAST:%8.1lf %sBps\\j",
			"STACK:forward".$color{"color23"}."A0:".sprintf("%-25s",$Lang::tr{'firewallhits'}." (FORWARD)"),
			"GPRINT:forward:MAX:%8.1lf %sBps",
			"GPRINT:forward:AVERAGE:%8.1lf %sBps",
			"GPRINT:forward:MIN:%8.1lf %sBps",
			"GPRINT:forward:LAST:%8.1lf %sBps\\j",
			"STACK:input".$color{"color24"}."A0:".sprintf("%-25s",$Lang::tr{'firewallhits'}." (INPUT)"),
			"GPRINT:input:MAX:%8.1lf %sBps",
			"GPRINT:input:AVERAGE:%8.1lf %sBps",
			"GPRINT:input:MIN:%8.1lf %sBps",
			"GPRINT:input:LAST:%8.1lf %sBps\\j",
			"STACK:newnotsyn".$color{"color14"}."A0:".sprintf("%-25s","NewNotSYN"),
			"GPRINT:newnotsyn:MAX:%8.1lf %sBps",
			"GPRINT:newnotsyn:AVERAGE:%8.1lf %sBps",
			"GPRINT:newnotsyn:MIN:%8.1lf %sBps",
			"GPRINT:newnotsyn:LAST:%8.1lf %sBps\\j",
			"STACK:portscan".$color{"color16"}."A0:".sprintf("%-25s",$Lang::tr{'portscans'}),
			"GPRINT:portscan:MAX:%8.1lf %sBps",
			"GPRINT:portscan:AVERAGE:%8.1lf %sBps",
			"GPRINT:portscan:MIN:%8.1lf %sBps",
			"GPRINT:portscan:LAST:%8.1lf %sBps\\j",
			"STACK:spoofedmartian".$color{"color12"}."A0:".sprintf("%-25s",$Lang::tr{'spoofed or martians'}),
			"GPRINT:spoofedmartian:MAX:%8.1lf %sBps",
			"GPRINT:spoofedmartian:AVERAGE:%8.1lf %sBps",
			"GPRINT:spoofedmartian:MIN:%8.1lf %sBps",
			"GPRINT:spoofedmartian:LAST:%8.1lf %sBps\\j",
			"STACK:hostilein".$color{"color13"}."A0:".sprintf("%-25s",$Lang::tr{'hostile networks in'}),
			"GPRINT:hostilein:MAX:%8.1lf %sBps",
			"GPRINT:hostilein:AVERAGE:%8.1lf %sBps",
			"GPRINT:hostilein:MIN:%8.1lf %sBps",
			"GPRINT:hostilein:LAST:%8.1lf %sBps\\j",
			"STACK:hostileout".$color{"color25"}."A0:".sprintf("%-25s",$Lang::tr{'hostile networks out'}),
			"GPRINT:hostileout:MAX:%8.1lf %sBps",
			"GPRINT:hostileout:AVERAGE:%8.1lf %sBps",
			"GPRINT:hostileout:MIN:%8.1lf %sBps",
			"GPRINT:hostileout:LAST:%8.1lf %sBps\\j",
			"LINE:hostile#000000A0:".sprintf("%-25s",$Lang::tr{'hostile networks total'}),
			"GPRINT:hostile:MAX:%8.1lf %sBps",
			"GPRINT:hostile:AVERAGE:%8.1lf %sBps",
			"GPRINT:hostile:MIN:%8.1lf %sBps",
			"GPRINT:hostile:LAST:%8.1lf %sBps\\j",
			);
	}
		$ERROR = RRDs::error;
		return "Error in RRD::graph for firewallhits: ".$ERROR."\n" if $ERROR;
}

# Generate the Line Quality Graph for the current period of time for values given by collecd

sub updatepinggraph {
	my $period    = $_[1];
	my $host    = $_[0];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-l 0",
		"-r",
		"-v ms",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:roundtrip=".$mainsettings{'RRDLOG'}."/collectd/localhost/ping/ping-".$host.".rrd:value:AVERAGE",
		"COMMENT:".sprintf("%-20s",$Lang::tr{'caption'})."\\j",
		"CDEF:roundavg=roundtrip,PREV(roundtrip),+,2,/",
		"CDEF:r0=roundtrip,30,MIN",
		"CDEF:r1=roundtrip,70,MIN",
		"CDEF:r2=roundtrip,150,MIN",
		"CDEF:r3=roundtrip,300,MIN",
		"AREA:roundtrip".$color{"color25"}."A0:>300 ms",
		"AREA:r3".$color{"color18"}."A0:150-300 ms",
		"AREA:r2".$color{"color14"}."A0:70-150 ms",
		"AREA:r1".$color{"color17"}."A0:30-70 ms",
		"AREA:r0".$color{"color12"}."A0:<30 ms\\j",
		"COMMENT:$Lang::tr{'maximal'}",
		"COMMENT:$Lang::tr{'average'}",
		"COMMENT:$Lang::tr{'minimal'}","COMMENT:$Lang::tr{'current'}\\j",
		"LINE1:roundtrip#707070:",
		"GPRINT:roundtrip:MAX:%3.2lf ms",
		"GPRINT:roundtrip:AVERAGE:%3.2lf ms",
		"GPRINT:roundtrip:MIN:%3.2lf ms",
		"GPRINT:roundtrip:LAST:%3.2lf ms\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for link quality: ".$ERROR."\n" if $ERROR;
}

sub updatewirelessgraph {
	my $period    = $_[1];
	my $interface    = $_[0];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-v dBm",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:noise=".$mainsettings{'RRDLOG'}."/collectd/localhost/wireless-".$interface."/signal_noise.rrd:value:AVERAGE",
		"DEF:power=".$mainsettings{'RRDLOG'}."/collectd/localhost/wireless-".$interface."/signal_power.rrd:value:AVERAGE",
		"COMMENT:".sprintf("%-20s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j",
		"LINE1:noise".$color{"color11"}."A0:".sprintf("%-20s","Signal Noise Ratio"),
		"GPRINT:noise:MAX:%5.1lf %sdBm",
		"GPRINT:noise:AVERAGE:%5.1lf %sdBm",
		"GPRINT:noise:MIN:%5.1lf %sdBm",
		"GPRINT:noise:LAST:%5.1lf %sdBm\\j",
		"LINE1:power".$color{"color12"}."A0:".sprintf("%-20s","Signal Power Ratio"),
		"GPRINT:power:MAX:%5.1lf %sdBm",
		"GPRINT:power:AVERAGE:%5.1lf %sdBm",
		"GPRINT:power:MIN:%5.1lf %sdBm",
		"GPRINT:power:LAST:%5.1lf %sdBm\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for wireless: ".$ERROR."\n" if $ERROR;
}

# Generate the HDD Temp Graph for the current period of time for values given by collecd and lm_sensors

sub updatehddgraph {
	my $disk = $_[0];
	my $period = $_[1];
	RRDs::graph(
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v Celsius",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"DEF:temperature=".$mainsettings{'RRDLOG'}."/hddtemp-$disk.rrd:temperature:AVERAGE",
		"DEF:standby=".$mainsettings{'RRDLOG'}."/hddshutdown-$disk.rrd:standby:AVERAGE",
		"CDEF:st=standby,INF,*",
		"AREA:st".$color{"color20"}."A0:standby",
		"LINE3:temperature".$color{"color11"}."A0:$Lang::tr{'hdd temperature in'} °C\\j",
		"COMMENT:$Lang::tr{'maximal'}",
		"COMMENT:$Lang::tr{'average'}",
		"COMMENT:$Lang::tr{'minimal'}",
		"COMMENT:$Lang::tr{'current'}\\j",
		"GPRINT:temperature:MAX:%3.0lf °C",
		"GPRINT:temperature:AVERAGE:%3.0lf °C",
		"GPRINT:temperature:MIN:%3.0lf °C",
		"GPRINT:temperature:LAST:%3.0lf °C\\j",
		);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for hdd-".$disk.": ".$ERROR."\n" if $ERROR;
}

# Generate the Temp Graph for the current period of time for values given by collecd and lm_sensors

sub updatehwtempgraph {
	my $period = $_[0];

	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v Celsius",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-29s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

		foreach(@sensorsgraphs){
			chomp($_);
			if ( $_ =~ /temperature/ ) {
				$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
				my $label = $2.$3;$label=~ s/-//g;
				if ( $sensorsettings{'LINE-'.$label} eq "off" ){next;}
				push(@command,"DEF:".$sensorsettings{'LABEL-'.$label}."=".$_.":value:AVERAGE");
			}
		}

		foreach(@sensorsgraphs){
			chomp($_);
			if ( $_ =~ /temperature/ ){
				$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
				my $label = $2.$3;$label=~ s/-//g;
				if ( $sensorsettings{'LINE-'.$label} eq "off" ){next;}
				push(@command,"LINE3:".$sensorsettings{'LABEL-'.$label}.random_hex_color(6)."A0:".sprintf("%-25s",$sensorsettings{'LABEL-'.$label}),"GPRINT:".$sensorsettings{'LABEL-'.$label}.":MAX:%3.2lf °C","GPRINT:".$sensorsettings{'LABEL-'.$label}.":AVERAGE:%3.2lf °C","GPRINT:".$sensorsettings{'LABEL-'.$label}.":MIN:%3.2lf °C","GPRINT:".$sensorsettings{'LABEL-'.$label}.":LAST:%3.2lf °C\\j",);
			}
		}

		RRDs::graph (@command);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for HDD Temp: ".$ERROR."\n" if $ERROR;
}

# Generate the Fan Graph for the current period of time for values given by collecd and lm_sensors

sub updatehwfangraph {
	my $period = $_[0];

	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-29s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

		foreach(@sensorsgraphs){
			chomp($_);
			if ( $_ =~ /fanspeed/ ) {
				$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
				my $label = $2.$3;$label=~ s/-//g;
				if ( $sensorsettings{'LINE-'.$label} eq "off" ){next;}
				push(@command,"DEF:".$sensorsettings{'LABEL-'.$label}."=".$_.":value:AVERAGE");
			}
		}

		foreach(@sensorsgraphs){
			chomp($_);
			if ( $_ =~ /fanspeed/ ){
				$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
				my $label = $2.$3;$label=~ s/-//g;
				if ( $sensorsettings{'LINE-'.$label} eq "off" ){next;}
				push(@command,"LINE3:".$sensorsettings{'LABEL-'.$label}.random_hex_color(6)."A0:".sprintf("%-25s",$sensorsettings{'LABEL-'.$label}),"GPRINT:".$sensorsettings{'LABEL-'.$label}.":MAX:%3.2lf RPM","GPRINT:".$sensorsettings{'LABEL-'.$label}.":AVERAGE:%3.2lf RPM","GPRINT:".$sensorsettings{'LABEL-'.$label}.":MIN:%3.2lf RPM","GPRINT:".$sensorsettings{'LABEL-'.$label}.":LAST:%3.2lf RPM\\j",);
			}
		}

		RRDs::graph (@command);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for Fan Speed: ".$ERROR."\n" if $ERROR;
}

# Generate the Voltage Graph for the current period of time for values given by collecd and lm_sensors

sub updatehwvoltgraph {
	my $period = $_[0];

	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-29s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

		foreach(@sensorsgraphs){
			chomp($_);
			if ( $_ =~ /voltage/ ) {
				$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
				my $label = $2.$3;$label=~ s/-//g;
				if ( $sensorsettings{'LINE-'.$label} eq "off" ){next;}
				push(@command,"DEF:".$sensorsettings{'LABEL-'.$label}."=".$_.":value:AVERAGE");
			}
		}

		foreach(@sensorsgraphs){
			chomp($_);
			if ( $_ =~ /voltage/ ){
				$_ =~ /\/(.*)sensors-(.*)\/(.*)\.rrd/;
				my $label = $2.$3;$label=~ s/-//g;
				if ( $sensorsettings{'LINE-'.$label} eq "off" ){next;}
				push(@command,"LINE3:".$sensorsettings{'LABEL-'.$label}.random_hex_color(6)."A0:".sprintf("%-25s",$sensorsettings{'LABEL-'.$label}),"GPRINT:".$sensorsettings{'LABEL-'.$label}.":MAX:%3.2lf V","GPRINT:".$sensorsettings{'LABEL-'.$label}.":AVERAGE:%3.2lf V","GPRINT:".$sensorsettings{'LABEL-'.$label}.":MIN:%3.2lf V","GPRINT:".$sensorsettings{'LABEL-'.$label}.":LAST:%3.2lf V\\j",);
			}
		}

		RRDs::graph (@command);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for Voltage: ".$ERROR."\n" if $ERROR;
}


# Generate the QoS Graph for the current period of time

sub updateqosgraph {

	my $period = $_[1];
	my %qossettings = ();
	&General::readhash("${General::swroot}/qos/settings", \%qossettings);

	my $classentry = "";
	my @classes = ();
	my @classline = ();
	my $classfile = "/var/ipfire/qos/classes";

	$qossettings{'DEV'} = $_[0];
	if ( $qossettings{'DEV'} eq $qossettings{'RED_DEV'} ) {
		$qossettings{'CLASSPRFX'} = '1';
	} else {
		$qossettings{'CLASSPRFX'} = '2';
	}

	my $ERROR="";
	my $count="1";
	my %colorMap = (); # maps traffic classes to graph colors

	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v ".$Lang::tr{'bytes per second'},
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-28s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

		open( FILE, "< $classfile" ) or die "Unable to read $classfile";
		@classes = <FILE>;
		close FILE;

		foreach $classentry (sort @classes){
			@classline = split( /\;/, $classentry );

			# create class <-> color mapping
			my $colorKey = uc $classline[8]; # upper case class name as key
			if(! exists $colorMap{$colorKey}) {
				# add missing color to table, use colors 11-25
				my $colorIndex = 11 + ((scalar keys %colorMap) % 15);
				$colorMap{$colorKey} = "$color{\"color$colorIndex\"}";
			}

			if ( $classline[0] eq $qossettings{'DEV'} ){
				push(@command, "DEF:$classline[1]=$mainsettings{'RRDLOG'}/class_$qossettings{'CLASSPRFX'}-$classline[1]_$qossettings{'DEV'}.rrd:bytes:AVERAGE");

				# get color to be used for this graph
				my $graphColor = $colorMap{$colorKey};

				if ($count eq "1") {
					push(@command, "AREA:$classline[1]$graphColor:$Lang::tr{'Class'} $classline[1] -".sprintf("%15s",$classline[8]));
				} else {
					push(@command, "STACK:$classline[1]$graphColor:$Lang::tr{'Class'} $classline[1] -".sprintf("%15s",$classline[8]));
				}

				push(@command, "GPRINT:$classline[1]:MAX:%8.1lf %sBps"
						, "GPRINT:$classline[1]:AVERAGE:%8.1lf %sBps"
						, "GPRINT:$classline[1]:MIN:%8.1lf %sBps"
						, "GPRINT:$classline[1]:LAST:%8.1lf %sBps\\j");
				$count++;
			}
		}
		RRDs::graph (@command);
		$ERROR = RRDs::error;
		return "Error in RRD::graph for qos device ".$qossettings{'DEV'}.": ".$ERROR."\n" if $ERROR;
}

# Generate the CPU Frequency Graph for the current period of time for values given by collectd an lm_sensors

sub updatecpufreqgraph {
	my $cpucount = `ls -dA $mainsettings{'RRDLOG'}/collectd/localhost/cpu-*/ 2>/dev/null | wc -l`;
	my $period    = $_[0];
	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v MHz",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-15s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

	my $j = 11;
	for(my $i = 0; $i < $cpucount; $i++) {
		$j++; $j = 1 if $j > 20;
		push(@command,"DEF:cpu".$i."_=".$mainsettings{'RRDLOG'}."/collectd/localhost/cpufreq-".$i."/cpufreq.rrd:value:AVERAGE"
				,"CDEF:cpu".$i."=cpu".$i."_,1000000,/"
				,"LINE1:cpu".$i.$color{"color$j"}."A0:cpu ".$i." "
				,"GPRINT:cpu".$i.":MAX:%3.0lf Mhz"
				,"GPRINT:cpu".$i.":AVERAGE:%3.0lf Mhz"
				,"GPRINT:cpu".$i.":MIN:%3.0lf Mhz"
				,"GPRINT:cpu".$i.":LAST:%3.0lf Mhz\\j");
	}

	RRDs::graph (@command);
	$ERROR = RRDs::error;
	return "Error in RRD::graph for cpu freq: ".$ERROR."\n" if $ERROR;
}

# Generate the Thermal Zone Temp CPU Graph

sub updatethermaltempgraph {
	my $thermalcount = `ls -dA $mainsettings{'RRDLOG'}/collectd/localhost/thermal-thermal_zone* 2>/dev/null | wc -l`;
	my $period    = $_[0];
	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1".$period,
		"-r",
		"-v Celsius",
		"--color=SHADEA".$color{"color19"},
		"--color=SHADEB".$color{"color19"},
		"--color=BACK".$color{"color21"},
		"COMMENT:".sprintf("%-10s",$Lang::tr{'caption'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'maximal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'average'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'minimal'}),
		"COMMENT:".sprintf("%15s",$Lang::tr{'current'})."\\j"
	);

	for(my $i = 0; $i < $thermalcount; $i++) {
		my $j=$i+1;
		push(@command,"DEF:temp".$i."_=".$mainsettings{'RRDLOG'}."/collectd/localhost/thermal-thermal_zone".$i."/temperature.rrd:value:AVERAGE"
				,"CDEF:temp".$i."=temp".$i."_,1,/"
				,"LINE3:temp".$i.$color{"color1$j"}."A0:Temp ".$i." "
				,"GPRINT:temp".$i.":MAX:%3.0lf °C"
				,"GPRINT:temp".$i.":AVERAGE:%3.0lf °C"
				,"GPRINT:temp".$i.":MIN:%3.0lf °C"
				,"GPRINT:temp".$i.":LAST:%3.0lf °C\\j");
	}

	RRDs::graph (@command);
	$ERROR = RRDs::error;
	return "Error in RRD::graph for thermal temp: ".$ERROR."\n" if $ERROR;
}


# Generate a random color, used by Qos Graph to be independent from the amount of values

sub random_hex_color {
	my $size = shift;
	$size = 6 if $size !~ /^3|6$/;
	my @hex = ( 0 .. 9, 'a' .. 'f' );
	my @color;
	push @color, @hex[rand(@hex)] for 1 .. $size;
	return join('', '#', @color);
}

sub getprocesses {
	my @processesgraph = `ls -dA $mainsettings{'RRDLOG'}/collectd/localhost/processes-*/ 2>/dev/null`;
	return @processesgraph;
}

sub updateconntrackgraph {
	my $period = $_[0];
	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1" . $period,
		"-r",
		"--lower-limit","0",
		"-v $Lang::tr{'open connections'}",
		"DEF:conntrack=$mainsettings{'RRDLOG'}/collectd/localhost/conntrack/conntrack.rrd:value:AVERAGE",
		"LINE3:conntrack#ff0000:" . sprintf("%-15s", $Lang::tr{'open connections'}),
		"VDEF:ctmin=conntrack,MINIMUM",
		"VDEF:ctmax=conntrack,MAXIMUM",
		"VDEF:ctavg=conntrack,AVERAGE",
		"GPRINT:ctmax:" . sprintf("%15s\\: %%5.0lf", $Lang::tr{'maximum'}),
		"GPRINT:ctmin:" . sprintf("%15s\\: %%5.0lf", $Lang::tr{'minimum'}),
		"GPRINT:ctavg:" . sprintf("%15s\\: %%5.0lf", $Lang::tr{'average'}) . "\\n",
		"--color=BACK" . $color{"color21"},
	);

	RRDs::graph(@command);
	$ERROR = RRDs::error;

	return "Error in RRD::Graph for conntrack: " . $ERROR . "\n" if $ERROR;
}

sub updateipsthroughputgraph {
	my $period = $_[0];

	my @command = (
		@GRAPH_ARGS,
		"-",
		"--start",
		"-1" . $period,
		"-r",
		"--lower-limit","0",
		"-v $Lang::tr{'bytes per second'}",
		"--color=BACK" . $color{"color21"},

		# Read bypassed packets
		"DEF:bypassed_bytes=$mainsettings{'RRDLOG'}/collectd/localhost/iptables-mangle-IPS/ipt_bytes-BYPASSED.rrd:value:AVERAGE",
		#"DEF:bypassed_packets=$mainsettings{'RRDLOG'}/collectd/localhost/iptables-mangle-IPS/ipt_packets-BYPASSED.rrd:value:AVERAGE",

		"VDEF:bypassed_bytes_avg=bypassed_bytes,AVERAGE",
		"VDEF:bypassed_bytes_min=bypassed_bytes,MINIMUM",
		"VDEF:bypassed_bytes_max=bypassed_bytes,MAXIMUM",

		# Read scanned packets
		"DEF:scanned_bytes=$mainsettings{'RRDLOG'}/collectd/localhost/iptables-mangle-IPS/ipt_bytes-SCANNED.rrd:value:AVERAGE",
		#"DEF:scanned_packets=$mainsettings{'RRDLOG'}/collectd/localhost/iptables-mangle-IPS/ipt_packets-SCANNED.rrd:value:AVERAGE",

		"VDEF:scanned_bytes_avg=scanned_bytes,AVERAGE",
		"VDEF:scanned_bytes_min=scanned_bytes,MINIMUM",
		"VDEF:scanned_bytes_max=scanned_bytes,MAXIMUM",

		# Read whitelisted packets
		"DEF:whitelisted_bytes=$mainsettings{'RRDLOG'}/collectd/localhost/iptables-mangle-IPS/ipt_bytes-WHITELISTED.rrd:value:AVERAGE",
		#"DEF:whitelisted_packets=$mainsettings{'RRDLOG'}/collectd/localhost/iptables-mangle-IPS/ipt_packets-WHITELISTED.rrd:value:AVERAGE",

		"VDEF:whitelisted_bytes_avg=whitelisted_bytes,AVERAGE",
		"VDEF:whitelisted_bytes_min=whitelisted_bytes,MINIMUM",
		"VDEF:whitelisted_bytes_max=whitelisted_bytes,MAXIMUM",

		# Total
		"CDEF:total_bytes=bypassed_bytes,scanned_bytes,ADDNAN,whitelisted_bytes,ADDNAN",
		#"CDEF:total_packets=bypassed_packets,scanned_packets,ADDNAN,whitelisted_packets,ADDNAN",

		"VDEF:total_bytes_avg=total_bytes,AVERAGE",
		"VDEF:total_bytes_min=total_bytes,MINIMUM",
		"VDEF:total_bytes_max=total_bytes,MAXIMUM",

		# Add some space below the graph
		"COMMENT: \\n",

		# Headline
		"COMMENT:" . sprintf("%32s", ""),
		"COMMENT:" . sprintf("%16s", $Lang::tr{'average'}),
		"COMMENT:" . sprintf("%16s", $Lang::tr{'minimum'}),
		"COMMENT:" . sprintf("%16s", $Lang::tr{'maximum'}) . "\\j",

		# Whitelisted Packets
		"AREA:whitelisted_bytes$color{'color12'}A0:" . sprintf("%-30s", $Lang::tr{'whitelisted'}),
		"GPRINT:whitelisted_bytes_avg:%9.2lf %sbps",
		"GPRINT:whitelisted_bytes_min:%9.2lf %sbps",
		"GPRINT:whitelisted_bytes_max:%9.2lf %sbps\\j",

		# Bypassed Packets
		"STACK:bypassed_bytes$color{'color11'}A0:" . sprintf("%-30s", $Lang::tr{'bypassed'}),
		"GPRINT:bypassed_bytes_avg:%9.2lf %sbps",
		"GPRINT:bypassed_bytes_min:%9.2lf %sbps",
		"GPRINT:bypassed_bytes_max:%9.2lf %sbps\\j",

		# Scanned Packets
		"STACK:scanned_bytes$color{'color13'}A0:" . sprintf("%-30s", $Lang::tr{'scanned'}),
		"GPRINT:scanned_bytes_avg:%9.2lf %sbps",
		"GPRINT:scanned_bytes_min:%9.2lf %sbps",
		"GPRINT:scanned_bytes_max:%9.2lf %sbps\\j",

		"COMMENT: \\n",

		# Total Packets
		"COMMENT:" . sprintf("%-32s", $Lang::tr{'total'}),
		"GPRINT:total_bytes_avg:%9.2lf %sbps",
		"GPRINT:total_bytes_min:%9.2lf %sbps",
		"GPRINT:total_bytes_max:%9.2lf %sbps\\j",
	);

	RRDs::graph(@command);
	$ERROR = RRDs::error;

	return "Error in RRD::Graph for suricata: " . $ERROR . "\n" if $ERROR;
}
