# `wayback-machine-spn-scripts` (full title pending)

`spn.sh`, a Bash script that asks the Internet Archive Wayback Machine's [Save Page Now (SPN)](https://web.archive.org/save/) to save live web pages

**Note:** Server-side changes are periodically made to the SPN service, so the script's behavior can become outdated quickly. Older revisions of the script are not supported and may not work.

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

The information on this page is focused on the script itself. More information about Save Page Now can be found at [the draft SPN2 public API documentation](https://docs.google.com/document/d/1Nsv52MvSjbLb2PCpHlat0gkzw0EvtSgpKHu4mk0MnrA/edit) by Vangelis Banos.

## spn.sh

### Installation

Download the script and make it executable with the command `chmod a+x spn.sh`. The script can be run directly and does not need to be compiled to a binary executable beforehand.

#### Arch Linux

On Arch Linux, this script is also available as an [AUR package](https://aur.archlinux.org/packages/wayback-spn-script-git) and you can install it with your favorite AUR helper.

```bash
yay -S wayback-spn-script-git
```

### Dependencies

This script is written in Bash and has been tested using the shell environment preinstalled binaries on macOS 10.14, macOS 12 and Windows 10 WSL Ubuntu. As far as possible, utilities have been used in ways in which behavior is consistent for both their GNU and BSD implementations. (The use of `sed -E` in particular may be a problem for older versions of GNU `sed`, but otherwise there should be no major compatibility issues.)

### Operation

The only required input (unless resuming a previous session) is the first argument, which can be a file name or URL. If the file doesn't exist or if there's more than one argument, then the input is treated as a set of URLs. A sub-subfolder of `~/spn-data` is created when the script starts, and logs and data are stored in the new folder. Some information is also sent to the standard output. All dates and times are in UTC.

The main list of URLs is stored in memory. Periodically, URLs for failed capture jobs and outlinks are added to the list. When there are no more URLs, the script terminates.

The script can be terminated from the command prompt with Ctrl+C (or by other methods like the task manager or the `kill` command). If this is done, no more capture jobs will be started, although active capture jobs may continue to run for a few minutes.

The script may sometimes not output to the console or to the log files for an extended period. This can occur if Save Page Now introduces a delay for captures of a specific domain, though typically the delay is only around a few minutes at most. [If you're on Windows, make sure it isn't just PowerShell.](https://serverfault.com/a/205898)

Using the `-q` flag (log fewer JSON responses) is recommended in order to save disk space during typical usage. `-n` (don't save error pages) is also recommended unless it is important to archive particular error pages.

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

Keep at most `20` capture jobs active at the same time. (The server-side rate limit may come into effect before reaching this limit.)
```bash
spn.sh -p 20 urls.txt
```

Don't run capture jobs in parallel. Wait at least 60 seconds between captures.
```bash
spn.sh -p 1 -w 60 urls.txt
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

 -p N           run at most N capture jobs in parallel (default: 20)

 -q             discard JSON for completed jobs instead of writing to log file

 -r folder      resume with the remaining URLs of an aborted session
                (settings are not carried over, except for outlinks options)

 -s             use HTTPS for all captures and change HTTP input URLs to HTTPS

 -t N           wait at least N seconds before updating the main list of URLs
                with outlinks and failed capture jobs (default: 3600)

 -w N           wait at least N seconds after starting a capture job before
                starting another capture job (default: 2.5)

 -x pattern     save detected capture outlinks not matching regex (ERE) pattern
                (if -o is also used, outlinks are filtered using both regexes)
```

All flags should be placed before arguments, but flags may be used in any order. If a string contains characters that need to be escaped in Bash, wrap the string in quotes; e.g. `-x '&action=edit'`.

* The `-a` flag allows the user to log in to an archive.org account with [S3 API keys](https://archive.org/account/s3.php). The keys should be provided in the form `accesskey:secret` (e.g. `-a YT2VJkcJV7ZuhA9h:7HeAKDvqN7ggrC3N`). If this flag is used, some login-only options can be enabled with the `-d` flag, in particular `capture_outlinks=1` and `capture_screenshot=1`. Additionally, much less data is downloaded when submitting URLs, and the captures will count towards the archive.org account's daily limit instead of that of the user's IP.
* The `-c` flag allows arbitrary options to be used for [`curl`](https://curl.se/), which the script uses to send HTTP requests. For example, `-c '-x socks5h://127.0.0.1:9150/'` could be used to proxy all connections through the Tor network via [Tor Browser](https://www.torproject.org/). Documentation for `curl` is available on [the project website](https://curl.se/docs/), as well as through the commands `curl -h` and `man curl`. If one of the strings to be passed contains a space or another character that needs to be escaped, nested quotation marks may be used (e.g. `-c '-K "config file.txt"'`).
* The `-d` flag allows the use of Save Page Now's [capture request options](https://docs.google.com/document/d/1Nsv52MvSjbLb2PCpHlat0gkzw0EvtSgpKHu4mk0MnrA/edit#heading=h.uu61fictja6r), which should be formatted as POST data (e.g. `-d 'force_get=1&if_not_archived_within=86400'`). Documentation for the available options is available in the linked Google Drive document. Some options, in particular `capture_outlinks=1` and `capture_screenshot=1`, require authentication through the `-a` flag. The options are set for all submitted URLs. By default, the script sets the option `capture_all=on`; the `-n` flag disables it, but it can also be disabled by including `capture_all=0` in the `-d` flag's argument. Note that as of March 2021, the `outlinks_availability=1` option does not appear to work as described, and other parts of the documentation may be out of date.
* The `-f` flag may be used to set a custom location for the data folder, which may be anywhere in the file system; the argument should be the location of the folder. The flag is primarily meant for `cron` jobs; as such, the script's behavior is slightly different, in that all `.txt` files other than `failed.txt`, `outlinks.txt` and `index.txt` will have the running script's process ID inserted into their names and will be deleted when the script finishes, in order to allow multiple instances of the script to run in the same folder without interfering with each other (although they will share `failed.txt`, `outlinks.txt` and `index.txt` and will be able to affect each other through those files). The folder may already exist, and it may also contain a previous session's files, which the script may modify (e.g. it will append data to existing log files). In particular, `index.txt` may be overwritten when the script starts. If the folder does not yet exist, it will be created.
* The `-i` flag appends a suffix to the name of the data folder. Normally, the name is just the Unix timestamp, so adding text (such as a website name) may be helpful for organizing and distinguishing folders. Other than changing the name of the data folder, it has no effect on the operation of the script.
* The `-o` and `-x` flags enable recursive saving of outlinks. To save as many outlinks as possible, use `-o ''`. The argument for each flag should be a POSIX ERE regular expression pattern. If only the `-o` flag is used, then all links matching the provided pattern are saved; if only the `-x` flag is used, then all links _not_ matching the provided pattern are saved; and if both are used, then all links matching the `-o` pattern but not the `-x` pattern are saved. Around every hour, matching outlinks in the JSON received from Save Page Now are added to the list of URLs to be submitted to Save Page Now. If an outlink has already been captured in a previous job, it will not be added to the list. A maximum of 100 outlinks per capture can be sent by Save Page Now, and the maximum number of provided outlinks to certain sites (e.g. outlinks matching `example.com`) may be limited server-side. The `-o` and `-x` flags are separate to the server-side `capture_outlinks=1` option, and will not work if that option is enabled through use of the `-a` and `-d` flags.
* The `-p` flag sets the maximum number of parallel capture jobs, which can be between 1 and 60. If the flag is not used, the maximum number will be set to 20. The Save Page Now rate limit will prevent a user from starting another capture job if the user has too many concurrently active jobs (not including queued jobs for which the URL has not been crawled yet). The default value is 20 to allow the script to work at a reasonable rate if captures are delayed by the server for several minutes before being started; in practice, the rate limit should prevent the script from actually reaching 20 parallel capture jobs. When capturing websites that may be easily overloaded, you may want to be careful and set a much lower maximum number.
* The `-n` flag causes error pages to not be saved to the Wayback Machine. (Not saving errors is the default in the SPN2 API, but the script's default is to save error pages, in order to reflect that the SPN website has the option "Save error pages" selected by default.)
* The `-q` flag tells the script not to write JSON for successful captures to the disk. This can save disk space if you don't intend to use the JSON for anything.
* The `-s` flag forces the use of HTTPS for all captures (excluding FTP links). Input URLs and outlinks are automatically changed to HTTPS.
* The `-t` flag sets the minimum amount of time (in seconds) that the script waits before updating the main URL list with discovered outlinks and the URLs of failed capture jobs. The value must be an integer. If the flag is not used, the amount of time between updates will be set to 3600 (1 hour).
* The `-w` flag sets the minimum amount of time (in seconds) that the script waits after starting a capture job before starting the next one. The value can be an integer or a non-integer number. If the flag is not used, the amount of time between capture jobs will be set to 2.5 seconds.
* The `-r` flag allows the script to resume with the remaining URLs of a prior aborted session; the argument should be the location of a folder. If this flag is used, the script does not take any arguments. It is necessary for `index.txt` and `success.log` to exist in the folder in order for the session to be resumed.  If `outlinks.txt` also exists, then the links in that file and the links in `captures.log` will also be accounted for, and the contents of `include_pattern.txt` and `exclude_pattern.txt` will be copied over if the `-o` and `-x` flags are not set. To avoid collecting any new outlinks, use `-x '.*'`.

#### Data files

The `.txt` files in the data folder of the running script may be modified manually to affect the script's operation, excluding old versions of those files which have been renamed to have a Unix timestamp in the title.

* `failed.txt` is used to compile the URLs that could not be saved, excluding files larger than 2 GB and URLs returning HTTP errors. They are periodically added back to the main list and retried. The user can add and remove URLs from this file to affect which URLs are added. Old versions of the file are renamed with a Unix timestamp.
* `outlinks.txt` is used to compile matching outlinks from captures. They are periodically deduplicated and added to the main list. The user can add and remove URLs from this file. When resuming an aborted session with the `-r` flag, the file is one of those used to determine which URLs have yet to be captured. Old versions of the file are renamed with a Unix timestamp once the contents have been combined into the main list. The file is created if the `-o` or `-x` flags are used, and is also created if a session that is being resumed contains `outlinks.txt`.
* `index.txt` is used to record which links are part of the list, and is created when the script starts. If outlinks are not being saved, this file is never used unless the `-r` flag is later used to resume the session. When outlinks are added to the main list, they are also appended to this file. When a capture job finishes successfully, if the submitted URL redirects to a different URL, the latter is added to the list (unless the -o flag is not used). The user can add and remove URLs from this file. When resuming an aborted session with the `-r` flag, the file is used to determine which URLs have yet to be captured.
* `include_pattern.txt` and `exclude_pattern.txt` contain the regular expression patterns used for recursive saving of outlinks; outlinks matching the former and not matching the latter are added to `outlinks.txt`. The contents are initially set by the `-o` and `-x` flags and can be changed at any time; both files are created even if one of the flags is not specified. If neither flag is set, then the values may be taken from a session that is being resumed if it contains `outlinks.txt`.
* `max_parallel_jobs.txt` is initially set to the argument of the `-p` flag if the flag is used, or 20 otherwise. The value must be an integer. The user can modify this file to change the maximum number of parallel capture jobs. If the `-p` flag is set to 1, this file is not created and has no effect if created by the user.
* `status_rate.txt` is the time in seconds that each process sleeps before checking or re-checking the job status. It is initially set to the same as the maximum number of parallel processes, and is set to 2 if the `-p` flag is set to 1. The user can modify this file to change the rate at which job statuses are checked, although the rate is intentionally set high enough to avoid causing too many refused connections.
* `list_update_rate.txt` is initially set to the argument of the `-t` flag if the flag is used, or 3600 otherwise. The value must be an integer. The user can modify this file to change the minimum amount of time between updates of the main URL list.
* `capture_job_rate.txt` is initially set to the argument of the `-w` flag if the flag is used, or 2.5 otherwise. The value can be an integer or a non-integer number. The user can modify this file to change the minimum amount of time that the script waits after starting a capture job before starting the next one.
* `lock.txt` is created whenever a rate limit message is received upon submitting a URL. Submission of the URL is retried until it is successfully submitted and the file is removed, and while it exists it prevents more new capture jobs from being started. Removing the file manually will cause all jobs that are waiting to retry submission. If the file is created manually or if a process fails to remove the file after having created it, it will be removed automatically after 5 minutes.
* `daily_limit.txt` is created if the user has reached the Save Page Now daily limit (presently 8,000 captures for logged-out users and 100,000 captures for logged-in users). The daily limit resets at 00:00 UTC. The script will pause until the end of the current hour if the file is created, and the file will then be removed; this will also happen if the file is created manually. Removing the file manually will not allow the script to continue.
* `quit.txt` lets the script exit if it exists. It is created when the list is empty and there are no more URLs to add to the list. It is also created after five instances (which may be non-consecutive) of the new list of URLs to submit being exactly the same as the previous one. If the file is created manually, the script will run through the remainder of the current list without adding any URLs from `failed.txt` or `outlinks.txt`, and then exit. The user can also end the script abruptly by typing `^C` (`Ctrl`+`C`) in the terminal, which will prevent any new jobs from starting.

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

Save outlinks matching MediaFire file download URLs, and update the URL list as frequently as possible so that the outlinks can be captured before they expire.
```bash
spn.sh -t 0 -o 'https?://download[0-9]+\.mediafire\.com/' https://www.mediafire.com/file/a28veehw21gq6dc
```

Save subdirectories and files in an IPFS folder, visiting each file twice (replace the example folder URL with that of the folder to be archived).
```bash
spn.sh -o 'https?://cloudflare-ipfs\.com/ipfs/(QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn/.+|[a-zA-Z0-9]{46}\?filename=)' https://cloudflare-ipfs.com/ipfs/QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn
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
* December 30, 2021: Change in the waiting time before a capture job fails from 5 minutes to 10
* February 25, 2022: Addition of `include_pattern.txt` and `exclude_pattern.txt`; improvements to how `-r` resumes sessions with outlinks (see [#11](https://github.com/overcast07/wayback-machine-spn-scripts/issues/11))
* April 10, 2022: Bug fix (server-side change)
* July 10, 2022: Bug fix (server-side change)
* December 17, 2022: Modification and addition of console messages that appear when the script starts and ends
* December 18, 2022: Addition of `-t` flag; change in the default amount of maximum parallel capture jobs from 1 to 8
* December 19, 2022: Bug fixes
* February 26, 2023: Bug fixes; addition of a check for messages received after submitting each URL; change in the default amount of maximum parallel capture jobs from 8 to 30
* March 2, 2023: Bug fix
* March 18, 2023: Change default location of the spn-data folder (see [#22](https://github.com/overcast07/wayback-machine-spn-scripts/pull/22))
* May 4, 2023: Addition of `-w` flag; addition of "first archive" check; addition of stalling check for downloads of large files; change in the default amount of maximum parallel capture jobs from 30 to 20
