## Test environments

**Local:** * macOS, R 4.6.1

**Continuous integration via GitHub Actions (`R-CMD-check.yaml`):**
* macOS latest, R release
* Windows latest, R release
* Ubuntu latest, R devel
* Ubuntu latest, R release
* Ubuntu latest, R oldrel-1

**Win-builder:**
* [win-builder](https://win-builder.r-project.org/) R release
* [win-builder](https://win-builder.r-project.org/) R-devel

**mac-builder:**
* [mac-builder](https://mac.r-project.org/macbuilder/submit.html) R release
* [mac-builder](https://mac.r-project.org/macbuilder/submit.html) R-devel

**R-Hub:**
* Linux containers (Debian, Ubuntu, Fedora) covering R release and R devel
* Windows, R release and R devel
* macOS, R release and R devel

(Platforms whose upstream R-hub container images are currently broken — stale
R-devel snapshots or sanitizer-instrumented images that fail to link their
runtime libraries — are excluded from the matrix; see the exclusion list in
`.github/workflows/rhub.yaml` and the reasons recorded there.)

## R CMD check results

0 errors | 0 warnings | 0 notes

(The results above are from the local check and the GitHub Actions CI matrix.
Win-builder, mac-builder and R-Hub runs for this first submission were
additionally clean where they completed.)

* This is a new release.
