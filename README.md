# `wayback-machine-spn-scripts` (full title pending)

`spn.sh`, a Bash script that asks the Internet Archive Wayback Machine's [Save Page Now (SPN)](https://web.archive.org/save/) to save live web pages

## Introduction

### Features

* Cross-platform compatible (Windows 10 WSL, macOS, Linux, BSD)
* Run capture jobs in parallel
* Automatic retry, including handling for Save Page Now internal errors
* Recursively and selectively save outlinks
* Extensible script structure

### Motivation

There exist several alternatives to this script, including [wayback-gsheets](https://archive.org/services/wayback-gsheets/) on archive.org. However, in terms of functionality, this script has some advantages over other methods of sending captures to the Wayback Machine.

* At present, Save Page Now has an error rate of around 20% to 30% regardless of the content being saved and the rate of operation. [This is a known issue](https://old.reddit.com/r/WaybackMachine/comments/m139pt/ive_got_an_amazing_response_from_the_wayback/) but has not been fixed for some time. The script will automatically retry those captures.
* In comparison to the outlinks function native to Save Page Now, the script allows outlinks to be recursively captured, and allows for inclusion/exclusion of groups of URLs. For example, the user can prevent a website's login form from being captured. Additionally, the website's outlinks function can sometimes overwhelm smaller websites, since all of the outlink captures are started at the same time, whereas the script allows the user to prevent this by limiting the number of parallel capture jobs.
* The script's structure is relatively extensible. For example, with minor modifications, any data returned by the Save Page Now JSON responses can be processed and output to a new log file and/or reused as input in another function. (The script uses POST requests rather than GET requests to submit URLs to Save Page Now; older scripts that use the latter method return much less data for completed captures.)

## spn.sh

### Installation

Download the script and make it executable with the command `chmod u+x spn.sh`.

### Dependencies

This script is written in Bash and has been tested using the shell environment preinstalled binaries on macOS and Windows 10 WSL Ubuntu. As far as possible, utilities have been used in ways in which behavior is consistent for both their GNU and BSD implementations.

### Operation

The only required input is the first argument, which can be a file name or URL. If the file doesn't exist or if there's more than one argument, then the input is treated as a set of URLs. A sub-subfolder of `~/spn-data` is created when the script starts, and logs and data are stored in the new folder. Some information is also sent to the standard output. All dates and times are in UTC.

The main list of URLs is stored in memory. Every time the script reaches the end of the main list, and approximately once every hour (if the list has more than 50 URLs), URLs for failed capture jobs and outlinks are added to the list. When there are no more URLs, the script terminates.

The script may sometimes not output to the console or to the log files for an extended period. This can occur if Save Page Now introduces a delay for captures of a specific domain, though typically the delay is only around a few minutes at most. [If you're on Windows, make sure it isn't just PowerShell.](https://serverfault.com/a/205898)

#### Flags

```
 -n             tell Save Page Now not to save errors into the Wayback Machine
 -o pattern     archive detected capture outlinks matching regex (ERE) pattern
 -p N           run at most N capture jobs in parallel (off by default)
 -q             discard JSON for completed jobs instead of writing to log file"
```

* The `-o` flag enables recursive saving of outlinks. The argument should be a POSIX ERE regular expression pattern. Around every hour, outlinks in the JSON received from Save Page Now that match the pattern are added to the list of URLs to be submitted to Save Page Now. If an outlink has already been captured in a previous job, it will not be added to the list. A maximum of 100 outlinks per capture can be sent by Save Page Now, and the maximum number of provided outlinks to certain sites (e.g. outlinks matching `example.com`) may be limited server-side. To save as many outlinks as possible, use `-o '.*'`.
* The `-p` flag sets the maximum number of parallel capture jobs, which can be between 2 and 30. If the flag is not used, capture jobs do not run simultaneously. The Save Page Now rate limit will prevent a user from starting another capture job if the user's load on the server is too high, so setting the value higher may not always be more efficient. Be careful with using this on websites that may be easily overloaded.
* The `-n` flag unsets the HTTP POST option `capture_all=on`. This tells Save Page Now not to save error pages to the Wayback Machine.
* The `-q` flag tells the script not to write JSON for successful captures to the disk. This can save disk space if you don't intend to use the JSON for anything.

#### Data files

The `.txt` files in the data folder of the running script may be modified manually to affect the script's operation, excluding old versions of those files which have been renamed to have a Unix timestamp in the title.

* `failed.txt` is used to compile the URLs that could not be saved, excluding files larger than 2 GB and URLs returning HTTP errors. They are periodically added back to the main list and retried. The user can add and remove URLs from this file to affect which URLs are added. Old versions of the file are renamed with a Unix timestamp.
* `outlinks.txt` is used to compile matching outlinks from captures if the `-o` flag is used. They are periodically deduplicated and added to the main list. The user can add and remove URLs from this file. If the `-o` flag is not used, this file is not created and has no effect if created by the user. Old versions of the file are renamed with a Unix timestamp.
* `index.txt` is used to check which outlinks have already been added to the list. When outlinks are added to the main list, they are also appended to this file. URLs that submitted URLs redirect to are added to the list. The user can add and remove URLs from this file. If the -o flag is not used, this file is not created and has no effect if created by the user.
* `max_parallel_jobs.txt` is initially set to the argument of the `-p` flag if the flag is used. The user can modify this file to change the maximum number of parallel capture jobs. If the `-p` flag is not used, this file is not created and has no effect if created by the user.
* `status_rate.txt` is the amount of time in seconds that each process sleeps before checking or re-checking the job status. It is initially set to 1 more than the maximum number of parallel processes (e.g. 3 for `-p 2`, 31 for `-p 30`), and is 2 if the `-p` flag is not used. The user can modify this file to change the rate at which job statuses are checked, although it is intentionally set low enough to avoid causing too many refused connections.
* `lock.txt` is created whenever a rate limit message is received upon submitting a URL. Submission of the URL is retried until it is successfully submitted and the file is removed, and while it exists it prevents more new capture jobs from being started. Removing the file manually will cause all jobs that are waiting to retry submission.
* `daily_limit.txt` is created if the user has reached the Save Page Now daily limit (presently 8,000 captures). The script will pause until the end of the current hour if the file is created, and the file will then be removed. Removing the file manually will not allow the script to continue.
* `quit.txt` lets the script exit if it exists. It is created when the list is empty and there are no more URLs to add to the list. It is also created after five instances (which may be non-consecutive) of the new list of URLs being exactly the same as the previous one. If the file is created manually, the script will run through the remainder of the current list without adding any URLs from `failed.txt` or `outlinks.txt`, and then exit. The user can also end the script abruptly by typing `^C` (`Ctrl`+`C`) in the terminal, which will prevent any new jobs from starting.

The `.log` files in the data folder of the running script do not affect the script's operation. The files will not be created until they receive data (which may include blank lines). They are updated continuously until the script finishes. If the script is aborted, the files may continue receiving data from capture jobs for a few minutes. Log files that contain JSON are not themselves valid JSON, but can be converted to valid JSON with the command `sed -e 's/}$/},/g' <<< "[$(<filename.log)]" > filename.json`.
* `success.log` contains the submitted URLs for successful capture jobs.
* `success-json.log` contains the final received status response JSON for successful capture jobs. If the `-q` flag is used, the file is not created and the JSON is discarded after being received.
* `captures.log` contains the Wayback Machine URLs for successful capture jobs (`https://web.archive.org` is omitted). If the submitted URL is a redirect, then the Wayback Machine URL may be different.
* `error-json.log` contains the final received status response JSON for unsuccessful capture jobs that return errors, including those which are retried (i.e. Save Page Now internal/proxy errors).
* `failed.log` contains the submitted URLs for unsuccessful capture jobs that are not retried, along with the date and time and the error code provided in the status response JSON.
* `invalid.log` contains the submitted URLs for capture jobs that fail to start and are not retried, along with the date and time and the site's error message (if any).
* `unknown-json.log` contains the final received status response for capture jobs that end unsuccessfully after receiving an unparsable status response.

## Changelog

* March 18, 2021: Initial release of `spn.sh`

### Future plans

* Make it possible to restart an aborted session
* Add HTTPS-only flag
* Add specialized scripts for specific purposes
