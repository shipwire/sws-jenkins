FROM jenkins:latest
MAINTAINER nick.maiorsky@shipwire.com

# Autoconfig is needed

USER root

RUN apt-get update \
    && apt-get install -y automake gcc make gcc-multilib zlib1g-dev libssl-dev

# Taken from Ruby Docker file. I need the tools on my jenkins instance and not of the slave
# skip installing gem documentation
RUN mkdir -p /usr/local/etc \
	&& { \
		echo 'install: --no-document'; \
		echo 'update: --no-document'; \
	} >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.2
ENV RUBY_VERSION 2.2.5
ENV RUBY_DOWNLOAD_SHA256 30c4b31697a4ca4ea0c8db8ad30cf45e6690a0f09687e5d483c933c03ca335e3
ENV RUBYGEMS_VERSION 2.6.6

# some of ruby's build scripts are written in ruby
# we purge this later to make sure our final image uses what we just built
RUN set -ex \
	&& buildDeps=' \
		bison \
		libgdbm-dev \
		ruby \
	' \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends $buildDeps \
	&& rm -rf /var/lib/apt/lists/* \
	&& curl -fSL -o ruby.tar.gz "http://cache.ruby-lang.org/pub/ruby/$RUBY_MAJOR/ruby-$RUBY_VERSION.tar.gz" \
	&& echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.gz" | sha256sum -c - \
	&& mkdir -p /usr/src/ruby \
	&& tar -xzf ruby.tar.gz -C /usr/src/ruby --strip-components=1 \
	&& rm ruby.tar.gz \
	&& cd /usr/src/ruby \
	&& { echo '#define ENABLE_PATH_CHECK 0'; echo; cat file.c; } > file.c.new && mv file.c.new file.c \
	&& autoconf \
	&& ./configure --disable-install-doc \
	&& make -j"$(nproc)" \
	&& make install \
	&& apt-get purge -y --auto-remove $buildDeps \
	&& gem update --system $RUBYGEMS_VERSION \
	&& rm -r /usr/src/ruby

ENV BUNDLER_VERSION 1.13.1

RUN gem install bundler --version "$BUNDLER_VERSION"

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
	BUNDLE_BIN="$GEM_HOME/bin" \
	BUNDLE_SILENCE_ROOT_WARNING=1 \
	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
	&& chmod 777 "$GEM_HOME" "$BUNDLE_BIN"
	
#Install capistrano

RUN gem install capistrano \
        capistrano-rvm \
        capistrano-rails \
        capistrano-bundler \
        capistrano-sidekiq \
        capistrano-passenger \
        capistrano-laravel \
        capistrano-composer \
        capistrano-npm

RUN echo en_US.UTF-8 UTF-8 >> /etc/locale.gen && \
    locale-gen && \
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# AWS CLI needs the PYTHONIOENCODING environment varialbe to handle UTF-8 correctly:
ENV PYTHONIOENCODING=UTF-8

# man and less are needed to view 'aws <command> help'
# ssh allows us to log in to new instances
# vim is useful to write shell scripts
# python* is needed to install aws cli using pip install

RUN apt-get install -y \
    less \
    man \
    ssh \
    python \
    python-pip \
    python-virtualenv \
    vim

RUN adduser --disabled-login --gecos '' aws
WORKDIR /home/aws

USER aws

RUN \
    mkdir aws && \
    virtualenv aws/env && \
    ./aws/env/bin/pip install awscli && \
    echo 'source $HOME/aws/env/bin/activate' >> .bashrc && \
    echo 'complete -C aws_completer aws' >> .bashrc

USER root

RUN mkdir examples
ADD examples/etag.sh /home/aws/examples/etag.sh
ADD examples/s3diff.sh /home/aws/examples/s3diff.sh
ADD examples/start.sh /home/aws/examples/start.sh
ADD examples/terminate.sh /home/aws/examples/terminate.sh
ADD examples/init-instance.script /home/aws/examples/init-instance.script
ADD examples/README.md /home/aws/examples/README.md
RUN chown -R aws:aws /home/aws/examples

USER aws
