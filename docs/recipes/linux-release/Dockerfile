FROM oraclelinux:8.5@sha256:cda8334297e86456c96986b4070891ed58f56151e8ae2e500d9e13b1d743b2c6 AS configured

RUN dnf install -y gcc gcc-c++ make perl ncurses-devel openssl-devel zlib-devel \
      git curl ca-certificates tar gzip unzip findutils which && dnf clean all

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

WORKDIR /tmp/otp-build
RUN curl --fail --location --retry 3 \
      https://github.com/erlang/otp/releases/download/OTP-28.5.0.5/otp_src_28.5.0.5.tar.gz \
      --output otp.tar.gz && \
    printf '%s  otp.tar.gz\n' 5231ba18f31f8041c2d6514cc8842e46954d3b39a53f1617f03f2abe6fea59c7 | sha256sum --check && \
    tar -xzf otp.tar.gz && cd otp_src_28.5.0.5 && \
    ./configure --prefix=/opt/erlang --disable-jit --without-javac --without-wx --without-odbc

FROM configured AS installed
RUN cd /tmp/otp-build/otp_src_28.5.0.5 && make -j4 && make install && \
    ln -s /opt/erlang/bin/erl /opt/erlang/bin/erlc /opt/erlang/bin/escript /usr/local/bin/

WORKDIR /tmp/elixir-build
RUN curl --fail --location --retry 3 \
      https://github.com/elixir-lang/elixir/releases/download/v1.19.3/elixir-otp-28.zip \
      --output elixir.zip && \
    printf '%s  elixir.zip\n' 537e976fd0f78644f6369efa87b64c9204a5ff0e7aa3185a4d3aec4e2805cae8 | sha256sum --check && \
    mkdir /opt/elixir && unzip -q elixir.zip -d /opt/elixir && \
    ln -s /opt/elixir/bin/elixir /opt/elixir/bin/elixirc /opt/elixir/bin/iex /opt/elixir/bin/mix /usr/local/bin/ && \
    elixir --version && mix local.hex --force && mix local.rebar --force

WORKDIR /work

FROM installed AS toolchain
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN dnf install -y xz && dnf clean all
WORKDIR /tmp/rust-install
RUN curl --fail --location --retry 3 https://static.rust-lang.org/dist/2025-10-30/rust-1.91.0-x86_64-unknown-linux-gnu.tar.xz --output rust.tar.xz && \
    printf '%s  rust.tar.xz\n' 5bea12c1911dda5c0a91cee4e9b617a65bcf23a21e2852a17b544936de1f83e3 | sha256sum --check && \
    tar -xJf rust.tar.xz && \
    ./rust-1.91.0-x86_64-unknown-linux-gnu/install.sh --prefix=/opt/rust \
      --components=rustc,cargo,rust-std-x86_64-unknown-linux-gnu && \
    /opt/rust/bin/rustc --version && /opt/rust/bin/cargo --version
ENV PATH="/opt/rust/bin:$PATH"
WORKDIR /work

FROM toolchain AS release
ARG RELEASE_NAME
ENV MIX_ENV=prod MDEX_NATIVE_BUILD=1
WORKDIR /work
COPY . .
RUN test -n "$RELEASE_NAME" && \
    case "$RELEASE_NAME" in *[!a-z0-9_]*) exit 1 ;; esac && \
    mix deps.get --check-locked && \
    mix release "$RELEASE_NAME" && \
    tar -czf /tmp/release.tar.gz -C "_build/prod/rel/$RELEASE_NAME" .
