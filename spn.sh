#!/bin/bash

no_errors=''
pattern=''
parallel=''
quiet=''

print_usage() {
	echo "Usage: $(basename "$0") [-nq] [-o pattern] [-p num] file
       $(basename "$0") [-nq] [-o pattern] [-p num] url [url]...

 -n             tell Save Page Now not to save errors into the Wayback Machine
 -o pattern     archive detected capture outlinks matching regex (ERE) pattern
 -p N           run at most N capture jobs in parallel (off by default)
 -q             discard JSON for completed jobs instead of writing to log file"
}

while getopts 'no:p:q' flag; do
	case "${flag}" in
		n)	no_errors='true' ;;
		o)	pattern="$OPTARG" ;;
		p)	parallel="$OPTARG" ;;
		q)	quiet='true' ;;
		*)	print_usage
			exit 1 ;;
	esac
done
shift "$((OPTIND-1))"

# File or at least one URL must be provided
if [[ -z "$1" ]]; then
	print_usage
	exit 1
fi

parent="spn-data"
month=$(date -u +%Y-%m)
now=$(date +%s)

for i in "$parent" "$parent/$month" "$parent/$month/$now"; do
	if [[ ! -d ~/"$i" ]]; then
		mkdir ~/"$i" || { echo "The folder ~/$i could not be created"; exit 1; }
	fi
done
dir="$parent/$month/$now"
echo "Created data folder ~/$dir"

# Get list
# Treat as filename if only one argument and file exists, and as URLs otherwise
if [[ -n "$2" || ! -f "$1" ]]; then
	list=$(for i in "$@"; do echo "$i"; done)
else
	list=$(<"$1")
fi

cd ~/"$dir"

# Set POST options (at present, only one option available while logged out)
if [[ -n "$no_errors" ]]; then
	capture_all=""
else
	capture_all="capture_all=on"
fi

# Create data files
# max_parallel_jobs.txt and status_rate.txt are created later
touch failed.txt
if [[ -n "$pattern" ]]; then
	echo "$list" | awk '!seen [$0]++' > index.txt
	touch outlinks.txt
fi

# Submit a URL to Save Page Now and check the result
function capture(){
	local finished="0"
	local tries="0"
	while [[ "$finished" == "0" ]] && ((tries < 3)); do
		# Submit
		local lock_wait=0
		local start_time=`date +%s`
		local submit_finished="0"
		while [[ "$submit_finished" == "0" ]]; do
			# Loop exit conditions:
			# - Forced exit of process upon error ("return 1")
			# - Job started successfully (submit_finished=1)
			if (( $(date +%s) - start_time > 210 )); then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
				echo "$1" >> failed.txt
				return 1
			fi
			local request=$(curl -s -m 60 -X POST --data-urlencode "url=${1}" --data-urlencode "${capture_all}" "https://web.archive.org/save/$1")
			local job_id=$(echo "$request" | grep -E 'spn\.watchJob\(' | grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
			if ! [[ -n "$job_id" ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Request failed] $1"
				local error_message=$(echo "$request" | grep -E -A 1 "<h2>")
				if [[ -n "$error_message" ]]; then
					echo "$error_message"
					if [[ "$error_message" =~ "You have already reached the limit of active sessions" ]]; then
						if [[ ! -f lock.txt ]]; then
							touch lock.txt
							while [[ -f lock.txt ]]; do
								sleep 2
								request=$(curl -s -m 60 -X POST --data-urlencode "url=${1}" --data-urlencode "${capture_all}" "https://web.archive.org/save/$1")
								job_id=$(echo "$request" | grep -E 'spn\.watchJob\(' | grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
								if ! [[ -n "$job_id" ]]; then
									echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Request failed] $1"
									error_message=$(echo "$request" | grep -E -A 1 "<h2>")
									if [[ -n "$error_message" ]]; then
										echo "$error_message"
										if [[ "$error_message" =~ "You have already reached the limit of active sessions" ]]; then
											:
										elif [[ "$error_message" =~ "You cannot make more than "[1-9][0-9,]*" captures per day" ]]; then
											rm lock.txt
											touch daily_limit.txt
											echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
											echo "$1" >> failed.txt
											return 1
										else
											rm lock.txt
											echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
											echo "$(date -u '+%Y-%m-%d %H:%M:%S') $1" >> invalid.log
											echo "$error_message" >> invalid.log
											return 1
										fi
									else
										rm lock.txt
									fi
								else
									submit_finished="1"
									rm lock.txt
								fi
							done
						else
							while [[ -f lock.txt ]]; do
								sleep 5
								((lock_wait+=5))
								if ((lock_wait > 120)); then
									echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
									echo "$1" >> failed.txt
									return 1
								fi
							done
						fi
					elif [[ "$error_message" =~ "You cannot make more than "[1-9][0-9,]*" captures per day" ]]; then
						touch daily_limit.txt
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$1" >> failed.txt
						return 1
					else
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') $1" >> invalid.log
						echo "$error_message" >> invalid.log
						return 1
					fi
				else
					sleep 5
				fi
				if [[ "$request" =~ "429 Too Many Requests" ]]; then
					echo "$request"
					sleep 20
				fi
			else
				submit_finished="1"
			fi
		done
		echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job submitted] $1"

		# Wait
		delay=$(echo "$request" | grep -Eo 'Your capture will begin in [1-9][0-9,]*s' | sed -Ee 's/[^0-9]*//g')
		if [[ -z "$delay" ]]; then
			delay="0"
		fi
		local start_time=`date +%s`
		local json_finished="0"
		while [[ "$json_finished" == "0" ]]; do
			# Loop exit conditions:
			# - Forced exit of process upon error ("return 1")
			# - Job complete or SPN internal error (json_finished=1)
			sleep "$(<status_rate.txt)"
			local request=$(curl -s -m 60 "https://web.archive.org/save/status/$job_id")
			local status=$(echo "$request" | grep -Eo '"status":"([^"\\]|\\["\\])*"' | head -1)
			if ! [[ -n "$status" ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Status request failed] $1"
				if [[ "$request" =~ "429 Too Many Requests" ]]; then
					echo "$request"
					sleep 20
				fi
				sleep "$(<status_rate.txt)"
				local request=$(curl -s -m 60 "https://web.archive.org/save/status/$job_id")
				local status=$(echo "$request" | grep -Eo '"status":"([^"\\]|\\["\\])*"' | head -1)
				if ! [[ -n "$status" ]]; then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Status request failed] $1"
					if [[ "$request" =~ "429 Too Many Requests" ]]; then
						echo "$request"
						sleep 20
						status='"status":"pending"'
						# Fake status response to allow while loop to continue
					else
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$request" >> unknown-json.log
						echo "$1" >> failed.txt
						return 1
					fi
				fi
			fi
			if [[ -n "$status" ]]; then
				if [[ "$status" == '"status":"success"' ]]; then
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job completed] $1"
					echo "$1" >> success.log
					timestamp=$(echo "$request" | grep -Eo '"timestamp":"[0-9]*"' | sed -Ee 's/^"timestamp":"(.*)"/\1/g')
					url=$(echo "$request" | grep -Eo '"original_url":"([^"\\]|\\["\\])*"' | sed -Ee 's/^"original_url":"(.*)"/\1/g;s/\\(["\\])/\1/g')
					echo "/web/$timestamp/$url" >> captures.log
					if ! [[ -n "$quiet" ]]; then
						echo "$request" >> success-json.log
					fi
					if [[ -n "$pattern" ]]; then
						if ! [[ "$url" == "$1" ]]; then
							# Prevent the URL from being submitted twice
							echo "$url" >> index.txt
						fi
						# grep matches array of strings (most special characters are converted server-side, but not square brackets)
						# sed transforms the array into just the URLs separated by line breaks
						echo "$request" | grep -Eo '"outlinks":\["([^"\\]|\\["\\])*"(,"([^"\\]|\\["\\])*")*\]' | sed -Ee 's/"outlinks":\["(.*)"\]/\1/g;s/(([^"\\]|\\["\\])*)","/\1\
/g;s/\\(["\\])/\1/g' | grep -E "$pattern" >> outlinks.txt
					fi
					json_finished="1"
					finished="1"
				elif [[ "$status" == '"status":"pending"' ]]; then
					if (( $(date +%s) - start_time > 210 + delay )); then
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job timed out] $1"
						json_finished="1"
					fi
				elif [[ "$status" == '"status":"error"' ]]; then
					echo "$request" >> error-json.log
					local status_ext=$(echo "$request" | grep -Eo '"status_ext":"([^"\\]|\\["\\])*"' | head -1 | sed -Ee 's/"status_ext":"(.*)"/\1/g')
					if [[ -z "$status_ext" ]]; then
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$1" >> failed.txt
						return 1
					fi
					if [[ "$status_ext" == 'error:filesize-limit' ]]; then
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [File size limit of 2 GB exceeded] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$status_ext] $1" >> failed.log
						return 1
					elif [[ "$status_ext" == 'error:proxy-error' ]]; then
						echo "$(date -u '+%Y-%m-%d %H:%M:%S') [SPN proxy error] $1"
					else
						local message=$(echo "$request" | grep -Eo '"message":"([^"\\]|\\["\\])*"' | sed -Ee 's/"message":"(.*)"/\1/g')
						if [[ -z "$message" ]]; then
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error: $status_ext] $1"
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
							echo "$1" >> failed.txt
							return 1
						fi
						if [[ "$message" == "Live page is not available: chrome-error://chromewebdata/" ]]; then
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [SPN internal error] $1"
						elif [[ "$message" =~ '.* (HTTP status=[45][0-9]*)\.$' ]]; then
							# HTTP error; assume the URL cannot be archived
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$message] $1"
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$status_ext] $1" >> failed.log
							return 1
						else
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [$message] $1"
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
							echo "$1" >> failed.txt
							return 1
						fi
					fi
					json_finished="1"
				else
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error] $1"
					echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
					echo "$1" >> failed.txt
					return 1
				fi
			else
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Unknown error] $1"
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
				echo "$1" >> failed.txt
				return 1
			fi
		done
		((tries++))
	done
	if [[ "$finished" == "0" ]]; then
		echo "$(date -u '+%Y-%m-%d %H:%M:%S') [Job failed] $1"
		echo "$1" >> failed.txt
	fi
}

function get_list(){
	local failed_file=failed-$(date +%s).txt
	mv failed.txt $failed_file
	touch failed.txt

	if [[ -n "$pattern" ]]; then
		local failed_list=$(<$failed_file)

		local outlinks_file=outlinks-$(date +%s).txt
		mv outlinks.txt $outlinks_file
		touch outlinks.txt
		# Remove duplicate lines; reading into string prevents awk from emptying the file
		awk '!seen [$0]++' <<< "$(<$outlinks_file)" > $outlinks_file
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
	else
		echo "$(<$failed_file)"
	fi
}

# Track the number of loops in which no URLs from the list are archived
repeats=0

# Parallel loop
if [[ -n "$parallel" ]]; then
	if ((parallel > 30)); then
		parallel=30
		echo "Setting maximum parallel jobs to 30"
	elif ((parallel < 2)); then
		parallel=2
		echo "Setting maximum parallel jobs to 2"
	fi
	echo "$parallel" > max_parallel_jobs.txt
	# Overall request rate stays at around 60 per minute
	echo "$((parallel + 1))" > status_rate.txt
	loop=1
	while [[ "$loop" == "1" && ! -f quit.txt ]]; do
		(
		hour=`date -u +%H`
		while IFS='' read -r line || [[ -n "$line" ]]; do
			capture "$line" & sleep 2
			extra_wait=0
			children=`jobs -p | wc -l`
			while ! (( children < $(<max_parallel_jobs.txt) )); do
				sleep 1
				((extra_wait++))
				if ((extra_wait < 600)); then
					children=`jobs -p | wc -l`
				else
					# Wait is longer than 600 seconds; something might be wrong
					# Increase limit and ignore the problem for now
					children=0
					echo $(( $(<max_parallel_jobs.txt) + 1 )) > max_parallel_jobs.txt
				fi
			done
			lock_wait=0
			while [[ -f lock.txt ]]; do
				sleep 2
				((lock_wait+=2))
				if ((lock_wait > 210)); then
					rm lock.txt
				fi
			done
			if [[ -f daily_limit.txt ]]; then
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for $(( (3600 - $(date +%s) % 3600) / 60 )) minutes"
				sleep $(( 3600 - $(date +%s) % 3600 ))
				rm daily_limit.txt
			fi
			((counter++))
			# Check failures and outlinks approximately every hour
			if ! ((counter % 50)) && ! [[ `date -u +%H` == "$hour" || -f quit.txt ]]; then
				hour=`date -u +%H`
				new_list=$(get_list)
				if [[ -n "$new_list" ]]; then
					while IFS='' read -r line2 || [[ -n "$line2" ]]; do
						capture "$line2" & sleep 2
						children_wait=0
						children=`jobs -p | wc -l`
						while ! ((children < $(<max_parallel_jobs.txt) )); do
							sleep 1
							((extra_wait++))
							if ((extra_wait < 600)); then
								children=`jobs -p | wc -l`
							else
								# Wait is longer than 600 seconds; something might be wrong
								# Increase limit and ignore the problem for now
								children=0
								echo $(( $(<max_parallel_jobs.txt) + 1 )) > max_parallel_jobs.txt
							fi
						done
						lock_wait=0
						while [[ -f lock.txt ]]; do
							sleep 2
							((lock_wait+=2))
							if ((lock_wait > 210)); then
								rm lock.txt
							fi
						done
						if [[ -f daily_limit.txt ]]; then
							echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for $(( (3600 - $(date +%s) % 3600) / 60 )) minutes"
							sleep $(( 3600 - $(date +%s) % 3600 ))
							rm daily_limit.txt
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
					# Leave the loop
					loop=0
				else
					sleep 1800
				fi
			fi
		fi
		list="$new_list"
		unset new_list
		if ! [[ -n "$list" ]]; then
			# Leave the loop
			loop=0
		fi
	done
fi

echo "2" > status_rate.txt

# Linear loop
while [[ ! -f quit.txt ]]; do
	if [[ -n "$list" ]]; then
		hour=`date -u +%H`
		while IFS='' read -r line || [[ -n "$line" ]]; do
			capture "$line"
			((counter++))
			# Check failures and outlinks approximately every hour
			if ! ((counter % 50)) && ! [[ `date -u +%H` == "$hour" || -f quit.txt ]]; then
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
	else
		if [[ -z "$(<failed.txt)" ]]; then
			# No more URLs
			touch quit.txt
		fi
	fi
	new_list=$(get_list)
	if [[ "$new_list" == "$list" ]]; then
		((repeats++))
		if ((repeats > 1)); then
			if ((repeats > 4)); then
				# Give up
				touch quit.txt
			else
				echo "$(date -u '+%Y-%m-%d %H:%M:%S') Pausing for 30 minutes"
				sleep 1800
			fi
		fi
	fi
	list="$new_list"
	unset new_list
done
