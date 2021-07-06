#!/bin/bash

trap "abort" SIGINT SIGTERM

function abort(){
	kill $tor_pid
	exit 1
}

auth=''
curl_args=()
post_data=''
custom_dir=''
dir_suffix=''
no_errors=''
outlinks=''
parallel=''
quiet=''
resume=''
ssl_only=''
pattern=''
exclude_pattern=''

print_usage() {
	echo "Usage: $(basename "$0") [options] file
       $(basename "$0") [options] url [url]...
       $(basename "$0") [options] -r folder

Options:
 -a auth        S3 API keys, in the form accesskey:secret
                (get account keys at https://archive.org/account/s3.php)

 -c args        pass additional arguments to curl

 -d data        capture request options, or other arbitrary POST data

 -f folder      use a custom location for the data folder
                (some files will be overwritten or deleted during the session)

 -i suffix      add a suffix to the name of the data folder
                (if -f is used, -i is ignored)

 -n             tell Save Page Now not to save errors into the Wayback Machine

 -o pattern     save detected capture outlinks matching regex (ERE) pattern

 -p N           run at most N capture jobs in parallel (off by default)

 -q             discard JSON for completed jobs instead of writing to log file

 -r folder      resume with the remaining URLs of an aborted session
                (aborted session's settings do not carry over)

 -s             use HTTPS for all captures and change HTTP input URLs to HTTPS

 -x pattern     save detected capture outlinks not matching regex (ERE) pattern
                (if -o is also used, outlinks are filtered using both regexes)"
}

while getopts 'a:c:d:f:i:no:p:qr:sx:' flag; do
	case "${flag}" in
		a)	auth="$OPTARG" ;;
		c)	declare -a "curl_args=($OPTARG)" ;;
		d)	post_data="$OPTARG" ;;
		f)	custom_dir="$OPTARG" ;;
		i)	dir_suffix="-$OPTARG" ;;
		n)	no_errors='true' ;;
		o)	outlinks='true'; pattern="$OPTARG" ;;
		p)	parallel="$OPTARG" ;;
		q)	quiet='true' ;;
		r)	resume="$OPTARG" ;;
		s)	ssl_only='true' ;;
		x)	outlinks='true'; exclude_pattern="$OPTARG" ;;
		*)	print_usage
			exit 1 ;;
	esac
done
shift "$((OPTIND-1))"

if [[ -n "$resume" ]]; then
	# There should not be any arguments
	if [[ -n "$1" ]]; then
		print_usage
		exit 1
	fi
	# Get list
	# List will be constructed from the specified folder
	if [[ ! -d "$resume" ]]; then
		echo "The folder $resume could not be found"
		exit 1
	fi
	cd "$resume"
	if ! [[ -f "index.txt" && -f "success.log" ]]; then
		echo "Could not resume session; required files not found"
		exit 1
	fi
	if [[ -f "outlinks.txt" ]]; then
		# Index will also include successful redirects, which should be logged in captures.log
		if [[ -f "captures.log" ]]; then
			success=$(cat success.log captures.log | sed -Ee 's|^/web/[0-9]+/||g')
		else
			success=$(<success.log)
		fi
		index=$(cat index.txt outlinks.txt)
		# Convert links to HTTPS
		if [[ -n "$ssl_only" ]]; then
			index=$(echo "$index" | sed -Ee 's|^[[:blank:]]*(https?://)?[[:blank:]]*([^[:blank:]]+)|https://\2|g;s|^https://ftp://|ftp://|g')
			success=$(echo "$success" | sed -Ee 's|^[[:blank:]]*(https?://)?[[:blank:]]*([^[:blank:]]+)|https://\2|g;s|^https://ftp://|ftp://|g')
		fi
		# Remove duplicate lines from new index
		index=$(awk '!seen [$0]++' <<< "$index")
		# Remove links that are in success.log and captures.log from new index
		list=$(awk '{if (f==1) { r[$0] } else if (! ($0 in r)) { print $0 } } ' f=1 <(echo "$success") f=2 <(echo "$index"))
	else
		# Remove links that are in success.log from index.txt
		list=$(awk '{if (f==1) { r[$0] } else if (! ($0 in r)) { print $0 } } ' f=1 success.log f=2 index.txt)
	fi
	if [[ -z "$list" ]]; then
		echo "Session already complete; not resuming"
		exit 1
	fi
	cd
else
	# File or at least one URL must be provided
	if [[ -z "$1" ]]; then
		print_usage
		exit 1
	fi
	# Get list
	# Treat as filename if only one argument and file exists, and as URLs otherwise
	if [[ -n "$2" || ! -f "$1" ]]; then
		list=$(for i in "$@"; do echo "$i"; done)
	else
		list=$(<"$1")
	fi
fi

parent="spn-data"
tor_dir="$parent/tor"
tor_data_dir="$tor_dir/data"

for i in "$parent" "$tor_dir" "$tor_data_dir"; do
	if [[ ! -d ~/"$i" ]]; then
		mkdir ~/"$i" || { echo "The folder ~/$i could not be created"; exit 1; }
	fi
done

if [[ -n "$custom_dir" ]]; then
	f="-$$"
	dir="$custom_dir"
	if [[ ! -d "$dir" ]]; then
		mkdir "$dir" || { echo "The folder $dir could not be created"; exit 1; }
		echo "Created data folder $dir"
	else
		echo "Using the existing data folder $dir"
	fi
	cd "$dir"

	for i in max_parallel_jobs$f.txt status_rate$f.txt lock$f.txt daily_limit$f.txt quit$f.txt; do
		if [[ -f "$i" ]]; then
			rm "$i"
		fi
	done
else
	f=''
	parent="spn-data"
	month=$(date -u +%Y-%m)
	now=$(date +%s)

	for i in "$parent" "$parent/$month"; do
		if [[ ! -d ~/"$i" ]]; then
			mkdir ~/"$i" || { echo "The folder ~/$i could not be created"; exit 1; }
		fi
	done

	# Wait between 0 and 0.07 seconds to try to avoid a collision, in case another session is started at exactly the same time
	sleep ".0$((RANDOM % 8))"

	# Wait between 0.1 and 0.73 seconds if the folder already exists
	while [[ -d ~/"$parent/$month/$now$dir_suffix" ]]; do
		sleep ".$((10 + RANDOM % 64))"
		now=$(date +%s)
	done
	dir="$parent/$month/$now$dir_suffix"

	# Try to create the folder
	mkdir ~/"$dir" || { echo "The folder ~/$dir could not be created"; exit 1; }
	echo "Created data folder ~/$dir"
	cd ~/"$dir"
fi

# Increment port number until finding one that is not in use
tor_port=45100
while : &>/dev/null </dev/tcp/127.0.0.1/$tor_port; do
	((tor_port++))
done
echo "SOCKSPort $tor_port
DataDirectory $HOME/$tor_data_dir/$tor_port" > ~/"$tor_dir/$tor_port"
tor -f ~/"$tor_dir/$tor_port" &
tor_pid=$!

# Wait for the connection to start working
sleep 1
curl -s -m 300 -X POST -x socks5h://127.0.0.1:$tor_port/ -H "Accept: application/json" "https://web.archive.org/save/" > /dev/null

# Convert links to HTTPS
if [[ -n "$ssl_only" ]]; then
	list=$(echo "$list" | sed -Ee 's|^[[:blank:]]*(https?://)?[[:blank:]]*([^[:blank:]]+)|https://\2|g;s|^https://ftp://|ftp://|g')
fi

# Set POST options
# The web form sets capture_all=on by default; this replicates the default behavior
if [[ -z "$no_errors" ]]; then
	if [[ -n "$post_data" ]]; then
		post_data="${post_data}&capture_all=on"
	else
		post_data="capture_all=on"
	fi
fi

# Create data files
# max_parallel_jobs.txt and status_rate.txt are created later
touch failed.txt
echo "$list" | awk '!seen [$0]++' > index.txt
if [[ -n "$outlinks" ]]; then
	touch outlinks.txt
fi

# Submit a URL to Save Page Now and check the result
function capture(){
	local tries="0"
	local request
	local job_id
	local message
	while ((tries < 3)); do
		# Submit
		local lock_wait=0
		local start_time=`date +%s`
		while :; do
			if (( $(date +%s) - start_time > 300 )); then
				break 2
			fi
			if [[ -n "$auth" ]]; then
				request=$(curl "${curl_args[@]}" -s -m 60 -X POST --data-urlencode "url=${1}" -d "${post_data}" -x socks5h://127.0.0.1:$tor_port/ -H "Accept: application/json" -H "Authorization: LOW ${auth}" "https://web.archive.org/save/")
				job_id=$(echo "$request" | grep -Eo '"job_id":"([^"\\]|\\["\\])*"' | head -1 | sed -Ee 's/"job_id":"(.*)"/\1/g')
				if [[ -n "$job_id" ]]; then
					break
				fi
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Request failed] $1"
				message=$(echo "$request" | grep -Eo '"message":"([^"\\]|\\["\\])*"' | sed -Ee 's/"message":"(.*)"/\1/g')
			else
				request=$(curl "${curl_args[@]}" -s -m 60 -X POST --data-urlencode "url=${1}" -d "${post_data}" -x socks5h://127.0.0.1:$tor_port/ "https://web.archive.org/save/")
				job_id=$(echo "$request" | grep -E 'spn\.watchJob\(' | sed -Ee 's/^.*spn\.watchJob\("([^"]*).*$/\1/g' | head -1)
				if [[ -n "$job_id" ]]; then
					break
				fi
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Request failed] $1"
				message=$(echo "$request" | grep -E -A 1 "<h2>" | tail -1 | sed -Ee 's|</?p>||g')
			fi
			if [[ -z "$message" ]]; then
				if [[ "$request" =~ "429 Too Many Requests" ]]; then
					echo "$request"
					if [[ ! -f lock$f.txt ]]; then
						kill -HUP $tor_pid
					else
						break 2
					fi
				elif [[ "$request" =~ "400 Bad Request" ]]; then
					echo "$request"
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') $1" >> invalid.log
					echo "$request" >> invalid.log
					return 1
				elif ! : &>/dev/null </dev/tcp/127.0.0.1/$tor_port; then
					break 2
				else
					sleep 5
				fi
			else
				echo "$message"
				if ! [[ "$message" =~ "You have already reached the limit of active sessions" || "$message" =~ "Cannot start capture" || "$message" =~ "Crawling this host is paused" ]]; then
					if [[ "$message" =~ "You cannot make more than "[1-9][0-9,]*" captures per day" ]]; then
						if [[ -n "$auth" ]]; then
							touch daily_limit$f.txt
							break 2
						else
							kill -HUP $tor_pid
						fi
					else
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') $1" >> invalid.log
						echo "$message" >> invalid.log
						return 1
					fi
				fi
				if [[ ! -f lock$f.txt ]]; then
					touch lock$f.txt
					while [[ -f lock$f.txt ]]; do
						# Retry the request until either the job is submitted or a different error is received
						if [[ -n "$auth" ]]; then
							sleep 2
							request=$(curl "${curl_args[@]}" -s -m 60 -X POST --data-urlencode "url=${1}" -d "${post_data}" -x socks5h://127.0.0.1:$tor_port/ -H "Accept: application/json" -H "Authorization: LOW ${auth}" "https://web.archive.org/save/")
							job_id=$(echo "$request" | grep -Eo '"job_id":"([^"\\]|\\["\\])*"' | head -1 | sed -Ee 's/"job_id":"(.*)"/\1/g')
							if [[ -n "$job_id" ]]; then
								rm lock$f.txt
								break 2
							fi
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Request failed] $1"
							message=$(echo "$request" | grep -Eo '"message":"([^"\\]|\\["\\])*"' | sed -Ee 's/"message":"(.*)"/\1/g')
						else
							kill -HUP $tor_pid
							request=$(curl "${curl_args[@]}" -s -m 60 -X POST --data-urlencode "url=${1}" -d "${post_data}" -x socks5h://127.0.0.1:$tor_port/ "https://web.archive.org/save/")
							job_id=$(echo "$request" | grep -E 'spn\.watchJob\(' | sed -Ee 's/^.*spn\.watchJob\("([^"]*).*$/\1/g' | head -1)
							if [[ -n "$job_id" ]]; then
								rm lock$f.txt
								break 2
							fi
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Request failed] $1"
							message=$(echo "$request" | grep -E -A 1 "<h2>" | tail -1 | sed -Ee 's|</?p>||g')
						fi
						if [[ -z "$message" ]]; then
							if [[ "$request" =~ "429 Too Many Requests" ]]; then
								echo "$request"
								kill -HUP $tor_pid
							elif ! : &>/dev/null </dev/tcp/127.0.0.1/$tor_port; then
								break 3
							else
								sleep 5
								rm lock$f.txt
								break
							fi
						else
							echo "$message"
							if [[ "$message" =~ "You have already reached the limit of active sessions" || "$message" =~ "Cannot start capture" || "$message" =~ "Crawling this host is paused" ]]; then
								:
							elif [[ "$message" =~ "You cannot make more than "[1-9][0-9,]*" captures per day" ]]; then
								if [[ -n "$auth" ]]; then
									rm lock$f.txt
									touch daily_limit$f.txt
									break 3
								else
									kill -HUP $tor_pid
								fi
							else
								rm lock$f.txt
								echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
								echo "$(date -u '+%Y-%m-%d %H:%M:%S') $1" >> invalid.log
								echo "$message" >> invalid.log
								return 1
							fi
						fi
					done
				else
					# If another process has already created lock.txt, wait for the other process to remove it
					while [[ -f lock$f.txt ]]; do
						sleep 5
						((lock_wait+=5))
						if ((lock_wait > 120)); then
							break 3
						fi
					done
				fi
			fi
		done
		echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job submitted] $1"

		# Wait
		delay=$(echo "$request" | grep -Eo 'Your capture will begin in [1-9][0-9,]*s' | sed -Ee 's/[^0-9]*//g')
		if [[ -z "$delay" ]]; then
			delay="0"
		fi
		local start_time=`date +%s`
		local status
		local status_ext
		while :; do
			sleep "$(<status_rate$f.txt)"
			request=$(curl "${curl_args[@]}" -s -m 60 -x socks5h://127.0.0.1:$tor_port/ "https://web.archive.org/save/status/$job_id")
			status=$(echo "$request" | grep -Eo '"status":"([^"\\]|\\["\\])*"' | head -1)
			if [[ -z "$status" ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Status request failed] $1"
				if [[ "$request" =~ "429 Too Many Requests" ]]; then
					echo "$request"
					kill -HUP $tor_pid
				elif ! : &>/dev/null </dev/tcp/127.0.0.1/$tor_port; then
					break 2
				fi
				sleep "$(<status_rate$f.txt)"
				request=$(curl "${curl_args[@]}" -s -m 60 -x socks5h://127.0.0.1:$tor_port/ "https://web.archive.org/save/status/$job_id")
				status=$(echo "$request" | grep -Eo '"status":"([^"\\]|\\["\\])*"' | head -1)
				if [[ -z "$status" ]]; then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Status request failed] $1"
					if [[ "$request" =~ "429 Too Many Requests" ]]; then
						echo "$request"
						kill -HUP $tor_pid
						status='"status":"pending"'
						# Fake status response to allow while loop to continue
					elif ! : &>/dev/null </dev/tcp/127.0.0.1/$tor_port; then
						break 2
					else
						echo "$request" >> unknown-json.log
						break 2
					fi
				fi
			fi
			if [[ -z "$status" ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error] $1"
				echo "$request" >> unknown-json.log
				break 2
			fi
			if [[ "$status" == '"status":"success"' ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job completed] $1"
				echo "$1" >> success.log
				timestamp=$(echo "$request" | grep -Eo '"timestamp":"[0-9]*"' | sed -Ee 's/^"timestamp":"(.*)"/\1/g')
				url=$(echo "$request" | grep -Eo '"original_url":"([^"\\]|\\["\\])*"' | sed -Ee 's/^"original_url":"(.*)"/\1/g;s/\\(["\\])/\1/g')
				echo "/web/$timestamp/$url" >> captures.log
				if [[ -z "$quiet" ]]; then
					echo "$request" >> success-json.log
				fi
				if [[ -n "$outlinks" ]]; then
					if [[ "$url" != "$1" ]]; then
						# Prevent the URL from being submitted twice
						echo "$url" >> index.txt
					fi
					# grep matches array of strings (most special characters are converted server-side, but not square brackets)
					# sed transforms the array into just the URLs separated by line breaks
					echo "$request" | grep -Eo '"outlinks":\["([^"\\]|\\["\\])*"(,"([^"\\]|\\["\\])*")*\]' | sed -Ee 's/"outlinks":\["(.*)"\]/\1/g;s/(([^"\\]|\\["\\])*)","/\1\
/g;s/\\(["\\])/\1/g' | { [[ -n "$exclude_pattern" ]] && { [[ -n "$pattern" ]] && grep -E "$pattern" | grep -Ev "$exclude_pattern" || grep -Ev "$exclude_pattern"; } || grep -E "$pattern"; } >> outlinks.txt
				fi
				return 0
			elif [[ "$status" == '"status":"pending"' ]]; then
				if (( $(date +%s) - start_time > 300 + delay )); then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job timed out] $1"
					break 2
				fi
			elif [[ "$status" == '"status":"error"' ]]; then
				echo "$request" >> error-json.log
				status_ext=$(echo "$request" | grep -Eo '"status_ext":"([^"\\]|\\["\\])*"' | head -1 | sed -Ee 's/"status_ext":"(.*)"/\1/g')
				if [[ -z "$status_ext" ]]; then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error] $1"
					break 2
				fi
				if [[ "$status_ext" == 'error:filesize-limit' ]]; then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [File size limit of 2 GB exceeded] $1"
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$status_ext] $1" >> failed.log
					return 1
				elif [[ "$status_ext" == 'error:proxy-error' ]]; then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [SPN proxy error] $1"
				else
					message=$(echo "$request" | grep -Eo '"message":"([^"\\]|\\["\\])*"' | sed -Ee 's/"message":"(.*)"/\1/g')
					if [[ -z "$message" ]]; then
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error: $status_ext] $1"
						break 2
					fi
					if [[ "$message" == "Live page is not available: chrome-error://chromewebdata/" ]]; then
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [SPN internal error] $1"
					elif [[ "$message" =~ ' (HTTP status='(40[89]|429|50[023478])').'$ ]]; then
						# HTTP status 408, 409, 429, 500, 502, 503, 504, 507 or 508
						# URL may become available later
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$message] $1"
						break 2
					elif [[ "$message" =~ ' (HTTP status='[45][0-9]*').'$ ]]; then
						# HTTP error; assume the URL cannot be archived
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$message] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$status_ext] $1" >> failed.log
						return 1
					else
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$message] $1"
						break 2
					fi
				fi
				break
			else
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error] $1"
				break 2
			fi
		done
		((tries++))
	done
	echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
	echo "$1" >> failed.txt
	return 1
}

function get_list(){
	local failed_file=failed-$(date +%s).txt
	mv failed.txt $failed_file
	touch failed.txt
	local failed_list=$(<$failed_file)

	if [[ -n "$outlinks" ]]; then
		local outlinks_file=outlinks-$(date +%s).txt
		mv outlinks.txt $outlinks_file
		touch outlinks.txt
		# Remove duplicate lines; reading into string prevents awk from emptying the file
		awk '!seen [$0]++' <<< "$(<$outlinks_file)" > $outlinks_file
		# Convert links to HTTPS
		if [[ -n "$ssl_only" ]]; then
			sed -Ee 's|^[[:blank:]]*(https?://)?[[:blank:]]*([^[:blank:]]+)|https://\2|g;s|^https://ftp://|ftp://|g' <<< "$(<$outlinks_file)" > $outlinks_file
		fi
		# Remove lines that are already in index.txt
		local outlinks_list=$(awk '{if (f==1) { r[$0] } else if (! ($0 in r)) { print $0 } } ' f=1 index.txt f=2 $outlinks_file)

		if [[ -n "$outlinks_list" ]]; then
			echo "$outlinks_list" >> index.txt

			if [[ -n "$failed_list" ]]; then
				echo "$failed_list
$outlinks_list"
			else
				echo "$outlinks_list"
			fi
		fi
		if [[ -z "$(<$outlinks_file)" ]]; then
			rm $outlinks_file
		fi
	else
		echo "$failed_list"
	fi
	if [[ -z "$failed_list" ]]; then
		rm $failed_file
	fi
}

# Track the number of loops in which no URLs from the list are archived
repeats=0

# Parallel loop
if [[ -n "$parallel" ]]; then
	if ((parallel > 60)); then
		parallel=60
		echo "Setting maximum parallel jobs to 60"
	elif ((parallel < 2)); then
		parallel=2
		echo "Setting maximum parallel jobs to 2"
	fi
	echo "$parallel" > max_parallel_jobs$f.txt
	# Overall request rate stays at around 60 per minute
	echo "$parallel" > status_rate$f.txt
	while [[ ! -f quit$f.txt ]]; do
		(
		hour=`date -u +%H`
		while IFS='' read -r line || [[ -n "$line" ]]; do
			capture "$line" & ((children > 2)) && sleep 2.5
			children_wait=0
			children=`jobs -p | wc -l`
			while ! (( children < $(<max_parallel_jobs$f.txt) )); do
				sleep 1
				((children_wait++))
				if ((children_wait < 600)); then
					children=`jobs -p | wc -l`
				else
					# Wait is longer than 600 seconds; something might be wrong
					# Increase limit and ignore the problem for now
					children=0
					echo $(( $(<max_parallel_jobs$f.txt) + 1 )) > max_parallel_jobs$f.txt
				fi
			done
			lock_wait=0
			while [[ -f lock$f.txt ]]; do
				sleep 2
				((lock_wait+=2))
				if ((lock_wait > 300)); then
					rm lock$f.txt
				fi
			done
			if [[ -f daily_limit$f.txt ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for $(( (3600 - $(date +%s) % 3600) / 60 )) minutes"
				sleep $(( 3600 - $(date +%s) % 3600 ))
				rm daily_limit$f.txt
			fi
			((counter++))
			# Check failures and outlinks approximately every hour
			if ! ((counter % 50)) && ! [[ `date -u +%H` == "$hour" || -f quit$f.txt ]]; then
				hour=`date -u +%H`
				new_list=$(get_list)
				if [[ -n "$new_list" ]]; then
					while IFS='' read -r line2 || [[ -n "$line2" ]]; do
						capture "$line2" & ((children > 2)) && sleep 2.5
						children_wait=0
						children=`jobs -p | wc -l`
						while ! ((children < $(<max_parallel_jobs$f.txt) )); do
							sleep 1
							((children_wait++))
							if ((children_wait < 600)); then
								children=`jobs -p | wc -l`
							else
								# Wait is longer than 600 seconds; something might be wrong
								# Increase limit and ignore the problem for now
								children=0
								echo $(( $(<max_parallel_jobs$f.txt) + 1 )) > max_parallel_jobs$f.txt
							fi
						done
						lock_wait=0
						while [[ -f lock$f.txt ]]; do
							sleep 2
							((lock_wait+=2))
							if ((lock_wait > 300)); then
								rm lock$f.txt
							fi
						done
						if [[ -f daily_limit$f.txt ]]; then
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for $(( (3600 - $(date +%s) % 3600) / 60 )) minutes"
							sleep $(( 3600 - $(date +%s) % 3600 ))
							rm daily_limit$f.txt
						fi
					done <<< "$new_list"
					unset new_list
				fi
			fi
		done <<< "$list"

		for job in `jobs -p`; do wait $job; done
		)

		new_list=$(get_list)
		if [[ "$new_list" == "$list" ]]; then
			((repeats++))
			if ((repeats > 1)); then
				if ((repeats > 3)); then
					break
				else
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for 30 minutes"
					sleep 1800
				fi
			fi
		fi
		list="$new_list"
		unset new_list
		if [[ -z "$list" && -z "$(<failed.txt)" ]]; then
			# No more URLs
			touch quit$f.txt
			rm failed.txt
		fi
	done
fi

if [[ ! -f quit$f.txt ]]; then
	echo "2" > status_rate$f.txt
fi

# Linear loop
while [[ ! -f quit$f.txt ]]; do
	hour=`date -u +%H`
	while IFS='' read -r line || [[ -n "$line" ]]; do
		capture "$line"
		((counter++))
		# Check failures and outlinks approximately every hour
		if ! ((counter % 50)) && ! [[ `date -u +%H` == "$hour" || -f quit$f.txt ]]; then
			hour=`date -u +%H`
			new_list=$(get_list)
			if [[ -n "$new_list" ]]; then
				while IFS='' read -r line2 || [[ -n "$line2" ]]; do
					capture "$line2"
				done <<< "$new_list"
			fi
			unset new_list
		fi
	done <<< "$list"
	new_list=$(get_list)
	if [[ "$new_list" == "$list" ]]; then
		((repeats++))
		if ((repeats > 1)); then
			if ((repeats > 4)); then
				# Give up
				touch quit$f.txt
			else
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for 30 minutes"
				sleep 1800
			fi
		fi
	fi
	list="$new_list"
	unset new_list
	if [[ -z "$list" && -z "$(<failed.txt)" ]]; then
		# No more URLs
		touch quit$f.txt
		rm failed.txt
	fi
done

if [[ -n "$custom_dir" ]]; then
	for i in max_parallel_jobs$f.txt status_rate$f.txt lock$f.txt daily_limit$f.txt quit$f.txt; do
		if [[ -f "$i" ]]; then
			rm "$i"
		fi
	done
fi

kill $tor_pid
