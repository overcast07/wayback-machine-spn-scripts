# `wayback-machine-spn-scripts` (full title pending)

`spn.sh`, a Bash script that asks the Internet Archive Wayback Machine's [Save Page Now (SPN)](https://web.archive.org/save/) to save live web pages

**Note (June 3, 2021):** Due to a server-side change, all earlier versions of this script no longer work without [a specific patch](https://github.com/overcast07/wayback-machine-spn-scripts/commit/10c5b087d76807170ed830abbd88a0118d234a21). **Please re-download the script if you installed it previously.**

## Introduction

### Features

* Cross-platform compatible (Windows 10 WSL, macOS, Linux, BSD)
* Run capture jobs in parallel
* Automatic retrying and error handling
* Recursively and selectively save outlinks
* Resume an aborted session
* Optional API authentication
* Extensible script structure

### Motivation

There exist several alternatives to this script, including the Python program [savepagenow by pastpages](https://github.com/pastpages/savepagenow) and the [wayback-gsheets](https://archive.org/services/wayback-gsheets/) interface on archive.org. However, in terms of functionality, this script has some advantages over other methods of sending captures to the Wayback Machine.

* In some cases, captures may fail due to issues with the website being captured or with Save Page Now. The script will automatically retry captures that fail. (Since April 2021, the error rate of Save Page Now has decreased significantly, but there may still be systematic issues with some content, such as pages that take a long time to load.)
* In comparison to the outlinks function native to Save Page Now, the script allows outlinks to be recursively captured, and allows for inclusion/exclusion of groups of URLs. For example, the user can prevent a website's login form from being repeatedly captured. Additionally, the website's outlinks function can sometimes overwhelm smaller websites, since all of the outlink captures are queued at the same time, whereas the script allows the user to prevent this by limiting the number of parallel capture jobs.
* The script's structure is relatively extensible. For example, with minor modifications, any data returned by the Save Page Now JSON responses can be processed and output to a new log file and/or reused as input in another function. (The script uses POST requests rather than non-authenticated GET requests to submit URLs to Save Page Now; older scripts that use the latter method return much less data for completed captures and cannot set [capture request options](https://docs.google.com/document/d/1Nsv52MvSjbLb2PCpHlat0gkzw0EvtSgpKHu4mk0MnrA/edit#heading=h.uu61fictja6r).)

## spn.sh

### Installation

Download the script and make it executable with the command `chmod a+x spn.sh`. The script can be run directly and does not need to be compiled to a binary executable beforehand.

### Dependencies

This script is written in Bash and has been tested using the shell environment preinstalled binaries on macOS and Windows 10 WSL Ubuntu. As far as possible, utilities have been used in ways in which behavior is consistent for both their GNU and BSD implementations. (The use of `sed -E` in particular may be a problem for older versions of GNU `sed`, but otherwise there should be no major compatibility issues.)

### Operation

The only required input (unless resuming a previous session) is the first argument, which can be a file name or URL. If the file doesn't exist or if there's more than one argument, then the input is treated as a set of URLs. A sub-subfolder of `~/spn-data` is created when the script starts, and logs and data are stored in the new folder. Some information is also sent to the standard output. All dates and times are in UTC.

The main list of URLs is stored in memory. Every time the script reaches the end of the main list, and approximately once every hour (if the list has more than 50 URLs), URLs for failed capture jobs and outlinks are added to the list. When there are no more URLs, the script terminates.

The script can be terminated from the command prompt with Ctrl+C (or by other methods like the task manager or the `kill` command). If this is done, no more capture jobs will be started. (If the `-p` flag is used, active capture jobs may continue to run for a few minutes.)

The script may sometimes not output to the console or to the log files for an extended period. This can occur if Save Page Now introduces a delay for captures of a specific domain, though typically the delay is only around a few minutes at most. [If you're on Windows, make sure it isn't just PowerShell.](https://serverfault.com/a/205898)

Note that the default behavior on the website is equivalent to `spn.sh -n` (don't save error pages). Using the flags `-p 10` (up to 10 parallel capture jobs) and `-q` (log fewer JSON responses) is also recommended.

#### Usage examples

##### Basic usage

Submit URLs from the command line.
```bash
spn.sh https://example.com/page1/ https://example.com/page2/
```

If this doesn't work, try specifying the file path of the script. For example, if you move the script into your home folder:
```bash
~/spn.sh https://example.com/page1/ https://example.com/page2/
```

Submit URLs from a text file containing one URL per line.
```bash
spn.sh urls.txt
```

##### Run jobs in parallel

Keep at most `10` capture jobs active at the same time. (The server-side rate limit may come into effect before reaching this limit.)
```bash
spn.sh -p 10 urls.txt
```

##### Save outlinks

Save all outlinks, outlinks of outlinks, and so on. (The script continues until either there are no more URLs or the script is terminated by the user.)
```bash
spn.sh -o '' https://example.com/
```

Save outlinks matching either `youtube` or `reddit`, except those matching `facebook`.
```bash
spn.sh -o 'youtube|reddit' -x 'facebook' https://example.com/
```

Save outlinks to the subdomain `www.example.org`.
```bash
spn.sh -o 'https?://www\.example\.org(/|$)' https://example.com/
```

#### Flags

```
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
                (if -o is also used, outlinks are filtered using both regexes)
```

All flags should be placed before arguments, but flags may be used in any order. If a string contains characters that need to be escaped in Bash, wrap the string in quotes; e.g. `-x '&action=edit'`.

* The `-a` flag allows the user to log in to an archive.org account with [S3 API keys](https://archive.org/account/s3.php). The keys should be provided in the form `accesskey:secret` (e.g. `-a YT2VJkcJV7ZuhA9h:7HeAKDvqN7ggrC3N`). If this flag is used, some login-only options can be enabled with the `-d` flag, in particular `capture_outlinks=1` and `capture_screenshot=1`. Additionally, much less data is downloaded when submitting URLs, and the captures will count towards the archive.org account's daily limit instead of that of the user's IP.
* The `-c` flag allows arbitrary options to be used for [`curl`](https://curl.se/), which the script uses to send HTTP requests. For example, `-c '-x socks5h://127.0.0.1:9150/'` could be used to proxy all connections through the Tor network via [Tor Browser](https://www.torproject.org/). Documentation for `curl` is available on [the project website](https://curl.se/docs/), as well as through the commands `curl -h` and `man curl`. If one of the strings to be passed contains a space or another character that needs to be escaped, nested quotation marks may be used (e.g. `-c '-K "config file.txt"'`).
* The `-d` flag allows the use of Save Page Now's [capture request options](https://docs.google.com/document/d/1Nsv52MvSjbLb2PCpHlat0gkzw0EvtSgpKHu4mk0MnrA/edit#heading=h.uu61fictja6r), which should be formatted as POST data (e.g. `-d 'force_get=1&if_not_archived_within=86400'`). Documentation for the available options is available in the linked Google Drive document. Some options, in particular `capture_outlinks=1` and `capture_screenshot=1`, require authentication through the `-a` flag. The options are set for all submitted URLs. By default, the script sets the option `capture_all=on`; the `-n` flag disables it, but it can also be disabled by including `capture_all=0` in the `-d` flag's argument. Note that as of March 2021, the `outlinks_availability=1` option does not appear to work as described, and other parts of the documentation may be out of date.
* The `-f` flag may be used to set a custom location for the data folder, which may be anywhere in the file system; the argument should be the location of the folder. The flag is primarily meant for `cron` jobs; as such, the script's behavior is slightly different, in that all `.txt` files other than `failed.txt`, `outlinks.txt` and `index.txt` will have the running script's process ID inserted into their names and be deleted when the script finishes, in order to allow multiple instances of the script to run in the same folder without interfering with each other (although they will share `failed.txt`, `outlinks.txt` and `index.txt` and will be able to affect each other through those files). The folder may already exist, and it may also contain a previous session's files, which the script may modify (e.g. it will append data to existing log files). In particular, `index.txt` may be overwritten when the script starts. If the folder does not yet exist, it will be created.
* The `-i` flag appends a suffix to the name of the data folder. Normally, the name is just the Unix timestamp, so adding text (such as a website name) may be helpful for organizing and distinguishing folders. Other than changing the name of the data folder, it has no effect on the operation of the script.
* The `-o` and `-x` flags enable recursive saving of outlinks. To save as many outlinks as possible, use `-o ''`. The argument for each flag should be a POSIX ERE regular expression pattern. If only the `-o` flag is used, then all links matching the provided pattern are saved; if only the `-x` flag is used, then all links _not_ matching the provided pattern are saved; and if both are used, then all links matching the `-o` pattern but not the `-x` pattern are saved. Around every hour, matching outlinks in the JSON received from Save Page Now are added to the list of URLs to be submitted to Save Page Now. If an outlink has already been captured in a previous job, it will not be added to the list. A maximum of 100 outlinks per capture can be sent by Save Page Now, and the maximum number of provided outlinks to certain sites (e.g. outlinks matching `example.com`) may be limited server-side. The `-o` and `-x` flags are separate to the server-side `capture_outlinks=1` option, and will not work if that option is enabled through use of the `-a` and `-d` flags.
* The `-p` flag sets the maximum number of parallel capture jobs, which can be between 2 and 60. If the flag is not used, capture jobs are not queued simultaneously. (Each submitted URL is queued for a period of time before the URL is actually crawled.) The Save Page Now rate limit will prevent a user from starting another capture job if the user has too many concurrently active jobs (not including queued jobs), so setting the value higher may not always be more efficient. Be careful with using this on websites that may be easily overloaded.
* The `-n` flag unsets the HTTP POST option `capture_all=on`. This tells Save Page Now not to save error pages to the Wayback Machine. Because the option is set by default when using the web form, the script does the same.
* The `-q` flag tells the script not to write JSON for successful captures to the disk. This can save disk space if you don't intend to use the JSON for anything.
* The `-s` flag forces the use of HTTPS for all captures (excluding FTP links). Input URLs and outlinks are automatically changed to HTTPS.
* The `-r` flag allows the script to resume with the remaining URLs of a prior aborted session; the argument should be the location of a folder. If this flag is used, the script does not take any arguments. It is necessary for `index.txt` and `success.log` to exist in the folder in order for the session to be resumed; if `outlinks.txt` also exists, then the links in that file and the links in `captures.log` will also be accounted for.

#### Data files

The `.txt` files in the data folder of the running script may be modified manually to affect the script's operation, excluding old versions of those files which have been renamed to have a Unix timestamp in the title.

* `failed.txt` is used to compile the URLs that could not be saved, excluding files larger than 2 GB and URLs returning HTTP errors. They are periodically added back to the main list and retried. The user can add and remove URLs from this file to affect which URLs are added. Old versions of the file are renamed with a Unix timestamp.
* `outlinks.txt` is used to compile matching outlinks from captures if the `-o` flag is used. They are periodically deduplicated and added to the main list. The user can add and remove URLs from this file. When resuming an aborted session with the `-r` flag, the file is used to determine which URLs have yet to be captured. If the `-o` flag is not used, this file is not created and has no effect if created by the user. Old versions of the file are renamed with a Unix timestamp.
* `index.txt` is used to record which links are part of the list, and is created when the script starts. If the -o flag is not used, this file is never used unless the `-r` flag is later used to resume the session. When outlinks are added to the main list, they are also appended to this file. When a capture job finishes successfully, if the submitted URL redirects to a different URL, the latter is added to the list (unless the -o flag is not used). The user can add and remove URLs from this file. When resuming an aborted session with the `-r` flag, the file is used to determine which URLs have yet to be captured.
* `max_parallel_jobs.txt` is initially set to the argument of the `-p` flag if the flag is used. The user can modify this file to change the maximum number of parallel capture jobs. If the `-p` flag is not used, this file is not created and has no effect if created by the user.
* `status_rate.txt` is the time in seconds that each process sleeps before checking or re-checking the job status. It is initially set to the same as the maximum number of parallel processes, and is 2 if the `-p` flag is not used. The user can modify this file to change the rate at which job statuses are checked, although it is intentionally set low enough to avoid causing too many refused connections.
* `lock.txt` is created whenever a rate limit message is received upon submitting a URL. Submission of the URL is retried until it is successfully submitted and the file is removed, and while it exists it prevents more new capture jobs from being started. Removing the file manually will cause all jobs that are waiting to retry submission. If the file is created manually or if a process fails to remove the file after having created it, it will be removed automatically after 5 minutes.
* `daily_limit.txt` is created if the user has reached the Save Page Now daily limit (presently 8,000 captures). The daily limit resets at 00:00 UTC. The script will pause until the end of the current hour if the file is created, and the file will then be removed; this will also happen if the file is created manually. Removing the file manually will not allow the script to continue.
* `quit.txt` lets the script exit if it exists. It is created when the list is empty and there are no more URLs to add to the list. It is also created after five instances (which may be non-consecutive) of the new list of URLs being exactly the same as the previous one. If the file is created manually, the script will run through the remainder of the current list without adding any URLs from `failed.txt` or `outlinks.txt`, and then exit. The user can also end the script abruptly by typing `^C` (`Ctrl`+`C`) in the terminal, which will prevent any new jobs from starting.

The `.log` files in the data folder of the running script do not affect the script's operation. The files will not be created until they receive data (which may include blank lines). They are updated continuously until the script finishes. If the script is aborted, the files may continue receiving data from capture jobs for a few minutes. Log files that contain JSON are not themselves valid JSON, but can be converted to valid JSON with the command `sed -e 's/}$/},/g' <<< "[$(<filename.log)]" > filename.json`.
* `success.log` contains the submitted URLs for successful capture jobs.  When resuming an aborted session with the `-r` flag, the file is used to determine which URLs have yet to be captured.
* `success-json.log` contains the final received status response JSON for successful capture jobs. If the `-q` flag is used, the file is not created and the JSON is discarded after being received.
* `captures.log` contains the Wayback Machine URLs for successful capture jobs (`https://web.archive.org` is omitted). If the submitted URL is a redirect, then the Wayback Machine URL may be different.  When resuming an aborted session with the `-r` flag, the file is used to determine which URLs have yet to be captured if `outlinks.txt` also exists.
* `error-json.log` contains the final received status response JSON for unsuccessful capture jobs that return errors, including those which are retried (i.e. Save Page Now internal/proxy errors).
* `failed.log` contains the submitted URLs for unsuccessful capture jobs that are not retried, along with the date and time and the error code provided in the status response JSON.
* `invalid.log` contains the submitted URLs for capture jobs that fail to start and are not retried, along with the date and time and the site's error message (if any).
* `unknown-json.log` contains the final received status response for capture jobs that end unsuccessfully after receiving an unparsable status response.

#### Additional usage examples

##### Outlinks

Save outlinks to all subdomains of `example.org`.
```bash
spn.sh -o 'https?://([^/]+\.)?example\.org(/|$)' https://example.com/
```

Save outlinks to `example.org/files/` and all its subdirectories, except for links with the file extension `.mp4`.
```bash
spn.sh -o 'https?://(www\.)?example\.org/files/' -x '\.mp4(\?|$)'  https://example.com/
```

Save outlinks matching YouTube video URLs.
```bash
spn.sh -o 'https?://(www\.|m\.)?youtube\.com/watch\?(.*\&)?v=[a-zA-Z0-9_-]{11}|https?://youtu\.be/[a-zA-Z0-9_-]{11}' https://example.com/
```

Save subdirectories and files in an IPFS folder, visiting each file twice (replace the example folder URL with that of the folder to be archived).
```bash
spn.sh -o 'https?://(gateway\.)?ipfs\.io/ipfs/(QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn/.+|[a-zA-Z0-9]{46}\?filename=)' https://ipfs.io/ipfs/QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn
```

## Changelog

* March 18, 2021: Initial release of `spn.sh` 
* March 28, 2021: Addition of `-a`, `-d`, `-r`, `-s` and `-x` options; code cleanup and bug fixes (aborted sessions of the previous version of the script cannot be restarted unless the `-o` flag was used or `index.txt` is manually created)
* March 29, 2021: Bug fixes
* April 6, 2021: Bug fixes and improvement of HTTP error handling
* April 7, 2021: Addition of `-c`, `-f` and `-i` options; bug fixes
* April 30, 2021: Bug fixes
* May 8, 2021: Bug fixes; addition of usage examples
* June 3, 2021: Bug fix (all previous versions of the script now require an API key to work correctly due to a server-side change in the format of job IDs)
* July 6, 2021: Bug fix (server-side change)
* September 30, 2021: Bug fix (server-side change)
* October 6, 2021: Bug fix (handle edge case)
* December 30, 2021: Changed waiting time before a capture job fails from 5 minutes to 10

### Future plans

* Add specialized scripts for specific purposes
* Allow outlinks to be added automatically from direct downloads of pages
* Add data logging/handling for server-side outlinks function
