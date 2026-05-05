# README

This is the README-BUILD file for the `Amazon-Credentials` project.

---

Version 1.3.0 introduces a build based on
[`CPAN::Maker::Bootstrapper`](https://github.com/rlauer6/CPAN-Maker-Bootstrapper.git)

# Build Dependencies

* GNU make
* `git`
* Perl Modules
  * `Module::ScanDeps::Static`
  * `Markdown::Render`
  * `CPAN::Maker`
  * `Pod::Extract`
  * ...and possibly others

The easiest way to install the module is using `cpanm`.

```
cpanm -n -v Amazon::Credentials
```

If you want to build the tarball, first install the dependencies listed,
then:

```
git clone https://github.com/rlauer6/Amazon-Credentials.git
cd Amazon-Credentials
make quick
cpanm -n -v Amazon-Credentials*.tar.gz
```
