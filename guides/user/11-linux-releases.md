# Build a release for Linux

Build the application, ERTS, and native libraries for the production CPU and
libc. A Linux build can compile successfully and still fail on an older Linux
system. Windows and macOS build products cannot run on Linux.

Issue [#10](https://github.com/agentjido/term_ui/issues/10) reports this failure
on Oracle Linux 8.5. That system has glibc 2.28. A release built with a newer
glibc can require symbols that the target does not provide. MDEx also has a
native library, so a compatible BEAM alone does not complete the check.

## Check the target

Run these commands on the target:

```sh
uname -m
ldd --version
```

The supplied recipe targets `x86_64` / `linux/amd64` with Oracle Linux 8.5.
Build another recipe for an ARM or musl target. Keep the target CPU, libc,
OTP, Elixir, and native dependency versions in the release record.

The production system does not need Docker, Mix, Elixir, or a compiler.
Build elsewhere, then transfer the release archive. The archive includes ERTS.

## Prepare the application

Use a clean checkout of the application and its committed `mix.lock`.
Add the Rustler build dependency to the application's `deps/0`:

```elixir
{:rustler, "~> 0.38.0", runtime: false}
```

In `project/0`, also configure the release. Use the same name as the build
argument. For example, add this entry to the project keyword list:

```elixir
releases: [my_app: [include_erts: true]]
```

Run `mix deps.get` and commit the resulting application lockfile. Rustler is
needed by the build. `runtime: false` keeps it out of the running release.

The builder sets `MDEX_NATIVE_BUILD=1`. This forces MDEx to build its NIF
against the builder's libc. This variable alone is not sufficient: the
application must also include Rustler. A downloaded MDExNative 0.2.9 GNU NIF
requires glibc 2.29 and fails on the tested glibc 2.28 target.

Copy the [Dockerfile](https://github.com/agentjido/term_ui/blob/maint/1.x/examples/linux_release/Dockerfile)
and [dockerignore](https://github.com/agentjido/term_ui/blob/maint/1.x/examples/linux_release/dockerignore)
from `examples/linux_release` into the application as `Dockerfile` and
`.dockerignore`. Keep any application-specific exclusions too. Exclude
`_build` and downloaded `deps`, so host build products do not enter the Linux
build. A local path dependency must be inside the build context.

The recipe pins the Oracle Linux image and checks the OTP, Elixir, and Rust
archive hashes. It uses OTP 28.5.0.5, Elixir 1.19.3, and Rust 1.91.0. Rust
1.91 is required by the tested MDExNative source. The builder uses a UTF-8
locale.

The recipe disables OTP JIT. The x86_64 JIT builds tested under macOS ARM
emulation failed during OTP terminal bootstrap. A clean interpreter build
passes. This record does not establish a JIT defect on a native x86_64 host.
The supported OTP build option is documented in the
[Erlang installation guide](https://www.erlang.org/docs/28/system/install.html).

## Build and transfer

Replace `my_app` with the configured Mix release name:

```sh
docker build --platform linux/amd64 \
  --build-arg RELEASE_NAME=my_app \
  --tag my_app-linux-build .
docker create --name my-app-release-copy my_app-linux-build
docker cp my-app-release-copy:/tmp/release.tar.gz ./my_app-linux-amd64.tar.gz
docker rm my-app-release-copy
sha256sum my_app-linux-amd64.tar.gz
```

On Windows, run the Docker commands in PowerShell with each command on one
line. Use `Get-FileHash my_app-linux-amd64.tar.gz -Algorithm SHA256` for the
archive hash. Docker must build a Linux image.

Transfer this archive and its hash to the production system. Extract it into
a new application release directory:

```sh
mkdir -p my_app-release
tar -xzf my_app-linux-amd64.tar.gz -C my_app-release
cd my_app-release
export LANG=C.UTF-8 LC_ALL=C.UTF-8
bin/my_app eval 'IO.inspect(:erlang.system_info(:otp_release))'
bin/my_app eval 'IO.puts(MDEx.to_html!("**native check**"))'
```

The second command must produce HTML with a `strong` element. It exercises
the native library. A successful `mix release` does not prove that the NIF
loads: the failure can first occur when Markdown is used.

Run the application's terminal entry point in an interactive terminal. For
an application that exposes `MyApp.UI` as its Elm root:

```sh
bin/my_app eval 'TermUI.Runtime.run(root: MyApp.UI)'
```

Check navigation, control keys, paste, resize, and normal quit. Compare
`stty -g` before startup and after shutdown in the same terminal. Check cursor
visibility and screen restoration. Repeat over the production SSH connection.
A non-interactive package check does not verify terminal input.

## Verification record

The cleanup check uses the pinned Oracle Linux 8.5 `linux/amd64` image with
its original glibc 2.28. It has no installed Mix, Elixir, or Erlang command.
Consumer releases include ERTS and use source-built MDExNative 0.2.9.
Both v1 and v2 releases render native Markdown on that target. V2's source-built
TermUI TTY NIF also loads.

Real Linux PTY checks pass for Raw and TTY on both consumer releases. Raw
receives Ctrl+C, Ctrl+S, and Ctrl+Q as input. Both modes receive a normal quit,
exit successfully, and restore the exact original `stty -g` settings.

The image is a compatibility fixture. Production host permissions, SSH
configuration, and terminal profiles still need the application checks above.
The v2 test code is on `next/v2`; it is not a published TermUI 2.0 release.
