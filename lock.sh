LOCKFILE=/tmp/`basename $0`.lock

trace ()
{
    opt=""
    if [ "$1" = "-n" ]
    then
	opt="$1"
	shift
    fi
    #echo $opt $$: `date` "$*"
    echo $opt "$*"
}

get_locker ()
{
    head -n 1 $LOCKFILE | awk '{print $1}'
}

get_sequence ()
{
    awk 'BEGIN {seq=0} {if ($2 > seq) {seq = $2}} END { print seq }' $LOCKFILE
}

_try_force_lock ()
{
    _locker=`get_locker`
    _proc=`ps agux | awk '{ print $2}' | grep "$_locker"`
    if [ "$_proc" = "" ]
    then
	_seq=`expr $(get_sequence) + 1`
	echo $$ $_seq >> $LOCKFILE
	_force_locker=`awk '$2 == "'$_seq'" { print $1; exit}' $LOCKFILE 2>/dev/null`
	if [ "$_force_locker" = $$ ]
	then
	    # we got the force lock, update with a normal lock
	    echo $$ > $LOCKFILE
	    return 0
	else
	    return 1
	fi
	return 1
    fi
    return 1
}

take_lock ()
{
    echo $$ >> $LOCKFILE
    _locker=`get_locker`
    if ! [ "$_locker" = $$ ]
    then
	# try to see if the locker still exists
	_proc=`ps agux | awk '{ print $2}' | grep "$_locker"`
	if [ "$_proc" = "" ]
	then
	    # locker has died? Let's take the lock
	    trace -n "Locker seems dead. Trying to take it... "
	    if _try_force_lock
	    then
		echo "Success!"
		return 0
	    else
		echo "Failed!"
		return 1
	    fi
	fi
	return 1
    fi
    return 0
}

release_lock ()
{
    _locker=`get_locker`
    if [ "$_locker" = $$ ]
    then
	rm -f $LOCKFILE
    else
	trace "Cannot unlock '$LOCKFILE'. Am not the locker!" >&2
    fi
}

getchildprocs ()
{
    for p in `pgrep -P $1`
    do
	echo $p `getchildprocs $p`
    done
}

force_take_lock ()
{
    _nb="$1"

    if take_lock
    then
	return 0
    else
	if [ "$(wc -l < $LOCKFILE)" -gt "$_nb" ]
	then
	    _locker=`get_locker`
	    trace "Lock older than $_nb retries. Killing locker..." 
	    CPIDS=$(getchildprocs $_locker)
	    trace "->killing $_locker and children $CPIDS"
   ps agux | grep "lftp hd1" | grep -v grep >&2
	    sudo kill -TERM $CPIDS $_locker
	    sleep 10
	    trace "->result:"
	    ps $_locker $CPIDS >&2
	    trace "->remaining:"
	    ps agux | grep getcamfile | grep -v grep >&2
	    sudo kill -KILL $CPIDS $_locker
	    trace -n "Trying to get lock... "
	    if _try_force_lock
	    then
		echo "Success!"
		return 0
	    else
		echo "Failed!"
		return 1
	    fi
	    return 1
	fi
	return 1
    fi
    return 1
}

