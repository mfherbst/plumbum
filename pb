#!/bin/bash
#Global:
IND="       "
WD="$PWD"
MAXMEM=0.75 #fraction of main RAM which is allowed to be used
	    #Background: mkvmerge used to have a problematic bug where it
	    #            tended to use ALL of RAM. This caps it with a ulimit
	    #            causing a crash if more than 75% of the memory is allocated.
DEBUG=n     # if y writes a debug log file debug.log

#TODO: Rewrite in python. Use plugin system to include extra commands
#TODO: Save and restore option to save and restore the titles
#	-> also do this automatically to a file in /tmp

#----------------------------------------------------------
#Print help if requested.

if [ "$1" == "-h" ]; then
	cat << EOF
	`basename $0` [ -h | -d ]  [ <DVDdev> ]
Starts an interactive environment to rip a DVD to the harddrive.

If no DVD device is given as first arg, the script tries to
automatically determine the currently active device. In most
cases this should work.

-d turns on debug mode with a debug log written to debug.log
EOF
	exit 0
fi

if [ "$1" == "-d" ]; then
       DEBUG=y
       DEBUGLOG="$PWD/debug.log"
       shift
fi

echo "TODO: get rid of dependency towards mencoder. This software is old and buggy
            use avconv or similar instead." >&2
echo >&2

#######################################################################

chkPreReq() {
	FFMPEGCMD=""
	type ffmpeg &> /dev/null && FFMPEGCMD="ffmpeg"
	type avconv &> /dev/null && FFMPEGCMD="avconv"
	if [ -z "$FFMPEGCMD" ]; then
		echo "Could not find ffmpeg or avconv in PATH." >&2
		exit 1
	fi

	if ! type lsdvd &> /dev/null; then
		echo "Could not find lsdvd in PATH." >&2
		exit 1
	fi

	if ! type mplayer &> /dev/null; then
		echo "Could not find mplayer in PATH." >&2
		exit 1
	fi

	if ! type mencoder &> /dev/null; then
		echo "Could not find mencoder in PATH." >&2
		echo "Ripping subtitles will not work." >&2
	fi

	if ! type mkvmerge &> /dev/null; then
		echo "Could not find mkvmerge in PATH." >&2
		exit 1
	fi

	if ! type dvdxchap &> /dev/null; then
		echo "Could not find dvdxchap in PATH." >&2
		exit 1
	fi

	if ! type html_extract_tables.py &> /dev/null; then
		echo "Could not find html_extract_tables.py in PATH."
		exit 1
	fi
}

set_maxmem() {
	local MEM=$(free -k | awk -v "fac=$MAXMEM" '/^Mem:/ {print $2*fac}')
	ulimit -v "$MEM"
}

get_active_dvddev() {
	local PREFIX="/dev/sr"

	local DEVICES=$(ls "$PREFIX"* 2> /dev/null)
	if [ "$(echo -n "$DEVICES" | grep -c "^")" == "1" ]; then
		echo_debug_log "get_active_dvddev selects the only device available: $DEVICES"
		echo "$DEVICES"
		return 0
	fi

	local WITH_MEDIUM="" # list of devices with a medium mounted
	for ((C=0; ; ++C)); do
		[ ! -b "$PREFIX$C" ] && break

		if LANG=C dd bs=1 count=1 if="$PREFIX$C" of=/dev/null |& grep -i -q "no medium"; then
			echo_debug_log "get_active_dvddev: ignoring $PREFIX$C since no medium"
			continue
		fi

		if mount | grep -q "^$PREFIX$C"; then
			echo_debug_log "get_active_dvddev selects the mounted device: $PREFIX$C"
			echo "$PREFIX$C"
			return 0
		fi

		if LANG=C dd bs=1 count=1 if="$PREFIX$C" &> /dev/null; then
			# seems like we have a hit
			if [ "$WITH_MEDIUM" ]; then
				echo_debug_log "get_active_dvddev failed to select device by inserted medium: More than one drive seems to contain a medium"
				WITH_MEDIUM=""
				break
			fi
			WITH_MEDIUM="$C"
		fi
	done
	if [ "$WITH_MEDIUM" ]; then
		echo_debug_log "get_active_dvddev selects the only device with a medium inserted: $PREFIX$WITH_MEDIUM"
		echo "$PREFIX$WITH_MEDIUM"
		return 0
	fi

	echo_debug_log "get_active_dvddev cannot find an active device."
	return 1
} 
set_dvd_dev() {
	# $1: the first arg input to program
	# Sets the variable DVDdev sanely, where the DVD is expected
	if [ "$1" ]; then
		if [ -b "$1" ]; then
			DVDdev="$1"
			echo "Using user-defined device \"$DVDdev\""
		else
			echo "Invalid device \"$1\""
			exit 1
		fi
	else
		if DVDdev=`get_active_dvddev`; then
			echo "Using automatically determined device \"$DVDdev\""
		else
			echo "Automatic determination of active device failed."
			echo "Is there any optical device ready?"
			echo "You can give a device as first arg to force usage"
			echo "of this specific device"
			exit 1
		fi
	fi
	echo
}

set_lsdvd() {
	#set the LSDVD, MAXTITLE and TITLES variables sanely

	LSDVD=`lsdvd $DVDdev`

	case $? in
		0) 	:
			;;
		2) echo "No medium inserted!!!"
			exit 1
			;;
		*) echo "lsdvd error"
			exit 1
			;;
	esac	

	MAXTITLE=`echo "$LSDVD" | awk 'BEGIN {maxtitle=0}; /^Title: [0-9]*, .*/ { title=$2; gsub(/,$/,"",title); if (title > maxtitle) maxtitle = title }; END {print maxtitle}'`
	MAXTITLE=${MAXTITLE#0}

	TITLES=`echo "" | awk -v max="$MAXTITLE" '{for (i=1;i<=max;i++) print "Track_" i}'`
}

echo_debug_log() {
	[ "$DEBUG" != "y" ] && return
	echo "$@" >> "$DEBUGLOG"
}

cat_debug_log() {
	[ "$DEBUG" != "y" ] && return
	cat >> "$DEBUGLOG"
}

normalise_num() {
	#$1 number to normalise to 2digit format

	local NUM=0$1
	NUM=${NUM: -2}
	echo $NUM
}

normalise_list() {
	for I in $@; do
		echo -n "`normalise_num $I` "
	done
	echo
}

is_list_sane() {
	for I in $@; do
		if [ "$I" -gt "$MAXTITLE" ] || [ "$I" -le "0" ]; then
			return 1
		fi
	done
	return 0
}

expand_list() {
	#$@: canonical list of the form 1 2 4-7 8

	local I
	for I in $@; do
		case "$I" in
			([0-9]|[0-9][0-9])
				echo -n "`normalise_num $I` "
				;;
			([0-9][0-9]-[0-9][0-9]|[0-9]-[0-9][0-9]|[0-9]-[0-9])
				PRE="${I%%"-"*}"
				POST="${I##*"-"}"

				for ((;PRE <= POST;PRE++)); do
					echo -n "`normalise_num $PRE` "
				done
				;;
			*)	echo
				return 1
				;;
		esac
	done

	echo
	return 0
}

max_of_list() {
	local I
	local J=0
	for I in $@; do
		[ $I -gt $J ] && J=$I
	done
	echo $J
}

len_of_list() {
	echo $#
}

get_dvd_path() {
	#$1: DVD title number
	#assumes DVDdev to be set:

	local NUM=`normalise_num $1`
	echo "dvd://$NUM//$DVDdev"
}

get_dump_fileprefix() {
	#$1: DVD title number
	local NUM=`normalise_num $1`
	echo "dump$NUM"
}

get_chapter_filename() {
	#$1: DVD title number
	local NUM=`normalise_num $1`
	echo "chapterinfo$NUM.txt"
}

print_dvd_contents() {
	#1: minimum length of items to be printed.

	local MINLENGTH=${1:-0} # at least one minute
	echo "$LSDVD" | awk -v "titles=$TITLES" -v "minlength=$MINLENGTH" '
		BEGIN { 
			split(titles,tit,"\n"); 
			indx=1 
		}

		function calc_length_in_seconds( stringin ) {
			split(stringin,a,":")
			#a[1]:   Stunden
			#a[2]:   Minuten
			#a[3]:   Sekunden
			return a[1]*60*60 + a[2]*60 + a[3]
		}

		/^Title:/ {
			green="\033[0;32m";
			white="\033[0m";

			if ($3 == "Length:") {
				lengthsecs = calc_length_in_seconds($4)

				# Is this Track longer than minimum lenght required?
				if ( lengthsecs < minlength ) {
					# suppress the next newline below
					suppress_next_print = 1

					# and skip this print:
					indx++
					next
				};
			}

			print; 
			print "           Track Name: " green tit[indx++] white;
		       	next
		}

		{
			if (suppress_next_print == 1) {
				suppress_next_print=0
				next
		       	}  
			print
		}
		'
	echo ""
}

expand_brace_pattern() {
	#TODO expand a construct like "a{01..04}b"
	# to a01b a02b, ...

	echo "Not yet implemented"
	return 1
}

####################################################################

command_prompt() {

	WD=`pwd`
	PREV="0"	#the previously selected record
	PRINT=1		#print the contents?
	INCREASE=1	#increase PREV?
	OLDCMD=""

	while true; do
		if [ $INCREASE -eq 1 ]; then
			#remove a leading 0:
			PREV="${PREV#0}"
			PREV=$(( PREV%MAXTITLE+1 ))
			PREV=`normalise_num $PREV`
		fi
		INCREASE=1

		if [ "$PRINT" == "1" ]; then
			print_dvd_contents	
			echo "Interactively rip the DVD. Enter 'h' for help, 'q' to quit."
			PRINT=0
		fi

		read -e -p " ($PREV) >" LINE
		history -s "$LINE"

		interpret_cmd_line $LINE
	done
}

interpret_cmd_line() {
	#interprets a command line and sets OLDCMD, PRINT, INCREASE and PREV appropriately

	CMD="$1"
	shift
	NR=$1
	LIST=$@
	
	[ -z "$CMD" ] && CMD="$OLDCMD"
	if [ -z "$CMD" ]; then
		INCREASE=0
		return
	fi

	#No arg following:
	case $CMD in
		h|help)
			do_help
			INCREASE=0
			return
			;;
		q|quit)
			exit 0
			;;
		e|eject)
			do_eject
			exit 0
			;;
		v|vi|vim)
			do_vi
			INCREASE=0
			return
			;;

	esac

	#number of seconds following:
	if [[ "$CMD" == "c" || "$CMD" == "contents" ]]; then
		INCREASE=0
		print_dvd_contents $NR
		return
	fi


	#----------------------------------
	OLDCMD="$CMD"

	#1 Number and some extra following.
	case $CMD in
		r|rip)
			[ -z "$NR" ] &&  NR="$PREV"

			if ! is_list_sane $NR; then
				INCREASE=0
				echo "${IND}!! Provided title number not sane: $NR !!"
				return
			fi
			PREV=${NR%%"-"*} #remove stuff if it is sth like 2-5
			PREV=`normalise_num $PREV`
			PRINT=1

			VLIST=""
			ALIST=""
			SLIST=""

			shift
			while [ "$1" ]; do
				[ "$1" == "--" ] && break
				VLIST="$VLIST $1"
				shift
			done
			shift
			while [ "$1" ]; do
				[ "$1" == "--" ] && break
				ALIST="$ALIST $1"
				shift
			done
			shift
			while [ "$1" ]; do
				SLIST="$SLIST $1"
				shift
			done

			do_rip $PREV "$VLIST" "$ALIST" "$SLIST"
			return
			;;
	esac

	#-----------------------------------
	#List only
	[ -z "$LIST" ] && LIST="$PREV"

	LIST=`expand_list $LIST`
	if ! is_list_sane $LIST; then
		echo "${IND}!! Input list given to command as argument is not sane !!"
		INCREASE=0
		return
	fi

	PREV=`max_of_list $LIST`

	case $CMD in
		ripall|ra)
			PRINT=1
			do_ripall $LIST
			return
			;;
		preview|p)
			do_preview $LIST
			INCREASE=0
			return
			;;
		streamlist|s)
			do_streamlist $LIST
			INCREASE=0
			return
			;;
		name|n)
			do_name $LIST
			return
			;;
		bulkname|b)
			do_bulkname $LIST
			return
			;;
		w|wikipedia)
			do_wikipedia $LIST
			return
	esac

	#--------------------------------
	#Unknown:

	echo "${IND}!! Unknown command: $CMD !!"
	echo
	INCREASE=0
	return
}

do_help() {
	cat << EOF
${IND}Use "rip" or "ripall" to convert some or all tracks of the DVD
${IND}onto the hardrive. Individual titles are ripped into an mkv
${IND}file within a folder which has the name associated with the
${IND}title selected for ripping. Rips some or all streams of the
${IND}titles and keeps the raw vob or demuxed streams if the user
${IND}wishes.

${IND}Available commands:
${IND}  ripall <list>          rip all streams of the titles given
${IND}  ra <list>              in list without asking any questions
${IND}                         (Temporary dump files are NOT deleted)

${IND}  rip <number> [<vlist> -- <alist> -- <slist>]
${IND}  r <number> [<vlist> -- <alist> -- <slist>]
${IND}                         rip some streams of the title <number>,
${IND}                         either the ones given in the lists or
${IND}                         if they are missing the user is asked 
${IND}                         interactively. The indices for the
${IND}                         lists a/re 0-based.

${IND}  preview <list>         Watch a preview of those tracks
${IND}  p <list>

${IND}  streamlist <list>      Print a list of streams for the titles
${IND}  s <list>               given in the list.

${IND}  name <list>            Change the name of each of the titles
${IND}  n <list>               in the list.

${IND}  bulkname <list>        Change the name of all these titles 
${IND}  b <list>               by specifying a pattern including a construct
                               like {01..04} that gets expanded to 01, 02, 03, 04

${IND}  contents <min_length>  Print the contents of the DVD
${IND}  c                      ie the list of titles and title names
${IND}                         <min_length> gives the minimum length
${IND}                         in seconds a title needs to have to be
${IND}                         listed.

${IND}  eject                  Eject the DVD and exit script.
${IND}  e

${IND}  vim                    Edit all titles using the editor selected
${IND}  vi                     via the EDITOR environment variable
${IND}  v

${IND} wikipedia <list>        Use wikipdia to obtain info about the DVD
${IND} w <list>                and rename titles accordingly.

${IND}  quit                   Exit the script.
${IND}  q

${IND}  help                   Provide this help.
${IND}  h

${IND}The number in brackets gives the title automatically selected 
${IND}if the user omits a title list or title number of a command.
${IND}Also the most recently used command is repeated on a simple 
${IND}enter.
EOF
}

do_vi() {
	if [ -z "$EDITOR" ]; then
		echo "Variable EDITOR empty. Please set to your favourite editor to use"
		return
	fi

	local TMP=$(mktemp)
	echo "$TITLES" > $TMP
	local MIN=$(echo "$TITLES" | wc -l)
	$EDITOR $TMP || return
	TITLES=`< $TMP awk -v "minlines=$MIN" '
		{ print }
		END {
			for (i=NR+1; i <= minlines; ++i) {
				print "Track_" i
			}
		}
	'`
	rm ${TMP}
}

do_eject() {
	eject $DVDdev
}

do_rip() {
	#$1:	title number
	#$2:	optional VLIST
	#$3:	optional ALIST
	#$4:	optional SLIST
	################################

	NUM="$1"
	TITLE=`echo "$TITLES" | awk -v num="$NUM" 'NR == num'`

	echo "Creating project directory $WD/$TITLE"
	mkdir "$WD/$TITLE"

	#goto subshell:
	(
		cd "$WD/$TITLE"

		rip_dump $NUM
		if [ -z "$2" ]; then
			#no list given
			demux_dump $NUM || return
		else
			demux_dump $NUM list "$2" "$3" "$4" || return
		fi

		merge_dumpfiles "$NUM" "$TITLE"

		if [ "$DEBUG" != "y" ]; then
			read -p "${IND}Remove temporary files? (y/N) >" RES
			[ "$RES" = "y" ] && remove_dumpfiles "$NUM"
		fi
	)

	echo ""
	echo "#############################################################"
	echo "#############################################################"
	echo "#############################################################"
	echo ""
}

do_ripall() {
	local NUM
	for NUM in $@; do
		TITLE=`echo "$TITLES" | awk -v num="$NUM" 'NR == num'`
		echo "Ripping $TITLE, number $NUM"
		echo
		echo "Creating project directory $WD/$TITLE"
		mkdir "$WD/$TITLE"

		#goto subshell:
		(
			cd "$WD/$TITLE"

			rip_dump $NUM

			#-- ANCIENT VERSION:
			#   Demux everything and then merge again:
			#demux_dump $NUM all
			#merge_dumpfiles "$NUM" "$TITLE"

			#-- OLD VERSION:
			#  just merge the vob file into an mkv: 
			#merge_dumpvob "$NUM" "$TITLE" #convert all streams directly from vob to mkv
			#  PROBLEM: This does not take the subtitles with it.



			#-- CURRENT VERSION:
			#TODO: put in some in-between-layer function, similar to demux_dump
			#      maybe with sth like a list of stream types to demux (eg, demux_dump vid, demux_dump aud&vid ...)
			#  demux subtitles and merge with audio and video from vob which mkvmerge can extract natively

			local VOB="`get_dump_fileprefix "$NUM"`.vob"
			echo ""
			echo "##############################################"
			echo "# -- Demuxing sub streams of $VOB -- #"
			echo "##############################################"
			echo ""

			if ! select_subs "$NUM" all ""; then
				return 1
			fi

			echo ""
			echo "-------------------------------------------------------------"
			echo "-------------------------------------------------------------"
			echo ""

			demux_subs "$VOB"

			# convert all video and audio streams directly from vob to mkv
			# take care of demuxed subtitles
			merge_dumpvob "$NUM" "$TITLE" "y"

			[ "$DEBUG" != "y" ] && remove_dumpfiles "$NUM" #remove temporary vob file
		)

		echo ""
		echo "#############################################################"
		echo "#############################################################"
		echo "#############################################################"
		echo ""
	done

	echo "${IND}No temporary vob file was removed. Please delete them manually."
	echo
}

do_preview() {
	#$@ list of preview numbers to watch
	#watch a preview on one ore more tracks

	local NUM
	for NUM in $@; do
		echo "${IND}Playing preview for track $NUM"
		xterm -T "Preview for track $NUM"  -e "mplayer dvd://$NUM//$DVDdev"
	done
}

do_streamlist() {
	local NUM
	for NUM in $@; do
		mplayer dvd://$NUM//$DVDdev --novideo --nosound --nosub |& awk -v "ind=${IND}" '
			/Missing video stream/ { next };
			/^debux/ { next };
			/stream|number|anäle|sub/ { print ind $0 }
		' 
		
	done
}

do_name() {
	local NUM
	for NUM in $@; do
		TITLE=`echo "$TITLES" | awk -v num="$NUM" 'NR == num'`
		read -e -p "${IND}Track name of title $NUM: " -i "$TITLE" TITLE
		TITLES=`echo "$TITLES" | awk -v num="$NUM" -v val="$TITLE" 'NR == num {print val;next}; {print}'`
	done
}

do_bulkname() {
	local PATTERN
	read -e -p "${IND}Please enter Pattern: " -i "Track_{1..$#}" PATTERN

	local EXP_TITLES=$(expand_brace_pattern "$PATTERN")
	if [[ $(echo "$EXP_TITLES" | wc ) != $# ]]; then
		echo "Number of titles generated from the Pattern and number"
		echo "of titles supplied as args does not match"
		return 1
	fi
	local NUM
	local CNT=0
	for NUM in $@; do
		((CNT++))
		VAL=`echo "$EXP_TITLES" | cut -d " " -f $CNT`
		TITLES=`echo "$TITLES" | awk -v num="$NUM" -v val="$VAL" 'NR == num {print val;next}; {print}'`
	done
}

do_wikipedia() {
	local URL
	read -e -p "${IND}Enter URL (including anchor into correct section): " URL

	local ANCHOR=${URL##*"#"}
	if [ -z "$ANCHOR" ]; then 
		echo "No URL with anchor given." >&2
		return 1
	fi

	local TABLE
	if ! TABLE=$(html_extract_tables.py --url "$URL" --regex ".*id=\"$ANCHOR.*" --first); then
		echo "Could not obtain table from URL" >&2
		return 1
	fi

	echo
	echo "${IND}Table downloaded:"
	echo "$TABLE" | awk -v "ind=$IND" 'NR %5 == 0 { printf ind "%4i: %s\n", NR, $0; next } ; { printf ind "      %s\n", $0; next }'

	#awk substitution code
	local AWKSUB="
			gsub(/( )/,\"_\",str)
			gsub(/(,|'|?|!|&|\"|\(|\))/,\"\",str)
			gsub(/_+/,\"_\",str)
		"
		

	local AWKFIELDS # fields string for awk
	local FORMATSTR="" # format string with which fields are printed
	local RECORDS # list of records (rows) to use
	while true; do 
		echo 
		read -e -p "${IND}Enter list of fields to use (1-based): "  LIST
		[ -z "$LIST" ] && return 
		LIST=$(expand_list "$LIST")

		if [ -z "$FORMATSTR" ]; then
			local C
			for ((C=0; C < $(len_of_list $LIST); ++C)); do
				FORMATSTR="$FORMATSTR%s"
				AWKFIELDS="$AWKFIELDS, \$$(echo "$LIST" | cut -f $((C+1)) -d " ")"
			done
		fi
		
		read -e -p "${IND}Enter printf format string: " -i "$FORMATSTR" FORMATSTR
		[ -z "$FORMATSTR" ] && return 
		read -e -p "${IND}Enter list of line numbers of rows to use: " -i "2-$(($#+1))" RECORDS
		[ -z "$RECORDS" ] && return 
		RECORDS=$(expand_list "$RECORDS")

		if [ $# != $(len_of_list $RECORDS) ]; then
			echo "Number of records and number of items to rename does not agree"
			continue
		fi

		echo
		echo "${IND}The assigned titles would look like:"
		local I
		for I in $RECORDS; do
			echo "$TABLE" | awk "
				BEGIN {FS=\"\t\"}; 
				NR == $I {
					str=sprintf(\"$FORMATSTR\" $AWKFIELDS)
					$AWKSUB
					print str
			       	}" | sed -e "s/^/${IND}  /g"
		done

		local RES
		read -e -p "${IND}Continue? (Y/n)" RES
		[ -z "$RES" ] && RES=y
		[ "$RES" == "y" ] && break
	done

	local NUM
	local VAL
	local CNT=0
	for NUM in $@; do
		((CNT++))
		VAL=`echo "$RECORDS" | cut -d " " -f $CNT`
		VAL=$(echo "$TABLE" | awk "
			BEGIN {FS=\"\t\"}; 
			NR == $VAL {
				str=sprintf(\"$FORMATSTR\" $AWKFIELDS)
				$AWKSUB
				print str
			}")
		TITLES=`echo "$TITLES" | awk -v num="$NUM" -v val="$VAL" 'NR == num {print val;next}; {print}'`
	done
}

####################################################################

rip_dump() {
	#rip one or more tracks to a sequence of dumpfiles called dump$NUM.vob
	#Also extract chapter information for these titles

	local NUM
	local DVDPATH
	local DUMPFILEPREFIX
	local CHAPTERFILENAME
	for NUM in $@; do
		DVDPATH=`get_dvd_path $NUM`
		DUMPFILEPREFIX=`get_dump_fileprefix $NUM`
		CHAPTERFILENAME=`get_chapter_filename $NUM`

		echo ""
		echo "################################################"
		echo "# -- Start ripping $DUMPFILEPREFIX.vob from Track $NUM -- #"
		echo "################################################"
		echo ""
		echo_debug_log "rip_dump mplayer command to dump vob file:"
		echo_debug_log "        mplayer \"$DVDPATH\" -v -dumpstream -dumpfile $DUMPFILEPREFIX.vob"
		mplayer "$DVDPATH" -v -dumpstream -dumpfile $DUMPFILEPREFIX.vob 
		echo ""
		echo "-------------------------------------------------------------"
		echo
		echo "Extracting chapter information for track $NUM" 
		echo 
		echo_debug_log "rip_dump dvdxchap command to dump chapter file:"
		echo_debug_log "        dvdxchap -t $NUM $DVDdev > \"$CHAPTERFILENAME\""
		dvdxchap -t $NUM $DVDdev > "$CHAPTERFILENAME"
		echo 
		echo "-------------------------------------------------------------"
		echo "-------------------------------------------------------------"
		echo

		

	done
}

merge_dumpfiles() {
	#$1: DVD title number
	#$2: Title of the final mkv file
	##########################################################

	local NUM=$1
	PREFIX=`get_dump_fileprefix "$NUM"`
	#    PREFIX:  dirname and basename of the vob file
	#              => the prefix for all video, audio and sub streams

	#The chaptername file (if it exists)
	local CHAPTERFILENAME=`get_chapter_filename $NUM`

	echo Merging mkv file:
	local CL=""
	[ -f "$CHAPTERFILENAME" ] && CL="$CL --chapters \"$CHAPTERFILENAME\""

	#Append files:
	local CFILES=""
	ls "$PREFIX"video* >> /dev/null 2>&1 && CFILES="$CFILES \"$PREFIX\"video*"
	ls "$PREFIX"audio* >> /dev/null 2>&1 && CFILES="$CFILES \"$PREFIX\"audio*"
	ls "$PREFIX"sub* >> /dev/null 2>&1 && CFILES="$CFILES \"$PREFIX\"sub*"

	if [ -z "$CFILES" ]; then
		echo "No files to merge into mkv"
		return 0
	fi
	echo_debug_log "mkvmerge line in merge_dumpfiles: \"mkvmerge $CL $CFILES -o \"$2\".mkv\""
	eval "mkvmerge $CL $CFILES -o \"$2\".mkv"

	echo ""
	echo "-------------------------------------------------------------"
	echo "-------------------------------------------------------------"
	echo ""
}

merge_dumpvob() {
	#$1: DVD title number
	#$2: Title of the final mkv file
	#$3: Optional: merge subs -- "y" or "n" (defaults to "n")
	#              if "y" all subtitles that are found in the folder are merged into the mkv
	############################################################

	local NUM=$1
	local MERGE_SUBS=${3:-n}

	PREFIX=`get_dump_fileprefix "$NUM"`
	#    PREFIX:  dirname and basename of the vob file
	#              => the prefix for all video, audio and sub streams

	#The chaptername file (if it exists)
	local CHAPTERFILENAME=`get_chapter_filename $NUM`

	echo Merging mkv file:
	local CL=""
	[ -f "$CHAPTERFILENAME" ] && CL="$CL --chapters \"$CHAPTERFILENAME\""

	#Append files:
	CL="$CL \"$PREFIX.vob\""
	if [ "$MERGE_SUBS" == "y" ]; then
		ls "$PREFIX"sub* >> /dev/null 2>&1 && CL="$CL \"$PREFIX\"sub*"
	fi
	echo_debug_log "mkvmerge line in merge_dumpvob: \"mkvmerge $CL -o \"$2\".mkv\""
	eval "mkvmerge $CL -o \"$2\".mkv"

	echo ""
	echo "-------------------------------------------------------------"
	echo "-------------------------------------------------------------"
	echo ""
}

remove_dumpfiles() {
	#$1: DVD title number
	######################

	local NUM=$1
	PREFIX=`get_dump_fileprefix "$NUM"`
	local CHAPTERFILENAME=`get_chapter_filename $NUM`
	#    PREFIX:  dirname and basename of the vob file
	#              => the prefix for all video, audio and sub streams
	rm -f "$PREFIX"audio*
	rm -f "$PREFIX"video*
	rm -f "$PREFIX"sub*
	rm -f "$PREFIX.vob"
	rm -f "$CHAPTERFILENAME"
}

#####################################################################

demux_dump() {
	#$1: DVD title number
	#$2: all | ask | list -- optional argument; defaults to ask
	#    all:    demuxes all audio/vide/subtitle streams found
	#    ask:    ask users which streams to demux
	#    list:   expect 3 lists of indices as $3,$4 and $5 with 
	#            the following content:
	#               $3: video indices
	#               $4: audio indices
	#               $5: subtitle indices
	#############################################################


	#TODO:  maybe add sth like a list of stream types to demux (eg, demux_dump vid, demux_dump aud&vid ...)
	#       see also todo in  do_ripall


	#Parse args
	local NUM="$1"
	VOB="`get_dump_fileprefix "$NUM"`.vob"
	OPT="$2"
	[ -z "$OPT" ] && OPT="ask"

	if [ "$OPT" == "list" ]; then
		VL=`expand_list $3`
		AL=`expand_list $4`
		SL=`expand_list $5`
	fi

	echo ""
	echo "#############################"
	echo "# -- Demuxing $VOB -- #"
	echo "#############################"
	echo ""

	FFMPEG=`$FFMPEGCMD -i "$VOB" 2>&1`

	echo ""
	echo "$FFMPEG" | grep -A15 "^Input "
	echo 


	if ! select_vid "$NUM" $OPT "$VL"; then
		return 1
	fi

	if ! select_aud "$NUM" $OPT "$AL"; then
		return 1
	fi

	if ! select_subs "$NUM" $OPT "$SL"; then
		return 1
	fi


	echo ""
	echo "-------------------------------------------------------------"
	echo "-------------------------------------------------------------"
	echo ""


	demux_vid "$VOB"
	demux_aud "$VOB"
	demux_subs "$VOB"
}

ffmpeg_to_type_list() {
	#$1 type of list to extract; valid are "Audio" and "Video"

	if [ "$1" == "Audio" ]; then
		local TYPE="Audio"
	elif [ "$1" == "Video" ]; then
		local TYPE="Video"
	else
		echo "Assert: Wrong type of list to extract from ffmpeg output."
		exit 1
	fi

	awk -v type="$TYPE" '
		function trimboth(str) {
			gsub(/^[[:space:]]*/,"",str)
			gsub(/[[:space:]]*$/,"",str)
			return str
		}

		function hasElem(elem,arr) {
			for (el in arr) {
				if (arr[el] == elem) return "true"
			}
			return "" #false
		}
	
		function extn_codec(params) {
			#returns extension and codec separated by a space character

			#split params and trim:
			split(params, arr , ",")
			gsub(/\(Main\)$/,"",arr[1])	#purges the (Main) in first param
			for (i = 1; i <= length(arr); i++)
				arr[i] = trimboth(arr[i])

			switch (arr[1]) {
				case "mpeg2video":
					return "mpeg copy"
				
				case /^dca[[:space:]].*/:	#usually something like dca (DTS ... )
					return "dts copy"
				
				case /^dts[[:space:]].*/:	#usually something like dts (DTS ... )
					return "dts copy"
				
				case "pcm_dvd":
					#signed 20|24-bit big-endian
					if (hasElem("s32",arr))	#actually 32 bits
						return "wav pcm_s32le" 
					if (hasElem("s24",arr))	#actually 24 bits
						return "wav pcm_s24le" 
					if (hasElem("s16",arr))	#actually 24 bits
						return "wav pcm_s16le" 

				case /pcm_s16[lb]e/:	#eg pcm_s16be
					return "wav pcm_s16le"
				
				case /pcm_s32[lb]e/:	#eg pcm_s16be
					return "wav pcm_s32le"
				
				case /pcm_s24[lb]e/:	#eg pcm_s16be
					return "wav pcm_s24le"
				
				#case bla:
				#	return "bla2 copy"
				default:
					return arr[1] " copy"
			}
		}
		$1 == "Stream" && $3 == type ":" {
							streamNo = substr($2,2,index($2,"[")-2)
							gsub(/\./,":",streamNo)
							restStr=""
							for (x=4; x<=NF; x++) {restStr= restStr " " $x}
							#restStr now contains parameters for this stream (eg. mpeg2video (Main), yuv420p, 720x480 [PAR 32:27 DAR 16:9], 4000 kb/s, 29.97 fps, ...)
						       	print (streamNo, " ", extn_codec(restStr) ," y" )
					       	}
		' #End of AWK code.
}

select_vid() {
	#fills the variables VS and VLENGTH containing info about the video streams to rip.
	#
	#$1: DVD title number
	#$2: all | ask | list -- optional argument; defaults to ask
	#$3: if list, list of indices of video streams to demux
	###########################################################

	echo "Selecting VIDEO streams"
	#Contains the video steams: <NR> <EXT> <CODEC> <DEMUX?>
	#                           <NR> <EXT> <CODEC> <DEMUX?> ...
	VS=`echo "$FFMPEG" | ffmpeg_to_type_list "Video" `
	VLENGTH=`echo "$VS" | wc -l`

	local OPT="$2"
	[ -z "$OPT" ] && OPT="ask"

	#-----------------------------------------------------------------
	[ "$OPT" == "all" ] && return #all are already selected!

	#-----------------------------------------------------------------
	if [ "$OPT" == "list" ]; then
		#set all to no:
		VS=`echo "$VS" | awk '{print $1 " " $2 " " $3 " n"}'`

		local CNT
		for CNT in $3; do
			if ! VS=`echo -n "$VS" | awk -v val="$((CNT+1))" 'BEGIN{ec=1}; NR == val {print $1 " " $2 " " $3 " y";ec=0;next }; {print }; END{exit ec}'`; then
				echo "${IND}Could not interpret item of VIDEO stream list: $CNT"
				return 1
			else
				local NUM=`echo "$VS" | awk -v val="$((CNT+1))" 'NR == val { print $1 } '`
				local TPE=`echo "$VS" | awk -v val="$((CNT+1))" 'NR ==  val { print $2 } '`
				echo "${IND}Demuxing VIDEO stream $NUM($TPE)."
			fi
		done
		echo_debug_log "select_vid $1 $2 $3 resulted in a VS with length $VLENGTH:"
		echo "$VS" | sed "s/^/     /g" | cat_debug_log
		return
	fi

	#-----------------------------------------------------------------
	#OPT == ask
	local CNT=0
	while [ $CNT -lt $VLENGTH ]; do
		CNT=`expr $CNT + 1`
		local NUM=`echo "$VS" | awk -v val="$CNT" 'NR == val { print $1 } '`
		local TPE=`echo "$VS" | awk -v val="$CNT" 'NR ==  val { print $2 } '`
		read -p "${IND}Do you want to demux VIDEO stream $NUM ($TPE)? (Y/n) >" RES
		[ "$RES" != "n" ] && RES="y"
		VS=`echo "$VS" | awk -v val="$CNT" -v res="$RES" 'NR == val {print $1 " " $2 " " $3 " " res}; NR != val {print }'`
	done

	echo_debug_log "select_vid $1 $2 $3 resulted in a VS with length $VLENGTH:"
	echo "$VS" | sed "s/^/     /g" | cat_debug_log
}

select_aud() {
	#fills the variables AS and ALENGTH containing info about the subtitles to rip.
	#
	#$1: DVD title number
	#$2: all | ask | list -- optional argument; defaults to ask
	#$3: if list, list of indices of audio streams to demux
	###########################################################

	echo "Selecting AUDIO streams"
	#Contains the audio steams: <NR> <EXT> <CODEC> <DEMUX?>
	#                           <NR> <EXT> <CODEC> <DEMUX?> ...
	AS=`echo "$FFMPEG" | ffmpeg_to_type_list "Audio" `
	ALENGTH=`echo "$AS" | awk 'BEGIN {c=0}; {c++}; END {print c}'`

	local OPT="$2"
	[ -z "$OPT" ] && OPT="ask"

	#-----------------------------------------------------------------
	[ "$OPT" == "all" ] && return #all are already selected!

	#-----------------------------------------------------------------
	if [ "$OPT" == "list" ]; then
		#set all to no:
		AS=`echo "$AS" | awk '{print $1 " " $2 " " $3 " n"}'`

		local CNT
		for CNT in $3; do
			if ! AS=`echo -n "$AS" | awk -v val="$((CNT+1))" 'BEGIN{ec=1}; NR == val {print $1 " " $2 " " $3 " y";ec=0;next }; {print }; END{exit ec}'`; then
				echo "${IND}Could not interpret item of AUDIO stream list: $CNT"
				return 1
			else
				local NUM=`echo "$AS" | awk -v val="$((CNT+1))" 'NR == val { print $1 } '`
				local TPE=`echo "$AS" | awk -v val="$((CNT+1))" 'NR ==  val { print $2 } '`
				echo "${IND}Demuxing AUDIO stream $NUM($TPE)."
			fi
		done
		echo_debug_log "select_aud $1 $2 $3 resulted in a AS with length $ALENGTH:"
		echo "$AS" | sed "s/^/     /g" | cat_debug_log
		return
	fi

	#-----------------------------------------------------------------
	#OPT == ask
	local CNT=0
	while [ $CNT -lt $ALENGTH ]; do
		CNT=`expr $CNT + 1`
		local NUM=`echo "$AS" | awk -v val="$CNT" 'NR == val { print $1 } '`
		local TPE=`echo "$AS" | awk -v val="$CNT" 'NR ==  val { print $2 } '`
		read  -p "${IND}Do you want to demux AUDIO stream $NUM ($TPE)? (Y/n) >" RES
		[ "$RES" != "n" ] && RES="y"
		AS=`echo "$AS" | awk -v val="$CNT" -v res="$RES" 'NR == val {print $1 " " $2 " " $3 " " res}; NR != val {print }'`
	done

	echo_debug_log "select_aud $1 $2 $3 resulted in a AS with length $ALENGTH:"
	echo "$AS" | sed "s/^/     /g" | cat_debug_log
}

select_subs() {
	#fills the variables SUBS and SLENGTH containing info about the subtitles to rip.
	#
	#$1: DVD title number
	#$2: all | ask | list -- optional argument; defaults to ask
	#$3: if list, list of indices of subtitles to demux
	###########################################################

	echo "Selecting subtitle streams"
	local DVDPATH=`get_dvd_path "$1"`
	SUBS=`mplayer "$DVDPATH" --novideo --nosound --nosub |& awk '/sid/ { print $5 " " $7 " y" }'`
	#Important note: Both stdout and stderr piped through awk !

	SLENGTH=0
	[ "$SUBS" ] && SLENGTH=`echo "$SUBS" | wc -l`

	local OPT="$2"
	[ -z "$OPT" ] && OPT="ask"

	#-----------------------------------------------------------------
	[ "$OPT" == "all" ] && return #all are already selected!

	#-----------------------------------------------------------------
	if [ "$OPT" == "list" ]; then
		#set all to no:
		SUBS=`echo "$SUBS" | awk '{print $1 " " $2 " n"}'`

		local CNT
		for CNT in $3; do
			if ! SUBS=`echo -n "$SUBS" | awk -v val="$CNT"  'BEGIN {ec=1}; $1 == val {print $1 " " $2 " y";ec=0;next }; {print }; END{exit ec}'`; then
				echo "${IND}Could not interpret item of subtitle stream list: $CNT"
				return 1
			else
				LANGE=`echo "$SUBS" | awk -v id=$CNT '$1 == id {print $2}'`
				echo "${IND}Demuxing Subtitle stream $CNT ($LANGE)."
			fi
		done

		echo_debug_log "select_subs $1 $2 $3 resulted in a SUBS with length $SLENGTH:"
		echo "$SUBS" | sed "s/^/     /g" | cat_debug_log
		return
	fi

	#-----------------------------------------------------------------
	#OPT == ask
	local CNT=0
	while [ $CNT -lt $SLENGTH ]; do
		LANGE=`echo "$SUBS" | awk -v id=$CNT '$1 == id {print $2}'`

		read  -p "${IND}Do you want to rip Subtitle Stream $CNT ($LANGE)? (Y/n) >" RES
		[ "$RES" != "n" ] && RES="y"
		SUBS=`echo "$SUBS" | awk -v val="$CNT" -v res="$RES" '$1 == val {print $1 " " $2 " " res}; $1 != val {print }'`

		CNT=`expr $CNT + 1`
	done

	echo_debug_log "select_subs $1 $2 $3 resulted in a SUBS with length $SLENGTH:"
	echo "$SUBS" | sed "s/^/     /g" | cat_debug_log
}

demux_vid() {
	#reads the variable VS and demuxes the video streams requested
	#into the same dir as $1
	#$1: filename of vob
	##############################################################

	#determine base and dir:
	local DIR=`dirname "$1"`
	local BN=`basename "$1" ".vob"`

	CNT=0
	while [ $CNT -lt $VLENGTH ]; do
		CNT=`expr $CNT + 1`
		[ "`echo "$VS" | awk -v val="$CNT" 'BEGIN {f="n"}; NR ==  val { f=$4 }; END { print f }'`" ==  "n" ] && continue
		STREAM=`echo "$VS" | awk -v val="$CNT" 'NR ==  val { print $1 }'`
		EXT=`echo "$VS" | awk -v val="$CNT" 'NR ==  val { print $2 }'`
		CODEC=`echo "$VS" | awk -v val="$CNT" 'NR ==  val { print $3 }'`

		echo_debug_log "demux_vid iteration $CNT:"
	       	echo_debug_log "        ffmpeg command is $FFMPEGCMD -i "$1" -map $STREAM -vcodec $CODEC -qscale 0 -an $DIR/${BN}video$CNT.$EXT"
		$FFMPEGCMD -i "$1" -map $STREAM -vcodec $CODEC -qscale 0 -an $DIR/${BN}video$CNT.$EXT
		echo ""
		echo "-------------------------------------------------------------"
		echo "-------------------------------------------------------------"
		echo ""
	done
}

demux_aud() {
	#reads the variable AS and demuxes the audio streams requested
	#into the same dir as $1
	#$1: filename of vob
	##############################################################

	#determine base and dir:
	local DIR=`dirname "$1"`
	local BN=`basename "$1" ".vob"`

	CNT=0
	while [ $CNT -lt $ALENGTH ]; do
		CNT=`expr $CNT + 1`
		R=`echo "$AS" | awk -v val="$CNT" 'BEGIN {f="n"}; NR ==  val { f=$4 }; END { print f }'`
		[ "$R"  ==  "n" ] && continue
		STREAM=`echo "$AS" | awk -v val="$CNT" 'NR ==  val { print $1 }'`
		EXT=`echo "$AS" | awk -v val="$CNT" 'NR ==  val { print $2 }'`
		CODEC=`echo "$AS" | awk -v val="$CNT" 'NR ==  val { print $3 }'`

		echo_debug_log "demux_aud iteration $CNT: ffmpeg command is:"
		echo_debug_log "        $FFMPEGCMD -i "$1" -map $STREAM -acodec $CODEC -qscale 0 $DIR/${BN}audio$CNT.$EXT"
		$FFMPEGCMD -i "$1" -map $STREAM -acodec $CODEC -qscale 0 $DIR/${BN}audio$CNT.$EXT

		echo ""
		echo "-------------------------------------------------------------"
		echo "-------------------------------------------------------------"
		echo ""
	done
}

demux_subs() {
	#reads the variable SUBS and demuxes the subtitle streams requested.
	#$1: filename of vob
	##############################################################

	# Check that we have mencoder
	if [ $SLENGTH -gt 0 ]; then
		if ! type mencoder &> /dev/null; then
			echo "We do not have mencoder. Skip ripping subtitles."
			return
		fi
	fi

	#determine base and dir:
	local DIR=`dirname "$1"`
	local BN=`basename "$1" ".vob"`

	local CNT=0
	while [ $CNT -lt $SLENGTH ]; do
		CNT=`expr $CNT + 1`
		SID=`echo "$SUBS" | awk -v val="$CNT" 'NR == val { print $1; exit }'`
		[ "`echo "$SUBS" | awk -v id=$SID '$1 == id {print $3; exit}'`" == "n" ] && continue
		LANGE=`echo "$SUBS" | awk -v id=$SID '$1 == id {print $2; exit}'`

		echo_debug_log "demux_subs iteration $CNT: mplayer command is:"
	        echo_debug_log "        mplayer \"$1\" --nosound --vc=null --vo=null --noframedrop --benchmark --slang $LANGE --sid $SID ???"
	        echo_debug_log "        mencoder \"$1\" -nosound -ovc frameno -o /dev/null -slang $LANGE -sid $SID -vobsuboutindex $SID -vobsuboutid $LANGE -vobsubout $DIR/${BN}sub${CNT}_${LANGE}"
		mencoder "$1" -nosound -ovc frameno -o /dev/null -slang $LANGE -sid $SID -vobsuboutindex $SID -vobsuboutid $LANGE -vobsubout $DIR/${BN}sub${CNT}_${LANGE}
			
		echo ""
		echo "-------------------------------------------------------------"
		echo "-------------------------------------------------------------"
		echo ""

		if [ ! -s $DIR/${BN}sub${CNT}_${LANGE}.sub ]; then
			# empty subtitle
			rm $DIR/${BN}sub${CNT}_${LANGE}.sub
			rm $DIR/${BN}sub${CNT}_${LANGE}.idx
		fi
	done
}

#######################################################################

cat_debug_log << EOF

#####################################################
#-- $(date) --#
####################################
EOF

chkPreReq	#check prerequisites

set_dvd_dev "$1"
set_lsdvd
set_maxmem

command_prompt
exit 0

#TODO:
#see above: problems with pcm_dvd (see also http://www.hydrogenaudio.org/forums/index.php?showtopic=83421 )
