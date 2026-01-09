#!/usr/bin/env bash

#
# Ashpodder - forked from Mashpodder for my own needs at the time
#
# Mashpodder by Chess Griffin <chess@chessgriffin.com>
# Licensed under the GPLv3
#
# Originally based on BashPodder by Linc Fessenden 12/1/2004

VERSION='1.0'
INFO='0'

### START USER CONFIGURATION
# Default values can be set here. Command-line flags override some of these.

# Display diagnostic info by default  set to "1"
DEBUG='0'

# BASEDIR: Location of podcast directories
BASEDIR=$HOME/podcasts

# DATESTRING: Valid date format for date-based archiving.  Default is
# '%Y%m%d'.  Can be changed to other valid formats.  See man date.
DATESTRING='%Y%m%d'

#RSSFILE: Default is 'kpi.conf.'  Can be changed to another file name.
RSSFILE=$BASEDIR/ashpodder.conf

#PARSE_ENCLOSURE: Location of parse_enclosure.xsl file.
PARSE_ENCLOSURE=$BASEDIR/parse_enclosure.xsl

# FIRST_ONLY: Default '' means look to ashpodder.conf on whether to download or
# update; 1 will override ashpodder.conf and download the newest episode
FIRST_ONLY=''

# M3U: Default '' means no m3u playlist created; 1 will create m3u playlist
M3U=''

# UPDATE: Default '' means look to kpi.conf on whether to download or update; 1
# will override kpi.conf and cause all feeds to be updated (meaning episodes
# will be marked as downloaded but not actually downloaded).
UPDATE=''

# VERBOSE: Default '' is quiet output; 1 is verbose
VERBOSE='1'

# WGET_QUIET: Default is '-q' for quiet wget output; change to '' for wget output
#WGET_QUIET='-q'
WGET_QUIET=''

# WGET_TIMEOUT: Default is 30 seconds; can decrease or increase if some files
# are cut short. Thanks to Phil Smith for the bug report.
WGET_TIMEOUT='30'

# Update the iPod by default (0 = no)
IPOD='0'

# Download and process podcasts by default (0 = no)
PODCASTS='1'

### END USER CONFIGURATION

### No changes should be necessary below this line

SCRIPT=${0##*/}
#VER=svn_r$(cat ${0} | grep '$Id: ' | head -1 | \
#sed -e 's/^.*Id: ashpodder.sh \([0-9.]*\) .*$/\1/')
VER=svn
CWD=$(pwd)
INCOMING=$BASEDIR/incoming
TEMPLOG=$BASEDIR/ashpodder_temp.log
PODLOG=$BASEDIR/ashpodder.log
SUMMARYLOG=$BASEDIR/ashpodder_summary.log
TEMPRSSFILE=$BASEDIR/ashpodder.conf.temp

crunch () {
    echo -e "$@" | tr -s ' ' | fmt -78
}

trace() {
    if [ -z "$1" ]; then
        crunch "DEBUG: routine invoked without parameters at `date`"
        crunch "DEBUG: $1 at `date`"
        return 0
    else
        crunch "DEBUG: $1 at `date`"
        return 1
    fi
}

debugset () {
    if [ "$DEBUG" = "1" ]; then
        return 0
    else
        return 1
    fi
}

verbose () {
    if [ "$VERBOSE" = "1" ]; then
        return 0
    else
        return 1
    fi
}

sanity_checks () {
    if debugset; then
           trace "+++++ Entering sanity_checks ()"
    fi
    # Perform some basic checks
    local FEED ARCHIVETYPE DLNUM DATADIR DLURL DOPURGE PLAYLIST MAXNUM DOPURGE

    rm -f $TEMPRSSFILE
    touch $TEMPRSSFILE

    # Make sure the ashpodder.conf file or the file passed with -c switch exists
    if [ ! -e "$RSSFILE" ]; then
        crunch "The file $RSSFILE does not exist in $BASEDIR.  Run $0 -h \
            for usage. Exiting."
        exit 0
    fi

    # Check the ashpodder.conf and do some basic error checking
    while read LINE; do
        PLAYLIST=' '
        DLNUM="none"
        FEED=$(echo $LINE | cut -f1 -d ' ')
        ARCHIVETYPE=$(echo $LINE | cut -f2 -d ' ')
        DLNUM=$(echo $LINE | cut -f3 -d ' ')
        DOPURGE=$(echo $LINE | cut -f4 -d ' ')
        MAXNUM=$(echo $LINE | cut -f5 -d ' ')
        PLAYLIST=$(echo $LINE | cut -f6 -d ' ')

        # Skip blank lines and lines beginning with '#'
        if echo $LINE | grep -E '^#|^$' > /dev/null
                then
                continue
        fi

        if [[ "$DLNUM" != "none" && "$DLNUM" != "all" && \
            "$DLNUM" != "update" && $DLNUM -lt 1 ]]; then
            crunch "Something is wrong with the download type for $FEED. \
                According to $RSSFILE, it is set to $DLNUM. \
                It should be set to 'none', 'all', 'update', or a number \
                greater than zero.  Please check $RSSFILE.  Exiting"
            exit 0
        fi

        # Check type of archiving for each feed
        if [ "$DLNUM" = "update" ]; then
            DATADIR=$ARCHIVETYPE
        else
            if [ ! "$ARCHIVETYPE" = "date" ]; then
                DATADIR=$ARCHIVETYPE
            elif [ "$ARCHIVETYPE" = "date" ]; then
                DATADIR=$(date +$DATESTRING)
            else
                crunch "Error in archive type for $FEED.  It should be set \
                    to 'date' for date-based archiving, or to a directory \
                    name for directory-based archiving.  Exiting."
                exit 0
            fi
        fi

        if [ "$FIRST_ONLY" = "1" ]; then
            DLNUM="1"
        fi
        if [ "$UPDATE" = "1" ]; then
            DLNUM="update"
        fi
        echo "$FEED $DATADIR $DLNUM $DOPURGE $MAXNUM $PLAYLIST" >> $TEMPRSSFILE
        if debugset; then
           trace "LINE=$LINE"
           trace "FEED=$FEED"
           trace "DOPURGE=$DOPURGE"
           trace "MAXNUM=$MAXNUM"
           trace "PLAYLIST=$PLAYLIST"
        fi
    done < $RSSFILE
    if debugset; then
           trace "----- Leaving sanity_checks ()"
    fi
}

initial_setup () {
    if debugset; then
           trace "+++++ Entering initial_setup ()"
    fi
    # Get some things ready first

    # Print the date
    if verbose; then
        echo
        echo "################################"
        printf "Starting ashpodder.sh at "
        date
        echo
    fi

    # Make incoming temp folder if necessary
    if [ ! -e $INCOMING -a $PODCASTS -eq '1' ]; then
        if verbose; then
            echo "Creating temp folders."
        fi
    mkdir -p $INCOMING
    fi

    # Delete the temp log:
    if [ ! -e $INCOMING -a $PODCASTS -eq '1' ]; then
        rm -f $TEMPLOG
        touch $TEMPLOG
    fi

    # Create podcast log if necessary
    if [ ! -e $PODLOG -a $PODCASTS -eq '1' ]; then
        if verbose; then
            echo "Creating $PODLOG file."
        fi
        touch $PODLOG
    fi
    if debugset; then
           trace "----- Leaving initial_setup ()"
    fi
}

fix_url () {
    if debugset; then
           trace "+++++ Entering fix_url ()"
    fi

    # Take a url embedded in a feed and perform some fixes; also
    # get the filename
    local FIXURL

    FIXURL=$1

    # Get the filename
    FIRSTFILENAME=$(echo $FIXURL|awk -F / '{print $NF}')
    FILENAME=$(echo $FIRSTFILENAME|awk -F ? '{print $1}')

    # Remove parentheses in filenames
    FILENAME=$(echo $FILENAME | tr -d "()")

    # Replace URL hex sequences in filename (like %20 for ' ' and %2B for '+')
    FILENAME=$(echo "echo $FILENAME" \
        |sed "s/%\(..\)/\$(printf \"\\\\x\\1\")/g" |bash)

    # Replace spaces in filename with underscore
    FILENAME=$(echo $FILENAME | sed -e 's/ /_/g')

    # Fix Podshow.com numbers that keep changing
    FILENAME=$(echo $FILENAME | sed -e 's/_pshow_[0-9]*//')

    # Fix MSNBC podcast names for audio feeds from Brian Reichart
    if echo $FIXURL | grep -q "msnbc.*pd_.*mp3$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(pd_.*mp3$\)/\1/')
        return
    fi
    if echo $FIXURL | grep -q "msnbc.*pdm_.*mp3$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(pdm_.*mp3$\)/\1/')
        return
    fi
    if echo $FIXURL | grep -q "msnbc.*vh-.*mp3$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(vh-.*mp3$\)/\1/')
        return
    fi
    if echo $FIXURL | grep -q "msnbc.*zeit.*m4v$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(a_zeit.*m4v$\)/\1/')
    fi

    # Fix MSNBC podcast names for video feeds
    if echo $FIXURL | grep -q "msnbc.*pdv_.*m4v$"; then
        FILENAME=$(echo $FIRSTFILENAME | sed -e 's/.*\(pdv_.*m4v$\)/\1/')
        return
    fi

    # Remove question marks at end
    FILENAME=$(echo $FILENAME | sed -e 's/?.*$//')

    if debugset; then
           trace "----- Leaving initial_setup ()"
    fi

    if debugset; then
           trace "----- Leaving fix_url ()"
    fi
}

check_directory () {
    if debugset; then
           trace "+++++ Entering check_directory ()"
    fi

    # Check to see if DATADIR exists and if not, create it
    if [ ! -e $DATADIR ]; then
        crunch "The directory $DATADIR for $FEED does not exist. Creating \
            now..."
        mkdir -p $DATADIR
    fi
    if debugset; then
           trace "----- Leaving check_directory ()"
    fi
    return 0
}

fetch_podcasts () {
    if debugset; then
           trace "+++++ Entering fetch_podcasts ()"
    fi

    # This is the main loop
    local LINE FEED DATADIR DLNUM COUNTER FILE URL FILENAME DLURL PLAYLIST

    # Read the ashpodder.conf file and wget any url not already in the
    # podcast.log file:
    while read LINE; do
        PLAYLIST=' '
        FEED=$(echo $LINE | cut -f1 -d ' ')
        DATADIR=$(echo $LINE | cut -f2 -d ' ')
        DLNUM=$(echo $LINE | cut -f3 -d ' ')
        DOPURGE=$(echo $LINE | cut -f4 -d ' ')
        MAXNUM=$(echo $LINE | cut -f5 -d ' ')
        PLAYLIST=$(echo $LINE | cut -f6 -d ' ')
        COUNTER=0

        if debugset; then
           trace "LINE=$LINE"
           trace "FEED=$FEED"
           trace "DOPURGE=$DOPURGE"
           trace "MAXNUM=$MAXNUM"
           trace "PLAYLIST=$PLAYLIST"
        fi
        if verbose; then
            if [ "$DLNUM" = "all" ]; then
                crunch "Checking $FEED -- all episodes."
            elif [ "$DLNUM" = "none" ]; then
                crunch "No downloads selected for $FEED."
                echo
                continue
            elif [ "$DLNUM" = "update" ]; then
                crunch "Catching $FEED up in logs."
            else
                crunch "Checking $FEED -- last $DLNUM episodes."
            fi
        fi

        FILE=$(wget -q $FEED -O - | \
            xsltproc $PARSE_ENCLOSURE - 2> /dev/null) || \
            FILE=$(wget -q $FEED -O - | tr '\r' '\n' | tr \' \" | \
            sed -n 's/.*url="\([^"]*\)".*/\1/p')

        for URL in $FILE; do
            FILENAME=''
            if [ "$DLNUM" = "$COUNTER" ]; then
                break
            fi
            DLURL=$(curl -s -I -L -w %{url_effective} --url $URL | tail -n 1)
            fix_url $DLURL
            if debugset; then
                trace "Found $FILENAME, adding to TEMPLOG"
            fi
            echo $FILENAME >> $TEMPLOG

            if ! grep -x "^$FILENAME" $PODLOG > /dev/null; then
                if [ "$DLNUM" = "update" ]; then
                    if verbose; then
                        crunch "Adding $FILENAME to log."
                        echo "$FILENAME added to log at `date`" >> $SUMMARYLOG
                    fi
                    continue
                fi
                check_directory $DATADIR
                if [ ! -e $DATADIR/"$FILENAME" ]; then
                    if verbose; then
                        crunch "NEW:  Fetching $FILENAME and saving in \
                            directory $DATADIR."
                        echo "$FILENAME downloaded to $DATADIR" >> $SUMMARYLOG
                    fi
                    cd $INCOMING
                    wget $WGET_QUIET -c -T $WGET_TIMEOUT -O "$FILENAME" \
                        "$DLURL"
                    mv "$FILENAME" $BASEDIR/$DATADIR/"$FILENAME"
                    if [ ! -z "$PLAYLIST" ]; then
                        if debugset; then
                                trace "Found an iPod playlist"
                        fi
                        if [ ! -d $BASEDIR/ipod_playlists/"$PLAYLIST" ]; then
                                mkdir -pv $BASEDIR/ipod_playlists/"$PLAYLIST"
                        fi
                        ln -sv $BASEDIR/$DATADIR/"$FILENAME" \
                                $BASEDIR/ipod_playlists/"$PLAYLIST"/"$FILENAME"
                        if verbose; then
                                crunch "Saving $FILENAME to iPod playlist $PLAYLIST"
                        fi
                        if debugset; then
                                trace "`ls -l $BASEDIR/ipod_playlists/"$PLAYLIST" | head -n 1`"
                        fi
                    fi
                    cd $BASEDIR
                fi
            fi
            ((COUNTER=COUNTER+1))
        done
        # Create an m3u playlist:
        if [ "$DLNUM" != "update" ]; then
            if [ -n "$m3u" ]; then
                if verbose; then
                    crunch "Creating $datadir m3u playlist."
                fi
                ls $DATADIR | grep -v m3u > $DATADIR/podcast.m3u
            fi
        fi
        if verbose; then
            crunch "Done.  Continuing to next feed."
            echo
        fi
    done < $TEMPRSSFILE
    if [ ! -f $TEMPLOG ]; then
        if verbose; then
            crunch "Nothing to download."
        fi
    fi

    if debugset; then
           trace "----- Leaving fetch_podcasts ()"
    fi
}

final_cleanup () {
    if debugset; then
           trace "+++++ Entering final_cleanup ()"
    fi

    # Delete temp files, create the log files and clean up
    if verbose; then
        crunch "Cleaning up."
    fi
    cat $PODLOG >> $TEMPLOG
    sort $TEMPLOG | uniq > $PODLOG
    rm -f $TEMPLOG
    rm -f $TEMPRSSFILE
    if verbose; then
        echo "All done."
        if [ -e $SUMMARYLOG ]; then
            echo
            echo "++SUMMARY++"
            cat $SUMMARYLOG
            rm -f $SUMMARYLOG
        fi
        echo "################################"
    fi

    if debugset; then
           trace "----- Leaving final_cleanup ()"
    fi
}

check_mounted () {
    if debugset; then
           trace "+++++ Entering check_mounted ()"
    fi

    if debugset; then
           trace "----- Leaving check_mounted ()"
    fi

    if [ -d $IPOD_MOUNTPOINT/iPod_Control/.gnupod ]; then
        return 0
    else
        return 1
    fi
}

remove_played_podcasts () {
    if debugset; then
           trace "+++++ Entering remove_played_podcasts ()"
    fi

# Parse the play count from the XML file but and this is a big but,
# no sense in doing that until we have don an update from the ItunesDB
# so might as well perform that now

        tunes2pod.pl --force

# Now pare the XML file

    XML=$IPOD_MOUNTPOINT/iPod_Control/.gnupod/GNUtunesDB.xml
    if [ -e $XML ]; then
# purge all mp3 files with a genre of podcast and a non-xero playcount
# _if_ and only if the ashpodder.conf tells us to do so

# Now provide a scrobble using the tool of choice...
# coming soon...
    if debugset; then
           trace "----- Leaving remove_played_podcasts ()"
    fi
        return 0
    else
        return 0

    fi

}

add_new_podcasts () {
    if debugset; then
           trace "+++++ Entering add_new_podcasts ()"
    fi

# Now find new podcasts not already on iPod based on playlist or subscription
# if we have not reached maxnumber on ipod for playlist or subscription.

# Process the ashpodder.conf file
    local LINE FEED DATADIR MAXNUM COUNTER FILE URL FILENAME 
    local DLURL DOPURGE PLAYLIST
    while read LINE; do
        PLAYLIST=' '
        FEED=$(echo $LINE | cut -f1 -d ' ')
        DATADIR=$(echo $LINE | cut -f2 -d ' ')
        MAXNUM=$(echo $LINE | cut -f5 -d ' ')
        DOPURGE=$(echo $LINE | cut -f4 -d ' ')
        PLAYLIST=$(echo $LINE | cut -f6 -d ' ')
        COUNTER=0
        if debugset; then
           trace "LINE=$LINE"
           trace "FEED=$FEED"
           trace "DOPURGE=$DOPURGE"
           trace "MAXNUM=$MAXNUM"
           trace "PLAYLIST=$PLAYLIST"
        fi

        # Skip blank lines and lines beginning with '#'
        if echo $LINE | grep -E '^#|^$' > /dev/null
                then
                continue
        fi

        FILE=$(wget -q $FEED -O - | \
            xsltproc $PARSE_ENCLOSURE - 2> /dev/null) || \
            FILE=$(wget -q $FEED -O - | tr '\r' '\n' | tr \' \" | \
            sed -n 's/.*url="\([^"]*\)".*/\1/p')

        for URL in $FILE; do
            FILENAME=''
            if [ "$DLNUM" = "$COUNTER" ]; then
                break
            fi
            DLURL=$(curl -s -I -L -w %{url_effective} --url $URL | tail -n 1)
            fix_url $DLURL
            echo $FILENAME >> $TEMPLOG

            if ! grep -x "^$FILENAME" $PODLOG > /dev/null; then
                if [ "$DLNUM" = "update" ]; then
                    if verbose; then
                        crunch "Adding $FILENAME to log."
                        echo "$FILENAME added to log" >> $SUMMARYLOG
                    fi
                    continue
                fi
                check_directory $DATADIR
                if [ ! -e $DATADIR/"$FILENAME" ]; then
                    if verbose; then
                        crunch "NEW:  Fetching $FILENAME and saving in \
                            directory $DATADIR."
                        echo "$FILENAME downloaded to $DATADIR" >> $SUMMARYLOG
                    fi
                    cd $INCOMING
                    wget $WGET_QUIET -c -T $WGET_TIMEOUT -O "$FILENAME" \
                        "$DLURL"
                    mv "$FILENAME" $BASEDIR/$DATADIR/"$FILENAME"
                    cd $BASEDIR
                fi
            fi
            ((COUNTER=COUNTER+1))
        done
        # Create an m3u playlist:
        if [ "$DLNUM" != "update" ]; then
            if [ -n "$m3u" ]; then
                if verbose; then
                    crunch "Creating $datadir m3u playlist."
                fi
                ls $DATADIR | grep -v m3u > $DATADIR/podcast.m3u
            fi
        fi
        if verbose; then
            crunch "Done.  Continuing to next feed."
            echo
        fi
    done < $TEMPRSSFILE
    if [ ! -f $TEMPLOG ]; then
        if verbose; then
            crunch "Nothing to download."
        fi
    fi





        if [ "$PODCAST" -ne "" ]; then
                echo "Hello"
        fi


#    FILES="*"
#    for f in "$FILES"
#    do
#       echo "Processing $f file..."
#       # take action on each file. $f store current file name
#       file $f
#    done

    if debugset; then
           trace "----- Leaving add_new_podcasts ()"
    fi
}

update_ipod () {
    if debugset; then
           trace "+++++ Entering add_new_podcasts ()"
    fi

# Check to see if it is mounted
    if check_mounted; then
        if verbose; then
                echo
                echo "Updating iPod mounted as $IPOD_MOUNTPOINT..."
                echo
        fi
        echo 
# Remove non-zero playcount podcast files from iPod and
# remove them from the system if specified in ashpodder.conf
        remove_played_podcasts
# Add new unplayed podcasts to iPod
        add_new_podcasts
# Now cleanup the database on the iPod
        mktunes.pl
    else
        echo
        echo "Error $IPOD_MOUNTPOINT is not mounted or"\
                "$IPOD_MOUNTPOINT/iPod_Control/.gnupod is missing."
        echo
    fi

    if debugset; then
           trace "----- Leaving add_new_podcasts ()"
    fi
}

# THIS IS THE ACTUAL START OF SCRIPT
# Here are the command line switches
while getopts ":c:d:fmuvVhipD" OPT ;do
    case $OPT in
        i )         IPOD=1
                    ;;
        p )         PODCASTS=0
                    ;;
        c )         RSSFILE="$OPTARG"
                    ;;
        d )         DATESTRING="$OPTARG"
                    ;;
        f )         FIRST_ONLY=1
                    ;;
        m )         M3U=1
                    ;;
        u )         UPDATE=1
                    ;;
        v )         VERBOSE=1
                    ;;
        V )         INFO=1
                    ;;
        D )         DEBUG=1
                    ;;
        h|* )       cat << EOF
$SCRIPT $VER 2009-11-22
Usage: $0 [OPTIONS] <arguments>
Options are:

-c <filename>   Use a different config file other than ashpodder.conf.

-d <date>       Valid date string for date-based archiving.

-f              Override ashpodder.conf and download the first newest episode.

-h              Display this help message.

-m              Create m3u playlists.

-u              Override ashpodder.conf and only update (mark downloaded).

-i              Update iPod (assumes IPOD_MOUNTPOINT variable is set)

-p              Ignore podcast processing (do nothing if -i is not specified).

-v              Display verbose messages.

-V              Display version and quit. All other options are ignored.

-D              Display debug and diagnostic information.

ashpodder.conf is the standard configuration file.  Please see the sample ashpodder.conf for
how this file is to be configured.

Some of the default settings can be set permanently at the top of the script
in the 'USER CONFIGURATION' section or temporarily by passing a command
line switch.

EOF
                    exit 0
                    ;;
    esac
done

# End of option parsing
shift $(($OPTIND - 1))

cd $BASEDIR
if [ $INFO -eq '1' ]; then
        echo "ashpodder.sh version $VERSION"
        exit 0
fi
sanity_checks
initial_setup
if [ $PODCASTS -eq '1' ]; then
        fetch_podcasts
        final_cleanup
else
        echo "Ignoring podcasts -p passed."
fi
if [ $IPOD -eq '1' ]; then
        update_ipod
fi
cd $CWD
# Print the time we exited
if verbose; then
   echo
   printf "ashpodder.sh finished at "
   date
   echo "++++++++++++++++++++++++++++++++"
   echo
fi
exit 0
