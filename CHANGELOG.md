# Revision history for krank

## Unreleased

* New `--json` argument. Violations are written to stdout as a JSON array,
  making the output consumable by other tools.
* A file which cannot be processed now exits with code `2` instead of `1`, so
  that a closed issue (`1`) can be told apart from `krank` failing to do its
  job. An issue tracker which cannot be reached is still a `warning` and does
  not affect the exit code.
* Failing to establish the list of files to check is now an error (`2`) instead
  of silently checking nothing and exiting `0`.
* The `find` fallback used when `git ls-files` is unavailable was invoked with
  an empty path and could never work.
* Diagnostics about the missing `git` / `find` commands are reported on stderr
  instead of stdout.

## 0.3.1 -- 2025-12-07

* Support for GHC up to 9.12
* Fix build with http-client >= 0.7.16
* Fix url parsing in markdown

## 0.2.3 -- 2021-07-18

* #88 krank tries to test files listed by `git ls-files` or `find` by default.
* #89 support `NO_COLOR`. https://no-color.org/.
* README is rebranded so it is obvious that `krank` checks for issue tracker / PR links.

## 0.2.2 -- 2020-06-30

* #84 fix build with `unordered-containers` 0.2.11.0
* #81, new `--version` command line argument

## 0.2.1 -- 2020-05-02

* #76 fix. ignore space in URL
* Output now includes the issue title.

## 0.2.0 -- 2020-04-19

* GHC 8.10 support
* Output is more compact and more detailed.
* Output is now colored (can be disabled with `--no-colors`).
* Gitlab support. See `--issuetracker-gitlabhost` for host / api key pairs.
* Huge performance improvement. Parsing a huge codebase should only be a matter
  of a few seconds.
* Parallel request execution. Requests to the issue tracker host are not
  sequential anymore. This can dramatically reduce the runtime.
* Ignore line. Add `krank:ignore-line` in your comments and the associated
  closed issue won't be seen as an error anymore.
* Failure mode: `krank` will return non 0 exit code if an issue is closed (an
  not ignored).

## 0.1.0.0 -- 2019-10-21

* First version. Released on an unsuspecting world.
* Support for Github issues tracking
